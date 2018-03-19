{-# LANGUAGE MultiParamTypeClasses #-}
module App.Kafka
  ( ConsumerGroupSuffix(..), TopicName(..)
  , KafkaConsumer, KafkaProducer, Timeout(..)
  , mkConsumer
  , mkProducer
  , unPartitionId
  , unOffset
  , jumpGuard
  ) where

import App.AppEnv
import App.AppError
import App.Options
import Arbor.Logger
import Control.Lens                 hiding (cons)
import Control.Monad                (void)
import Control.Monad.Logger         (LogLevel (..))
import Control.Monad.Reader
import Control.Monad.Trans.Resource
import Data.Conduit
import Data.Foldable
import Data.Int
import Data.List.Split
import Data.Monoid                  ((<>))
import Kafka.Conduit.Sink           as KSnk
import Kafka.Conduit.Source         as KSrc

import qualified Data.Map as M

newtype ConsumerGroupSuffix = ConsumerGroupSuffix String deriving (Show, Eq)

mkConsumer :: (MonadResource m, MonadReader r m, HasKafkaConfig r, HasLogger r)
            => ConsumerGroupId
            -> TopicName
            -> (RebalanceEvent -> IO ())
            -> m KafkaConsumer
mkConsumer cgid topic onRebalance = do
  conf <- view kafkaConfig
  logs <- view logger
  let props = fold
        [ KSrc.brokersList [conf ^. broker]
        , cgid & groupId
        , conf ^. queuedMaxMsgKBytes & queuedMaxMessagesKBytes
        , noAutoCommit
        , KSrc.suppressDisconnectLogs
        , KSrc.logLevel (kafkaLogLevel (logs ^. lgLogLevel))
        , KSrc.debugOptions (kafkaDebugEnable (conf ^. debugOpts))
        , KSrc.setCallback (logCallback   (\l s1 s2 -> pushLogMessage (logs ^. lgLogger) (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
        , KSrc.setCallback (errorCallback (\e s -> pushLogMessage (logs ^. lgLogger) LevelError ("[" <> show e <> "] " <> s)))
        , KSrc.setCallback (rebalanceCallback (\_ e -> onRebalance e))
        ]
      sub = topics [topic] <> offsetReset Earliest
      cons = newConsumer props sub >>= either throwM return
  snd <$> allocate cons (void . closeConsumer)

mkProducer :: (MonadResource m, MonadReader r m, HasKafkaConfig r, HasLogger r) => m KafkaProducer
mkProducer = do
  conf <- view kafkaConfig
  logs <- view logger
  let props = KSnk.brokersList [conf ^. broker]
           <> KSnk.suppressDisconnectLogs
           <> KSnk.sendTimeout (Timeout 0) -- message sending timeout, 0 means "no timeout"
           <> KSnk.logLevel (kafkaLogLevel (logs ^. lgLogLevel))
           <> KSnk.setCallback (logCallback   (\l s1 s2 -> pushLogMessage (logs ^. lgLogger) (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
           <> KSnk.setCallback (errorCallback (\e s -> pushLogMessage (logs ^. lgLogger) LevelError ("[" <> show e <> "] " <> s)))
           <> KSnk.setCallback (deliveryErrorsCallback (logAndDieHard (logs ^. lgLogger)))
           <> KSnk.extraProps (M.singleton "linger.ms"                 "100")
           <> KSnk.extraProps (M.singleton "message.send.max.retries"  "0"  )
           <> KSnk.compression Gzip
      prod = newProducer props >>= either throwM return
  snd <$> allocate prod closeProducer

logAndDieHard :: TimedFastLogger -> KafkaError -> IO ()
logAndDieHard lgr err = do
  let errMsg = "Producer is unable to deliver messages: " <> show err
  pushLogMessage lgr LevelError errMsg
  error errMsg

kafkaLogLevel :: LogLevel -> KafkaLogLevel
kafkaLogLevel l = case l of
  LevelDebug   -> KafkaLogDebug
  LevelInfo    -> KafkaLogInfo
  LevelWarn    -> KafkaLogWarning
  LevelError   -> KafkaLogErr
  LevelOther _ -> KafkaLogCrit

kafkaLogLevelToLogLevel :: KafkaLogLevel -> LogLevel
kafkaLogLevelToLogLevel l = case l of
  KafkaLogDebug   -> LevelDebug
  KafkaLogInfo    -> LevelInfo
  KafkaLogWarning -> LevelWarn
  KafkaLogErr     -> LevelError
  KafkaLogCrit    -> LevelError
  KafkaLogAlert   -> LevelWarn
  KafkaLogNotice  -> LevelInfo
  KafkaLogEmerg   -> LevelError

kafkaDebugEnable :: String -> [KafkaDebug]
kafkaDebugEnable str = map debug (splitWhen (== ',') str)
  where
    debug :: String -> KafkaDebug
    debug m = case m of
      "generic"  -> DebugGeneric
      "broker"   -> DebugBroker
      "topic"    -> DebugTopic
      "metadata" -> DebugMetadata
      "queue"    -> DebugQueue
      "msg"      -> DebugMsg
      "protocol" -> DebugProtocol
      "cgrp"     -> DebugCgrp
      "security" -> DebugSecurity
      "fetch"    -> DebugFetch
      "feature"  -> DebugFeature
      "all"      -> DebugAll
      _          -> DebugGeneric

unPartitionId :: PartitionId -> Int
unPartitionId (PartitionId p) = p

unOffset :: Offset -> Int64
unOffset (Offset o) = o

-- Detects sudden offsets jumps in a stream and compensates
-- by seeking to the expected positions.
jumpGuard :: (MonadIO m, MonadLogger m, MonadThrow m)
          => KafkaConsumer
          -> Conduit (ConsumerRecord k v) m (ConsumerRecord k v)
jumpGuard consumer = go M.empty
  where
    go state = do
      mmsg <- await
      case mmsg of
        Nothing  -> pure () -- stream has exhausted
        Just msg -> do
          -- was there a jump? Should we compensate?
          (mjmp, state') <- compensateJumpPos consumer msg state
          case mjmp of
            Nothing -> do
              --  No jump, great! Yield the message downstream, update  state and recurse
              let (rt, rp, Offset ro) = (crTopic msg, crPartition msg, crOffset msg)
              yield msg
              go (M.insert (rt, rp) (PartitionOffset ro) state')
            Just pos -> do
              -- Jump detected! Report it and seek back to a compensating position
              reportProblem (crTopic msg) (crPartition msg) (crOffset msg) (tpOffset pos)
              seek consumer (Timeout 10000) [pos] >>= throwAs' KafkaErr
              go state'

    reportProblem t p srcOffset dstOffset = do
      let errMsg = "Jump detected for" <> show (t, p) <> ": " <> show srcOffset <> " -> " <> show dstOffset
      logWarn errMsg

-- | Detects sudden jumps in offsets and provides positions to compensate (seek) if necessary.
--
-- Checks current record offset against what has been seen already.
-- When there is no "seen" offsets for a given patition, latest committed offset is used.
--
-- The return is a tuple of:
-- 1. Optional position to compensate for the jump ('Nothing' if no jump detected).
-- 2. Updated "seen" positions.
--
-- When a compensation position is returned the cunsumer is expected to 'seek' to that
-- position to compensate for a jump.
compensateJumpPos :: (MonadIO m, MonadThrow m)
                  => KafkaConsumer
                  -> ConsumerRecord k v -- received record
                  -> M.Map (TopicName, PartitionId) PartitionOffset -- seen offsets (state)
                  -> m (Maybe TopicPartition, M.Map (TopicName, PartitionId) PartitionOffset)
                     -- ^ Maybe position to jump to (compensate) + new seen offsets (state)
compensateJumpPos consumer cr mem = do
  let (rt, rp, Offset ro) = (crTopic cr, crPartition cr, crOffset cr)
  let lastPos = M.lookup (rt, rp) mem
  case lastPos of
    _                          | ro == 0     -> pure (Nothing, mem) -- 1st record, OK
    Just (PartitionOffset pos) | ro <= pos+1 -> pure (Nothing, mem) -- expected, OK
    _ -> do
      comm <- committed consumer (Timeout 10000) [(rt, rp)] >>= throwAs KafkaErr
      let mem' = (M.fromList $ tupledTP <$> comm) `M.union` mem
      case M.lookup (rt, rp) mem' of
        Just (PartitionOffset pos) | ro <= pos+1 -> pure (Nothing, mem') -- expected, OK
        Just (PartitionOffset pos) -> pure (Just $ TopicPartition rt rp (PartitionOffset pos), mem')
        _                          -> pure (Just $ TopicPartition rt rp PartitionOffsetBeginning, mem')
  where
    tupledTP tp = ((tpTopicName tp, tpPartition tp), tpOffset tp)
