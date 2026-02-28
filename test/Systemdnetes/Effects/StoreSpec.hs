module Systemdnetes.Effects.StoreSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Domain.Pod (FlakeRef (..), Pod (..), PodName (..), PodSpec (..), PodState (..), ResourceRequests (..))
import Systemdnetes.Effects.Store
import Systemdnetes.Effects.Store.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.Store"
    [ testPropertyNamed "submitPod then getPod returns the pod" "prop_submitGet" prop_submitGet,
      testPropertyNamed "submitPod then listPods includes it" "prop_submitList" prop_submitList,
      testPropertyNamed "submitted pod starts in Pending state" "prop_submitPending" prop_submitPending,
      testPropertyNamed "deletePod then getPod returns Nothing" "prop_deleteGet" prop_deleteGet,
      testPropertyNamed "listPods on empty store returns []" "prop_listEmpty" prop_listEmpty,
      testPropertyNamed "getPod on unknown name returns Nothing" "prop_getUnknown" prop_getUnknown
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

genPodSpec :: Gen PodSpec
genPodSpec =
  (PodSpec . PodName <$> genText)
    <*> (FlakeRef <$> genText)
    <*> (ResourceRequests <$> genText <*> genText)
    <*> Gen.int (Range.linear 1 10)

prop_submitGet :: Property
prop_submitGet = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        getPod (podName spec)
  case result of
    Just pod -> podSpec pod === spec
    Nothing -> failure

prop_submitList :: Property
prop_submitList = property $ do
  spec <- forAll genPodSpec
  let (_, pods) = run $ storeToPure Map.empty $ do
        submitPod spec
        listPods
  length pods === 1

prop_submitPending :: Property
prop_submitPending = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        getPod (podName spec)
  case result of
    Just pod -> do
      podState pod === Pending
      podNode pod === Nothing
    Nothing -> failure

prop_deleteGet :: Property
prop_deleteGet = property $ do
  spec <- forAll genPodSpec
  let (_, result) = run $ storeToPure Map.empty $ do
        submitPod spec
        deletePod (podName spec)
        getPod (podName spec)
  result === Nothing

prop_listEmpty :: Property
prop_listEmpty = property $ do
  let (_, pods) = run $ storeToPure Map.empty listPods
  pods === []

prop_getUnknown :: Property
prop_getUnknown = property $ do
  name <- forAll (PodName <$> genText)
  let (_, result) = run $ storeToPure Map.empty (getPod name)
  result === Nothing
