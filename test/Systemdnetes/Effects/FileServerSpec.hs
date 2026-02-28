module Systemdnetes.Effects.FileServerSpec (tests) where

import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Effects.FileServer
import Systemdnetes.Effects.FileServer.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.FileServer"
    [ testPropertyNamed "known file returns its content" "prop_knownFile" prop_knownFile,
      testPropertyNamed "unknown file returns empty" "prop_unknownFile" prop_unknownFile
    ]

genFilePath :: Gen FilePath
genFilePath = Gen.string (Range.linear 1 50) Gen.alphaNum

genContent :: Gen LBS.ByteString
genContent = LBS.pack <$> Gen.list (Range.linear 0 200) (Gen.word8 Range.linearBounded)

prop_knownFile :: Property
prop_knownFile = property $ do
  path <- forAll genFilePath
  content <- forAll genContent
  let files = Map.singleton path content
      result = run $ fileServerToPure files $ readStaticFile path
  result === content

prop_unknownFile :: Property
prop_unknownFile = property $ do
  path <- forAll genFilePath
  let result = run $ fileServerToPure Map.empty $ readStaticFile path
  result === ""
