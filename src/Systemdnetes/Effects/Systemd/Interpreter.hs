module Systemdnetes.Effects.Systemd.Interpreter
  ( SystemdState,
    systemdToPure,
    systemdToIO,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Polysemy.State
import Systemdnetes.Domain.Node (Node, NodeName (..))
import Systemdnetes.Domain.Nspawn (parseMachinectlList, parseMachinectlState, renderMachineSetup)
import Systemdnetes.Domain.Network (IPv4, ipToText)
import Systemdnetes.Domain.Pod (ContainerInfo (..), ContainerState (..), FlakeRef (..), PodName (..))
import Systemdnetes.Effects.Log (Log, logError, logInfo)
import Systemdnetes.Effects.NodeStore (NodeStore, getNode)
import Systemdnetes.Effects.Ssh (Ssh, runSshCommand)
import Systemdnetes.Effects.Systemd

type SystemdState = Map NodeName (Map PodName ContainerState)

systemdToPure ::
  SystemdState ->
  Sem (Systemd ': r) a ->
  Sem r (SystemdState, a)
systemdToPure initial =
  runState initial
    . reinterpret
      ( \case
          ListContainers node -> do
            s <- get @SystemdState
            let containers = maybe [] Map.toList (Map.lookup node s)
            pure [ContainerInfo pod st | (pod, st) <- containers]
          GetContainer node pod -> do
            s <- get @SystemdState
            pure $ Map.lookup node s >>= Map.lookup pod
          StartContainer node pod -> do
            modify' @SystemdState $
              Map.alter
                (Just . maybe (Map.singleton pod ContainerRunning) (Map.insert pod ContainerRunning))
                node
          StopContainer node pod -> do
            modify' @SystemdState $
              Map.adjust (Map.insert pod ContainerStopped) node
          RebuildContainer node pod _flakeRef _mIp -> do
            modify' @SystemdState $
              Map.alter
                (Just . maybe (Map.singleton pod ContainerRunning) (Map.insert pod ContainerRunning))
                node
      )

-- | IO interpreter: uses SSH + machinectl to manage nspawn containers on
-- worker nodes. Requires Ssh, NodeStore, and Log in the remaining stack.
systemdToIO ::
  (Member Ssh r, Member NodeStore r, Member Log r) =>
  Sem (Systemd ': r) a ->
  Sem r a
systemdToIO = interpret $ \case
  ListContainers nodeName -> do
    withNode nodeName [] $ \node -> do
      result <- runSshCommand node "sudo machinectl list --no-legend --no-pager"
      case result of
        Right output -> pure $ parseMachinectlList output
        Left err -> do
          logError $ "Failed to list containers on " <> showNodeName nodeName <> ": " <> err
          pure []
  GetContainer nodeName (PodName pod) -> do
    withNode nodeName Nothing $ \node -> do
      result <- runSshCommand node ("sudo machinectl show " <> pod <> " --property=State --value")
      case result of
        Right output -> pure $ parseMachinectlState output
        Left _ -> pure Nothing
  StartContainer nodeName (PodName pod) -> do
    withNode nodeName () $ \node -> do
      logInfo $ "Starting container " <> pod <> " on " <> showNodeName nodeName
      result <- runSshCommand node ("sudo machinectl start " <> pod)
      case result of
        Right _ -> pure ()
        Left err ->
          logError $ "Failed to start " <> pod <> " on " <> showNodeName nodeName <> ": " <> err
  StopContainer nodeName (PodName pod) -> do
    withNode nodeName () $ \node -> do
      logInfo $ "Stopping container " <> pod <> " on " <> showNodeName nodeName
      result <- runSshCommand node ("sudo machinectl stop " <> pod)
      case result of
        Right _ -> pure ()
        Left err ->
          logError $ "Failed to stop " <> pod <> " on " <> showNodeName nodeName <> ": " <> err
  RebuildContainer nodeName podName@(PodName pod) flakeRef@(FlakeRef flakeRefText) mIp -> do
    withNode nodeName () $ \node -> do
      logInfo $ "Rebuilding container " <> pod <> " on " <> showNodeName nodeName <> " from " <> flakeRefText
      -- 1. Build the system closure on the worker using compose-pod.nix
      let cmd = composePodBuildCommand podName flakeRef mIp
      buildResult <- runSshCommand node cmd
      case buildResult of
        Left err -> logError $ "Build failed for " <> pod <> ": " <> err
        Right output -> do
          let systemPath = T.strip output
          -- 2. Set up machine rootfs and .nspawn file
          let setupScript = renderMachineSetup podName systemPath
          setupResult <- runSshCommand node ("bash -c " <> quote setupScript)
          case setupResult of
            Left err -> logError $ "Machine setup failed for " <> pod <> ": " <> err
            Right _ -> do
              -- 3. Stop if already running, then start
              stateResult <- runSshCommand node ("sudo machinectl show " <> pod <> " --property=State --value 2>/dev/null")
              case stateResult of
                Right st | T.strip st == "running" -> do
                  _ <- runSshCommand node ("sudo machinectl stop " <> pod)
                  pure ()
                _ -> pure ()
              startResult <- runSshCommand node ("sudo machinectl start " <> pod)
              case startResult of
                Right _ -> logInfo $ "Container " <> pod <> " started on " <> showNodeName nodeName
                Left err -> logError $ "Failed to start " <> pod <> " after rebuild: " <> err

-- | Look up a node by name; if not found, log an error and return the default.
withNode ::
  (Member NodeStore r, Member Log r) =>
  NodeName ->
  a ->
  (Node -> Sem r a) ->
  Sem r a
withNode nodeName def action = do
  nodeResult <- getNode nodeName
  case nodeResult of
    Just node -> action node
    Nothing -> do
      logError $ "Node not found: " <> showNodeName nodeName
      pure def

showNodeName :: NodeName -> Text
showNodeName (NodeName n) = n

-- | Shell-quote a text value for use in @bash -c '...'@.
quote :: Text -> Text
quote t = "'" <> T.replace "'" "'\"'\"'" t <> "'"

-- | Build the @nix build@ command that wraps a user flake through compose-pod.nix.
-- Uses @--impure@ because compose-pod.nix imports the user flake at eval time.
composePodBuildCommand :: PodName -> FlakeRef -> Maybe IPv4 -> Text
composePodBuildCommand (PodName name) (FlakeRef flake) mIp =
  "nix build --impure --no-link --print-out-paths --expr "
    <> quote nixExpr
  where
    nixExpr =
      "(import /etc/systemdnetes/compose-pod.nix { userFlakeRef = "
        <> nixString flake
        <> "; podName = "
        <> nixString name
        <> ";"
        <> ipArg
        <> " }).config.system.build.toplevel"
    ipArg = case mIp of
      Nothing -> ""
      Just ip -> " podIp = " <> nixString (ipToText ip) <> ";"
    nixString t = "\"" <> T.concatMap escapeNix t <> "\""
    escapeNix '\\' = "\\\\"
    escapeNix '"' = "\\\""
    escapeNix '$' = "\\$"
    escapeNix c = T.singleton c
