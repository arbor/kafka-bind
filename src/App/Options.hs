{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeApplications  #-}

module App.Options where

import Arbor.Network.StatsD.Type (SampleRate (..))
import Control.Lens
import Control.Monad.Logger      (LogLevel (..))
import Data.Generics.Product.Any
import Data.Semigroup            ((<>))
import Kafka.Types
import Network.AWS.Data.Text     (FromText (..), fromText)
import Options.Applicative
import Text.Read                 (readEither)

import qualified App.Options.Types as Z
import qualified Data.Text         as T
import qualified Network.AWS       as AWS

statsConfigParser :: Parser Z.StatsConfig
statsConfigParser = Z.StatsConfig
  <$> strOption
      (  long "statsd-host"
      <> metavar "HOST_NAME"
      <> showDefault <> value "127.0.0.1"
      <> help "StatsD host name or IP address")
  <*> readOption
      ( long "statsd-port"
        <> metavar "PORT"
        <> showDefault <> value 8125
        <> help "StatsD port"
        <> hidden)
  <*> ( string2Tags <$> strOption
        (  long "statsd-tags"
        <> metavar "TAGS"
        <> showDefault <> value []
        <> help "StatsD tags"))
  <*> ( SampleRate <$> readOption
        (  long "statsd-sample-rate"
        <> metavar "SAMPLE_RATE"
        <> showDefault <> value 0.01
        <> help "StatsD sample rate"))

kafkaConfigParser :: Parser Z.KafkaConfig
kafkaConfigParser = Z.KafkaConfig
  <$> ( BrokerAddress <$> strOption
        (  long "kafka-broker"
        <> metavar "ADDRESS:PORT"
        <> help "Kafka bootstrap broker"
        ))
  <*> strOption
      (  long "kafka-schema-registry"
      <> metavar "HTTP_URL:PORT"
      <> help "Schema registry address")
  <*> (Timeout <$> readOption
      (  long "kafka-poll-timeout-ms"
      <> metavar "KAFKA_POLL_TIMEOUT_MS"
      <> showDefault <> value 1000
      <> help "Kafka poll timeout (in milliseconds)"))
  <*> readOption
      (  long "kafka-queued-max-messages-kbytes"
      <> metavar "KAFKA_QUEUED_MAX_MESSAGES_KBYTES"
      <> showDefault <> value 100000
      <> help "Kafka queued.max.messages.kbytes")
  <*> strOption
      (  long "kafka-debug-enable"
      <> metavar "KAFKA_DEBUG_ENABLE"
      <> showDefault <> value "broker,protocol"
      <> help "Kafka debug modules, comma separated names: see debug in CONFIGURATION.md"
      )
  <*> readOption
      (  long "kafka-consumer-commit-period-sec"
      <> metavar "KAFKA_CONSUMER_COMMIT_PERIOD_SEC"
      <> showDefault <> value 60
      <> help "Kafka consumer offsets commit period (in seconds)"
      )

awsLogLevel :: Z.GlobalOptions a -> AWS.LogLevel
awsLogLevel o = case o ^. the @"logLevel" of
  LevelError -> AWS.Error
  LevelWarn  -> AWS.Error
  LevelInfo  -> AWS.Error
  LevelDebug -> AWS.Info
  _          -> AWS.Trace

readOption :: Read a => Mod OptionFields a -> Parser a
readOption = option $ eitherReader readEither

readOptionMsg :: Read a => String -> Mod OptionFields a -> Parser a
readOptionMsg msg = option $ eitherReader (either (Left . const msg) Right . readEither)

readOrFromTextOption :: (Read a, FromText a) => Mod OptionFields a -> Parser a
readOrFromTextOption = option $ eitherReader fromStr
  where fromStr s = readEither s <|> fromText (T.pack s)

string2Tags :: String -> [Z.StatsTag]
string2Tags s = Z.StatsTag . splitTag <$> splitTags
  where splitTags = T.split (== ',') (T.pack s)
        splitTag t = T.drop 1 <$> T.break (== ':') t
