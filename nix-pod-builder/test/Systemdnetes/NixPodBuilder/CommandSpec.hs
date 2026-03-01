module Systemdnetes.NixPodBuilder.CommandSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Network (IPv4 (..), ipToText)
import Systemdnetes.Domain.Pod (FlakeRef (..), PodName (..))
import Systemdnetes.NixPodBuilder.Command
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.NixPodBuilder.Command"
    [ testPropertyNamed "command contains flake ref" "prop_commandContainsFlakeRef" prop_commandContainsFlakeRef,
      testPropertyNamed "command contains pod name" "prop_commandContainsPodName" prop_commandContainsPodName,
      testPropertyNamed "command starts with nix build" "prop_commandStartsWithNixBuild" prop_commandStartsWithNixBuild,
      testPropertyNamed "command includes --impure" "prop_commandIncludesImpure" prop_commandIncludesImpure,
      testPropertyNamed "expression references compose-pod.nix path" "prop_exprReferencesComposePodPath" prop_exprReferencesComposePodPath,
      testPropertyNamed "with IP contains IP text" "prop_withIpContainsIpText" prop_withIpContainsIpText,
      testPropertyNamed "without IP omits podIp" "prop_withoutIpOmitsPodIp" prop_withoutIpOmitsPodIp,
      testPropertyNamed "shell quoting handles single quotes" "prop_shellQuotingHandlesSingleQuotes" prop_shellQuotingHandlesSingleQuotes
    ]

-- Generators

genAlphaNumText :: Gen Text
genAlphaNumText = Gen.text (Range.linear 1 30) Gen.alphaNum

genPodName :: Gen PodName
genPodName = PodName <$> genAlphaNumText

genFlakeRef :: Gen FlakeRef
genFlakeRef = do
  owner <- genAlphaNumText
  repo <- genAlphaNumText
  pure $ FlakeRef ("github:" <> owner <> "/" <> repo)

genIPv4 :: Gen IPv4
genIPv4 = do
  a <- Gen.word32 (Range.linear 1 254)
  b <- Gen.word32 (Range.linear 0 255)
  c <- Gen.word32 (Range.linear 0 255)
  d <- Gen.word32 (Range.linear 1 254)
  pure $ IPv4 (a * 16777216 + b * 65536 + c * 256 + d)

cfg :: PodBuildConfig
cfg = defaultPodBuildConfig

-- Properties

prop_commandContainsFlakeRef :: Property
prop_commandContainsFlakeRef = property $ do
  name <- forAll genPodName
  flake@(FlakeRef flakeText) <- forAll genFlakeRef
  let cmd = buildPodCommand cfg name flake Nothing
  assert $ T.isInfixOf flakeText cmd

prop_commandContainsPodName :: Property
prop_commandContainsPodName = property $ do
  name@(PodName nameText) <- forAll genPodName
  flake <- forAll genFlakeRef
  let cmd = buildPodCommand cfg name flake Nothing
  assert $ T.isInfixOf nameText cmd

prop_commandStartsWithNixBuild :: Property
prop_commandStartsWithNixBuild = property $ do
  name <- forAll genPodName
  flake <- forAll genFlakeRef
  let cmd = buildPodCommand cfg name flake Nothing
  assert $ T.isPrefixOf "nix build" cmd

prop_commandIncludesImpure :: Property
prop_commandIncludesImpure = property $ do
  name <- forAll genPodName
  flake <- forAll genFlakeRef
  let cmd = buildPodCommand cfg name flake Nothing
  assert $ T.isInfixOf "--impure" cmd

prop_exprReferencesComposePodPath :: Property
prop_exprReferencesComposePodPath = property $ do
  name <- forAll genPodName
  flake <- forAll genFlakeRef
  let expr = buildPodNixExpression cfg name flake Nothing
  assert $ T.isInfixOf (T.pack (pbcComposePodNixPath cfg)) expr

prop_withIpContainsIpText :: Property
prop_withIpContainsIpText = property $ do
  name <- forAll genPodName
  flake <- forAll genFlakeRef
  ip <- forAll genIPv4
  let cmd = buildPodCommand cfg name flake (Just ip)
  assert $ T.isInfixOf (ipToText ip) cmd

prop_withoutIpOmitsPodIp :: Property
prop_withoutIpOmitsPodIp = property $ do
  name <- forAll genPodName
  flake <- forAll genFlakeRef
  let expr = buildPodNixExpression cfg name flake Nothing
  assert $ not (T.isInfixOf "podIp" expr)

prop_shellQuotingHandlesSingleQuotes :: Property
prop_shellQuotingHandlesSingleQuotes = property $ do
  let name = PodName "test's-pod"
      flake = FlakeRef "github:user/it's-a-repo"
      cmd = buildPodCommand cfg name flake Nothing
  -- The command should still be well-formed (not crash, contains the data)
  assert $ T.isInfixOf "nix build" cmd
  -- Single quotes in the data should be escaped via the '\"'\"' pattern
  assert $ T.isInfixOf "'\"'\"'" cmd
