module Systemdnetes.Effects.Ssh.Interpreter
  ( sshToPure,
    sshToIO,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Polysemy
import System.Exit (ExitCode (..))
import System.Process (readProcessWithExitCode)
import Systemdnetes.Domain.Node (Node (..), NodeName)
import Systemdnetes.Effects.Ssh

-- | Pure interpreter: known nodes return canned output, unknown return error.
sshToPure ::
  Map NodeName Text ->
  Sem (Ssh ': r) a ->
  Sem r a
sshToPure known = interpret $ \case
  RunSshCommand node _cmd ->
    pure $ case Map.lookup (nodeName node) known of
      Just output -> Right output
      Nothing -> Left "unreachable"

-- | IO interpreter: shells out to the ssh command.
sshToIO :: (Member (Embed IO) r) => Sem (Ssh ': r) a -> Sem r a
sshToIO = interpret $ \case
  RunSshCommand node cmd -> embed $ do
    let addr = T.unpack (nodeAddress node)
    (exitCode, stdout, stderr) <-
      readProcessWithExitCode
        "ssh"
        [ "-o",
          "ConnectTimeout=2",
          "-o",
          "StrictHostKeyChecking=no",
          addr,
          T.unpack cmd
        ]
        ""
    pure $ case exitCode of
      ExitSuccess -> Right (T.pack stdout)
      ExitFailure _ -> Left (T.pack stderr)
