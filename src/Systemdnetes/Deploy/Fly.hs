module Systemdnetes.Deploy.Fly
  ( FlyMachine (..),
    appExists,
    ensureApp,
    deploy,
    setSecret,
    createWorker,
    listMachines,
    updateMachine,
    waitForMachine,
  )
where

import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Config (FlyApp (..))
import Systemdnetes.Effects.Log

data FlyMachine = FlyMachine
  { machineId :: Text,
    machineName :: Text,
    machinePrivateIp :: Maybe Text
  }
  deriving stock (Eq, Show)

instance FromJSON FlyMachine where
  parseJSON = withObject "FlyMachine" $ \o ->
    FlyMachine
      <$> o .: "id"
      <*> o .: "name"
      <*> o .:? "private_ip"

-- | Check if a Fly app already exists.
appExists :: (Member Cmd r) => FlyApp -> Sem r Bool
appExists app = do
  result <- runCmd "fly" ["status", "--app", flyAppName app] ""
  pure (cmdExitCode result == 0)

-- | Create the Fly app if it doesn't exist.
ensureApp :: (Member Cmd r, Member Log r) => FlyApp -> Sem r (Either Text ())
ensureApp app = do
  exists <- appExists app
  if exists
    then do
      logInfo ("App " <> flyAppName app <> " already exists")
      pure (Right ())
    else do
      logInfo ("Creating app " <> flyAppName app)
      runCmd_ "fly" ["apps", "create", flyAppName app, "--org", "personal"]

-- | Deploy the orchestrator image using fly deploy.
deploy :: (Member Cmd r, Member Log r) => FlyApp -> Text -> Sem r (Either Text ())
deploy app image = do
  logInfo ("Deploying " <> image <> " to " <> flyAppName app)
  runCmd_ "fly" ["deploy", "--app", flyAppName app, "--image", image]

-- | Set a Fly secret.
setSecret :: (Member Cmd r, Member Log r) => FlyApp -> Text -> Text -> Sem r (Either Text ())
setSecret app key value = do
  logInfo ("Setting secret " <> key)
  result <- runCmd "fly" ["secrets", "set", key <> "=" <> value, "--app", flyAppName app] ""
  pure $
    if cmdExitCode result == 0
      then Right ()
      else Left (cmdStderr result)

-- | Create a worker machine.
createWorker ::
  (Member Cmd r, Member Log r) =>
  FlyApp ->
  Text ->
  Text ->
  Text ->
  Sem r (Either Text ())
createWorker app image workerName pubKey = do
  logInfo ("Creating worker " <> workerName)
  runCmd_
    "fly"
    [ "machine",
      "run",
      image,
      "--name",
      workerName,
      "--region",
      flyAppRegion app,
      "--app",
      flyAppName app,
      "--env",
      "SSH_AUTHORIZED_KEYS=" <> pubKey
    ]

-- | List machines as JSON text (caller parses).
listMachines :: (Member Cmd r) => FlyApp -> Sem r (Either Text Text)
listMachines app =
  readCmd "fly" ["machine", "list", "--json", "--app", flyAppName app]

-- | Update a machine's image.
updateMachine :: (Member Cmd r, Member Log r) => FlyApp -> Text -> Text -> Sem r (Either Text ())
updateMachine app machineId' image = do
  logInfo ("Updating machine " <> machineId' <> " to " <> image)
  runCmd_ "fly" ["machine", "update", machineId', "--image", image, "--app", flyAppName app, "--yes"]

-- | Wait for a machine to reach started state.
waitForMachine :: (Member Cmd r) => FlyApp -> Text -> Sem r (Either Text ())
waitForMachine app machineId' =
  runCmd_
    "fly"
    [ "machine",
      "wait",
      machineId',
      "--state",
      "started",
      "--app",
      flyAppName app,
      "--timeout",
      T.pack (show (60 :: Int))
    ]
