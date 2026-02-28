module Main (main) where

import Control.Concurrent.STM (newTVarIO)
import Data.Map.Strict qualified as Map
import Network.Wai.Handler.Warp (run)
import Systemdnetes

main :: IO ()
main = do
  store <- newTVarIO Map.empty
  runApp store $ logInfo "Starting systemdnetes on :8080"
  run 8080 $ \req respond -> do
    response <- runApp store (handleRequest req)
    respond response
