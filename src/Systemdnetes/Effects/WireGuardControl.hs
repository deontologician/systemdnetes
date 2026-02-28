module Systemdnetes.Effects.WireGuardControl
  ( WireGuardControl (..),
    generateKeyPair,
    addPeer,
    removePeer,
    listPeers,
  )
where

import Polysemy
import Systemdnetes.Domain.Node (NodeName)
import Systemdnetes.Domain.WireGuard (WgKeyPair, WgPeer, WgPublicKey)

data WireGuardControl m a where
  GenerateKeyPair :: WireGuardControl m WgKeyPair
  AddPeer :: NodeName -> WgPeer -> WireGuardControl m ()
  RemovePeer :: NodeName -> WgPublicKey -> WireGuardControl m ()
  ListPeers :: NodeName -> WireGuardControl m [WgPeer]

makeSem ''WireGuardControl
