{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications      #-}

module App.Kafka
  ( ConsumerGroupSuffix(..), K.TopicName(..)
  , K.KafkaConsumer, K.KafkaProducer, K.Timeout(..)
  , mkConsumer
  , mkProducer
  , unPartitionId
  , unOffset
  , jumpGuard
  ) where

import App.AppError
import Arbor.Logger
import Control.Lens                 hiding (cons)
import Control.Monad                (void)
import Control.Monad.Logger         (LogLevel (..))
import Control.Monad.Reader
import Control.Monad.Trans.Resource
import Data.Conduit
import Data.Foldable
import Data.Generics.Product.Any
import Data.Int
import Data.List.Split
import Data.Monoid                  ((<>))

import qualified App.Has              as H
import qualified Data.Map             as M
import qualified Kafka.Conduit.Sink   as KSnk
import qualified Kafka.Conduit.Sink   as K
import qualified Kafka.Conduit.Source as KSrc
import qualified Kafka.Conduit.Source as K

newtype ConsumerGroupSuffix = ConsumerGroupSuffix String deriving (Show, Eq)

mkConsumer :: (MonadResource m, MonadReader r m, H.HasKafkaConfig r, H.HasLogger r)
            => K.ConsumerGroupId
            -> K.TopicName
            -> (K.RebalanceEvent -> IO ())
            -> m K.KafkaConsumer
mkConsumer cgid topic onRebalance = do
  conf <- view H.kafkaConfig
  logs <- view H.logger
  let props = fold
        [ KSrc.brokersList [conf ^. the @"broker"]
        , cgid & K.groupId
        , conf ^. the @"queuedMaxMsgKBytes" & K.queuedMaxMessagesKBytes
        , K.noAutoCommit
        , KSrc.suppressDisconnectLogs
        , KSrc.logLevel (kafkaLogLevel (logs ^. the @"logLevel"))
        , KSrc.debugOptions (kafkaDebugEnable (conf ^. the @"debugOpts"))
        , KSrc.setCallback (K.logCallback   (\l s1 s2 -> pushLogMessage (logs ^. the @"logger") (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
        , KSrc.setCallback (K.errorCallback (\e s -> pushLogMessage (logs ^. the @"logger") LevelError ("[" <> show e <> "] " <> s)))
        , KSrc.setCallback (K.rebalanceCallback (\_ e -> onRebalance e))
        ]
      sub = K.topics [topic] <> K.offsetReset K.Earliest
      cons = K.newConsumer props sub >>= either throwM return
  snd <$> allocate cons (void . K.closeConsumer)

mkProducer :: (MonadResource m, MonadReader r m, H.HasKafkaConfig r, H.HasLogger r) => m K.KafkaProducer
mkProducer = do
  conf <- view H.kafkaConfig
  logs <- view H.logger
  let props = KSnk.brokersList [conf ^. the @"broker"]
           <> KSnk.suppressDisconnectLogs
           <> KSnk.sendTimeout (K.Timeout 0) -- message sending timeout, 0 means "no timeout"
           <> KSnk.logLevel (kafkaLogLevel (logs ^. the @"logLevel"))
           <> KSnk.setCallback (K.logCallback   (\l s1 s2 -> pushLogMessage (logs ^. the @"logger") (kafkaLogLevelToLogLevel $ toEnum l) ("[" <> s1 <> "] " <> s2)))
           <> KSnk.setCallback (K.errorCallback (\e s -> pushLogMessage (logs ^. the @"logger") LevelError ("[" <> show e <> "] " <> s)))
           <> KSnk.setCallback (K.deliveryCallback (logAndDieHard (logs ^. the @"logger")))
           <> KSnk.extraProps (M.singleton "linger.ms"                 "100")
           <> KSnk.extraProps (M.singleton "message.send.max.retries"  "0"  )
           <> KSnk.compression K.Gzip
      prod = K.newProducer props >>= either throwM return
  snd <$> allocate prod K.closeProducer

logAndDieHard :: TimedFastLogger -> K.DeliveryReport -> IO ()
logAndDieHard lgr (K.DeliveryFailure _ err) = do
  let errMsg = "Producer is unable to deliver messages: " <> show err
  pushLogMessage lgr LevelError errMsg
  error errMsg
logAndDieHard _ _ = return ()

kafkaLogLevel :: LogLevel -> K.KafkaLogLevel
kafkaLogLevel l = case l of
  LevelDebug   -> K.KafkaLogDebug
  LevelInfo    -> K.KafkaLogInfo
  LevelWarn    -> K.KafkaLogWarning
  LevelError   -> K.KafkaLogErr
  LevelOther _ -> K.KafkaLogCrit

kafkaLogLevelToLogLevel :: K.KafkaLogLevel -> LogLevel
kafkaLogLevelToLogLevel l = case l of
  K.KafkaLogDebug   -> LevelDebug
  K.KafkaLogInfo    -> LevelInfo
  K.KafkaLogWarning -> LevelWarn
  K.KafkaLogErr     -> LevelError
  K.KafkaLogCrit    -> LevelError
  K.KafkaLogAlert   -> LevelWarn
  K.KafkaLogNotice  -> LevelInfo
  K.KafkaLogEmerg   -> LevelError

kafkaDebugEnable :: String -> [K.KafkaDebug]
kafkaDebugEnable str = map debug (splitWhen (== ',') str)
  where
    debug :: String -> K.KafkaDebug
    debug m = case m of
      "generic"  -> K.DebugGeneric
      "broker"   -> K.DebugBroker
      "topic"    -> K.DebugTopic
      "metadata" -> K.DebugMetadata
      "queue"    -> K.DebugQueue
      "msg"      -> K.DebugMsg
      "protocol" -> K.DebugProtocol
      "cgrp"     -> K.DebugCgrp
      "security" -> K.DebugSecurity
      "fetch"    -> K.DebugFetch
      "feature"  -> K.DebugFeature
      "all"      -> K.DebugAll
      _          -> K.DebugGeneric

unPartitionId :: K.PartitionId -> Int
unPartitionId (K.PartitionId p) = p

unOffset :: K.Offset -> Int64
unOffset (K.Offset o) = o

-- Detects sudden offsets jumps in a stream and compensates
-- by seeking to the expected positions.
jumpGuard :: (MonadIO m, MonadLogger m, MonadThrow m)
          => K.KafkaConsumer
          -> ConduitT (K.ConsumerRecord k v) (K.ConsumerRecord k v) m ()
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
              let (rt, rp, K.Offset ro) = (K.crTopic msg, K.crPartition msg, K.crOffset msg)
              yield msg
              go (M.insert (rt, rp) (K.PartitionOffset ro) state')
            Just pos -> do
              -- Jump detected! Report it and seek back to a compensating position
              reportProblem (K.crTopic msg) (K.crPartition msg) (K.crOffset msg) (K.tpOffset pos)
              K.seek consumer (K.Timeout 10000) [pos] >>= throwAs' KafkaErr
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
                  => K.KafkaConsumer
                  -> K.ConsumerRecord k v -- received record
                  -> M.Map (K.TopicName, K.PartitionId) K.PartitionOffset -- seen offsets (state)
                  -> m (Maybe K.TopicPartition, M.Map (K.TopicName, K.PartitionId) K.PartitionOffset)
                     -- ^ Maybe position to jump to (compensate) + new seen offsets (state)
compensateJumpPos consumer cr mem = do
  let (rt, rp, K.Offset ro) = (K.crTopic cr, K.crPartition cr, K.crOffset cr)
  let lastPos = M.lookup (rt, rp) mem
  case lastPos of
    _                            | ro == 0     -> pure (Nothing, mem) -- 1st record, OK
    Just (K.PartitionOffset pos) | ro <= pos+1 -> pure (Nothing, mem) -- expected, OK
    _ -> do
      comm <- K.committed consumer (K.Timeout 10000) [(rt, rp)] >>= throwAs KafkaErr
      let mem' = (M.fromList $ tupledTP <$> comm) `M.union` mem
      case M.lookup (rt, rp) mem' of
        Just (K.PartitionOffset pos) | ro <= pos + 1 -> pure (Nothing, mem') -- expected, OK
        Just (K.PartitionOffset pos)                 -> pure (Just $ K.TopicPartition rt rp (K.PartitionOffset pos), mem')
        _                                            -> pure (Just $ K.TopicPartition rt rp K.PartitionOffsetBeginning, mem')
  where
    tupledTP tp = ((K.tpTopicName tp, K.tpPartition tp), K.tpOffset tp)
