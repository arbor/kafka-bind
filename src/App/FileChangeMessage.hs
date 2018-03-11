{-# LANGUAGE TemplateHaskell #-}

module App.FileChangeMessage
where

import Data.Aeson
import Data.Avro.Deriving
import HaskellWorks.Data.Aeson

-- automagically creates data types and ToAvro/FromAvro instances
-- for a given schema.
deriveAvro "contract/file_change_message.avsc"

instance ToJSON FileChangeMessage where
  toJSON r = objectWithoutNulls
    [ "eventName"  .= fileChangeMessageEventName  r
    , "eventTime"  .= fileChangeMessageEventTime  r
    , "bucketName" .= fileChangeMessageBucketName r
    , "objectKey"  .= fileChangeMessageObjectKey  r
    , "objectSize" .= fileChangeMessageObjectSize r
    , "objectTag"  .= fileChangeMessageObjectTag  r
    ]
