{-# LANGUAGE DeriveAnyClass   #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell  #-}

module App.Options.Cmd.SqsToKafka
  ( CmdSqsToKafka(..)
  , parserCmdSqsToKafka
  ) where

import App
import App.AWS.Sqs
import App.Kafka
import App.Options
import App.RunApplication
import Arbor.Logger
import Conduit
import Control.Arrow                        (left)
import Control.Concurrent
import Control.Exception
import Control.Lens
import Control.Monad.Except
import Data.Aeson                           as J
import Data.ByteString                      (ByteString)
import Data.ByteString.Char8                as C8
import Data.ByteString.Lazy                 (fromStrict, toStrict)
import Data.Maybe                           (catMaybes)
import Data.Monoid
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Sink
import Kafka.Conduit.Source
import Network.StatsD                       as S
import Options.Applicative

import qualified Data.Avro.Decode  as A
import qualified Data.Avro.Schema  as A
import qualified Data.Avro.Types   as A
import qualified Data.Conduit.List as L
import qualified Data.Text         as T
import qualified System.IO         as P

data CmdSqsToKafka = CmdSqsToKafka
  {
    _cmdSqsToKafkaInputSqsUrl :: String
  , _cmdSqsToKafkaOutputTopic :: TopicName
  , _cmdSqsToKafkaKafkaConfig :: KafkaConfig
  } deriving (Show, Eq)

makeLenses ''CmdSqsToKafka

instance RunApplication CmdSqsToKafka where
  runApplication envApp = runApplicationM envApp $ do
    liftIO $ P.putStrLn "Not yet implemented"
    _ <- forever $ liftIO $ threadDelay 1000
    return ()

parserCmdSqsToKafka :: Parser CmdSqsToKafka
parserCmdSqsToKafka = CmdSqsToKafka
  <$> strOption
    (  long "input-sqs-url"
    <> metavar "SQS_URL"
    <> help "Input SQS URL")
  <*> (TopicName <$>
    strOption
    (  long "output-topic-name"
    <> metavar "OUTPUT_TOPIC"
    <> help "Output kafka topic"))
  <*> kafkaConfigParser
