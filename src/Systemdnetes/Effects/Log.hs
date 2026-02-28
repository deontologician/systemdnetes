module Systemdnetes.Effects.Log
  ( LogLevel (..),
    LogMessage (..),
    Log (..),
    logMsg,
    logDebug,
    logInfo,
    logWarn,
    logError,
  )
where

import Data.Text (Text)
import Polysemy

data LogLevel = Debug | Info | Warn | Error
  deriving stock (Eq, Ord, Show)

data LogMessage = LogMessage
  { logMessageLevel :: LogLevel,
    logMessageContent :: Text
  }
  deriving stock (Eq, Show)

data Log m a where
  LogMsg :: LogLevel -> Text -> Log m ()

makeSem ''Log

logDebug :: (Member Log r) => Text -> Sem r ()
logDebug = logMsg Debug

logInfo :: (Member Log r) => Text -> Sem r ()
logInfo = logMsg Info

logWarn :: (Member Log r) => Text -> Sem r ()
logWarn = logMsg Warn

logError :: (Member Log r) => Text -> Sem r ()
logError = logMsg Error
