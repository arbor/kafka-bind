{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

module App.Json where

import App.AppError
import Control.Lens
import Control.Monad.Trans.Except
import Data.Generics.Product.Any
import Data.Monoid

import qualified Antiope.Contract.SQS.FileChangeMessage as SQSM
import qualified Antiope.Contract.SQS.ResourceChanged   as SQSM
import qualified Data.Aeson                             as J

fileChangeMessageToResourceChanged :: Monad m => J.Value -> ExceptT AppError m J.Value
fileChangeMessageToResourceChanged v = case J.fromJSON v of
  J.Success (fcm :: SQSM.FileChangeMessage) -> return $ J.toJSON $ SQSM.ResourceChanged
    { SQSM.eventTime  = fcm ^. the @"eventTime"
    , SQSM.uri        = "s3://" <> (fcm ^. the @"bucketName") <> "/" <> (fcm ^. the @"objectKey")
    }
  J.Error msg                               -> throwError (AppErr msg)
