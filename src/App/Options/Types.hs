{-# LANGUAGE FlexibleInstances #-}

module App.Options.Types where

import Arbor.Network.StatsD.Type (SampleRate (..))
import Control.Monad.Logger      (LogLevel (..))
import Data.Text                 (Text)
import GHC.Generics
import Kafka.Types
import Network.AWS.S3.Types      (Region (..))
import Network.Socket            (HostName)

newtype StatsTag = StatsTag (Text, Text) deriving (Show, Eq)

data KafkaConfig = KafkaConfig
  { broker                :: BrokerAddress
  , schemaRegistryAddress :: String
  , pollTimeoutMs         :: Timeout
  , queuedMaxMsgKBytes    :: Int
  , debugOpts             :: String
  , commitPeriodSec       :: Int
  } deriving (Eq, Show, Generic)

data StatsConfig = StatsConfig
  { host       :: HostName
  , port       :: Int
  , tags       :: [StatsTag]
  , sampleRate :: SampleRate
  } deriving (Eq, Show, Generic)

data GlobalOptions a = GlobalOptions
  { logLevel    :: LogLevel
  , region      :: Region
  , cmd         :: a
  , statsConfig :: StatsConfig
  } deriving (Show, Generic)
