module Main (main) where

import Control.Concurrent.STM (newTVarIO)
import Data.Map.Strict qualified as Map
import Network.Wai (strictRequestBody)
import Network.Wai.Handler.Warp (run)
import Systemdnetes

main :: IO ()
main = do
  podStore <- newTVarIO Map.empty
  nodeStore <- newTVarIO Map.empty
  runApp podStore nodeStore $ logInfo "Starting systemdnetes on :8080"
  run 8080 $ \req respond -> do
    body <- strictRequestBody req
    response <- runApp podStore nodeStore (handleRequest body req)
    respond response
