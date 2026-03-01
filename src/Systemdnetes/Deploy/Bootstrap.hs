module Systemdnetes.Deploy.Bootstrap
  ( bootstrap,
    authRegistry,
    checkPrereqs,
    pollHealth,
    registerNode,
    verifyNodes,
  )
where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy.Char8 qualified as LBS8
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Config
import Systemdnetes.Deploy.Fly
import Systemdnetes.Deploy.HttpReq
import Systemdnetes.Deploy.Nix (buildImages)
import Systemdnetes.Deploy.Skopeo
import Systemdnetes.Effects.Log

-- | Full bootstrap: create app, build images, push, deploy orchestrator,
-- generate SSH keys, create workers, register nodes.
bootstrap ::
  (Member Log r, Member Cmd r, Member HttpReq r) =>
  DeployConfig ->
  Sem r (Either Text ())
bootstrap cfg = runEither $ do
  let app = deployFlyApp cfg
      appName = flyAppName app
      registryOrch = "registry.fly.io/" <> appName <> ":latest"
      registryWorker = "registry.fly.io/" <> appName <> ":worker"
      keyDir = deploySshKeyDir cfg
      keyPath = T.pack keyDir <> "/id_ed25519"
      pubKeyPath = keyPath <> ".pub"
      apiBase = "https://" <> appName <> ".fly.dev"

  -- 1. Check prerequisites
  liftE checkPrereqs

  -- 2. Ensure app exists
  liftE $ ensureApp app

  -- 3-4. Build images
  liftE $ buildImages cfg

  -- 5. Authenticate registry and push images
  liftE authRegistry
  liftE $ pushImage "result-container" registryOrch
  liftE $ pushImage "result-worker" registryWorker

  -- 6. Generate SSH keypair (skip if exists)
  liftE $ ensureSshKeypair keyDir keyPath

  -- 7. Set SSH secret
  privKey <- liftE $ readCmd "cat" [keyPath]
  liftE $ setSecret app "SSH_PRIVATE_KEY" (T.stripEnd privKey)

  -- 8. Deploy orchestrator
  liftE $ deploy app registryOrch

  -- 9. Poll health
  liftE $ pollHealth apiBase 30

  -- 10. Create workers
  pubKey <- liftE $ readCmd "cat" [pubKeyPath]
  let cleanPubKey = T.stripEnd pubKey
  mapM_
    ( \i -> do
        let name = "worker-" <> T.pack (show (i :: Int))
        liftE $ createWorker app registryWorker name cleanPubKey
    )
    [1 .. deployWorkerCount cfg]

  -- 11. List machines to get 6PN addresses
  machinesJson <- liftE $ listMachines app
  machines <- case Aeson.eitherDecode (LBS8.pack (T.unpack machinesJson)) of
    Right ms -> pure (ms :: [FlyMachine])
    Left err -> failE ("Failed to parse machine list: " <> T.pack err)

  let workers = filter (T.isPrefixOf "worker-" . machineName) machines

  -- 12. Register nodes
  mapM_
    ( \m ->
        case machinePrivateIp m of
          Just ip -> liftE $ registerNode apiBase (machineName m) ip
          Nothing -> failE ("Worker " <> machineName m <> " has no private IP")
    )
    workers

  -- 13. Verify
  liftE $ verifyNodes apiBase

-- | Authenticate with the Fly docker registry.
authRegistry :: (Member Cmd r, Member Log r) => Sem r (Either Text ())
authRegistry = do
  logInfo "Authenticating with Fly registry"
  runCmd_ "fly" ["auth", "docker"]

-- | Check that required tools are installed.
-- Uses tool-specific version commands since not all tools support --version.
checkPrereqs :: (Member Cmd r, Member Log r) => Sem r (Either Text ())
checkPrereqs = runEither $ do
  lift $ logInfo "Checking prerequisites"
  mapM_
    ( \(tool, args) -> do
        result <- lift $ runCmd tool args ""
        if cmdExitCode result == 0
          then pure ()
          else failE (tool <> " is not installed")
    )
    [ ("fly", ["version"]),
      ("skopeo", ["--version"]),
      ("nix", ["--version"])
    ]

