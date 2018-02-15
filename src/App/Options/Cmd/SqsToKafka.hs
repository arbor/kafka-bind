{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell   #-}

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
import Network.AWS
import Network.AWS.SQS.DeleteMessage
import Network.AWS.SQS.ReceiveMessage
import Network.AWS.SQS.Types
import Network.StatsD                       as S hiding (send)
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

instance HasKafkaConfig (GlobalOptions CmdSqsToKafka) where
  kafkaConfig = optCmd . cmdSqsToKafkaKafkaConfig

instance HasKafkaConfig (AppEnv CmdSqsToKafka) where
  kafkaConfig = appOptions . kafkaConfig

instance RunApplication CmdSqsToKafka where
  runApplication envApp = runApplicationM envApp $ do
    opt <- view appOptions
    let sqsUrl = opt ^. optCmd . cmdSqsToKafkaInputSqsUrl

    runConduit $
      receiveMessageC sqsUrl
      .| effectC (\m -> liftIO (print (m ^. mReceiptHandle)))
      -- .| handleMessage
      .| ackMessageC sqsUrl
      .| sinkNull
    return ()

receiveMessageC :: (MonadLogger m, Monad m, MonadAWS m) => String -> Source m Message
receiveMessageC sqsUrl = do
  let rm = receiveMessage (T.pack sqsUrl)
  rmr <- send (rm & (rmMaxNumberOfMessages .~ Just 10))
  forM_ (rmr ^.. rmrsMessages . each) Conduit.yield
  receiveMessageC sqsUrl

ackMessageC :: (MonadLogger m, Monad m, MonadAWS m) => String -> Conduit Message m ()
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
