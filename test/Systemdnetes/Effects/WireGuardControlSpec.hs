module Systemdnetes.Effects.WireGuardControlSpec (tests) where

import Data.List (nub)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Network (IPv4 (..))
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.WireGuard (WgKeyPair (..), WgPeer (..))
import Systemdnetes.Effects.WireGuardControl
import Systemdnetes.Effects.WireGuardControl.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.WireGuardControl"
    [ testPropertyNamed "generated keys are unique" "prop_keyUniqueness" prop_keyUniqueness,
      testPropertyNamed "addPeer then listPeers includes it" "prop_addList" prop_addList,
      testPropertyNamed "removePeer then listPeers excludes it" "prop_removeList" prop_removeList,
      testPropertyNamed "listPeers on empty node returns []" "prop_listEmpty" prop_listEmpty
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genNodeName :: Gen NodeName
genNodeName = NodeName <$> genText

runPure :: Sem (WireGuardControl ': r) a -> Sem r a
runPure = fmap snd . wireGuardControlToPure

prop_keyUniqueness :: Property
prop_keyUniqueness = property $ do
  n <- forAll $ Gen.int (Range.linear 2 20)
  let keys = run $ runPure $ mapM (const generateKeyPair) [1 .. n]
      pubKeys = map wgPublicKey keys
  length (nub pubKeys) === length pubKeys

prop_addList :: Property
prop_addList = property $ do
  nodeName <- forAll genNodeName
  ip <- forAll $ IPv4 <$> Gen.word32 Range.linearBounded
  let (_, peers) = run $ wireGuardControlToPure $ do
        kp <- generateKeyPair
        let peer = WgPeer (wgPublicKey kp) ip nodeName
        addPeer nodeName peer
        listPeers nodeName
  length peers === 1

prop_removeList :: Property
prop_removeList = property $ do
  nodeName <- forAll genNodeName
  ip <- forAll $ IPv4 <$> Gen.word32 Range.linearBounded
  let (_, peers) = run $ wireGuardControlToPure $ do
        kp <- generateKeyPair
        let peer = WgPeer (wgPublicKey kp) ip nodeName
        addPeer nodeName peer
        removePeer nodeName (wgPublicKey kp)
        listPeers nodeName
  peers === []

prop_listEmpty :: Property
prop_listEmpty = property $ do
  nodeName <- forAll genNodeName
  let peers = run $ runPure $ listPeers nodeName
  peers === []
