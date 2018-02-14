{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}

module App.Options.Cmd.KafkaToSqs where

import App
import App.AWS.Sqs
import App.Kafka
import App.RunApplication
import Arbor.Logger
import Conduit
import Control.Arrow                        (left)
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
import Kafka.Conduit.Sink                   hiding (logLevel)
import Kafka.Conduit.Source
import Network.StatsD                       as S
import Options.Applicative

import qualified Data.Avro.Decode  as A
import qualified Data.Avro.Schema  as A
import qualified Data.Avro.Types   as A
import qualified Data.Conduit.List as L
import qualified Data.Text         as T

data CmdKafkaToSqs = CmdKafkaToSqs
  { _optInputTopic            :: TopicName
  , _consumerGroupId          :: ConsumerGroupId
  , _outputSqsUrl             :: String
  , _cmdKafkaToSqsKafkaConfig :: KafkaConfig
  } deriving (Show, Eq)

makeLenses ''CmdKafkaToSqs

parserCmdKafkaToSqs :: Parser CmdKafkaToSqs
parserCmdKafkaToSqs = CmdKafkaToSqs
  <$> ( TopicName <$> strOption
        (  long "input-topic"
        <> metavar "TOPIC"
        <> help "Input topic"))
  <*> ( ConsumerGroupId <$> strOption
        (  long "kafka-group-id"
        <> metavar "GROUP_ID"
        <> help "Kafka consumer group id"))
  <*>  strOption
        (  long "output-sqs-url"
        <> metavar "OUTPUT_SQS_URL"
        <> help "Kafka consumer group id")
  <*> kafkaConfigParser

instance HasKafkaConfig (GlobalOptions CmdKafkaToSqs) where
  kafkaConfig = optCmd . cmdKafkaToSqsKafkaConfig

instance HasKafkaConfig (AppEnv CmdKafkaToSqs) where
  kafkaConfig = appOptions . kafkaConfig

instance RunApplication CmdKafkaToSqs where
  runApplication envApp = runApplicationM envApp $ do
    opt <- view appOptions
    kafkaConf <- view kafkaConfig

    logInfo "Creating Kafka Consumer"
    consumer <- mkConsumer (opt ^. optCmd ^. consumerGroupId) (opt ^. optCmd ^. optInputTopic)

    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (kafkaConf ^. schemaRegistryAddress)

    logInfo "Running Kafka Consumer"
    runConduit $
      kafkaSourceNoClose consumer (kafkaConf ^. pollTimeoutMs)
      .| throwLeftSatisfyC KafkaErr isFatal            -- throw any fatal error
      .| skipNonFatalExcept [isPollTimeout]            -- discard any non-fatal except poll timeouts
      .| rightC (handleStream opt sr)              -- handle messages (see Service.hs)
      .| everyNSeconds (kafkaConf ^. commitPeriodSec)  -- only commit ever N seconds, so we don't hammer Kafka.
      .| commitOffsetsSink consumer

-- | Handles the stream of incoming messages.
-- Emit values downstream because offsets are committed based on their present.
handleStream  :: MonadApp CmdKafkaToSqs m
              => GlobalOptions CmdKafkaToSqs
              -> SchemaRegistry
              -> Conduit (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) m ()
handleStream opt sr =
  mapC crValue                 -- extracting only value from consumer record
  .| L.catMaybes               -- discard empty values
  .| mapMC (decodeMessage sr)  -- decode avro message.
  .| mapC failBadly            -- error on decode failure
  .| mapMC (sendSqs (T.pack (opt ^. optCmd ^. outputSqsUrl)) . T.pack . C8.unpack . toStrict . J.encode)

asExceptT :: Monad m => (e -> e') -> m (Either e a) -> ExceptT e' m a
asExceptT f me = ExceptT $ left f <$> me

asExceptTPure :: Monad m => (e -> e') -> Either e a -> ExceptT e' m a
asExceptTPure f e = ExceptT. pure $ left f e

maybeToEither :: e -> Maybe a -> Either e a
maybeToEither e = maybe (Left e) Right

failBadly :: Show e => Either e a -> a
failBadly (Left e)  = error (show e)
failBadly (Right a) = a

decodeMessage :: MonadIO m => SchemaRegistry -> ByteString -> m (Either DecodeError (A.Value A.Type))
decodeMessage sr bs = runExceptT $ do
  (sid, payload) <- asExceptTPure id . maybeToEither BadPayloadNoSchemaId $ extractSchemaId $ fromStrict bs
  sch            <- asExceptT DecodeRegistryError (loadSchema sr sid)
  asExceptT (DecodeError sch) (pure $ A.decodeAvro sch payload)


---------------------- TO BE MOVED TO A LIBRARY -------------------------------
throwLeftC :: MonadAppError m => (e -> AppError) -> Conduit (Either e a) m (Either e a)
throwLeftC f = awaitForever $ \msg ->
  throwErrorAs f msg

throwLeftSatisfyC :: MonadAppError m => (e -> AppError) -> (e -> Bool) -> Conduit (Either e a) m (Either e a)
throwLeftSatisfyC f p = awaitForever $ \msg ->
  case msg of
    Right a -> yield (Right a)
    Left e  | p e -> throwErrorAs f (Left e)
    Left e  -> yield (Left e)
-------------------------------------------------------------------------------

withStatsClient :: AppName -> StatsConfig -> (StatsClient -> IO a) -> IO a
withStatsClient appName statsConf f = do
  globalTags <- mkStatsTags statsConf
  let statsOpts = DogStatsSettings (statsConf ^. statsHost) (statsConf ^. statsPort)
  bracket (createStatsClient statsOpts (MetricName appName) globalTags) closeStatsClient f

mkStatsTags :: StatsConfig -> IO [Tag]
mkStatsTags statsConf = do
  deplId <- envTag "TASK_DEPLOY_ID" "deploy_id"
  let envTags = catMaybes [deplId]
  return $ envTags <> (statsConf ^. statsTags <&> toTag)
  where
    toTag (StatsTag (k, v)) = S.tag k v


