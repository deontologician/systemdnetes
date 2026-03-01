module Systemdnetes.Deploy.ConfigSpec (tests) where

import Data.Either (isLeft, isRight)
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Deploy.Config
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Deploy.Config"
    [ testPropertyNamed "parses valid fly.toml" "prop_validToml" prop_validToml,
      testPropertyNamed "parses app name correctly" "prop_appName" prop_appName,
      testPropertyNamed "parses region correctly" "prop_region" prop_region,
      testPropertyNamed "fails on missing app" "prop_missingApp" prop_missingApp,
      testPropertyNamed "fails on missing region" "prop_missingRegion" prop_missingRegion
    ]

genName :: Gen Text
genName = Gen.text (Range.linear 1 20) Gen.alphaNum

mkToml :: Text -> Text -> Text
mkToml app region =
  "app = \"" <> app <> "\"\nprimary_region = \"" <> region <> "\"\n"

prop_validToml :: Property
prop_validToml = property $ do
  app <- forAll genName
  region <- forAll genName
  let result = parseFlyToml (mkToml app region)
  assert $ isRight result

prop_appName :: Property
prop_appName = property $ do
  app <- forAll genName
  region <- forAll genName
  let Right flyApp = parseFlyToml (mkToml app region)
  flyAppName flyApp === app

prop_region :: Property
prop_region = property $ do
  app <- forAll genName
  region <- forAll genName
  let Right flyApp = parseFlyToml (mkToml app region)
  flyAppRegion flyApp === region

prop_missingApp :: Property
prop_missingApp = property $ do
  region <- forAll genName
  let result = parseFlyToml ("primary_region = \"" <> region <> "\"\n")
  assert $ isLeft result

prop_missingRegion :: Property
prop_missingRegion = property $ do
  app <- forAll genName
  let result = parseFlyToml ("app = \"" <> app <> "\"\n")
  assert $ isLeft result
