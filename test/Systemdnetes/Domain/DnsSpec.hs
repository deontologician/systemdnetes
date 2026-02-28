module Systemdnetes.Domain.DnsSpec (tests) where

import Data.List (isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Dns
import Systemdnetes.Domain.Network (IPv4 (..), ipToText)
import Systemdnetes.Domain.Pod (PodName (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Dns"
    [ testPropertyNamed "renderHostsEntry contains IP" "prop_entryContainsIp" prop_entryContainsIp,
      testPropertyNamed "renderHostsEntry contains hostname" "prop_entryContainsHostname" prop_entryContainsHostname,
      testPropertyNamed "renderHostsFile line count" "prop_fileLineCount" prop_fileLineCount,
      testPropertyNamed "hostsFileName has .hosts suffix" "prop_fileNameSuffix" prop_fileNameSuffix
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 20) Gen.alphaNum

genEntry :: Gen HostsEntry
genEntry =
  HostsEntry
    <$> (IPv4 <$> Gen.word32 Range.linearBounded)
    <*> genText
    <*> (PodName <$> genText)

prop_entryContainsIp :: Property
prop_entryContainsIp = property $ do
  entry <- forAll genEntry
  let rendered = renderHostsEntry entry
  assert $ T.isInfixOf (ipToText (hostsIp entry)) rendered

prop_entryContainsHostname :: Property
prop_entryContainsHostname = property $ do
  entry <- forAll genEntry
  let rendered = renderHostsEntry entry
  assert $ T.isInfixOf (hostsHostname entry) rendered

prop_fileLineCount :: Property
prop_fileLineCount = property $ do
  entries <- forAll $ Gen.list (Range.linear 0 10) genEntry
  let rendered = renderHostsFile entries
      -- T.unlines adds a trailing newline, so split gives n+1 elements
      lineCount = if T.null rendered then 0 else length (T.lines rendered)
  lineCount === length entries

prop_fileNameSuffix :: Property
prop_fileNameSuffix = property $ do
  name <- forAll genText
  let fname = hostsFileName (PodName name)
  assert $ ".hosts" `isSuffixOf` fname
