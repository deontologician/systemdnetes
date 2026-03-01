module Systemdnetes.Domain.NspawnSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Systemdnetes.Domain.Nspawn
import Systemdnetes.Domain.Pod (ContainerInfo (..), ContainerState (..), PodName (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Domain.Nspawn"
    [ testPropertyNamed "parseMachinectlList empty returns []" "prop_parseListEmpty" prop_parseListEmpty,
      testPropertyNamed "parseMachinectlList running entry" "prop_parseListRunning" prop_parseListRunning,
      testPropertyNamed "parseMachinectlList multiple entries" "prop_parseListMultiple" prop_parseListMultiple,
      testPropertyNamed "parseMachinectlList skips blank lines" "prop_parseListSkipsBlanks" prop_parseListSkipsBlanks,
      testPropertyNamed "parseMachinectlState running" "prop_parseStateRunning" prop_parseStateRunning,
      testPropertyNamed "parseMachinectlState stopped" "prop_parseStateStopped" prop_parseStateStopped,
      testPropertyNamed "parseMachinectlState failed" "prop_parseStateFailed" prop_parseStateFailed,
      testPropertyNamed "parseMachinectlState unknown" "prop_parseStateUnknown" prop_parseStateUnknown,
      testPropertyNamed "parseMachinectlState strips whitespace" "prop_parseStateStrips" prop_parseStateStrips,
      testPropertyNamed "renderNspawnFile contains Boot=yes" "prop_nspawnBoot" prop_nspawnBoot,
      testPropertyNamed "renderNspawnFile contains BindReadOnly" "prop_nspawnBind" prop_nspawnBind,
      testPropertyNamed "renderMachineSetup contains pod name" "prop_setupContainsName" prop_setupContainsName,
      testPropertyNamed "renderMachineSetup contains system path" "prop_setupContainsPath" prop_setupContainsPath,
      testPropertyNamed "renderMachineSetup contains nspawn config" "prop_setupContainsNspawnConfig" prop_setupContainsNspawnConfig
    ]

genPodName :: Gen PodName
genPodName = PodName <$> Gen.text (Range.linear 1 30) Gen.alphaNum

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

prop_parseListEmpty :: Property
prop_parseListEmpty = property $ do
  parseMachinectlList "" === []

prop_parseListRunning :: Property
prop_parseListRunning = property $ do
  name <- forAll genText
  let input = name <> " running systemd-nspawn nixos -"
      result = parseMachinectlList input
  length result === 1
  containerPod (head result) === PodName name
  containerState (head result) === ContainerRunning

prop_parseListMultiple :: Property
prop_parseListMultiple = property $ do
  let input =
        T.unlines
          [ "web running systemd-nspawn nixos -",
            "db stopped systemd-nspawn nixos -"
          ]
      result = parseMachinectlList input
  length result === 2
  containerState (head result) === ContainerRunning
  containerState (result !! 1) === ContainerStopped

prop_parseListSkipsBlanks :: Property
prop_parseListSkipsBlanks = property $ do
  let input =
        T.unlines
          [ "",
            "web running systemd-nspawn nixos -",
            "",
            "  ",
            ""
          ]
  length (parseMachinectlList input) === 1

prop_parseStateRunning :: Property
prop_parseStateRunning = property $
  parseMachinectlState "running" === Just ContainerRunning

prop_parseStateStopped :: Property
prop_parseStateStopped = property $
  parseMachinectlState "stopped" === Just ContainerStopped

prop_parseStateFailed :: Property
prop_parseStateFailed = property $
  parseMachinectlState "failed" === Just ContainerFailed

prop_parseStateUnknown :: Property
prop_parseStateUnknown = property $ do
  txt <- forAll $ Gen.element ["starting", "closing", "unknown", ""]
  parseMachinectlState txt === Nothing

prop_parseStateStrips :: Property
prop_parseStateStrips = property $
  parseMachinectlState "  running  \n" === Just ContainerRunning

prop_nspawnBoot :: Property
prop_nspawnBoot = property $ do
  name <- forAll genPodName
  assert $ T.isInfixOf "Boot=yes" (renderNspawnFile name)

prop_nspawnBind :: Property
prop_nspawnBind = property $ do
  name <- forAll genPodName
  assert $ T.isInfixOf "BindReadOnly=/nix/store" (renderNspawnFile name)

prop_setupContainsName :: Property
prop_setupContainsName = property $ do
  PodName name <- forAll genPodName
  path <- forAll genText
  assert $ T.isInfixOf name (renderMachineSetup (PodName name) path)

prop_setupContainsPath :: Property
prop_setupContainsPath = property $ do
  podName <- forAll genPodName
  path <- forAll genText
  assert $ T.isInfixOf path (renderMachineSetup podName path)

prop_setupContainsNspawnConfig :: Property
prop_setupContainsNspawnConfig = property $ do
  podName <- forAll genPodName
  path <- forAll genText
  let script = renderMachineSetup podName path
  assert $ T.isInfixOf "Boot=yes" script
  assert $ T.isInfixOf "BindReadOnly=/nix/store" script
