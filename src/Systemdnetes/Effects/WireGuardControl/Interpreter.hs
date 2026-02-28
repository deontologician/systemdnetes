module Systemdnetes.Effects.WireGuardControl.Interpreter
  ( wireGuardControlToPure,
    wireGuardControlToIO,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import Polysemy.State
import System.Process (readProcess)
import Systemdnetes.Domain.Node (Node (..), NodeName)
import Systemdnetes.Domain.WireGuard
  ( WgKeyPair (..),
    WgPeer (..),
    WgPrivateKey (..),
    WgPublicKey (..),
    renderRemovePeerArgs,
    renderSetPeerArgs,
  )
import Systemdnetes.Effects.Ssh (Ssh, runSshCommand)
import Systemdnetes.Effects.WireGuardControl

type WgPureState = (Int, Map NodeName [WgPeer])

-- | Pure interpreter: generates deterministic counter-based fake keys.
wireGuardControlToPure ::
  Sem (WireGuardControl ': r) a ->
  Sem r (WgPureState, a)
wireGuardControlToPure =
  runState @WgPureState (0, Map.empty)
    . reinterpret
      ( \case
          GenerateKeyPair -> do
            (counter, peers) <- get @WgPureState
            let privKey = WgPrivateKey ("fake-priv-" <> T.pack (show counter))
                pubKey = WgPublicKey ("fake-pub-" <> T.pack (show counter))
            put @WgPureState (counter + 1, peers)
            pure WgKeyPair {wgPrivateKey = privKey, wgPublicKey = pubKey}
          AddPeer nodeName peer -> do
            (counter, peers) <- get @WgPureState
            let updated = Map.insertWith (<>) nodeName [peer] peers
            put @WgPureState (counter, updated)
          RemovePeer nodeName pubKey -> do
            (counter, peers) <- get @WgPureState
            let updated = Map.adjust (filter (\p -> peerPublicKey p /= pubKey)) nodeName peers
            put @WgPureState (counter, updated)
          ListPeers nodeName -> do
            (_, peers) <- get @WgPureState
            pure $ Map.findWithDefault [] nodeName peers
      )

-- | IO interpreter: generates real WireGuard keys via wg(8) and pushes
--   peer configs to nodes via SSH.
wireGuardControlToIO ::
  (Member (Embed IO) r, Member Ssh r) =>
  Text ->
  Sem (WireGuardControl ': r) a ->
  Sem r a
wireGuardControlToIO iface = interpret $ \case
  GenerateKeyPair -> embed $ do
    privKeyStr <- T.strip . T.pack <$> readProcess "wg" ["genkey"] ""
    pubKeyStr <- T.strip . T.pack <$> readProcess "wg" ["pubkey"] (T.unpack privKeyStr)
    pure WgKeyPair {wgPrivateKey = WgPrivateKey privKeyStr, wgPublicKey = WgPublicKey pubKeyStr}
  AddPeer nodeName peer -> do
    let args = renderSetPeerArgs iface peer
        cmd = T.intercalate " " args
    _ <- runSshCommand (Node nodeName "") cmd
    pure ()
  RemovePeer nodeName pubKey -> do
    let args = renderRemovePeerArgs iface pubKey
        cmd = T.intercalate " " args
    _ <- runSshCommand (Node nodeName "") cmd
    pure ()
  ListPeers _nodeName ->
    -- In production, would parse `wg show <iface> dump` output.
    -- For now, returns empty — the source of truth is the allocator state.
    pure []
