module Systemdnetes.NixPodBuilder.Command
  ( PodBuildConfig (..),
    defaultPodBuildConfig,
    buildPodNixExpression,
    buildPodCommand,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Systemdnetes.Domain.Network (IPv4, ipToText)
import Systemdnetes.Domain.Pod (FlakeRef (..), PodName (..))

newtype PodBuildConfig = PodBuildConfig
  { pbcComposePodNixPath :: FilePath
  }
  deriving stock (Eq, Show)

defaultPodBuildConfig :: PodBuildConfig
defaultPodBuildConfig =
  PodBuildConfig
    { pbcComposePodNixPath = "/etc/systemdnetes/compose-pod.nix"
    }

-- | Generate the Nix expression string that imports compose-pod.nix with arguments.
buildPodNixExpression :: PodBuildConfig -> PodName -> FlakeRef -> Maybe IPv4 -> Text
buildPodNixExpression cfg (PodName name) (FlakeRef flake) mIp =
  "(import "
    <> T.pack (pbcComposePodNixPath cfg)
    <> " { userFlakeRef = "
    <> nixString flake
    <> "; podName = "
    <> nixString name
    <> ";"
    <> ipArg
    <> " }).config.system.build.toplevel"
  where
    ipArg = case mIp of
      Nothing -> ""
      Just ip -> " podIp = " <> nixString (ipToText ip) <> ";"

-- | Generate the full @nix build@ command for execution via SSH.
buildPodCommand :: PodBuildConfig -> PodName -> FlakeRef -> Maybe IPv4 -> Text
buildPodCommand cfg name flake mIp =
  "nix build --impure --no-link --print-out-paths --expr "
    <> shellQuote (buildPodNixExpression cfg name flake mIp)

-- | Escape a text value as a Nix string literal (double-quoted).
nixString :: Text -> Text
nixString t = "\"" <> T.concatMap escapeNixChar t <> "\""
  where
    escapeNixChar '\\' = "\\\\"
    escapeNixChar '"' = "\\\""
    escapeNixChar '$' = "\\$"
    escapeNixChar c = T.singleton c

-- | Shell-quote a text value for use in @bash -c '...'@ or similar.
-- Uses single quotes with the standard escape pattern for embedded single quotes.
shellQuote :: Text -> Text
shellQuote t = "'" <> T.replace "'" "'\"'\"'" t <> "'"
