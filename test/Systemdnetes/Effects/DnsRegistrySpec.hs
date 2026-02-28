module Systemdnetes.Effects.DnsRegistrySpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Dns (HostsEntry (..))
import Systemdnetes.Domain.Network (IPv4 (..))
import Systemdnetes.Domain.Pod (PodName (..))
import Systemdnetes.Effects.DnsRegistry
import Systemdnetes.Effects.DnsRegistry.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.DnsRegistry"
    [ testPropertyNamed "register then list includes entry" "prop_registerList" prop_registerList,
      testPropertyNamed "unregister then list excludes entry" "prop_unregisterList" prop_unregisterList,
      testPropertyNamed "register overwrites existing" "prop_registerOverwrite" prop_registerOverwrite,
      testPropertyNamed "list on empty returns []" "prop_listEmpty" prop_listEmpty
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genPodName :: Gen PodName
genPodName = PodName <$> genText

genEntry :: Gen HostsEntry
genEntry =
  HostsEntry
    <$> (IPv4 <$> Gen.word32 Range.linearBounded)
    <*> genText
    <*> genPodName

runPure :: Sem (DnsRegistry ': r) a -> Sem r (DnsRegistryState, a)
runPure = dnsRegistryToPure Map.empty

prop_registerList :: Property
prop_registerList = property $ do
  podName <- forAll genPodName
  entry <- forAll genEntry
  let (_, entries) = run $ runPure $ do
        registerPodDns podName entry
        listDnsEntries
  length entries === 1
  case entries of
    [(pn, e)] -> do
      pn === podName
      e === entry
    _ -> failure

prop_unregisterList :: Property
prop_unregisterList = property $ do
  podName <- forAll genPodName
  entry <- forAll genEntry
  let (_, entries) = run $ runPure $ do
        registerPodDns podName entry
        unregisterPodDns podName
        listDnsEntries
  entries === []

prop_registerOverwrite :: Property
prop_registerOverwrite = property $ do
  podName <- forAll genPodName
  entry1 <- forAll genEntry
  entry2 <- forAll genEntry
  let (_, entries) = run $ runPure $ do
        registerPodDns podName entry1
        registerPodDns podName entry2
        listDnsEntries
  length entries === 1
  case entries of
    [(_, e)] -> e === entry2
    _ -> failure

prop_listEmpty :: Property
prop_listEmpty = property $ do
  let (_, entries) = run $ runPure listDnsEntries
  entries === []
