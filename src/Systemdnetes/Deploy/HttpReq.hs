module Systemdnetes.Deploy.HttpReq
  ( HttpReq (..),
    HttpResponse (..),
    httpGet,
    httpPost,
  )
where

import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Polysemy

data HttpResponse = HttpResponse
  { httpStatus :: Int,
    httpBody :: LBS.ByteString
  }
  deriving stock (Eq, Show)

data HttpReq m a where
  HttpGet :: Text -> HttpReq m HttpResponse
  HttpPost :: Text -> LBS.ByteString -> HttpReq m HttpResponse

makeSem ''HttpReq
