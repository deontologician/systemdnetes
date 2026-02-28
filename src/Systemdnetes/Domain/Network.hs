module Systemdnetes.Domain.Network
  ( IPv4 (..),
    CidrBlock (..),
    parseCidr,
    cidrContains,
    cidrHostCount,
    cidrNthHost,
    ipToText,
    textToIPv4,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Bits (Bits (..), shiftL, shiftR)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import GHC.Generics (Generic)
import Text.Read (readMaybe)

-- | IPv4 address stored as a 32-bit word in network byte order.
newtype IPv4 = IPv4 {unIPv4 :: Word32}
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | CIDR block: base address + prefix length (0-32).
data CidrBlock = CidrBlock
  { cidrBase :: IPv4,
    cidrPrefix :: Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Parse "10.100.0.0/16" into a CidrBlock. Normalises the base address
--   to the network address (clears host bits).
parseCidr :: Text -> Maybe CidrBlock
parseCidr t = case T.splitOn "/" t of
  [addrPart, prefixPart] -> do
    ip <- textToIPv4 addrPart
    prefix <- readMaybe (T.unpack prefixPart)
    if prefix >= 0 && prefix <= 32
      then
        let mask = cidrMask prefix
            base = IPv4 (unIPv4 ip .&. mask)
         in Just (CidrBlock base prefix)
      else Nothing
  _ -> Nothing

-- | Check whether an IP falls within the CIDR block.
cidrContains :: CidrBlock -> IPv4 -> Bool
cidrContains (CidrBlock (IPv4 base) prefix) (IPv4 addr) =
  let mask = cidrMask prefix
   in (addr .&. mask) == (base .&. mask)

-- | Number of usable host addresses in the block. For prefix < 31 this
--   excludes network and broadcast; for /31 and /32 returns 2 and 1.
cidrHostCount :: CidrBlock -> Word32
cidrHostCount (CidrBlock _ prefix)
  | prefix >= 31 = if prefix == 32 then 1 else 2
  | otherwise = (1 `shiftL` (32 - prefix)) - 2

-- | Return the nth host address (0-indexed) within the CIDR. Returns
--   Nothing if n is out of range. Skips the network address (host 0 maps
--   to base+1).
cidrNthHost :: CidrBlock -> Word32 -> Maybe IPv4
cidrNthHost cidr n
  | n >= cidrHostCount cidr = Nothing
  | otherwise = Just $ IPv4 (unIPv4 (cidrBase cidr) + n + 1)

-- | Render an IPv4 as dotted-quad text: "10.100.0.1".
ipToText :: IPv4 -> Text
ipToText (IPv4 w) =
  T.intercalate
    "."
    [ T.pack (show (shiftR w 24 .&. 0xFF)),
      T.pack (show (shiftR w 16 .&. 0xFF)),
      T.pack (show (shiftR w 8 .&. 0xFF)),
      T.pack (show (w .&. 0xFF))
    ]

-- | Parse a dotted-quad text into an IPv4.
textToIPv4 :: Text -> Maybe IPv4
textToIPv4 t = case mapM (readMaybe . T.unpack) (T.splitOn "." t) of
  Just [a, b, c, d]
    | all (\x -> (x :: Word32) <= 255) [a, b, c, d] ->
        Just $ IPv4 (shiftL a 24 .|. shiftL b 16 .|. shiftL c 8 .|. d)
  _ -> Nothing

-- Internal: build a /prefix mask (e.g. /16 -> 0xFFFF0000).
cidrMask :: Int -> Word32
cidrMask 0 = 0
cidrMask prefix = complement (shiftL 1 (32 - prefix) - 1)
