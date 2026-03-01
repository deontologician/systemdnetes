module Systemdnetes.Deploy.RedeploySpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Polysemy
import Systemdnetes.Deploy.App
import Systemdnetes.Deploy.Cmd (CmdResult (..))
import Systemdnetes.Deploy.Config
import Systemdnetes.Deploy.HttpReq (HttpResponse (..))
import Systemdnetes.Deploy.Redeploy
import Systemdnetes.Effects.Log (LogMessage (..), logMessageContent)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Deploy.Redeploy"
    [ testPropertyNamed "redeploy succeeds with cooperative stubs" "prop_redeploySuccess" prop_redeploySuccess,
      testPropertyNamed "redeploy fails when prereq missing" "prop_redeployPrereqFail" prop_redeployPrereqFail,
      testPropertyNamed "redeploy logs update actions" "prop_redeployLogs" prop_redeployLogs
    ]

testConfig :: DeployConfig
testConfig =
  DeployConfig
    { deployFlyApp = FlyApp "test-app" "ord",
      deployWorkerCount = 2,
      deploySshKeyDir = "/tmp/test-ssh"
    }

cooperativeCmdHandler :: Text -> [Text] -> Maybe CmdResult
cooperativeCmdHandler "fly" ("machine" : "list" : _) =
  Just
    ( CmdResult
        0
        "[{\"id\":\"m1\",\"name\":\"worker-1\",\"private_ip\":\"fdaa::1\"},{\"id\":\"m2\",\"name\":\"worker-2\",\"private_ip\":\"fdaa::2\"}]"
        ""
    )
cooperativeCmdHandler "fly" _ = Just (CmdResult 0 "" "")
cooperativeCmdHandler "skopeo" _ = Just (CmdResult 0 "" "")
cooperativeCmdHandler "nix" _ = Just (CmdResult 0 "" "")
cooperativeCmdHandler _ _ = Nothing

cooperativeHttpHandler :: Text -> Maybe HttpResponse
cooperativeHttpHandler url
  | "/healthz" `T.isSuffixOf` url = Just (HttpResponse 200 "ok")
  | "/api/v1/nodes" `T.isSuffixOf` url = Just (HttpResponse 200 "[]")
  | otherwise = Nothing

cooperativeConfig :: DeployPureConfig
cooperativeConfig =
  DeployPureConfig
    { pureCmdHandler = cooperativeCmdHandler,
      pureHttpHandler = cooperativeHttpHandler
    }

prop_redeploySuccess :: Property
prop_redeploySuccess = property $ do
  let result = runDeployPure cooperativeConfig (redeploy testConfig)
  deployResultValue result === Right ()

prop_redeployPrereqFail :: Property
prop_redeployPrereqFail = property $ do
  let failHandler _ _ = Nothing
      cfg =
        DeployPureConfig
          { pureCmdHandler = failHandler,
            pureHttpHandler = cooperativeHttpHandler
          }
      result = runDeployPure cfg (redeploy testConfig)
  case deployResultValue result of
    Left err -> assert $ T.isInfixOf "not installed" err
    Right () -> failure

prop_redeployLogs :: Property
prop_redeployLogs = property $ do
  let result = runDeployPure cooperativeConfig (redeploy testConfig)
      logTexts = map logMessageContent (deployResultLogs result)
  assert $ any (T.isInfixOf "Building") logTexts
  assert $ any (T.isInfixOf "Deploying") logTexts
  assert $ any (T.isInfixOf "Updating machine") logTexts
