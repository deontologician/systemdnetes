module Systemdnetes.Deploy.App
  ( DeployEffects,
    DeployPureConfig (..),
    DeployPureResult (..),
    runDeploy,
    runDeployPure,
  )
where

import Polysemy
import Systemdnetes.Deploy.Cmd
import Systemdnetes.Deploy.Cmd.Interpreter
import Systemdnetes.Deploy.HttpReq
import Systemdnetes.Deploy.HttpReq.Interpreter
import Systemdnetes.Effects.Log
import Systemdnetes.Effects.Log.Interpreter

type DeployEffects = '[Log, Cmd, HttpReq, Embed IO, Final IO]

-- | Run the deploy effect stack with IO interpreters.
runDeploy :: Sem DeployEffects a -> IO a
runDeploy =
  runFinal
    . embedToFinal
    . httpReqToIO
    . cmdToIO
    . logToIO

-- | Configuration for the pure deploy interpreter stack.
data DeployPureConfig = DeployPureConfig
  { pureCmdHandler :: CmdHandler,
    pureHttpHandler :: HttpReqHandler
  }

-- | Result of running through the pure deploy interpreter stack.
data DeployPureResult a = DeployPureResult
  { deployResultLogs :: [LogMessage],
    deployResultValue :: a
  }
  deriving stock (Show)

-- | Pure counterpart of 'runDeploy'.
runDeployPure ::
  DeployPureConfig ->
  Sem '[Log, Cmd, HttpReq] a ->
  DeployPureResult a
runDeployPure cfg =
  toResult
    . run
    . httpReqToPure (pureHttpHandler cfg)
    . cmdToPure (pureCmdHandler cfg)
    . logToList
  where
    toResult (logs, a) =
      DeployPureResult
        { deployResultLogs = logs,
          deployResultValue = a
        }
