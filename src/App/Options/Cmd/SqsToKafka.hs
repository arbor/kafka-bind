{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}

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
import Control.Arrow                        (left)
import Control.Lens
import Control.Monad                        (when)
import Control.Monad.Except
import Data.Either.Combinators
import Data.Generics.Product.Any
import Data.Monoid
import GHC.Generics
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Sink
import Network.AWS
import Network.AWS.SQS.DeleteMessageBatch
import Network.AWS.SQS.ReceiveMessage
import Network.AWS.SQS.Types
import Options.Applicative

import qualified App.Has              as H
import qualified App.Options.Types    as Z
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Maybe           as DM (catMaybes)
import qualified Data.Text            as T

data CmdSqsToKafka = CmdSqsToKafka
  { inputSqsUrl :: String
  , outputTopic :: TopicName
  , kafkaConfig :: Z.KafkaConfig
  } deriving (Show, Eq, Generic)

makeLenses ''CmdSqsToKafka

instance H.HasKafkaConfig (Z.GlobalOptions CmdSqsToKafka) where
  kafkaConfig = the @"cmd" . the @"kafkaConfig"

instance H.HasKafkaConfig (AppEnv CmdSqsToKafka) where
  kafkaConfig = the @"options" . H.kafkaConfig

instance RunApplication CmdSqsToKafka where
  runApplication envApp = runApplicationM envApp $ do
    opt <- view $ the @"options"
    kafkaConf <- view H.kafkaConfig

    let sqsUrl      = opt ^. the @"cmd" . the @"inputSqsUrl"
    let kafkaTopic  = opt ^. the @"cmd" . the @"outputTopic"

    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (kafkaConf ^. the @"schemaRegistryAddress")

    logInfo "Creating Kafka Producer"
    producer <- mkProducer

    runExceptT $ runConduit $
      receiveMessageC sqsUrl
      .| batchByOrFlush (BatchSize 10)
      .| effectC (handleMessages sr kafkaTopic producer)
      .| ackMessages sqsUrl
      .| sinkNull

receiveMessageC :: MonadAWS m => String -> ConduitT () (Maybe Message) m ()
receiveMessageC sqsUrl = do
  let rm = receiveMessage (T.pack sqsUrl)
  rmr <- lift $ send (rm & (rmMaxNumberOfMessages ?~ 10))
  case rmr ^.. rmrsMessages . each of
    []   -> yield Nothing
    msgs -> forM_ msgs $ yield . Just
  receiveMessageC sqsUrl

handleMessages :: (MonadIO m, MonadLogger m, MonadError AppError m) => SchemaRegistry -> TopicName -> KafkaProducer -> [Message] -> m ()
handleMessages sr t@(TopicName topic) producer msgs =
  forM_ msgs $ \msg -> do
    let sqsMessage = decodeSqsNotification msg

    case sqsMessage of
      Just (SqsMessageOfFileChangeMessage fcm) -> do
        payload <- encodeValue sr (Subject (T.pack topic)) fcm <&> left EncodeErr >>= eitherToError
        let p = ProducerRecord t UnassignedPartition Nothing (Just (LBS.toStrict payload))
        void $ produceMessage producer p
        logInfo $ "Produced record: " <> show p

      Just SqsMessageOfS3TestEvent -> do
        logInfo "s3:TestEvent found"
        return ()

      _ -> throwError (AppErr "Unable to decode SQS message")


ackMessages :: (MonadAWS m, MonadError AppError m) => String -> ConduitT [Message] () m ()
ackMessages sqsUrl =
  mapMC $ \msgs -> do
    let receipts = DM.catMaybes $ msgs ^.. each . mReceiptHandle
    -- each dmbr needs an ID. just use the list index.
    let dmbres = (\(r, i) -> deleteMessageBatchRequestEntry (T.pack (show i)) r) <$> zip receipts ([0..] :: [Int])
    case dmbres of
      [] -> return ()
      _  -> do
        resp <- send $ deleteMessageBatch (T.pack sqsUrl) & dmbEntries .~ dmbres
        -- only acceptable if no errors.
        when (resp ^. dmbrsResponseStatus == 200) $
          case resp ^. dmbrsFailed of
            [] -> return ()
            _  -> throwError (AppErr "deleteMessageBatch error, aborting")

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
