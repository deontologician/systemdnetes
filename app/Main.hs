module Main (main) where

import Network.HTTP.Types (status200)
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp (run)
import Systemdnetes

main :: IO ()
main = do
  runApp $ logInfo "Starting systemdnetes on :8080"
  run 8080 app

app :: Application
app _req respond =
  respond $ responseLBS status200 [("Content-Type", "text/plain")] "systemdnetes ok\n"
