module Systemdnetes.Domain.NetworkSpec (tests) where

import Data.List (nub)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Network
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Network"
    [ testPropertyNamed "IP text roundtrip" "prop_ipTextRoundtrip" prop_ipTextRoundtrip,
      testPropertyNamed "parseCidr valid" "prop_parseCidr" prop_parseCidr,
      testPropertyNamed "CIDR containment" "prop_cidrContains" prop_cidrContains,
      testPropertyNamed "nth host in bounds" "prop_nthHostInBounds" prop_nthHostInBounds,
      testPropertyNamed "nth host out of bounds" "prop_nthHostOob" prop_nthHostOob,
      testPropertyNamed "hosts are distinct" "prop_hostsDistinct" prop_hostsDistinct
    ]

genIPv4 :: Gen IPv4
genIPv4 = IPv4 <$> Gen.word32 Range.linearBounded

genOctet :: Gen Word32
genOctet = Gen.word32 (Range.linear 0 255)

showT :: (Show a) => a -> Text
showT = T.pack . show

prop_ipTextRoundtrip :: Property
prop_ipTextRoundtrip = property $ do
  ip <- forAll genIPv4
  textToIPv4 (ipToText ip) === Just ip

prop_parseCidr :: Property
prop_parseCidr = property $ do
  a <- forAll genOctet
  b <- forAll genOctet
  c <- forAll genOctet
  d <- forAll genOctet
  prefix <- forAll $ Gen.int (Range.linear 0 32)
  let txt = ipToText (IPv4 (a * 16777216 + b * 65536 + c * 256 + d)) <> "/" <> showT prefix
  case parseCidr txt of
    Just cidr -> cidrPrefix cidr === prefix
    Nothing -> failure

prop_cidrContains :: Property
prop_cidrContains = property $ do
  prefix <- forAll $ Gen.int (Range.linear 8 28)
  base <- forAll genIPv4
  let Just cidr = parseCidr (ipToText base <> "/" <> showT prefix)
  -- The base network address should be contained
  assert $ cidrContains cidr (cidrBase cidr)
  -- Every nth host should be contained
  n <- forAll $ Gen.word32 (Range.linear 0 (min 100 (cidrHostCount cidr - 1)))
  case cidrNthHost cidr n of
    Just ip -> assert $ cidrContains cidr ip
    Nothing -> failure

prop_nthHostInBounds :: Property
prop_nthHostInBounds = property $ do
  prefix <- forAll $ Gen.int (Range.linear 16 28)
  base <- forAll genIPv4
  let Just cidr = parseCidr (ipToText base <> "/" <> showT prefix)
      count = cidrHostCount cidr
  n <- forAll $ Gen.word32 (Range.linear 0 (count - 1))
  assert $ isJust (cidrNthHost cidr n)

prop_nthHostOob :: Property
prop_nthHostOob = property $ do
  prefix <- forAll $ Gen.int (Range.linear 16 28)
  base <- forAll genIPv4
  let Just cidr = parseCidr (ipToText base <> "/" <> showT prefix)
      count = cidrHostCount cidr
  n <- forAll $ Gen.word32 (Range.linear count (count + 100))
  assert $ isNothing (cidrNthHost cidr n)

prop_hostsDistinct :: Property
prop_hostsDistinct = property $ do
  prefix <- forAll $ Gen.int (Range.linear 24 28)
  base <- forAll genIPv4
  let Just cidr = parseCidr (ipToText base <> "/" <> showT prefix)
      count = cidrHostCount cidr
      hosts = [cidrNthHost cidr i | i <- [0 .. count - 1]]
  length (nub hosts) === fromIntegral count
