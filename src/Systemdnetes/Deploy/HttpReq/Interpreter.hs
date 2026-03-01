module Systemdnetes.Deploy.HttpReq.Interpreter
  ( HttpReqHandler,
    httpReqToPure,
    httpReqToIO,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client qualified as HTTP
import Network.HTTP.Client.TLS qualified as TLS
import Network.HTTP.Types.Status (statusCode)
import Polysemy
import Systemdnetes.Deploy.HttpReq

-- | Handler for pure interpreter: URL-keyed canned responses.
-- Return Nothing for unrecognised URLs (interpreted as 404).
type HttpReqHandler = Text -> Maybe HttpResponse

-- | Pure interpreter driven by a handler function.
httpReqToPure :: HttpReqHandler -> Sem (HttpReq ': r) a -> Sem r a
httpReqToPure handler = interpret $ \case
  HttpGet url ->
    pure $ case handler url of
      Just resp -> resp
      Nothing -> HttpResponse 404 ""
  HttpPost url _body ->
    pure $ case handler url of
      Just resp -> resp
      Nothing -> HttpResponse 404 ""

-- | IO interpreter using http-client + http-client-tls.
httpReqToIO :: (Member (Embed IO) r) => Sem (HttpReq ': r) a -> Sem r a
httpReqToIO = interpret $ \case
  HttpGet url -> embed $ do
    manager <- TLS.newTlsManager
    request <- HTTP.parseRequest (T.unpack url)
    response <- HTTP.httpLbs request manager
    pure
      HttpResponse
        { httpStatus = statusCode (HTTP.responseStatus response),
          httpBody = HTTP.responseBody response
        }
  HttpPost url body -> embed $ do
    manager <- TLS.newTlsManager
    initReq <- HTTP.parseRequest (T.unpack url)
    let request =
          initReq
            { HTTP.method = TE.encodeUtf8 "POST",
              HTTP.requestBody = HTTP.RequestBodyLBS body,
              HTTP.requestHeaders = [("Content-Type", "application/json")]
            }
    response <- HTTP.httpLbs request manager
    pure
      HttpResponse
        { httpStatus = statusCode (HTTP.responseStatus response),
          httpBody = HTTP.responseBody response
        }