-- | Ensure SSH keypair exists, creating it if necessary.
ensureSshKeypair :: (Member Cmd r, Member Log r) => FilePath -> Text -> Sem r (Either Text ())
ensureSshKeypair keyDir keyPath = runEither $ do
  liftE $ runCmd_ "mkdir" ["-p", T.pack keyDir]
  exists <- lift $ do
    result <- runCmd "test" ["-f", keyPath] ""
    pure (cmdExitCode result == 0)
  if exists
    then lift $ logInfo "SSH keypair already exists"
    else do
      lift $ logInfo "Generating SSH keypair"
      liftE $ runCmd_ "ssh-keygen" ["-t", "ed25519", "-f", keyPath, "-N", ""]

-- | Poll the health endpoint until it returns 200.
pollHealth :: (Member HttpReq r, Member Log r) => Text -> Int -> Sem r (Either Text ())
pollHealth apiBase maxRetries = go 0
  where
    url = apiBase <> "/healthz"
    go n
      | n >= maxRetries = pure (Left ("Health check failed after " <> T.pack (show maxRetries) <> " retries"))
      | otherwise = do
          logInfo ("Health check attempt " <> T.pack (show (n + 1)))
          resp <- httpGet url
          if httpStatus resp == 200
            then do
              logInfo "Health check passed"
              pure (Right ())
            else go (n + 1)

-- | Register a node with the API.
registerNode :: (Member HttpReq r, Member Log r) => Text -> Text -> Text -> Sem r (Either Text ())
registerNode apiBase name addr = do
  logInfo ("Registering node " <> name <> " at " <> addr)
  let body = "{\"nodeName\":\"" <> TE.encodeUtf8 name <> "\",\"nodeAddress\":\"" <> TE.encodeUtf8 addr <> "\"}"
  resp <- httpPost (apiBase <> "/api/v1/nodes") (LBS.fromStrict body)
  if httpStatus resp >= 200 && httpStatus resp < 300
    then pure (Right ())
    else pure (Left ("Failed to register node " <> name <> ": status " <> T.pack (show (httpStatus resp))))

-- | Verify nodes are registered.
verifyNodes :: (Member HttpReq r, Member Log r) => Text -> Sem r (Either Text ())
verifyNodes apiBase = do
  logInfo "Verifying nodes"
  resp <- httpGet (apiBase <> "/api/v1/nodes")
  if httpStatus resp == 200
    then do
      logInfo "Nodes verified successfully"
      pure (Right ())
    else pure (Left ("Failed to verify nodes: status " <> T.pack (show (httpStatus resp))))

-- Tiny Either-based control flow helpers to avoid deeply nested case chains.

newtype EitherT e m a = EitherT {runEitherT :: m (Either e a)}

instance (Functor m) => Functor (EitherT e m) where
  fmap f (EitherT m) = EitherT (fmap (fmap f) m)

instance (Monad m) => Applicative (EitherT e m) where
  pure = EitherT . pure . Right
  EitherT mf <*> EitherT ma = EitherT $ do
    ef <- mf
    case ef of
      Left e -> pure (Left e)
      Right f -> fmap (fmap f) ma

instance (Monad m) => Monad (EitherT e m) where
  EitherT m >>= f = EitherT $ do
    ea <- m
    case ea of
      Left e -> pure (Left e)
      Right a -> runEitherT (f a)

runEither :: EitherT e (Sem r) a -> Sem r (Either e a)
runEither = runEitherT

liftE :: (Monad m) => m (Either e a) -> EitherT e m a
liftE = EitherT

lift :: (Monad m) => m a -> EitherT e m a
lift = EitherT . fmap Right

failE :: (Monad m) => e -> EitherT e m a
failE = EitherT . pure . Left
