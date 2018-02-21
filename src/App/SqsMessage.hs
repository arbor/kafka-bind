module App.SqsMessage
  ( decodeSqsMessage
  ) where

import App.FileChangeMessage
import Control.Lens
import Data.Aeson
import Data.Aeson.Lens
import Data.ByteString.Lazy  (fromStrict)
import Data.Maybe            (fromMaybe)
import Network.AWS.SQS.Types

import qualified Data.ByteString.Char8 as C8
import qualified Data.Text             as T

decodeSqsMessage :: Message -> Maybe FileChangeMessage
decodeSqsMessage sqsMessage = do
  -- level 1
  outermost <- sqsMessage ^. mBody
  let sqsJSON = fromStrict $ C8.pack $ T.unpack outermost
  decodedSqs <- decode sqsJSON
  -- level 2
  msgJson <- decodedSqs ^. key "Message"
  msg <- decode $ fromStrict $ C8.pack msgJson

  -- from atlasdos-submissions-balancer

  -- just 1 record in each sqs event
  record     <- msg       ^. key "Records" . nth 0
  bucket     <- record    ^. key "s3"     ^. key "bucket"
  objectAws  <- record    ^. key "s3"     ^. key "object"

  eventName  <- record    ^. key "eventName"
  eventTime  <- record    ^. key "eventTime"
  bucketName <- bucket    ^. key "name"
  objectKey  <- objectAws ^. key "key"
  objectSize <- objectAws ^. key "size"
  -- there is `eTag` field in ObjectCreated:Putevent and no such field in ObjectCreated:Copy
  let objectTag = fromMaybe "" (objectAws  ^. key "eTag")

  return FileChangeMessage
    { fileChangeMessageEventName  = eventName
    , fileChangeMessageEventTime  = eventTime
    , fileChangeMessageBucketName = bucketName
    , fileChangeMessageObjectKey  = objectKey
    , fileChangeMessageObjectSize = objectSize
    , fileChangeMessageObjectTag  = objectTag
    }
