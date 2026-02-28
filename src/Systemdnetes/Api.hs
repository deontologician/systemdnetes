module Systemdnetes.Api
  ( handleRequest,
    defaultNodes,
    defaultNodeCapacities,
  )
where

import Data.Aeson (ToJSON, eitherDecode, encode)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text, pack)
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
import Network.Wai (Request, Response, pathInfo, requestMethod, responseLBS, strictRequestBody)
import Polysemy
import Systemdnetes.Domain.Cluster (NodeCapacity (..), buildClusterState)
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
import Systemdnetes.Domain.Pod (PodName (..), PodSpec (..))
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Systemdnetes.Effects.Log (Log, logInfo)
import Systemdnetes.Effects.Store (Store, deletePod, getPod, listPods, submitPod)

-- | Static node capacities for the PoC. Will be replaced by config/discovery.
defaultNodeCapacities :: [(Node, NodeCapacity)]
defaultNodeCapacities =
  [ (Node (NodeName "node-1") "192.168.1.10", NodeCapacity (Millicores 2000) (Mebibytes 2048)),
    (Node (NodeName "node-2") "192.168.1.11", NodeCapacity (Millicores 4000) (Mebibytes 4096)),
    (Node (NodeName "node-3") "192.168.1.12", NodeCapacity (Millicores 1000) (Mebibytes 1024))
  ]

-- | Static node list derived from capacities.
defaultNodes :: [Node]
defaultNodes = map fst defaultNodeCapacities

handleRequest ::
  (Member Log r, Member Store r, Member (Embed IO) r) =>
  Request ->
  Sem r Response
handleRequest req = do
  body <- embed $ strictRequestBody req
  route (requestMethod req) (pathInfo req) body
  where
    route "GET" [] _ = do
      logInfo "GET /"
      html <- embed $ LBS.readFile "static/index.html"
      pure $ responseLBS status200 [(hContentType, "text/html")] html
    route "GET" ["healthz"] _ =
      pure $ textResponse status200 "ok\n"
    route "GET" ["api", "v1", "cluster"] _ = do
      logInfo "GET /api/v1/cluster"
      pods <- listPods
      let cs = buildClusterState defaultNodeCapacities pods
      pure $ jsonResponse status200 cs
    route "GET" ["api", "v1", "nodes"] _ = do
      logInfo "GET /api/v1/nodes"
      pure $ jsonResponse status200 defaultNodes
    route "GET" ["api", "v1", "nodes", name] _ = do
      logInfo $ "GET /api/v1/nodes/" <> name
      case findNode name of
        Just node -> pure $ jsonResponse status200 node
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
    route "GET" ["api", "v1", "pods", name] _ = do
      logInfo $ "GET /api/v1/pods/" <> name
      result <- getPod (PodName name)
      case result of
        Just pod -> pure $ jsonResponse status200 pod
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

findNode :: Text -> Maybe Node
findNode name = case filter (\n -> nodeName n == NodeName name) defaultNodes of
  [node] -> Just node
  _ -> Nothing

jsonResponse :: (ToJSON a) => Status -> a -> Response
jsonResponse status val =
  responseLBS status [(hContentType, "application/json")] (encode val)

textResponse :: Status -> LBS.ByteString -> Response
textResponse status =
  responseLBS status [(hContentType, "text/plain")]
