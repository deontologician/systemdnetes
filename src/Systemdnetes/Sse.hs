module Systemdnetes.Sse (sseLogResponse) where

import Control.Exception (SomeException, catch)
import Data.ByteString.Builder (byteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Types (hContentType, status200)
import Network.Wai (Response, responseStream)
import System.IO (BufferMode (..), hSetBuffering)
import System.Process
  ( CreateProcess (..),
    StdStream (..),
    createProcess,
    proc,
    terminateProcess,
  )

-- | Build a WAI streaming response that SSE-streams journal logs from a node.
--
-- Spawns @ssh \<nodeAddr\> journalctl -f -u \<unitName\>@ and pipes each line
-- as an SSE @data:@ event. The SSH process is terminated when the stream
-- ends (client disconnect or EOF).
sseLogResponse :: Text -> Text -> Response
sseLogResponse nodeAddr unitName =
  responseStream status200 [(hContentType, "text/event-stream")] $ \write flush -> do
    let cmd =
          (proc "ssh" [Text.unpack nodeAddr, "journalctl", "-f", "-u", Text.unpack unitName])
            { std_out = CreatePipe
            }
    (_, Just hOut, _, ph) <- createProcess cmd
    hSetBuffering hOut LineBuffering
    let loop = do
          line <- BS8.hGetLine hOut
          write (byteString "data: " <> byteString line <> byteString "\n\n")
          flush
          loop
    loop `catch` \(_ :: SomeException) -> terminateProcess ph
