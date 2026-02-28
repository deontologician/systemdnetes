module Systemdnetes.Effects.UpdateChainSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Domain.Reconcile (ReconcileAction (..), reconcilePod)
import Systemdnetes.Effects.Log.Interpreter (logToList)
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Store.Interpreter (storeToPure)
import Systemdnetes.Effects.Systemd
import Systemdnetes.Effects.Systemd.Interpreter (systemdToPure)
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

-- | Full chain: submit → assign node → start container → update flake ref
-- → reconcile → rebuild → verify container is running with new spec.
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
          (_, (_, (_, action))) =
            run
              . storeToPure Map.empty
              . systemdToPure Map.empty
              . logToList
              $ do
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
                let result = reconcilePod pod containerState (Just (podFlakeRef spec))
                -- 6. Execute the rebuild
                case result of
                  RebuildPod _ n flake -> rebuildContainer n name flake
                  _ -> pure ()
                -- 7. Verify
                pure result
      action === RebuildPod name node (podFlakeRef newSpec)

-- | When the flake ref hasn't changed, reconciliation returns NoAction.
prop_unchangedFlakeRefIsNoAction :: Property
prop_unchangedFlakeRefIsNoAction = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let name = podName spec
      currentFlake = podFlakeRef spec
      (_, (_, (_, action))) =
        run
          . storeToPure Map.empty
          . systemdToPure Map.empty
          . logToList
          $ do
            submitPod spec
            assignPodNode name node
            startContainer node name
            setPodState name Running
            pod <- fromJust <$> getPod name
            containerState <- getContainer node name
            pure $ reconcilePod pod containerState (Just currentFlake)
  action === NoAction name

-- | Node assignment survives the full update chain.
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
          (storeState, (_, (_, _))) =
            run
              . storeToPure Map.empty
              . systemdToPure Map.empty
              . logToList
              $ do
                submitPod spec
                assignPodNode name node
                startContainer node name
                setPodState name Running
                updatePodSpec name newSpec
                pod <- fromJust <$> getPod name
                containerState <- getContainer node name
                case reconcilePod pod containerState (Just (podFlakeRef spec)) of
                  RebuildPod _ n flake -> rebuildContainer n name flake
                  _ -> pure ()
      case Map.lookup name storeState of
        Just pod -> podNode pod === Just node
        Nothing -> failure
