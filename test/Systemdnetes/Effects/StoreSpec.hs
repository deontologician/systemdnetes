module Systemdnetes.Effects.StoreSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Store.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.Store"
    [ testPropertyNamed "submitPod then getPod returns the pod" "prop_submitGet" prop_submitGet,
      testPropertyNamed "submitPod then listPods includes it" "prop_submitList" prop_submitList,
      testPropertyNamed "submitted pod starts in Pending state" "prop_submitPending" prop_submitPending,
      testPropertyNamed "deletePod then getPod returns Nothing" "prop_deleteGet" prop_deleteGet,
      testPropertyNamed "listPods on empty store returns []" "prop_listEmpty" prop_listEmpty,
      testPropertyNamed "getPod on unknown name returns Nothing" "prop_getUnknown" prop_getUnknown,
      testPropertyNamed "updatePodSpec preserves node assignment" "prop_updatePodSpecPreservesNode" prop_updatePodSpecPreservesNode,
      testPropertyNamed "updatePodSpec sets state to Rebuilding" "prop_updatePodSpecSetsRebuilding" prop_updatePodSpecSetsRebuilding,
      testPropertyNamed "updatePodSpec changes the flake ref" "prop_updatePodSpecChangesFlakeRef" prop_updatePodSpecChangesFlakeRef,
      testPropertyNamed "setPodState changes the state" "prop_setPodStateChangesState" prop_setPodStateChangesState,
      testPropertyNamed "assignPodNode sets node and Scheduled" "prop_assignPodNodeSetsNodeAndScheduled" prop_assignPodNodeSetsNodeAndScheduled,
      testPropertyNamed "updatePodSpec on unknown pod is noop" "prop_updatePodSpecUnknownIsNoop" prop_updatePodSpecUnknownIsNoop
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genPodSpec :: Gen PodSpec
genPodSpec =
  (PodSpec . PodName <$> genText)
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> genText <*> genText)
    <*> Gen.int (Range.linear 1 10)

prop_submitGet :: Property
prop_submitGet = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        getPod (podName spec)
  case result of
    Just pod -> podSpec pod === spec
    Nothing -> failure

prop_submitList :: Property
prop_submitList = property $ do
  spec <- forAll genPodSpec
  let (_, pods) = run $ storeToPure Map.empty $ do
        submitPod spec
        listPods
  length pods === 1

prop_submitPending :: Property
prop_submitPending = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        getPod (podName spec)
  case result of
    Just pod -> do
      podState pod === Pending
      podNode pod === Nothing
    Nothing -> failure

prop_deleteGet :: Property
prop_deleteGet = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        deletePod (podName spec)
        getPod (podName spec)
  result === Nothing

prop_listEmpty :: Property
prop_listEmpty = property $ do
  let (_, pods) = run $ storeToPure Map.empty listPods
  pods === []

prop_getUnknown :: Property
prop_getUnknown = property $ do
  name <- forAll (PodName <$> genText)
  let (_, result) = run $ storeToPure Map.empty (getPod name)
  result === Nothing

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

prop_updatePodSpecPreservesNode :: Property
prop_updatePodSpecPreservesNode = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  newSpec <- forAll genPodSpec
  let newSpecSameName = newSpec {podName = podName spec}
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        assignPodNode (podName spec) node
        updatePodSpec (podName spec) newSpecSameName
        getPod (podName spec)
  case result of
    Just pod -> podNode pod === Just node
    Nothing -> failure

prop_updatePodSpecSetsRebuilding :: Property
prop_updatePodSpecSetsRebuilding = property $ do
  spec <- forAll genPodSpec
  newSpec <- forAll genPodSpec
  let newSpecSameName = newSpec {podName = podName spec}
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        updatePodSpec (podName spec) newSpecSameName
        getPod (podName spec)
  case result of
    Just pod -> podState pod === Rebuilding
    Nothing -> failure

prop_updatePodSpecChangesFlakeRef :: Property
prop_updatePodSpecChangesFlakeRef = property $ do
  spec <- forAll genPodSpec
  newSpec <- forAll genPodSpec
  let newSpecSameName = newSpec {podName = podName spec}
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        updatePodSpec (podName spec) newSpecSameName
        getPod (podName spec)
  case result of
    Just pod -> podFlakeRef (podSpec pod) === podFlakeRef newSpecSameName
    Nothing -> failure

prop_setPodStateChangesState :: Property
prop_setPodStateChangesState = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        setPodState (podName spec) Running
        getPod (podName spec)
  case result of
    Just pod -> podState pod === Running
    Nothing -> failure

prop_assignPodNodeSetsNodeAndScheduled :: Property
prop_assignPodNodeSetsNodeAndScheduled = property $ do
  spec <- forAll genPodSpec
  node <- forAll genNodeName
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        assignPodNode (podName spec) node
        getPod (podName spec)
  case result of
    Just pod -> do
      podNode pod === Just node
      podState pod === Scheduled
    Nothing -> failure

prop_updatePodSpecUnknownIsNoop :: Property
prop_updatePodSpecUnknownIsNoop = property $ do
  spec <- forAll genPodSpec
  let (st, _) = run $ storeToPure Map.empty $ do
        updatePodSpec (podName spec) spec
  st === Map.empty
