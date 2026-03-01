module Systemdnetes.Api
  ( handleRequest,
  )
where

import Data.Aeson (ToJSON, eitherDecode, encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types
  ( Status,
    hContentType,
    status200,
    status201,
    status400,
    status404,
    status405,
  )
import Network.Wai (Request, Response, pathInfo, requestMethod, responseLBS)
import Polysemy
import Systemdnetes.Domain.Cluster (buildClusterState)
import Systemdnetes.Domain.Node (HealthStatus (..), Node (..), NodeName (..), NodeStatus (..))
import Systemdnetes.Domain.Pod (FlakeRef, Pod (..), PodName (..), PodSpec (..))
import Systemdnetes.Effects.FileServer (FileServer, readStaticFile)
import Systemdnetes.Effects.Log (Log, logInfo)
import Systemdnetes.Effects.NodeStore (NodeStore, getNode, listNodes, registerNode, removeNode)
import Systemdnetes.Effects.Ssh (Ssh, runSshCommand)
import Systemdnetes.Effects.Store (Store, deletePod, getPod, listPods, submitPod)
import Systemdnetes.Effects.Systemd (Systemd, getContainer, listContainers)
import Systemdnetes.Sse (sseLogResponse)

handleRequest ::
  (Member Log r, Member Store r, Member NodeStore r, Member Ssh r, Member FileServer r, Member Systemd r) =>
  [FlakeRef] ->
  LBS.ByteString ->
  Request ->
  Sem r Response
handleRequest flakes body req =
  route (requestMethod req) (pathInfo req) body
  where
    route "GET" [] _ = do
      logInfo "GET /"
      html <- readStaticFile "static/index.html"
      pure $ responseLBS status200 [(hContentType, "text/html")] html
    route "GET" ["healthz"] _ =
      pure $ textResponse status200 "ok\n"
    route "GET" ["api", "v1", "cluster"] _ = do
      logInfo "GET /api/v1/cluster"
      nodes <- listNodes
      pods <- listPods
      let cs = buildClusterState nodes pods
      pure $ jsonResponse status200 cs
    route "GET" ["api", "v1", "flakes"] _ = do
      logInfo "GET /api/v1/flakes"
      pure $ jsonResponse status200 flakes
    route "POST" ["api", "v1", "nodes"] body = do
      logInfo "POST /api/v1/nodes"
      case eitherDecode body of
        Left err ->
          pure $ textResponse status400 $ LBS.fromStrict $ encodeUtf8 $ "bad request: " <> pack err <> "\n"
        Right node -> do
          registerNode node
          pure $ jsonResponse status201 node
    route "GET" ["api", "v1", "nodes"] _ = do
      logInfo "GET /api/v1/nodes"
      nodes <- listNodes
      statuses <- traverse checkNodeHealth nodes
      pure $ jsonResponse status200 statuses
    route "GET" ["api", "v1", "nodes", name] _ = do
      logInfo $ "GET /api/v1/nodes/" <> name
      result <- getNode (NodeName name)
      case result of
        Just node -> do
          status <- checkNodeHealth node
          containers <- listContainers (NodeName name)
          pure $ jsonResponse status200 (status, containers)
        Nothing -> pure $ textResponse status404 "node not found\n"
    route "GET" ["api", "v1", "nodes", name, "containers"] _ = do
      logInfo $ "GET /api/v1/nodes/" <> name <> "/containers"
      result <- getNode (NodeName name)
      case result of
        Just _ -> do
          containers <- listContainers (NodeName name)
          pure $ jsonResponse status200 containers
        Nothing -> pure $ textResponse status404 "node not found\n"
    route "DELETE" ["api", "v1", "nodes", name] _ = do
      logInfo $ "DELETE /api/v1/nodes/" <> name
      result <- getNode (NodeName name)
      case result of
        Just _ -> do
          removeNode (NodeName name)
          pure $ textResponse status200 "deleted\n"
        Nothing -> pure $ textResponse status404 "node not found\n"
    route "POST" ["api", "v1", "pods"] body = do
      logInfo "POST /api/v1/pods"
      case eitherDecode body of
        Left err ->
          pure $ textResponse status400 $ LBS.fromStrict $ encodeUtf8 $ "bad request: " <> pack err <> "\n"
        Right spec -> do
          submitPod spec
          result <- getPod (podName spec)
          case result of
            Just pod -> pure $ jsonResponse status201 pod
            Nothing -> pure $ textResponse status201 "created\n"
    route "GET" ["api", "v1", "pods"] _ = do
      logInfo "GET /api/v1/pods"
      jsonResponse status200 <$> listPods
    route "GET" ["api", "v1", "pods", name, "logs"] _ = do
      logInfo $ "GET /api/v1/pods/" <> name <> "/logs"
      result <- getPod (PodName name)
      case result of
        Nothing -> pure $ textResponse status404 "pod not found\n"
        Just pod -> case podNode pod of
          Nothing -> pure $ textResponse status400 "pod not scheduled\n"
          Just assignedNode -> do
            nodeResult <- getNode assignedNode
            case nodeResult of
              Nothing -> pure $ textResponse status404 "node not found\n"
              Just node -> pure $ sseLogResponse (nodeAddress node) name
    route "GET" ["api", "v1", "pods", name] _ = do
      logInfo $ "GET /api/v1/pods/" <> name
      result <- getPod (PodName name)
      case result of
        Just pod -> do
          containerState <- case podNode pod of
            Just assignedNode -> getContainer assignedNode (PodName name)
            Nothing -> pure Nothing
          pure $ jsonResponse status200 (pod, containerState)
        Nothing -> pure $ textResponse status404 "pod not found\n"
    route "DELETE" ["api", "v1", "pods", name] _ = do
      logInfo $ "DELETE /api/v1/pods/" <> name
      result <- getPod (PodName name)
      case result of
        Just _ -> do
          deletePod (PodName name)
          pure $ textResponse status200 "deleted\n"
        Nothing -> pure $ textResponse status404 "pod not found\n"
    route _ _ _ =
      pure $ textResponse status405 "method not allowed\n"

checkNodeHealth :: (Member Ssh r) => Node -> Sem r NodeStatus
checkNodeHealth node = do
  result <- runSshCommand node "systemdnetes-health"
  pure $ case result of
    Right output -> NodeStatus (nodeName node) (nodeAddress node) Healthy (Just output)
    Left err -> NodeStatus (nodeName node) (nodeAddress node) Unhealthy (Just err)

jsonResponse :: (ToJSON a) => Status -> a -> Response
jsonResponse status val =
  responseLBS status [(hContentType, "application/json")] (encode val)

textResponse :: Status -> LBS.ByteString -> Response
textResponse status =
  responseLBS status [(hContentType, "text/plain")]
