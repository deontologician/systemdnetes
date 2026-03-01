module Systemdnetes.Deploy.BootstrapSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Hedgehog
import Polysemy
import Systemdnetes.Deploy.App
import Systemdnetes.Deploy.Bootstrap
import Systemdnetes.Deploy.Cmd (CmdResult (..))
import Systemdnetes.Deploy.Config
import Systemdnetes.Deploy.HttpReq (HttpResponse (..))
import Systemdnetes.Effects.Log (LogMessage (..), logMessageContent)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

tests :: TestTree
tests =
  testGroup
    "Systemdnetes.Deploy.Bootstrap"
    [ testPropertyNamed "bootstrap succeeds with cooperative stubs" "prop_bootstrapSuccess" prop_bootstrapSuccess,
      testPropertyNamed "bootstrap fails when prereq missing" "prop_bootstrapPrereqFail" prop_bootstrapPrereqFail,
      testPropertyNamed "bootstrap logs key actions" "prop_bootstrapLogs" prop_bootstrapLogs
    ]

testConfig :: DeployConfig
testConfig =
  DeployConfig
    { deployFlyApp = FlyApp "test-app" "ord",
      deployWorkerCount = 2,
      deploySshKeyDir = "/tmp/test-ssh"
    }

-- | A handler that succeeds for all known deploy commands.
cooperativeCmdHandler :: Text -> [Text] -> Maybe CmdResult
cooperativeCmdHandler "fly" ("status" : _) = Just (CmdResult 0 "" "")
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
cooperativeCmdHandler "mkdir" _ = Just (CmdResult 0 "" "")
cooperativeCmdHandler "test" _ = Just (CmdResult 0 "" "")
cooperativeCmdHandler "cat" ["/tmp/test-ssh/id_ed25519"] = Just (CmdResult 0 "private-key-content\n" "")
cooperativeCmdHandler "cat" ["/tmp/test-ssh/id_ed25519.pub"] = Just (CmdResult 0 "ssh-ed25519 AAAA...\n" "")
cooperativeCmdHandler "ssh-keygen" _ = Just (CmdResult 0 "" "")
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

prop_bootstrapSuccess :: Property
prop_bootstrapSuccess = property $ do
  let result = runDeployPure cooperativeConfig (bootstrap testConfig)
  deployResultValue result === Right ()

prop_bootstrapPrereqFail :: Property
prop_bootstrapPrereqFail = property $ do
  let failHandler _ _ = Nothing
      cfg =
        DeployPureConfig
          { pureCmdHandler = failHandler,
            pureHttpHandler = cooperativeHttpHandler
          }
      result = runDeployPure cfg (bootstrap testConfig)
  case deployResultValue result of
    Left err -> assert $ T.isInfixOf "not installed" err
    Right () -> failure

prop_bootstrapLogs :: Property
prop_bootstrapLogs = property $ do
  let result = runDeployPure cooperativeConfig (bootstrap testConfig)
      logTexts = map logMessageContent (deployResultLogs result)
  assert $ any (T.isInfixOf "prerequisites") logTexts
  assert $ any (T.isInfixOf "Building") logTexts
  assert $ any (T.isInfixOf "Deploying") logTexts
