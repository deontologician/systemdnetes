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
import System.IO (hClose, hGetContents, hPutStr)
import System.Process
  ( CreateProcess (..),
    StdStream (..),
    createProcess,
    proc,
    waitForProcess,
  )
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

-- | IO interpreter: shells out via createProcess.
-- Stderr is inherited so build progress streams to the terminal in real time.
-- Stdout is captured (needed by 'readCmd').
cmdToIO :: (Member (Embed IO) r) => Sem (Cmd ': r) a -> Sem r a
cmdToIO = interpret $ \case
  RunCmd prog args stdin' -> embed $ do
    let cp =
          (proc (T.unpack prog) (map T.unpack args))
            { std_in = if T.null stdin' then Inherit else CreatePipe,
              std_out = CreatePipe,
              std_err = Inherit
            }
    (mbStdinH, Just stdoutH, _, ph) <- createProcess cp
    case mbStdinH of
      Just h -> do
        hPutStr h (T.unpack stdin')
        hClose h
      Nothing -> pure ()
    stdout <- hGetContents stdoutH
    exitCode <- waitForProcess ph
    pure
      CmdResult
        { cmdExitCode = case exitCode of
            ExitSuccess -> 0
            ExitFailure n -> n,
          cmdStdout = T.pack stdout,
          cmdStderr = ""
        }
