{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeApplications      #-}

module App.Json where

import Control.Lens
import Data.Aeson                as J
import Data.Generics.Product.Any
import Data.Monoid

import qualified Antiope.Contract.SQS.FileChangeMessage as SQSM
import qualified Antiope.Contract.SQS.ResourceChanged   as SQSM

fileChangeMessageToResourceChanged :: J.Value -> J.Value
fileChangeMessageToResourceChanged v = case J.fromJSON v of
  J.Success (fcm :: SQSM.FileChangeMessage) -> J.toJSON $ SQSM.ResourceChanged
    { SQSM.eventTime  = fcm ^. the @"eventTime"
    , SQSM.uri        = "s3://" <> (fcm ^. the @"bucketName") <> "/" <> (fcm ^. the @"objectKey")
    }
  J.Error _                                 -> v
