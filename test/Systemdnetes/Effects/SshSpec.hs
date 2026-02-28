module Systemdnetes.Effects.SshSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (Node (..), NodeCapacity (..), NodeName (..))
import Systemdnetes.Domain.Resource (Mebibytes (..), Millicores (..))
import Systemdnetes.Effects.Ssh
import Systemdnetes.Effects.Ssh.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.Ssh"
    [ testPropertyNamed "known node returns Right with canned output" "prop_knownNode" prop_knownNode,
      testPropertyNamed "unknown node returns Left unreachable" "prop_unknownNode" prop_unknownNode
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genCapacity :: Gen NodeCapacity
genCapacity =
  NodeCapacity
    <$> (Millicores <$> Gen.int (Range.linear 1000 8000))
    <*> (Mebibytes <$> Gen.int (Range.linear 512 8192))

genNode :: Gen Node
genNode = (Node . NodeName <$> genText) <*> genText <*> genCapacity

prop_knownNode :: Property
prop_knownNode = property $ do
  node <- forAll genNode
  cannedOutput <- forAll genText
  let known = Map.singleton (nodeName node) cannedOutput
      result = run $ sshToPure known (runSshCommand node "any-command")
  result === Right cannedOutput

prop_unknownNode :: Property
prop_unknownNode = property $ do
  node <- forAll genNode
  let result = run $ sshToPure Map.empty (runSshCommand node "any-command")
  result === Left "unreachable"
