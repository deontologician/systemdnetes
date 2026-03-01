module Systemdnetes.Deploy.Redeploy
  ( redeploy,
  )
where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS8
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Systemdnetes.Deploy.Bootstrap (checkPrereqs, pollHealth, registerNode, verifyNodes)
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Config
import Systemdnetes.Deploy.Fly
import Systemdnetes.Deploy.HttpReq
import Systemdnetes.Deploy.Nix
import Systemdnetes.Deploy.Skopeo
import Systemdnetes.Effects.Log

-- | Redeploy: rebuild images, push, update orchestrator + workers,
-- re-register nodes (in-memory node store is lost on restart).
redeploy ::
  (Member Log r, Member Cmd r, Member HttpReq r) =>
  DeployConfig ->
  Sem r (Either Text ())
redeploy cfg = runEither $ do
  let app = deployFlyApp cfg
      appName = flyAppName app
      registryOrch = "registry.fly.io/" <> appName <> ":latest"
      registryWorker = "registry.fly.io/" <> appName <> ":worker"
      apiBase = "https://" <> appName <> ".fly.dev"

  -- 1. Check prerequisites
  liftE checkPrereqs

  -- 2. Build + push both images
  liftE $ nixBuild ".#container" "result-container"
  liftE $ nixBuild ".#worker" "result-worker"
  liftE $ pushImage "result-container" registryOrch
  liftE $ pushImage "result-worker" registryWorker

  -- 3. Deploy orchestrator
  liftE $ deploy app registryOrch

  -- 4. List machines, get worker IDs
  machinesJson <- liftE $ listMachines app
  machines <- case Aeson.eitherDecode (LBS8.pack (T.unpack machinesJson)) of
    Right ms -> pure (ms :: [FlyMachine])
    Left err -> failE ("Failed to parse machine list: " <> T.pack err)

  let workers = filter (T.isPrefixOf "worker-" . machineName) machines

  -- 5. Update each worker
  mapM_
    (\m -> liftE $ updateMachine app (machineId m) registryWorker)
    workers

  -- 6. Poll health
  liftE $ pollHealth apiBase 30

  -- 7. Re-register nodes
  mapM_
    ( \m ->
        case machinePrivateIp m of
          Just ip -> liftE $ registerNode apiBase (machineName m) ip
          Nothing -> failE ("Worker " <> machineName m <> " has no private IP")
    )
    workers

  liftE $ verifyNodes apiBase

-- Same EitherT helpers as Bootstrap (re-defined to keep modules self-contained).

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

failE :: (Monad m) => e -> EitherT e m a
failE = EitherT . pure . Left
