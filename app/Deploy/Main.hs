module Main (main) where

import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import Systemdnetes.Deploy.App
import Systemdnetes.Deploy.Bootstrap (bootstrap)
import Systemdnetes.Deploy.Config
import Systemdnetes.Deploy.Redeploy (redeploy)
import Systemdnetes.Effects.Log

main :: IO ()
main = do
  args <- getArgs
  tomlText <- TIO.readFile "fly.toml"
  flyApp <- case parseFlyToml tomlText of
    Right app -> pure app
    Left err -> do
      putStrLn ("Error parsing fly.toml: " <> T.unpack err)
      exitFailure

  numWorkers <- maybe 2 read <$> lookupEnv "NUM_WORKERS"
  remoteHost <- fmap T.pack <$> lookupEnv "REMOTE_HOST"

  let cfg =
        DeployConfig
          { deployFlyApp = flyApp,
            deployWorkerCount = numWorkers,
            deploySshKeyDir = "deploy/.ssh",
            deployRemoteHost = remoteHost
          }

  case args of
    ["bootstrap"] -> do
      result <- runDeploy $ do
        logInfo "Starting bootstrap"
        bootstrap cfg
      case result of
        Right () -> putStrLn "Bootstrap complete"
        Left err -> do
          putStrLn ("Bootstrap failed: " <> T.unpack err)
          exitFailure
    ["redeploy"] -> do
      result <- runDeploy $ do
        logInfo "Starting redeploy"
        redeploy cfg
      case result of
        Right () -> putStrLn "Redeploy complete"
        Left err -> do
          putStrLn ("Redeploy failed: " <> T.unpack err)
          exitFailure
    _ -> do
      putStrLn "Usage: systemdnetes-deploy <bootstrap|redeploy>"
      putStrLn ""
      putStrLn "Commands:"
      putStrLn "  bootstrap  First-time deploy (create app, SSH keys, workers)"
      putStrLn "  redeploy   Update existing deployment (rebuild + push images)"
      putStrLn ""
      putStrLn "Environment:"
      putStrLn "  NUM_WORKERS   Number of worker machines (default: 2)"
      putStrLn "  REMOTE_HOST   SSH host for remote nix builds (default: local)"
      exitFailure
