module Systemdnetes.Deploy.Nix
  ( nixBuild,
  )
where

import Data.Text (Text)
import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Effects.Log

-- | Build a Nix flake output with a named --out-link.
nixBuild :: (Member Cmd r, Member Log r) => Text -> Text -> Sem r (Either Text ())
nixBuild flakeRef outLink = do
  logInfo ("Building " <> flakeRef <> " -> " <> outLink)
  runCmd_ "nix" ["build", flakeRef, "--out-link", outLink]
