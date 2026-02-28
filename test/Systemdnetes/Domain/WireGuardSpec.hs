module Systemdnetes.Domain.WireGuardSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Network (IPv4 (..))
import Systemdnetes.Domain.Node (NodeName (..))
import Systemdnetes.Domain.WireGuard
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.WireGuard"
    [ testPropertyNamed "renderSetPeerArgs has 7 elements" "prop_setPeerArgCount" prop_setPeerArgCount,
      testPropertyNamed "renderSetPeerArgs contains peer key" "prop_setPeerContainsKey" prop_setPeerContainsKey,
      testPropertyNamed "renderSetPeerArgs contains allowed-ips" "prop_setPeerAllowedIps" prop_setPeerAllowedIps,
      testPropertyNamed "renderRemovePeerArgs has 6 elements" "prop_removePeerArgCount" prop_removePeerArgCount,
      testPropertyNamed "renderRemovePeerArgs ends with remove" "prop_removePeerEndsRemove" prop_removePeerEndsRemove
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genPubKey :: Gen WgPublicKey
genPubKey = WgPublicKey <$> Gen.text (Range.singleton 44) Gen.alphaNum

genPeer :: Gen WgPeer
genPeer =
  WgPeer
    <$> genPubKey
    <*> (IPv4 <$> Gen.word32 Range.linearBounded)
    <*> (NodeName <$> genText)

prop_setPeerArgCount :: Property
prop_setPeerArgCount = property $ do
  iface <- forAll genText
  peer <- forAll genPeer
  length (renderSetPeerArgs iface peer) === 7

prop_setPeerContainsKey :: Property
prop_setPeerContainsKey = property $ do
  iface <- forAll genText
  peer <- forAll genPeer
  let args = renderSetPeerArgs iface peer
  assert $ unWgPublicKey (peerPublicKey peer) `elem` args

prop_setPeerAllowedIps :: Property
prop_setPeerAllowedIps = property $ do
  iface <- forAll genText
  peer <- forAll genPeer
  let args = renderSetPeerArgs iface peer
  assert $ any (T.isSuffixOf "/32") args

prop_removePeerArgCount :: Property
prop_removePeerArgCount = property $ do
  iface <- forAll genText
  pubkey <- forAll genPubKey
  length (renderRemovePeerArgs iface pubkey) === 6

prop_removePeerEndsRemove :: Property
prop_removePeerEndsRemove = property $ do
  iface <- forAll genText
  pubkey <- forAll genPubKey
  let args = renderRemovePeerArgs iface pubkey
  last args === "remove"
