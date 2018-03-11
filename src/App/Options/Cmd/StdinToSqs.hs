{-# LANGUAGE DeriveAnyClass        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}

module App.Options.Cmd.StdinToSqs where

import App
import App.AWS.Sqs
import App.FileChangeMessage
import App.RunApplication
import Arbor.Logger
import Conduit
import Control.Lens
import Data.Aeson            as J
import Data.ByteString.Char8 as C8
import Data.ByteString.Lazy  (toStrict)
import Data.Monoid
import Network.AWS
import Options.Applicative

import qualified Data.Text as T

data CmdStdinToSqs = CmdStdinToSqs
  { _outputSqsUrl  :: String
  , _fcmEventName  :: String
  , _fcmEventTime  :: String
  , _fcmBucketName :: String
  , _fcmObjectKey  :: String
  , _fcmObjectSize :: String
  , _fcmObjectTag  :: String
  } deriving (Show, Eq)

makeLenses ''CmdStdinToSqs

parserCmdStdinToSqs :: Parser CmdStdinToSqs
parserCmdStdinToSqs = CmdStdinToSqs
  <$> strOption
        (  long "output-sqs-url"
        <> metavar "OUTPUT_SQS_URL"
        <> help "Kafka consumer group id")
  <*> strOption
        (  long "fcm-eventname"
        <> metavar "FCM_EVENTNAME"
        <> help "FileChangeMessage EventName")
  <*> strOption
        (  long "fcm-eventtime"
        <> metavar "FCM_EVENTTIME"
        <> help "FileChangeMessage EventTime")
  <*> strOption
        (  long "fcm-bucketname"
        <> metavar "FCM_BUCKETNAME"
        <> help "FileChangeMessage BucketName")
  <*> strOption
        (  long "fcm-objectkey"
        <> metavar "FCM_OBJECTKEY"
        <> help "FileChangeMessage ObjectKey")
  <*> strOption
        (  long "fcm-objectsize"
        <> metavar "FCM_OBJECTSIZE"
        <> help "FileChangeMessage ObjectSize")
  <*> strOption
        (  long "fcm-objecttag"
        <> metavar "FCM_OBJECTTAG"
        <> help "FileChangeMessage ObjectTag")

instance RunApplication CmdStdinToSqs where
  runApplication envApp = runApplicationM envApp $ do
    opt <- view appOptions

    logInfo "Sending to Sqs"

    let fcm = FileChangeMessage
              { fileChangeMessageEventName  = T.pack $ opt ^. optCmd ^. fcmEventName
              , fileChangeMessageEventTime  = T.pack $ opt ^. optCmd ^. fcmEventTime
              , fileChangeMessageBucketName = T.pack $ opt ^. optCmd ^. fcmBucketName
              , fileChangeMessageObjectKey  = T.pack $ opt ^. optCmd ^. fcmObjectKey
              , fileChangeMessageObjectSize = read $ opt ^. optCmd ^. fcmObjectSize
              , fileChangeMessageObjectTag  = T.pack $ opt ^. optCmd ^. fcmObjectTag
              }

    sendFcmToSqs (T.pack $ opt ^. optCmd ^. outputSqsUrl) fcm

sendFcmToSqs :: (MonadAWS m, MonadResource m)
  => T.Text
  -> FileChangeMessage
  -> m ()
sendFcmToSqs queueUrl = sendSqs queueUrl . T.pack . C8.unpack . toStrict . J.encode
