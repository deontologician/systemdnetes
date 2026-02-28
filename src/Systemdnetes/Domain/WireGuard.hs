module Systemdnetes.Domain.WireGuard
  ( WgPrivateKey (..),
    WgPublicKey (..),
    WgKeyPair (..),
    WgPeer (..),
    NodeWgConfig (..),
    renderSetPeerArgs,
    renderRemovePeerArgs,
  )
where

import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import Systemdnetes.Domain.Network (IPv4, ipToText)
import Systemdnetes.Domain.Node (NodeName)

-- | Base64-encoded WireGuard private key.
newtype WgPrivateKey = WgPrivateKey {unWgPrivateKey :: Text}
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Base64-encoded WireGuard public key.
newtype WgPublicKey = WgPublicKey {unWgPublicKey :: Text}
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | A WireGuard key pair.
data WgKeyPair = WgKeyPair
  { wgPrivateKey :: WgPrivateKey,
    wgPublicKey :: WgPublicKey
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | A WireGuard peer entry on a node's interface.
data WgPeer = WgPeer
  { peerPublicKey :: WgPublicKey,
    peerAllowedIp :: IPv4,
    peerNode :: NodeName
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Static WireGuard configuration for a node (infrastructure-level).
data NodeWgConfig = NodeWgConfig
  { nodeWgName :: NodeName,
    nodeWgKeyPair :: WgKeyPair,
    nodeWgListenPort :: Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Render arguments for @wg set <iface> peer ...@ to add/update a peer.
--   Returns a list of argument strings suitable for shell invocation.
renderSetPeerArgs :: Text -> WgPeer -> [Text]
renderSetPeerArgs iface peer =
  [ "wg",
    "set",
    iface,
    "peer",
    unWgPublicKey (peerPublicKey peer),
    "allowed-ips",
    ipToText (peerAllowedIp peer) <> "/32"
  ]

-- | Render arguments for @wg set <iface> peer ... remove@ to remove a peer.
renderRemovePeerArgs :: Text -> WgPublicKey -> [Text]
renderRemovePeerArgs iface pubkey =
  [ "wg",
    "set",
    iface,
    "peer",
    unWgPublicKey pubkey,
    "remove"
  ]
