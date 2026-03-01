module Systemdnetes.Deploy.Cmd.Interpreter
  ( CmdHandler,
    cmdToPure,
    cmdToIO,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Systemdnetes.Deploy.Cmd

-- | Handler for pure interpreter: pattern-match on command name/args
-- to return canned results. Return Nothing for unrecognised commands
-- (interpreted as exit 127).
type CmdHandler = Text -> [Text] -> Maybe CmdResult

-- | Pure interpreter driven by a handler function.
cmdToPure :: CmdHandler -> Sem (Cmd ': r) a -> Sem r a
cmdToPure handler = interpret $ \case
  RunCmd prog args _stdin ->
    pure $ case handler prog args of
      Just result -> result
      Nothing -> CmdResult 127 "" ("command not found: " <> prog)

-- | IO interpreter: shells out via readProcessWithExitCode.
cmdToIO :: (Member (Embed IO) r) => Sem (Cmd ': r) a -> Sem r a
cmdToIO = interpret $ \case
  RunCmd prog args stdin' -> embed $ do
    (exitCode, stdout, stderr) <-
      readProcessWithExitCode
        (T.unpack prog)
        (map T.unpack args)
        (T.unpack stdin')
    pure
      CmdResult
        { cmdExitCode = case exitCode of
            ExitSuccess -> 0
            ExitFailure n -> n,
          cmdStdout = T.pack stdout,
          cmdStderr = T.pack stderr
        }
