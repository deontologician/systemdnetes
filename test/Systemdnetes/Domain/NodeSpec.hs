module Systemdnetes.Domain.NodeSpec (tests) where

import Data.Aeson (eitherDecode, encode)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Node
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Node"
    [ testPropertyNamed "NodeName JSON round-trip" "prop_nodeNameJson" prop_nodeNameJson,
      testPropertyNamed "Node JSON round-trip" "prop_nodeJson" prop_nodeJson,
      testPropertyNamed "NodeCapacity JSON round-trip" "prop_nodeCapacityJson" prop_nodeCapacityJson,
      testPropertyNamed "HealthStatus JSON round-trip" "prop_healthStatusJson" prop_healthStatusJson,
      testPropertyNamed "NodeStatus JSON round-trip" "prop_nodeStatusJson" prop_nodeStatusJson
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

genCapacity :: Gen NodeCapacity
genCapacity =
  NodeCapacity
    <$> (Millicores <$> Gen.int (Range.linear 1000 8000))
    <*> (Mebibytes <$> Gen.int (Range.linear 512 8192))

genNode :: Gen Node
genNode = Node <$> genNodeName <*> genText <*> genCapacity

genHealthStatus :: Gen HealthStatus
genHealthStatus = Gen.element [Healthy, Unhealthy, Unknown]

genNodeStatus :: Gen NodeStatus
genNodeStatus =
  NodeStatus
    <$> genNodeName
    <*> genText
    <*> genHealthStatus
    <*> Gen.maybe genText

prop_nodeNameJson :: Property
prop_nodeNameJson = property $ do
  x <- forAll genNodeName
  tripping x encode eitherDecode

prop_nodeJson :: Property
prop_nodeJson = property $ do
  x <- forAll genNode
  tripping x encode eitherDecode

prop_nodeCapacityJson :: Property
prop_nodeCapacityJson = property $ do
  x <- forAll genCapacity
  tripping x encode eitherDecode

prop_healthStatusJson :: Property
prop_healthStatusJson = property $ do
  x <- forAll genHealthStatus
  tripping x encode eitherDecode

prop_nodeStatusJson :: Property
prop_nodeStatusJson = property $ do
  x <- forAll genNodeStatus
  tripping x encode eitherDecode
