{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module App.DecodeSpec (spec) where

import App.FileChangeMessage
import App.SqsMessage
import HaskellWorks.Hspec.Hedgehog
import Hedgehog
import Test.Hspec
import Text.RawString.QQ

import qualified Data.Text as T

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

exampleS3PutMessage :: T.Text
exampleS3PutMessage = [r|
  {
    "Type" : "Notification",
    "MessageId" : "875ecfdc-7e3b-580e-8c9d-9cd5ec8765fb",
    "TopicArn" : "arn:aws:sns:us-west-2:143032791481:bucket-name-topic",
    "Subject" : "Amazon S3 Notification",
    "Message" : "{\"Records\":[{\"eventVersion\":\"2.0\",\"eventSource\":\"aws:s3\",\"awsRegion\":\"us-west-2\",\"eventTime\":\"2018-02-23T03:54:35.970Z\",\"eventName\":\"ObjectCreated:Copy\",\"userIdentity\":{\"principalId\":\"AWS:AIDAJAL75C3RB3PKI7HKQ\"},\"requestParameters\":{\"sourceIPAddress\":\"61.88.11.160\"},\"responseElements\":{\"x-amz-request-id\":\"E14924D002ECB131\",\"x-amz-id-2\":\"uRQ60xweMvw+wANFMbLZLR7mrXYT6Rkz/bzwbncCx8k2Etcx7jyk5WsVFfBt2EEebfYD8lg+QOM=\"},\"s3\":{\"s3SchemaVersion\":\"1.0\",\"configurationId\":\"YzMyMWRjYWUtYzE5MC00ZjcxLWFkMTItMzc1NjE0MGNjOWU4\",\"bucket\":{\"name\":\"bucket-name\",\"ownerIdentity\":{\"principalId\":\"A1T0U83IEG360Q\"},\"arn\":\"arn:aws:s3:::bucket-name\"},\"object\":{\"key\":\"1.2.3.4-1514864593.00\",\"size\":336,\"sequencer\":\"005A8F907BD60CAFF1\"}}}]}",
    "Timestamp" : "2018-02-23T03:54:36.132Z",
    "SignatureVersion" : "1",
    "Signature" : "cPvrn3nF07JrnP5YsPc5NO8OtdSQz57ovpA7ncWIbfgcJlys+HGEyYLqcyH6tn1KCPGfkzWkBXvrQ2X+Viph8wkmLjlI9iSyaen7biJcUMAi1gju5EDDP31W+1FuNdVcmJd8AJ0cyWbUCk2/DzepnbN3kE9Pb/KxwWuMuTMsfNNgXoCjE3slCVxIaNBJtWt/lJ/EYy4YU0mMy6vlKDYjyl0a8Np6moS8m/hENHeIoZ0WtZ3cFF6fVqXpL00LfHPCYAd9O9mZ3FaB+1NCuYZ2z2sDSnmbKl9BNkqVAuiS/YI5frYn7QFw+OGJ+TK7bMWGXu9A3Z/abBdbnsXcrRL5Iw==",
    "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-433026a4050d206028891664da859041.pem",
    "UnsubscribeURL" : "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-west-2:143032791481:bucket-name-topic:bd435f50-bbc7-464d-b76b-eda1ed5163b8"
  }
  |]

spec :: Spec
spec = describe "App.DecodeSpec" $ do
  it "should parse s3 copy event" $ require $ withTests 1 $ property $ do
    let expected = Just $ SqsMessageOfFileChangeMessage FileChangeMessage
          { fileChangeMessageEventName = "ObjectCreated:Copy"
          , fileChangeMessageEventTime = "2018-02-23T03:54:35.970Z"
          , fileChangeMessageBucketName = "bucket-name"
          , fileChangeMessageObjectKey = "1.2.3.4-1514864593.00"
          , fileChangeMessageObjectSize = 336
          , fileChangeMessageObjectTag = ""
          }
    decodeSqsNotificationBody exampleS3PutMessage === expected
