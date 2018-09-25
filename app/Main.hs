{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Main where

import App
import App.AWS.Env
import App.Options.Cmd
import App.Options.Cmd.KafkaToSqs
import App.Options.Parser
import App.RunApplication
import Arbor.Logger
import Arbor.Network.StatsD       (StatsClient)
import Control.Concurrent.STM     (newTVarIO)
import Control.Lens
import Control.Monad.IO.Class
import Data.Generics.Product.Any
import Data.Semigroup             ((<>))
import Network.AWS.Env
import System.Environment

import qualified App.Options.Types as Z
import qualified Data.Text         as T

mkAppEnv :: MonadIO m
  => StatsClient
  -> Logger
  -> Env
  -> Z.GlobalOptions c
  -> c
  -> m (AppEnv c)
mkAppEnv stats lgr envAws opt cmd = do
  let newOpt = opt { Z.cmd = cmd }
  counters <- do
    processedMessages <- liftIO $ newTVarIO 0
    return AppCounters {..}
  let envApp = AppEnv newOpt envAws stats lgr counters
  return envApp

main :: IO ()
main = do
  opt <- parseOptions
  progName <- T.pack <$> getProgName
  let logLvk    = opt ^. the @"logLevel"
  let statsConf = opt ^. the @"statsConfig"

  withStdOutTimedFastLogger $ \lgr -> do
    withStatsClient progName statsConf $ \stats -> do
      envAws <- mkEnv (opt ^. the @"region") logLvk lgr
      let mkAppEnv2 cmd = mkAppEnv stats (Logger lgr logLvk) envAws (opt { Z.cmd = cmd }) cmd
      res <- case opt ^. the @"cmd" of
        CmdOfCmdKafkaToSqs cmd -> mkAppEnv2 cmd >>= runApplication
        CmdOfCmdSqsToKafka cmd -> mkAppEnv2 cmd >>= runApplication
        cmd                    -> return $ Left (AppErr ("Not implemented: " <> show cmd))
      case res of
        Left err -> pushLogMessage lgr LevelError ("Exiting: " <> show err)
        Right _  -> pure ()
    pushLogMessage lgr LevelError ("Premature exit, must not happen." :: String)
