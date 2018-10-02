{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

module App.Options.Cmd.KafkaToSqs where

import App.AppError
import App.Application
import App.AWS.Sqs
import App.Json
import App.Kafka
import App.Options
import App.RunApplication
import Arbor.Logger
import Arbor.Network.StatsD                 (StatsClient)
import Conduit
import Control.Arrow                        (left)
import Control.Concurrent.STM               (atomically, modifyTVar, readTVarIO)
import Control.Exception
import Control.Lens
import Control.Monad.Except
import Control.Monad.Reader
import Data.Aeson                           as J
import Data.ByteString                      (ByteString)
import Data.ByteString.Lazy                 (fromStrict, toStrict)
import Data.Generics.Product.Any
import Data.Maybe                           (catMaybes)
import Data.Monoid
import GHC.Generics
import HaskellWorks.Data.Conduit.Combinator
import Kafka.Avro
import Kafka.Conduit.Source
import Network.AWS
import Options.Applicative

import qualified App.AppEnv                as E
import qualified App.Has                   as H
import qualified App.Options.Types         as Z
import qualified Arbor.Network.StatsD      as S
import qualified Arbor.Network.StatsD.Type as Z
import qualified Data.Avro.Decode          as A
import qualified Data.Avro.Schema          as A
import qualified Data.Avro.Types           as A
import qualified Data.ByteString.Char8     as C8
import qualified Data.Conduit.List         as L
import qualified Data.Text                 as T
import qualified Kafka.Conduit.Source      as K

type RewriteJson = String

data CmdKafkaToSqs = CmdKafkaToSqs
  { inputTopic              :: TopicName
  , consumerGroupId         :: ConsumerGroupId
  , outputSqsUrl            :: String
  , rewriteJson             :: [RewriteJson]
  , kafkaConfig             :: Z.KafkaConfig
  } deriving (Show, Eq, Generic)

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
  <*> strOption
        (  long "output-sqs-url"
        <> metavar "OUTPUT_SQS_URL"
        <> help "Kafka consumer group id")
  <*> many
      ( strOption
        (  long "rewrite-json"
        <> metavar "REWRITE_STRATEGY"
        <> help "Rewrite JSON strategy")
      )
  <*> kafkaConfigParser

instance H.HasKafkaConfig (Z.GlobalOptions CmdKafkaToSqs) where
  kafkaConfig = the @"cmd" . the @"kafkaConfig"

instance H.HasKafkaConfig (E.AppEnv CmdKafkaToSqs) where
  kafkaConfig = the @"options" . H.kafkaConfig

instance RunApplication CmdKafkaToSqs where
  runApplication envApp = runApplicationM envApp $ runExceptT $ do
    opt               <- view $ the @"options"
    kafkaConf         <- view H.kafkaConfig
    env               <- ask
    processedMessages <- view $ the @"counters" . the @"processedMessages"
    let lgr   = env ^. the @"logger" . the @"logger"
    let stats = env ^. the @"statsClient"

    rjs <- opt ^. the @"cmd" . the @"rewriteJson" <&> pickRewriteJson & sequence

    let rj = rjs & foldr rewriteOrElse (const (throw (AppErr "Failed to rewrite")))

    logDebug "Debug logging enabled"

    logInfo "Creating Kafka Consumer"
    consumer <- mkConsumer
      (opt ^. the @"cmd" . the @"consumerGroupId")
      (opt ^. the @"cmd" . the @"inputTopic")
      (onRebalance lgr stats)

    logInfo "Instantiating Schema Registry"
    sr <- schemaRegistry (kafkaConf ^. the @"schemaRegistryAddress")

    logInfo "Running Kafka Consumer"
    runConduit $
      kafkaSourceNoClose consumer (kafkaConf ^. the @"pollTimeoutMs")
      .| effectC (\e -> logDebug $ "Message: " <> show e)
      .| throwLeftSatisfyC KafkaErr isFatal             -- throw any fatal error
      .| skipNonFatalExcept [isPollTimeout]             -- discard any non-fatal except poll timeouts
      .| rightC (jumpGuard consumer)
      .| effectC (\case
        Left y -> do
          logDebug $ "Error polling message: " <> show y
          return Nothing
        Right cr -> do
          logDebug $ "Polled message: " <> show (K.unPartitionId (crPartition cr)) <> ":" <> show (K.unOffset (crOffset cr))
          liftIO $ atomically $ modifyTVar processedMessages (+1)
          return $ Just cr)
      .| rightC (handleStream rj opt sr)                      -- handle messages (see Service.hs)
      .| everyNSeconds (kafkaConf ^. the @"commitPeriodSec")  -- only commit ever N seconds, so we don't hammer Kafka.
      .| effectC' (do
          n <- liftIO $ readTVarIO processedMessages
          logInfo $ "Committing offsets.  Messages processed: " <> show n)
      .| effectC' (commitAllOffsets OffsetCommit consumer)
      .| sinkNull

