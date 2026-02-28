module Systemdnetes.Effects.SshSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Node (Node (..), NodeName (..))
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

genNode :: Gen Node
genNode = Node <$> (NodeName <$> genText) <*> genText

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
