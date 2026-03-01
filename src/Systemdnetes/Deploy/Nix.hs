module Systemdnetes.Deploy.Nix
  ( nixBuild,
    remoteBuild,
    buildImages,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Config
import Systemdnetes.Effects.Log

-- | Build a Nix flake output with a named --out-link.
nixBuild :: (Member Cmd r, Member Log r) => Text -> Text -> Sem r (Either Text ())
nixBuild flakeRef outLink = do
  logInfo ("Building " <> flakeRef <> " -> " <> outLink)
  runCmd_ "nix" ["build", flakeRef, "--out-link", outLink]

-- | Build a Nix flake output on a remote host via SSH, then copy the result back.
-- Mirrors the logic of deploy/remote-build.sh.
remoteBuild :: (Member Cmd r, Member Log r) => Text -> Text -> Text -> Sem r (Either Text ())
remoteBuild host flakeTarget outLink = do
  logInfo ("Building " <> flakeTarget <> " on " <> host <> " -> " <> outLink)
  let remoteDir = "~/Code/systemdnetes"
      buildCmd = "cd " <> remoteDir <> " && git pull --ff-only && nix build .#" <> flakeTarget <> " --out-link " <> outLink
  result <- runCmd_ "ssh" [host, buildCmd]
  case result of
    Left err -> pure (Left err)
    Right () -> do
      storePath <- readCmd "ssh" [host, "readlink -f " <> remoteDir <> "/" <> outLink]
      case storePath of
        Left err -> pure (Left err)
        Right path -> do
          let cleanPath = stripNewline path
          _ <- runCmd_ "rm" ["-f", outLink]
          runCmd_ "scp" [host <> ":" <> cleanPath, outLink]
  where
    stripNewline t = case T.stripSuffix "\n" t of
      Just t' -> t'
      Nothing -> t

-- | Build both container and worker images, using remote host if configured.
buildImages :: (Member Cmd r, Member Log r) => DeployConfig -> Sem r (Either Text ())
buildImages cfg = case deployRemoteHost cfg of
  Just host -> do
    result <- remoteBuild host "container" "result-container"
    case result of
      Left err -> pure (Left err)
      Right () -> remoteBuild host "worker" "result-worker"
  Nothing -> do
    result <- nixBuild ".#container" "result-container"
    case result of
      Left err -> pure (Left err)
      Right () -> nixBuild ".#worker" "result-worker"