onRebalance :: TimedFastLogger -> StatsClient -> RebalanceEvent -> IO ()
onRebalance lgr stats e = case e of
  RebalanceBeforeAssign ps -> do
    let partitionsText = "Partitions assigned: " <> T.pack (show (K.unPartitionId . snd <$> ps))
    pushLogMessage lgr LevelInfo $ "kafka-to-sqs: Rebalanced. " <> partitionsText
    S.sendEvt stats $ S.event "Rebalanced" partitionsText
  RebalanceRevoke ps -> do
    let partitionsText = "Partitions revoked: " <> T.pack (show (K.unPartitionId . snd <$> ps))
    pushLogMessage lgr LevelInfo $ "kafka-to-sqs: Rebalancing. " <> partitionsText
    S.sendEvt stats $ S.event "Rebalancing" partitionsText
  _ -> pure ()

-- | Handles the stream of incoming messages.
-- Emit values downstream because offsets are committed based on their present.
handleStream  :: MonadApp CmdKafkaToSqs m
              => (J.Value -> ExceptT AppError m J.Value)
              -> Z.GlobalOptions CmdKafkaToSqs
              -> SchemaRegistry
              -> ConduitT (ConsumerRecord (Maybe ByteString) (Maybe ByteString)) () (ExceptT AppError m) ()
handleStream rj opt sr =
  mapC crValue                 -- extracting only value from consumer record
  .| L.catMaybes               -- discard empty values
  .| mapMC (decodeMessage sr)  -- decode avro message.
  .| mapC failBadly            -- error on decode failure
  .| mapC J.toJSON
  .| mapMC rj
  .| mapC pure
  .| batchByOrFlush 10
  .| mapMC (sendSqsBatch queueUrl)
  where queueUrl    = T.pack (opt ^. the @"cmd" . the @"outputSqsUrl")

sendSqsBatch :: (MonadAWS m, MonadResource m)
  => T.Text
  -> [J.Value]
  -> m ()
sendSqsBatch queueUrl msgs =
  sendSqs queueUrl (msgs <&> T.pack . C8.unpack . toStrict . J.encode)

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
throwLeftC :: MonadError AppError m => (e -> AppError) -> ConduitT (Either e a) (Either e a) m ()
throwLeftC f = awaitForever $ \msg ->
  throwErrorAs f msg

throwLeftSatisfyC :: MonadError AppError m => (e -> AppError) -> (e -> Bool) -> ConduitT (Either e a) (Either e a) m ()
throwLeftSatisfyC f p = awaitForever $ \case
    Right a -> yield (Right a)
    Left e  | p e -> throwErrorAs f (Left e)
    Left e  -> yield (Left e)

-------------------------------------------------------------------------------

withStatsClient :: AppName -> Z.StatsConfig -> (StatsClient -> IO a) -> IO a
withStatsClient appName statsConf f = do
  globalTags <- mkStatsTags statsConf
  let statsOpts = Z.DogStatsSettings (statsConf ^. the @"host") (statsConf ^. the @"port")
  bracket (S.createStatsClient statsOpts (Z.MetricName appName) globalTags) S.closeStatsClient f

mkStatsTags :: Z.StatsConfig -> IO [Z.Tag]
mkStatsTags statsConf = do
  deplId <- S.envTag "TASK_DEPLOY_ID" "deploy_id"
  let envTags = catMaybes [deplId]
  return $ envTags <> (statsConf ^. the @"tags" <&> toTag)
  where toTag (Z.StatsTag (k, v)) = S.tag k v

rewriteOrElse :: Monad m
  => (J.Value -> ExceptT AppError m J.Value)
  -> (J.Value -> ExceptT AppError m J.Value)
  -> J.Value
  -> ExceptT AppError m J.Value
rewriteOrElse f g v = f v `catchError` const (g v)

pickRewriteJson :: Monad m => String -> ExceptT AppError m (J.Value -> ExceptT AppError m J.Value)
pickRewriteJson strategyName = case strategyName of
  "fcm-to-rc" -> return fileChangeMessageToResourceChanged
  "id"        -> return return
  unknown     -> throwError $ AppErr $ "Unknown rewrite strategy: " <> unknown
