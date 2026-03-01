module Systemdnetes.Reconciler.LoopSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Systemdnetes.App (PureAppConfig (..), PureResult (..), defaultPureConfig, runAppPure)
import Systemdnetes.Domain.Node (Node (..), NodeCapacity (..), NodeName (..), NodeRole (..))
import Systemdnetes.Domain.Pod (ContainerState (..), FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Reconcile (ReconcileAction (..))
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Systemdnetes.Effects.Log (LogMessage (..))
import Systemdnetes.Effects.Store (submitPod)
import Systemdnetes.Effects.Systemd.Interpreter (SystemdState)
import Systemdnetes.Reconciler.Loop (executeAction, reconcileOnce)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Reconciler.Loop"
    [ testPropertyNamed "pending pod + node gets scheduled and started" "prop_pendingPodGetsScheduledAndStarted" prop_pendingPodGetsScheduledAndStarted,
      testPropertyNamed "running pod + running container is NoAction" "prop_runningPodRunningContainerNoAction" prop_runningPodRunningContainerNoAction,
      testPropertyNamed "running pod + stopped container gets restarted" "prop_runningPodStoppedContainerRestarted" prop_runningPodStoppedContainerRestarted,
      testPropertyNamed "multiple pods limited capacity partial scheduling" "prop_multiplePodLimitedCapacity" prop_multiplePodLimitedCapacity,
      testPropertyNamed "no nodes pods stay pending with warnings" "prop_noNodesPodsPending" prop_noNodesPodsPending,
      testPropertyNamed "executeAction StartPod updates state and creates container" "prop_executeStartPod" prop_executeStartPod,
      testPropertyNamed "executeAction RebuildPod stops and rebuilds" "prop_executeRebuildPod" prop_executeRebuildPod
    ]

-- Test helpers

mkWorkerNode :: Text -> Int -> Int -> Node
mkWorkerNode name cpuM memMi =
  Node
    { nodeName = NodeName name,
      nodeAddress = "10.0.0.1",
      nodeCapacity = NodeCapacity (Millicores cpuM) (Mebibytes memMi),
      nodeRole = Worker
    }

mkPodSpec :: Text -> Text -> Int -> Int -> PodSpec
mkPodSpec name flake cpuM memMi =
  PodSpec
    { podName = PodName name,
      podFlakeRef = FlakeRef flake,
      podResources = ResourceRequests (T.pack (show cpuM) <> "m") (T.pack (show memMi) <> "Mi"),
      podReplicas = 1
    }

-- Properties

prop_pendingPodGetsScheduledAndStarted :: Property
prop_pendingPodGetsScheduledAndStarted = property $ do
  let node = mkWorkerNode "worker-1" 2000 4096
      spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node
          }
      result = runAppPure cfg $ do
        submitPod spec
        reconcileOnce
  let pods = Map.elems (pureResultStore result)
  case pods of
    [pod] -> do
      podNode pod === Just (NodeName "worker-1")
      podState pod === Running
    _ -> do
      annotate $ "Expected exactly 1 pod, got " <> show (length pods)
      failure

prop_runningPodRunningContainerNoAction :: Property
prop_runningPodRunningContainerNoAction = property $ do
  let node = mkWorkerNode "worker-1" 2000 4096
      spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      pod =
        Pod
          { podSpec = spec,
            podState = Running,
            podNode = Just (NodeName "worker-1"),
            podNetwork = Nothing
          }
      systemdState :: SystemdState
      systemdState =
        Map.singleton
          (NodeName "worker-1")
          (Map.singleton (PodName "my-pod") ContainerRunning)
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node,
            pureStoreState = Map.singleton (PodName "my-pod") pod,
            pureSystemdState = systemdState
          }
      result = runAppPure cfg reconcileOnce
      actions = pureResultValue result
  assert $ all isNoAction actions
  where
    isNoAction (NoAction _) = True
    isNoAction _ = False

