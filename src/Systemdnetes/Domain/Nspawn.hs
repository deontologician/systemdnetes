module Systemdnetes.Domain.Nspawn
  ( parseMachinectlList,
    parseMachinectlState,
    renderNspawnFile,
    renderMachineSetup,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Systemdnetes.Domain.Pod (ContainerInfo (..), ContainerState (..), PodName (..))

-- | Parse output of @machinectl list --no-legend --no-pager@.
--
-- Each line has whitespace-separated columns: MACHINE STATE SERVICE OS VERSION …
-- We care about MACHINE (col 0) and STATE (col 1).
parseMachinectlList :: Text -> [ContainerInfo]
parseMachinectlList raw =
  [ ContainerInfo (PodName name) state
    | line <- T.lines raw,
      not (T.null (T.strip line)),
      (name : stateCol : _) <- [T.words line],
      Just state <- [parseState stateCol]
  ]

-- | Parse a single state value from @machinectl show --property=State --value@.
parseMachinectlState :: Text -> Maybe ContainerState
parseMachinectlState = parseState . T.strip

parseState :: Text -> Maybe ContainerState
parseState "running" = Just ContainerRunning
parseState "stopped" = Just ContainerStopped
parseState "failed" = Just ContainerFailed
parseState "degraded" = Just ContainerFailed
parseState _ = Nothing

-- | Render the @.nspawn@ INI file for a systemd-nspawn container.
--
-- Enables boot mode and bind-mounts @/nix/store@ read-only from the host,
-- so all nix store paths are available inside the container.
renderNspawnFile :: PodName -> Text
renderNspawnFile (PodName _name) =
  T.unlines
    [ "[Exec]",
      "Boot=yes",
      "",
      "[Files]",
      "BindReadOnly=/nix/store"
    ]

-- | Render a shell script that sets up @/var/lib/machines/<pod>/@ with
-- the init symlink pointing at the given NixOS system closure.
--
-- The script:
-- 1. Creates the machine directory with a nix profile path
-- 2. Symlinks the system closure into the profile
-- 3. Creates @/sbin/init@ pointing through the profile to the closure's init
renderMachineSetup :: PodName -> Text -> Text
renderMachineSetup (PodName name) systemPath =
  T.unlines
    [ "set -euo pipefail",
      "sudo mkdir -p /var/lib/machines/" <> name <> "/nix/var/nix/profiles",
      "sudo ln -sfn " <> systemPath <> " /var/lib/machines/" <> name <> "/nix/var/nix/profiles/system",
      "sudo mkdir -p /var/lib/machines/" <> name <> "/sbin",
      "sudo ln -sfn /nix/var/nix/profiles/system/init /var/lib/machines/" <> name <> "/sbin/init",
      "sudo mkdir -p /etc/systemd/nspawn",
      "printf '%s\\n' '[Exec]' 'Boot=yes' '' '[Files]' 'BindReadOnly=/nix/store' | sudo tee /etc/systemd/nspawn/" <> name <> ".nspawn > /dev/null"
    ]
