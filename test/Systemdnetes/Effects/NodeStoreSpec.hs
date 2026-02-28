module Systemdnetes.Effects.NodeStoreSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
import Systemdnetes.Effects.NodeStore
import Systemdnetes.Effects.NodeStore.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.NodeStore"
    [ testPropertyNamed "registerNode then getNode returns the node" "prop_registerGet" prop_registerGet,
      testPropertyNamed "registerNode then listNodes includes it" "prop_registerList" prop_registerList,
      testPropertyNamed "removeNode then getNode returns Nothing" "prop_removeGet" prop_removeGet,
      testPropertyNamed "listNodes on empty store returns []" "prop_listEmpty" prop_listEmpty,
      testPropertyNamed "getNode on unknown name returns Nothing" "prop_getUnknown" prop_getUnknown,
      testPropertyNamed "registerNode overwrites existing node" "prop_registerOverwrite" prop_registerOverwrite
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genNode :: Gen Node
genNode = Node <$> (NodeName <$> genText) <*> genText

prop_registerGet :: Property
prop_registerGet = property $ do
  node <- forAll genNode
  let (_, result) = run $ nodeStoreToPure Map.empty $ do
        registerNode node
        getNode (nodeName node)
  result === Just node

prop_registerList :: Property
prop_registerList = property $ do
  node <- forAll genNode
  let (_, nodes) = run $ nodeStoreToPure Map.empty $ do
        registerNode node
        listNodes
  length nodes === 1

prop_removeGet :: Property
prop_removeGet = property $ do
  node <- forAll genNode
  let (_, result) = run $ nodeStoreToPure Map.empty $ do
        registerNode node
        removeNode (nodeName node)
        getNode (nodeName node)
  result === Nothing

prop_listEmpty :: Property
prop_listEmpty = property $ do
  let (_, nodes) = run $ nodeStoreToPure Map.empty listNodes
  nodes === []

prop_getUnknown :: Property
prop_getUnknown = property $ do
  name <- forAll (NodeName <$> genText)
  let (_, result) = run $ nodeStoreToPure Map.empty (getNode name)
  result === Nothing

prop_registerOverwrite :: Property
prop_registerOverwrite = property $ do
  name <- forAll (NodeName <$> genText)
  addr1 <- forAll genText
  addr2 <- forAll genText
  let node1 = Node name addr1
      node2 = Node name addr2
      (_, result) = run $ nodeStoreToPure Map.empty $ do
        registerNode node1
        registerNode node2
        getNode name
  result === Just node2
