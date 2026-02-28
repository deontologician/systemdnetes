module Systemdnetes.Domain.Resource
  ( Millicores (..),
    Mebibytes (..),
    parseCpu,
    parseMemory,
  )
where

import Data.Aeson (ToJSON)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read (decimal)
import GHC.Generics (Generic)

-- | CPU in thousandths of a core. "500m" = 500, "2" = 2000.
newtype Millicores = Millicores Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (ToJSON, Num)

-- | Memory in mebibytes. "512Mi" = 512, "1Gi" = 1024.
newtype Mebibytes = Mebibytes Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (ToJSON, Num)

-- | Parse a CPU resource string. Returns 'Nothing' on malformed input.
--
-- Accepted formats:
--   "500m"  -> Just (Millicores 500)
--   "2"     -> Just (Millicores 2000)
parseCpu :: Text -> Maybe Millicores
parseCpu t = case decimal t of
  Right (n, rest)
    | rest == "m" -> Just (Millicores n)
    | T.null rest -> Just (Millicores (n * 1000))
  _ -> Nothing

-- | Parse a memory resource string. Returns 'Nothing' on malformed input.
--
-- Accepted formats:
--   "512Mi" -> Just (Mebibytes 512)
--   "1Gi"   -> Just (Mebibytes 1024)
parseMemory :: Text -> Maybe Mebibytes
parseMemory t = case decimal t of
  Right (n, rest)
    | rest == "Mi" -> Just (Mebibytes n)
    | rest == "Gi" -> Just (Mebibytes (n * 1024))
  _ -> Nothing
