module Systemdnetes.Effects.LogSpec (tests) where

import Data.Text (Text)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Polysemy
import Systemdnetes.Effects.Log
import Systemdnetes.Effects.Log.Interpreter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Effects.Log"
    [ testPropertyNamed "single logMsg produces one message" "prop_logMsgSingle" prop_logMsgSingle,
      testPropertyNamed "logMsg preserves level" "prop_logMsgLevel" prop_logMsgLevel,
      testPropertyNamed "logMsg preserves content" "prop_logMsgContent" prop_logMsgContent,
      testPropertyNamed "multiple messages collected in order" "prop_logMsgOrder" prop_logMsgOrder,
      testPropertyNamed "convenience functions use correct level" "prop_convenienceLevels" prop_convenienceLevels
    ]

genLogLevel :: Gen LogLevel
genLogLevel = Gen.element [Debug, Info, Warn, Error]

genText :: Gen Text
genText = Gen.text (Range.linear 0 100) Gen.unicode

prop_logMsgSingle :: Property
prop_logMsgSingle = property $ do
  level <- forAll genLogLevel
  msg <- forAll genText
  let (msgs, ()) = run . logToList $ logMsg level msg
  length msgs === 1

prop_logMsgLevel :: Property
prop_logMsgLevel = property $ do
  level <- forAll genLogLevel
  msg <- forAll genText
  let (msgs, ()) = run . logToList $ logMsg level msg
  case msgs of
    [m] -> logMessageLevel m === level
    _ -> failure

prop_logMsgContent :: Property
prop_logMsgContent = property $ do
  level <- forAll genLogLevel
  msg <- forAll genText
  let (msgs, ()) = run . logToList $ logMsg level msg
  case msgs of
    [m] -> logMessageContent m === msg
    _ -> failure

prop_logMsgOrder :: Property
prop_logMsgOrder = property $ do
  levels <- forAll $ Gen.list (Range.linear 1 20) genLogLevel
  let program = mapM_ (`logMsg` "msg") levels
      (msgs, ()) = run . logToList $ program
  map logMessageLevel msgs === levels

prop_convenienceLevels :: Property
prop_convenienceLevels = property $ do
  msg <- forAll genText
  let (msgs, ()) =
        run . logToList $ do
          logDebug msg
          logInfo msg
          logWarn msg
          logError msg
  map logMessageLevel msgs === [Debug, Info, Warn, Error]
