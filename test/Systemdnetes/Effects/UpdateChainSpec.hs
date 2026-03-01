module Systemdnetes.Effects.UpdateChainSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.App (PureResult (..), defaultPureConfig, runAppPure)
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Reconcile (ReconcileAction (..), reconcilePod)
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Systemd
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.UpdateChain"
    [ testPropertyNamed "update flake ref triggers rebuild" "prop_updateFlakeRefTriggersRebuild" prop_updateFlakeRefTriggersRebuild,
      testPropertyNamed "unchanged flake ref is no action" "prop_unchangedFlakeRefIsNoAction" prop_unchangedFlakeRefIsNoAction,
      testPropertyNamed "rebuild preserves node assignment" "prop_rebuildPreservesNodeAssignment" prop_rebuildPreservesNodeAssignment
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genPodSpec :: Gen PodSpec
genPodSpec =
  PodSpec . PodName
    <$> genText
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> genText <*> genText)
    <*> Gen.int (Range.linear 1 10)

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

genFlakeRef :: Gen FlakeRef
genFlakeRef = FlakeRef <$> genText

-- | When a pod's flake reference changes, the reconciler should detect the
-- drift and issue a rebuild. This test walks through the full lifecycle
-- (submit → assign → start → update flake ref → reconcile → rebuild) and
-- checks that reconciliation produces a RebuildPod action with the new ref.
prop_updateFlakeRefTriggersRebuild :: Property
prop_updateFlakeRefTriggersRebuild = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  newFlake <- forAll genFlakeRef
  -- Ensure the new flake differs from the original
  case newFlake == podFlakeRef spec of
    True -> discard
    False -> do
      let name = podName spec
          newSpec = spec {podFlakeRef = newFlake}
          result =
            runAppPure defaultPureConfig $ do
              -- 1. Submit and assign
              submitPod spec
              assignPodNode name node
              -- 2. Start the container
              startContainer node name
              setPodState name Running
              -- 3. Update the flake ref
              updatePodSpec name newSpec
              -- 4. Get current state for reconciliation
              pod <- fromJust <$> getPod name
              containerState <- getContainer node name
              -- 5. Reconcile should decide to rebuild
              let action = reconcilePod pod containerState (Just (podFlakeRef spec))
              -- 6. Execute the rebuild
              case action of
                RebuildPod _ n flake -> rebuildContainer n name flake Nothing
                _ -> pure ()
              -- 7. Verify
              pure action
      pureResultValue result === RebuildPod name node (podFlakeRef newSpec)

-- | When the deployed flake ref already matches the spec, reconciliation
-- should be a no-op. This ensures we don't trigger unnecessary rebuilds
-- for pods that are already up to date.
prop_unchangedFlakeRefIsNoAction :: Property
prop_unchangedFlakeRefIsNoAction = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let name = podName spec
      currentFlake = podFlakeRef spec
      result =
        runAppPure defaultPureConfig $ do
          submitPod spec
          assignPodNode name node
          startContainer node name
          setPodState name Running
          pod <- fromJust <$> getPod name
          containerState <- getContainer node name
          pure $ reconcilePod pod containerState (Just currentFlake)
  pureResultValue result === NoAction name

-- | After a rebuild triggered by a flake ref change, the pod should still
-- be assigned to the same node. This catches regressions where the update
-- path accidentally clears or reassigns the node.
prop_rebuildPreservesNodeAssignment :: Property
prop_rebuildPreservesNodeAssignment = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  newFlake <- forAll genFlakeRef
  case newFlake == podFlakeRef spec of
    True -> discard
    False -> do
      let name = podName spec
          newSpec = spec {podFlakeRef = newFlake}
          result =
            runAppPure defaultPureConfig $ do
              submitPod spec
              assignPodNode name node
              startContainer node name
              setPodState name Running
              updatePodSpec name newSpec
              pod <- fromJust <$> getPod name
              containerState <- getContainer node name
              case reconcilePod pod containerState (Just (podFlakeRef spec)) of
                RebuildPod _ n flake -> rebuildContainer n name flake Nothing
                _ -> pure ()
      case Map.lookup name (pureResultStore result) of
        Just pod -> podNode pod === Just node
        Nothing -> failure
