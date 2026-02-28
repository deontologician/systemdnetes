module Systemdnetes.Domain.ResourceSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Resource
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Resource"
    [ testPropertyNamed "parseCpu: millicores suffix" "prop_cpuMillicores" prop_cpuMillicores,
      testPropertyNamed "parseCpu: whole cores" "prop_cpuWholeCores" prop_cpuWholeCores,
      testPropertyNamed "parseCpu: malformed returns Nothing" "prop_cpuMalformed" prop_cpuMalformed,
      testPropertyNamed "parseMemory: Mi suffix" "prop_memMi" prop_memMi,
      testPropertyNamed "parseMemory: Gi suffix" "prop_memGi" prop_memGi,
      testPropertyNamed "parseMemory: malformed returns Nothing" "prop_memMalformed" prop_memMalformed
    ]

prop_cpuMillicores :: Property
prop_cpuMillicores = property $ do
  n <- forAll $ Gen.int (Range.linear 0 100000)
  let input = T.pack (show n) <> "m"
  parseCpu input === Just (Millicores n)

prop_cpuWholeCores :: Property
prop_cpuWholeCores = property $ do
  n <- forAll $ Gen.int (Range.linear 0 128)
  let input = T.pack (show n)
  parseCpu input === Just (Millicores (n * 1000))

prop_cpuMalformed :: Property
prop_cpuMalformed = property $ do
  input <- forAll genMalformedResource
  parseCpu input === Nothing

prop_memMi :: Property
prop_memMi = property $ do
  n <- forAll $ Gen.int (Range.linear 0 1048576)
  let input = T.pack (show n) <> "Mi"
  parseMemory input === Just (Mebibytes n)

prop_memGi :: Property
prop_memGi = property $ do
  n <- forAll $ Gen.int (Range.linear 0 1024)
  let input = T.pack (show n) <> "Gi"
  parseMemory input === Just (Mebibytes (n * 1024))

prop_memMalformed :: Property
prop_memMalformed = property $ do
  input <- forAll genMalformedResource
  parseMemory input === Nothing

genMalformedResource :: Gen Text
genMalformedResource =
  Gen.element
    [ "",
      "abc",
      "m500",
      "Mi512",
      "100x",
      "-5m",
      "hello world"
    ]
