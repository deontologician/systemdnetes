module Systemdnetes.Deploy.HttpReqSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Deploy.HttpReq
import Systemdnetes.Deploy.HttpReq.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Deploy.HttpReq"
    [ testPropertyNamed "known URL returns canned response" "prop_knownUrl" prop_knownUrl,
      testPropertyNamed "unknown URL returns 404" "prop_unknownUrl" prop_unknownUrl,
      testPropertyNamed "POST to known URL returns canned response" "prop_postKnown" prop_postKnown,
      testPropertyNamed "POST to unknown URL returns 404" "prop_postUnknown" prop_postUnknown
    ]

genUrl :: Gen Text
genUrl = do
  path <- Gen.text (Range.linear 1 30) Gen.alphaNum
  pure ("https://example.com/" <> path)

prop_knownUrl :: Property
prop_knownUrl = property $ do
  url <- forAll genUrl
  let handler u = if u == url then Just (HttpResponse 200 "body") else Nothing
      result = run $ httpReqToPure handler (httpGet url)
  httpStatus result === 200
  httpBody result === "body"

prop_unknownUrl :: Property
prop_unknownUrl = property $ do
  url <- forAll genUrl
  let handler _ = Nothing
      result = run $ httpReqToPure handler (httpGet url)
  httpStatus result === 404

prop_postKnown :: Property
prop_postKnown = property $ do
  url <- forAll genUrl
  let handler u = if u == url then Just (HttpResponse 201 "created") else Nothing
      result = run $ httpReqToPure handler (httpPost url "payload")
  httpStatus result === 201

prop_postUnknown :: Property
prop_postUnknown = property $ do
  url <- forAll genUrl
  let handler _ = Nothing
      result = run $ httpReqToPure handler (httpPost url "payload")
  httpStatus result === 404
