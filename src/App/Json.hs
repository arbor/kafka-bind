{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
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
import qualified Data.Text                              as T
import qualified Network.URI                            as URI

fileChangeMessageToResourceChanged :: Monad m => J.Value -> ExceptT AppError m J.Value
fileChangeMessageToResourceChanged v = case J.fromJSON v of
  J.Success (fcm :: SQSM.FileChangeMessage) -> return $ J.toJSON $ SQSM.ResourceChanged
    { SQSM.eventTime  = fcm ^. the @"eventTime"
    , SQSM.uri        = "s3://" <> (fcm ^. the @"bucketName") <> "/" <> (unescape $ fcm ^. the @"objectKey")
    }
  J.Error msg                               -> throwError (AppErr msg)
  where
    unescape = T.pack . URI.unEscapeString . T.unpack
