module Systemdnetes.Deploy.Config
  ( FlyApp (..),
    DeployConfig (..),
    parseFlyToml,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

data FlyApp = FlyApp
  { flyAppName :: Text,
    flyAppRegion :: Text
  }
  deriving stock (Eq, Show)

data DeployConfig = DeployConfig
  { deployFlyApp :: FlyApp,
    deployWorkerCount :: Int,
    deploySshKeyDir :: FilePath,
    deployRemoteHost :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | Parse app name and primary_region from fly.toml text.
parseFlyToml :: Text -> Either Text FlyApp
parseFlyToml contents =
  case (findValue "app" contents, findValue "primary_region" contents) of
    (Just app, Just region) -> Right (FlyApp app region)
    (Nothing, _) -> Left "missing 'app' in fly.toml"
    (_, Nothing) -> Left "missing 'primary_region' in fly.toml"

-- | Find a top-level key = "value" or key = 'value' line.
findValue :: Text -> Text -> Maybe Text
findValue key contents =
  case filter (isKeyLine key) (T.lines contents) of
    (line : _) -> extractValue line
    [] -> Nothing

isKeyLine :: Text -> Text -> Bool
isKeyLine key line =
  let stripped = T.stripStart line
   in T.isPrefixOf (key <> " ") stripped
        || T.isPrefixOf (key <> "=") stripped

extractValue :: Text -> Maybe Text
extractValue line =
  case T.breakOn "=" line of
    (_, rest)
      | T.null rest -> Nothing
      | otherwise ->
          let val = T.strip (T.drop 1 rest)
           in Just (T.dropAround (\c -> c == '"' || c == '\'') val)
