module Systemdnetes.Effects.SystemdSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod (ContainerState (..), FlakeRef (..), PodName (..))
import Systemdnetes.Effects.Systemd
import Systemdnetes.Effects.Systemd.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.Systemd"
    [ testPropertyNamed "listContainers on empty state returns []" "prop_listEmpty" prop_listEmpty,
      testPropertyNamed "startContainer then getContainer returns Running" "prop_startGet" prop_startGet,
      testPropertyNamed "stopContainer then getContainer returns Stopped" "prop_stopGet" prop_stopGet,
      testPropertyNamed "startContainer then listContainers includes it" "prop_startList" prop_startList,
      testPropertyNamed "getContainer on unknown pod returns Nothing" "prop_getUnknown" prop_getUnknown,
      testPropertyNamed "rebuildContainer sets container to Running" "prop_rebuildContainerSetsRunning" prop_rebuildContainerSetsRunning,
      testPropertyNamed "rebuildContainer on empty creates container" "prop_rebuildContainerOnEmptyCreatesContainer" prop_rebuildContainerOnEmptyCreatesContainer
    ]

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

genPodName :: Gen PodName
genPodName = PodName <$> genText

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

prop_listEmpty :: Property
prop_listEmpty = property $ do
  node <- forAll genNodeName
  let (_, result) = run $ systemdToPure Map.empty (listContainers node)
  result === []

prop_startGet :: Property
prop_startGet = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  let (_, result) = run $ systemdToPure Map.empty $ do
        startContainer node pod
        getContainer node pod
  result === Just ContainerRunning

prop_stopGet :: Property
prop_stopGet = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  let (_, result) = run $ systemdToPure Map.empty $ do
        startContainer node pod
        stopContainer node pod
        getContainer node pod
  result === Just ContainerStopped

prop_startList :: Property
prop_startList = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  let (_, containers) = run $ systemdToPure Map.empty $ do
        startContainer node pod
        listContainers node
  length containers === 1

prop_getUnknown :: Property
prop_getUnknown = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  let (_, result) = run $ systemdToPure Map.empty (getContainer node pod)
  result === Nothing

genFlakeRef :: Gen FlakeRef
genFlakeRef = FlakeRef <$> genText

prop_rebuildContainerSetsRunning :: Property
prop_rebuildContainerSetsRunning = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  flake <- forAll genFlakeRef
  let (_, result) = run $ systemdToPure Map.empty $ do
        startContainer node pod
        stopContainer node pod
        rebuildContainer node pod flake
        getContainer node pod
  result === Just ContainerRunning

prop_rebuildContainerOnEmptyCreatesContainer :: Property
prop_rebuildContainerOnEmptyCreatesContainer = property $ do
  node <- forAll genNodeName
  pod <- forAll genPodName
  flake <- forAll genFlakeRef
  let (_, result) = run $ systemdToPure Map.empty $ do
        rebuildContainer node pod flake
        getContainer node pod
  result === Just ContainerRunning
