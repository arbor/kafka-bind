{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE QuasiQuotes           #-}

module App.JsonSpec (spec) where

import App.Json
import HaskellWorks.Hspec.Hedgehog
import Hedgehog
import Test.Hspec

import qualified Antiope.Contract.SQS.FileChangeMessage as Z
import qualified Antiope.Contract.SQS.ResourceChanged   as Z
import qualified Data.Aeson                             as J

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

spec :: Spec
spec = describe "App.JsonSpec" $ do
  it "should be able to convert file change message to resource changed" $ require $ withTests 1 $ property $ do
    let fcm = Z.FileChangeMessage
          { Z.eventName   = "ObjectCreated:Copy"
          , Z.eventTime   = "2018-02-23T03:54:35.970Z"
          , Z.bucketName  = "bucket-name"
          , Z.objectKey   = "1.2.3.4-1514864593.00"
          , Z.objectSize  = 336
          , Z.objectTag   = ""
          }
    let rc = Z.ResourceChanged
          { Z.eventTime   = "2018-02-23T03:54:35.970Z"
          , Z.uri         = "s3://bucket-name/1.2.3.4-1514864593.00"
          }
    fileChangeMessageToResourceChanged (J.toJSON fcm) === (J.toJSON rc)
