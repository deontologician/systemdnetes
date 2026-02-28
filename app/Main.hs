module Main (main) where

import Control.Concurrent.STM (newTVarIO)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Network.Wai (strictRequestBody)
import Network.Wai.Handler.Warp (run)
import Polysemy (Sem)
import System.Environment (lookupEnv)
import Systemdnetes

main :: IO ()
main = do
  podStore <- newTVarIO Map.empty
  nodeStore <- newTVarIO Map.empty

  -- Parse pod CIDR from env (default: 10.100.0.0/16)
  cidrStr <- maybe "10.100.0.0/16" id <$> lookupEnv "SYSTEMDNETES_POD_CIDR"
  cidr <- case parseCidr (T.pack cidrStr) of
    Just c -> pure c
    Nothing -> error $ "Invalid SYSTEMDNETES_POD_CIDR: " <> cidrStr

  allocatorState <- newTVarIO (mkAllocatorState cidr)

  -- DNS hosts directory (default: /var/lib/systemdnetes/dns)
  hostsDir <- maybe "/var/lib/systemdnetes/dns" id <$> lookupEnv "SYSTEMDNETES_DNS_HOSTS_DIR"

  -- WireGuard interface name (default: systemdnetes)
  wgIface <- maybe "systemdnetes" T.pack <$> lookupEnv "SYSTEMDNETES_WG_IFACE"

  let runApp' :: Sem AppEffects a -> IO a
      runApp' = runApp podStore nodeStore allocatorState wgIface hostsDir
  runApp' $ logInfo "Starting systemdnetes on :8080"
  run 8080 $ \req respond -> do
    body <- strictRequestBody req
    response <- runApp' (handleRequest body req)
    respond response
