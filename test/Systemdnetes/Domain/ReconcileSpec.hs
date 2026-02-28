module Systemdnetes.Domain.ReconcileSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (ContainerState (..), FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Reconcile
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Reconcile"
    [ testPropertyNamed "pending pod with no node schedules" "prop_pendingNoNodeSchedules" prop_pendingNoNodeSchedules,
      testPropertyNamed "scheduled pod with no container starts" "prop_scheduledNoContainerStarts" prop_scheduledNoContainerStarts,
      testPropertyNamed "running container with matching flake is no action" "prop_runningMatchingFlakeIsNoAction" prop_runningMatchingFlakeIsNoAction,
      testPropertyNamed "running container with different flake rebuilds" "prop_runningDifferentFlakeRebuilds" prop_runningDifferentFlakeRebuilds,
      testPropertyNamed "running container with no flake info rebuilds" "prop_runningNoFlakeInfoRebuilds" prop_runningNoFlakeInfoRebuilds,
      testPropertyNamed "stopped container starts" "prop_stoppedContainerStarts" prop_stoppedContainerStarts,
      testPropertyNamed "failed container starts" "prop_failedContainerStarts" prop_failedContainerStarts,
      testPropertyNamed "rebuild action carries desired flake ref" "prop_rebuildActionCarriesDesiredFlakeRef" prop_rebuildActionCarriesDesiredFlakeRef
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genPodName :: Gen PodName
genPodName = PodName <$> genText

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

genFlakeRef :: Gen FlakeRef
genFlakeRef = FlakeRef <$> genText

genResources :: Gen ResourceRequests
genResources = ResourceRequests <$> genText <*> genText

genPodSpec :: Gen PodSpec
genPodSpec =
  PodSpec
    <$> genPodName
    <*> genFlakeRef
    <*> genResources
    <*> Gen.int (Range.linear 1 10)

prop_pendingNoNodeSchedules :: Property
prop_pendingNoNodeSchedules = property $ do
  spec <- forAll genPodSpec
  let pod = Pod {podSpec = spec, podState = Pending, podNode = Nothing}
  reconcilePod pod Nothing Nothing === SchedulePod (podName spec)

prop_scheduledNoContainerStarts :: Property
prop_scheduledNoContainerStarts = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Scheduled, podNode = Just node}
  reconcilePod pod Nothing Nothing === StartPod (podName spec) node

prop_runningMatchingFlakeIsNoAction :: Property
prop_runningMatchingFlakeIsNoAction = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Running, podNode = Just node}
      currentFlake = podFlakeRef spec
  reconcilePod pod (Just ContainerRunning) (Just currentFlake) === NoAction (podName spec)

prop_runningDifferentFlakeRebuilds :: Property
prop_runningDifferentFlakeRebuilds = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  otherFlake <- forAll genFlakeRef
  let pod = Pod {podSpec = spec, podState = Running, podNode = Just node}
  -- Use a flake ref that differs from the pod's spec
  case otherFlake == podFlakeRef spec of
    True -> discard
    False -> reconcilePod pod (Just ContainerRunning) (Just otherFlake) === RebuildPod (podName spec) node (podFlakeRef spec)

prop_runningNoFlakeInfoRebuilds :: Property
prop_runningNoFlakeInfoRebuilds = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Running, podNode = Just node}
  reconcilePod pod (Just ContainerRunning) Nothing === RebuildPod (podName spec) node (podFlakeRef spec)

prop_stoppedContainerStarts :: Property
prop_stoppedContainerStarts = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Running, podNode = Just node}
  reconcilePod pod (Just ContainerStopped) Nothing === StartPod (podName spec) node

prop_failedContainerStarts :: Property
prop_failedContainerStarts = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Running, podNode = Just node}
  reconcilePod pod (Just ContainerFailed) Nothing === StartPod (podName spec) node

prop_rebuildActionCarriesDesiredFlakeRef :: Property
prop_rebuildActionCarriesDesiredFlakeRef = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let pod = Pod {podSpec = spec, podState = Rebuilding, podNode = Just node}
      desiredFlake = podFlakeRef spec
  -- When no current flake info, rebuild carries the pod's spec flake ref
  case reconcilePod pod (Just ContainerRunning) Nothing of
    RebuildPod _ _ flake -> flake === desiredFlake
    other -> do
      annotate $ "Expected RebuildPod but got: " <> show other
      failure
