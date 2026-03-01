module Systemdnetes.Deploy.CmdSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Cmd.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Deploy.Cmd"
    [ testPropertyNamed "known command returns canned result" "prop_knownCmd" prop_knownCmd,
      testPropertyNamed "unknown command returns exit 127" "prop_unknownCmd" prop_unknownCmd,
      testPropertyNamed "runCmd_ returns Right on exit 0" "prop_runCmdSuccess" prop_runCmdSuccess,
      testPropertyNamed "runCmd_ returns Left on non-zero exit" "prop_runCmdFailure" prop_runCmdFailure,
      testPropertyNamed "readCmd returns stdout on success" "prop_readCmdSuccess" prop_readCmdSuccess,
      testPropertyNamed "checkCmd returns True on exit 0" "prop_checkCmdTrue" prop_checkCmdTrue,
      testPropertyNamed "checkCmd returns False on non-zero exit" "prop_checkCmdFalse" prop_checkCmdFalse
    ]

genText :: Gen Text
genText = Gen.text (Range.linear 1 50) Gen.alphaNum

alwaysSucceed :: CmdHandler
alwaysSucceed _ _ = Just (CmdResult 0 "ok" "")

alwaysFail :: CmdHandler
alwaysFail _ _ = Just (CmdResult 1 "" "error")

nothingHandler :: CmdHandler
nothingHandler _ _ = Nothing

prop_knownCmd :: Property
prop_knownCmd = property $ do
  prog <- forAll genText
  stdout <- forAll genText
  let handler p _ = if p == prog then Just (CmdResult 0 stdout "") else Nothing
      result = run $ cmdToPure handler (runCmd prog [] "")
  cmdExitCode result === 0
  cmdStdout result === stdout

prop_unknownCmd :: Property
prop_unknownCmd = property $ do
  prog <- forAll genText
  let result = run $ cmdToPure nothingHandler (runCmd prog [] "")
  cmdExitCode result === 127

prop_runCmdSuccess :: Property
prop_runCmdSuccess = property $ do
  prog <- forAll genText
  let result = run $ cmdToPure alwaysSucceed (runCmd_ prog [])
  result === Right ()

prop_runCmdFailure :: Property
prop_runCmdFailure = property $ do
  prog <- forAll genText
  let result = run $ cmdToPure alwaysFail (runCmd_ prog [])
  result === Left "error"

prop_readCmdSuccess :: Property
prop_readCmdSuccess = property $ do
  prog <- forAll genText
  stdout <- forAll genText
  let handler _ _ = Just (CmdResult 0 stdout "")
      result = run $ cmdToPure handler (readCmd prog [])
  result === Right stdout

prop_checkCmdTrue :: Property
prop_checkCmdTrue = property $ do
  prog <- forAll genText
  let result = run $ cmdToPure alwaysSucceed (checkCmd prog)
  result === True

prop_checkCmdFalse :: Property
prop_checkCmdFalse = property $ do
  prog <- forAll genText
  let result = run $ cmdToPure alwaysFail (checkCmd prog)
  result === False
