module App.SqsMessage
  ( decodeSqsNotification
  , decodeSqsNotificationBody
  , SqsMessage (..)
  ) where

import Control.Lens
import Data.Aeson
import Data.Aeson.Lens
import Data.ByteString.Lazy (fromStrict)
import Data.Maybe           (fromMaybe)
import Network.AWS.SQS

import qualified Antiope.Contract.SQS.FileChangeMessage as Z
import qualified Data.ByteString.Char8                  as C8
import qualified Data.Text                              as T
import qualified Network.URI                            as URI

data SqsMessage
  = SqsMessageOfS3TestEvent
  | SqsMessageOfFileChangeMessage Z.FileChangeMessage
  | NoMessage
  deriving (Eq, Show)

decodeSqsNotification :: Message -> Maybe SqsMessage
decodeSqsNotification sqsMessage = case sqsMessage ^. mBody of
  Just body -> decodeSqsNotificationBody body
  Nothing   -> Just NoMessage

decodeSqsNotificationBody :: T.Text -> Maybe SqsMessage
decodeSqsNotificationBody body = do
    let sqsJson = fromStrict $ C8.pack $ T.unpack body
    let decodedSqs = decode sqsJson

    -- level 2
    msgJson <- decodedSqs ^. key "Message"

    let msg = decode $ fromStrict $ C8.pack msgJson :: Maybe Value

    case msg ^. key "Event" :: Maybe String of
      -- check if test event
      Just event ->
        if event == "s3:TestEvent"
          then Just SqsMessageOfS3TestEvent
          else Just NoMessage

      -- otherwise, it's a real message
      Nothing -> decodeSqsMessage msg

decodeSqsMessage :: Maybe Value -> Maybe SqsMessage
decodeSqsMessage msg = do
   -- just 1 record in each sqs event
  record     <- msg       ^. key "Records" . nth 0
  bucket     <- record    ^. key "s3"     ^. key "bucket"
  objectAws  <- record    ^. key "s3"     ^. key "object"

  eventName  <- record    ^. key "eventName"
  eventTime  <- record    ^. key "eventTime"
  bucketName <- bucket    ^. key "name"
  objectKey  <- objectAws ^. key "key"

  let objectSize = objectAws ^. key "size" & fromMaybe 0
  -- there is `eTag` field in ObjectCreated:Putevent and no such field in ObjectCreated:Copy
  let objectTag = fromMaybe "" (objectAws ^. key "eTag")

  return $ SqsMessageOfFileChangeMessage
    Z.FileChangeMessage
      { Z.eventName  = eventName
      , Z.eventTime  = eventTime
      , Z.bucketName = bucketName
      , Z.objectKey  = T.pack . URI.unEscapeString . T.unpack $ objectKey
      , Z.objectSize = objectSize
      , Z.objectTag  = objectTag
      }
