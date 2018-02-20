{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module App.Options.Cmd.SqsToKafka
  ( CmdSqsToKafka(..)
  , parserCmdSqsToKafka
  ) where

import App
import App.Kafka
import App.RunApplication
import App.SqsMessage
import Arbor.Logger
import Conduit
import Control.Lens
import Control.Monad.Except
import Data.Monoid
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Sink
import Network.AWS
import Network.AWS.SQS.DeleteMessage
import Network.AWS.SQS.ReceiveMessage
import Network.AWS.SQS.Types
import Options.Applicative

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text            as T

data CmdSqsToKafka = CmdSqsToKafka
  { _cmdSqsToKafkaInputSqsUrl :: String
  , _cmdSqsToKafkaOutputTopic :: TopicName
  , _cmdSqsToKafkaKafkaConfig :: KafkaConfig
  } deriving (Show, Eq)

makeLenses ''CmdSqsToKafka

instance HasKafkaConfig (GlobalOptions CmdSqsToKafka) where
  kafkaConfig = optCmd . cmdSqsToKafkaKafkaConfig

instance HasKafkaConfig (AppEnv CmdSqsToKafka) where
  kafkaConfig = appOptions . kafkaConfig

instance RunApplication CmdSqsToKafka where
  runApplication envApp = runApplicationM envApp $ do
    opt <- view appOptions
    kafkaConf <- view kafkaConfig

    let sqsUrl = opt ^. optCmd . cmdSqsToKafkaInputSqsUrl
    let kafkaTopic = opt ^. optCmd . cmdSqsToKafkaOutputTopic

    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (kafkaConf ^. schemaRegistryAddress)

    logInfo "Creating Kafka Producer"
    producer <- mkProducer

    runConduit $
      receiveMessageC sqsUrl
      .| effectC (handleMessage sr kafkaTopic producer)
      .| ackMessageC sqsUrl
      .| sinkNull
    return ()

receiveMessageC :: (Monad m, MonadAWS m) => String -> Source m Message
receiveMessageC sqsUrl = do
  let rm = receiveMessage (T.pack sqsUrl)
  rmr <- send (rm & (rmMaxNumberOfMessages .~ Just 10))
  forM_ (rmr ^.. rmrsMessages . each) Conduit.yield
  receiveMessageC sqsUrl

handleMessage :: (MonadIO m, MonadLogger m) => SchemaRegistry -> TopicName -> KafkaProducer -> Message -> m ()
handleMessage sr t@(TopicName topic) producer message = do
  case decodeSqsMessage message of
    Just fcm -> do
      payload <- encodeValue sr (Subject (T.pack topic)) fcm
      case bimap EncodeErr (ProducerRecord t UnassignedPartition Nothing . Just . LBS.toStrict) payload of
        Left err -> do
          logInfo $ "err: " <> show err
          return ()
        Right p -> do
          _ <- produceMessage producer p
          logInfo $ "rec: " <> show p
          return ()
      return ()
    Nothing -> do
       logInfo "nope!"
       return ()
  return ()

ackMessageC :: (Monad m, MonadAWS m) => String -> Conduit Message m ()
ackMessageC sqsUrl =
  mapMC $ \msg -> do
    let receipts = msg ^. mReceiptHandle

    forM_ receipts $ \receipt -> do
      let dm = deleteMessage (T.pack sqsUrl) receipt
      void $ send dm

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
