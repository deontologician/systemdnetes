module Systemdnetes.Domain.PodSpec (tests) where

import Data.Aeson (eitherDecode, encode)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.Pod
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Pod"
    [ testPropertyNamed "PodName JSON round-trip" "prop_podNameJson" prop_podNameJson,
      testPropertyNamed "FlakeRef JSON round-trip" "prop_flakeRefJson" prop_flakeRefJson,
      testPropertyNamed "PodSpec JSON round-trip" "prop_podSpecJson" prop_podSpecJson,
      testPropertyNamed "PodState JSON round-trip" "prop_podStateJson" prop_podStateJson,
      testPropertyNamed "Pod JSON round-trip" "prop_podJson" prop_podJson,
      testPropertyNamed "ContainerState JSON round-trip" "prop_containerStateJson" prop_containerStateJson,
      testPropertyNamed "ContainerInfo JSON round-trip" "prop_containerInfoJson" prop_containerInfoJson
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genPodName :: Gen PodName
genPodName = PodName <$> genText

genFlakeRef :: Gen FlakeRef
genFlakeRef = FlakeRef <$> genText

genResourceRequests :: Gen ResourceRequests
genResourceRequests = ResourceRequests <$> genText <*> genText

genPodSpec :: Gen PodSpec
genPodSpec =
  PodSpec
    <$> genPodName
    <*> genFlakeRef
    <*> genResourceRequests
    <*> Gen.int (Range.linear 1 10)

genPodState :: Gen PodState
genPodState = Gen.element [Pending, Scheduled, Running, Failed]

genPod :: Gen Pod
genPod =
  Pod
    <$> genPodSpec
    <*> genPodState
    <*> Gen.maybe (NodeName <$> genText)

genContainerState :: Gen ContainerState
genContainerState = Gen.element [ContainerRunning, ContainerStopped, ContainerFailed]

genContainerInfo :: Gen ContainerInfo
genContainerInfo = ContainerInfo <$> genPodName <*> genContainerState

prop_podNameJson :: Property
prop_podNameJson = property $ do
  x <- forAll genPodName
  tripping x encode eitherDecode

prop_flakeRefJson :: Property
prop_flakeRefJson = property $ do
  x <- forAll genFlakeRef
  tripping x encode eitherDecode

prop_podSpecJson :: Property
prop_podSpecJson = property $ do
  x <- forAll genPodSpec
  tripping x encode eitherDecode

prop_podStateJson :: Property
prop_podStateJson = property $ do
  x <- forAll genPodState
  tripping x encode eitherDecode

prop_podJson :: Property
prop_podJson = property $ do
  x <- forAll genPod
  tripping x encode eitherDecode

prop_containerStateJson :: Property
prop_containerStateJson = property $ do
  x <- forAll genContainerState
  tripping x encode eitherDecode

prop_containerInfoJson :: Property
prop_containerInfoJson = property $ do
  x <- forAll genContainerInfo
  tripping x encode eitherDecode