prop_runningPodStoppedContainerRestarted :: Property
prop_runningPodStoppedContainerRestarted = property $ do
  let node = mkWorkerNode "worker-1" 2000 4096
      spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      pod =
        Pod
          { podSpec = spec,
            podState = Running,
            podNode = Just (NodeName "worker-1"),
            podNetwork = Nothing
          }
      systemdState :: SystemdState
      systemdState =
        Map.singleton
          (NodeName "worker-1")
          (Map.singleton (PodName "my-pod") ContainerStopped)
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node,
            pureStoreState = Map.singleton (PodName "my-pod") pod,
            pureSystemdState = systemdState
          }
      result = runAppPure cfg reconcileOnce
      actions = pureResultValue result
  assert $ any isStartPod actions
  case Map.lookup (NodeName "worker-1") (pureResultSystemd result) >>= Map.lookup (PodName "my-pod") of
    Just ContainerRunning -> pure ()
    other -> do
      annotate $ "Expected ContainerRunning, got: " <> show other
      failure
  where
    isStartPod (StartPod _ _) = True
    isStartPod _ = False

prop_multiplePodLimitedCapacity :: Property
prop_multiplePodLimitedCapacity = property $ do
  let node = mkWorkerNode "worker-1" 1000 4096
      spec1 = mkPodSpec "pod-1" "github:user/repo1" 600 256
      spec2 = mkPodSpec "pod-2" "github:user/repo2" 600 256
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node
          }
      result = runAppPure cfg $ do
        submitPod spec1
        submitPod spec2
        reconcileOnce
  let pods = Map.elems (pureResultStore result)
      scheduled = filter (isJust . podNode) pods
      pending = filter (\p -> podState p == Pending) pods
  length scheduled === 1
  length pending === 1

prop_noNodesPodsPending :: Property
prop_noNodesPodsPending = property $ do
  let spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      result = runAppPure defaultPureConfig $ do
        submitPod spec
        reconcileOnce
  let pods = Map.elems (pureResultStore result)
  case pods of
    [pod] -> podState pod === Pending
    _ -> failure
  let logs = pureResultLogs result
  assert $ any (T.isInfixOf "Unschedulable" . logMessageContent) logs

prop_executeStartPod :: Property
prop_executeStartPod = property $ do
  let node = mkWorkerNode "worker-1" 2000 4096
      spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node
          }
      result = runAppPure cfg $ do
        submitPod spec
        executeAction (StartPod (PodName "my-pod") (NodeName "worker-1"))
  case Map.lookup (PodName "my-pod") (pureResultStore result) of
    Just pod -> podState pod === Running
    Nothing -> failure
  case Map.lookup (NodeName "worker-1") (pureResultSystemd result) of
    Just containers ->
      case Map.lookup (PodName "my-pod") containers of
        Just ContainerRunning -> pure ()
        other -> do
          annotate $ "Expected ContainerRunning, got: " <> show other
          failure
    Nothing -> failure

prop_executeRebuildPod :: Property
prop_executeRebuildPod = property $ do
  let node = mkWorkerNode "worker-1" 2000 4096
      spec = mkPodSpec "my-pod" "github:user/repo" 500 512
      pod =
        Pod
          { podSpec = spec,
            podState = Running,
            podNode = Just (NodeName "worker-1"),
            podNetwork = Nothing
          }
      systemdState :: SystemdState
      systemdState =
        Map.singleton
          (NodeName "worker-1")
          (Map.singleton (PodName "my-pod") ContainerRunning)
      cfg =
        defaultPureConfig
          { pureNodeStoreState = Map.singleton (NodeName "worker-1") node,
            pureStoreState = Map.singleton (PodName "my-pod") pod,
            pureSystemdState = systemdState
          }
      result = runAppPure cfg $ do
        executeAction (RebuildPod (PodName "my-pod") (NodeName "worker-1") (FlakeRef "github:user/repo-v2"))
  case Map.lookup (PodName "my-pod") (pureResultStore result) of
    Just p -> podState p === Running
    Nothing -> failure
  case Map.lookup (NodeName "worker-1") (pureResultSystemd result) of
    Just containers ->
      case Map.lookup (PodName "my-pod") containers of
        Just ContainerRunning -> pure ()
        other -> do
          annotate $ "Expected ContainerRunning, got: " <> show other
          failure
    Nothing -> failure
