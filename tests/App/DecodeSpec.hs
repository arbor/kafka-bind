{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module App.DecodeSpec (spec) where

import App.SqsMessage
import HaskellWorks.Hspec.Hedgehog
import Hedgehog
import Test.Hspec
import Text.RawString.QQ

import qualified Antiope.Contract.SQS.FileChangeMessage as Z
import qualified Data.Text                              as T

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

exampleS3CopyMessage :: T.Text
exampleS3CopyMessage = [r|
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

exampleS3PutMessage :: T.Text
exampleS3PutMessage = [r|
  {
    "Type" : "Notification",
    "MessageId" : "bb979d44-4fc9-5574-801d-ce491dee0df8",
    "TopicArn" : "arn:aws:sns:us-west-2:143032791481:bucket-name-topic",
    "Subject" : "Amazon S3 Notification",
    "Message" : "{\"Records\":[{\"eventVersion\":\"2.0\",\"eventSource\":\"aws:s3\",\"awsRegion\":\"us-west-2\",\"eventTime\":\"2018-02-26T00:08:07.000Z\",\"eventName\":\"ObjectCreated:Put\",\"userIdentity\":{\"principalId\":\"AWS:AIDAJAL75C3RB3PKI7HKQ\"},\"requestParameters\":{\"sourceIPAddress\":\"61.88.11.160\"},\"responseElements\":{\"x-amz-request-id\":\"628827AB329237F8\",\"x-amz-id-2\":\"DgRXSwqO5OwJaPqv+rCtLvBBp5zYMRq8DLahjAQqYjEKlbBr+sjDtocUiSSLCL5X2D2j+I5tKG4=\"},\"s3\":{\"s3SchemaVersion\":\"1.0\",\"configurationId\":\"YzMyMWRjYWUtYzE5MC00ZjcxLWFkMTItMzc1NjE0MGNjOWU4\",\"bucket\":{\"name\":\"bucket-name\",\"ownerIdentity\":{\"principalId\":\"A1T0U83IEG360Q\"},\"arn\":\"arn:aws:s3:::bucket-name\"},\"object\":{\"key\":\"1.2.3.4-1514864593.00\",\"size\":336,\"eTag\":\"9e30708dc09064bb76d8460c08cbabcb\",\"sequencer\":\"005A934FE6C0A58C72\"}}}]}",
    "Timestamp" : "2018-02-26T00:08:07.095Z",
    "SignatureVersion" : "1",
    "Signature" : "TKQFPdojpgYM3ElG14fKLEqobefrCgcAjmTR6mv9cLB9sn6C8gTkpKAnNK8xnlbxarqeVDrR38VeS3FS9CU0GvNpOEHffHezO5i+0sFwSokfheaBvTQ8Bcu415nDG4N7KCY5T3zcN1Jyx2H+Erruh8gdt36TBerwStTEKu3TNvbwnD1Z7AXjTItHr0TWQmaiGaWh8YsObTlHfmH0YQgAtR8Me+KFFAAUKhra4Mg720x+ZoG92nYlyheAtwH2GVN3uio9UOQU5C6UV/QsomiTCYpoEjDUnrcdd++J4b9XmSl3I+x0J4J2mRd5NGQQSv6bn0DXyfDTJRiCNcL4ASAJbg==",
    "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-433026a4050d206028891664da859041.pem",
    "UnsubscribeURL" : "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-west-2:143032791481:bucket-name-topic:bd435f50-bbc7-464d-b76b-eda1ed5163b8"
  }
  |]

exampleS3CompleteMultipartUploadMessage :: T.Text
exampleS3CompleteMultipartUploadMessage = [r|
  {
    "Type" : "Notification",
    "MessageId" : "3d40b760-6593-541c-97c1-e46d3235662d",
    "TopicArn" : "arn:aws:sns:us-west-2:143032791481:bucket-name-topic",
    "Subject" : "Amazon S3 Notification",
    "Message" : "{\"Records\":[{\"eventVersion\":\"2.0\",\"eventSource\":\"aws:s3\",\"awsRegion\":\"us-west-2\",\"eventTime\":\"2018-02-26T00:31:34.009Z\",\"eventName\":\"ObjectCreated:CompleteMultipartUpload\",\"userIdentity\":{\"principalId\":\"AWS:AIDAJAL75C3RB3PKI7HKQ\"},\"requestParameters\":{\"sourceIPAddress\":\"61.88.11.160\"},\"responseElements\":{\"x-amz-request-id\":\"27F3B63D9494C195\",\"x-amz-id-2\":\"rFDKxrqIZBOi9amGkwIVrpEa1bMpbIbWJx3kGm7Bq1Yd3//UYP4dxuWQ2p/5Uu0b+PofG1tC+io=\"},\"s3\":{\"s3SchemaVersion\":\"1.0\",\"configurationId\":\"YzMyMWRjYWUtYzE5MC00ZjcxLWFkMTItMzc1NjE0MGNjOWU4\",\"bucket\":{\"name\":\"bucket-name\",\"ownerIdentity\":{\"principalId\":\"A1T0U83IEG360Q\"},\"arn\":\"arn:aws:s3:::bucket-name\"},\"object\":{\"key\":\"1.2.3.4-1514864593.00\",\"size\":6442450944,\"eTag\":\"767e7a8379c0f62c39e0ceeea0e13de9-768\",\"sequencer\":\"005A935416CD0A0275\"}}}]}",
    "Timestamp" : "2018-02-26T00:31:34.105Z",
    "SignatureVersion" : "1",
    "Signature" : "L7BLCoXZ5gjcsLxVBxVipc5VsexW9XBGX6RF00NW1UQ8qqe20caJHGYsMB2Yeuy4hKJpKZF2qjH4I+6WBJHE43JUExcBHD4lgO+au0tnDVV+0wQZpGatGCzIq/e2rAm6s9crZNtLYRbiDY2sFeyQ5IWjRE6TRt2zlFekZu2dAFCVHgqbbGsZEz5UJwJ7aG8F3ZG+YR6+xOyHvXH00YeSYug7TBvrSKZn2ie4NRJPeyAa0DwFfbrIvcw8+nrnG3SYc/kfkY45GPpbAHtWW+chhvFQSNo+YzDZ5lZOa2Q6YMS3pY3fU6jpK7RxJiExH1JhkNObKazrCcLNPzPs2IhOmw==",
    "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-433026a4050d206028891664da859041.pem",
    "UnsubscribeURL" : "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-west-2:143032791481:bucket-name-topic:bd435f50-bbc7-464d-b76b-eda1ed5163b8"
  }
  |]

exampleS3ObjectRemovedMessage :: T.Text
exampleS3ObjectRemovedMessage = [r|
  {
    "Type" : "Notification",
    "MessageId" : "65e500f2-6815-56aa-8036-53ff14e29fe5",
    "TopicArn" : "arn:aws:sns:us-west-2:143032791481:bucket-name-topic",
    "Subject" : "Amazon S3 Notification",
    "Message" : "{\"Records\":[{\"eventVersion\":\"2.0\",\"eventSource\":\"aws:s3\",\"awsRegion\":\"us-west-2\",\"eventTime\":\"2018-02-26T03:10:47.522Z\",\"eventName\":\"ObjectRemoved:Delete\",\"userIdentity\":{\"principalId\":\"AWS:AIDAJAL75C3RB3PKI7HKQ\"},\"requestParameters\":{\"sourceIPAddress\":\"61.88.11.160\"},\"responseElements\":{\"x-amz-request-id\":\"5A7DE296C9367ACE\",\"x-amz-id-2\":\"0/dfEGrNM5l7V5InPext2UQTyTVwarmiwV3cJtq/Stp81xcoscoP5bnnKvzRBqSQU+oE8CQypmQ=\"},\"s3\":{\"s3SchemaVersion\":\"1.0\",\"configurationId\":\"tf-s3-topic-at6frxoaaffgpc2gg4d42wkism\",\"bucket\":{\"name\":\"bucket-name\",\"ownerIdentity\":{\"principalId\":\"A1T0U83IEG360Q\"},\"arn\":\"arn:aws:s3:::bucket-name\"},\"object\":{\"key\":\"1.2.3.4-1514864593.00\",\"sequencer\":\"005A937AB75B924C8A\"}}}]}",
    "Timestamp" : "2018-02-26T03:10:47.585Z",
    "SignatureVersion" : "1",
    "Signature" : "NUrMzy9xXOQTbzuW/jzXFds3HqV/jQcm8lGniN6tuVHNgF+MY5QsXDkDwNM7z7AXl1tr//C00pXJhAja6uGh9XeMwj4BxUgrsNYiUfzCYYWMkeh2Cfjaxdt/z+2cSKTJ75ja+jFhEzx3d8wPAUS3NJSz4regqS+AWE3EQuHfQoJwufaz/xaQYNg08upq6s29m+1s9Gb7IaXzAaHPuZWGMDKpetCkPfpV0FTjrzVlp9S5pqWDIQ5Z5CYz2oFI38Rhb7K7kcUoV8Gely3OjYDj/5ejaEXpdc3qbIg/x82rqBlCybaDsUc7Min9hsE3+4ZOUiUzIY0Pyrr9toUeB/Z8pA==",
    "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-433026a4050d206028891664da859041.pem",
    "UnsubscribeURL" : "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-west-2:143032791481:bucket-name-topic:bd435f50-bbc7-464d-b76b-eda1ed5163b8"
  }
  |]

exampleTestMessage :: T.Text
exampleTestMessage = [r|
  {
    "Type" : "Notification",
    "MessageId" : "1e5883e9-1558-5843-ba73-d0e09f1c51f4",
    "TopicArn" : "arn:aws:sns:us-west-2:143032791481:bucket-name-topic",
    "Subject" : "Amazon S3 Notification",
    "Message" : "{\"Service\":\"Amazon S3\",\"Event\":\"s3:TestEvent\",\"Time\":\"2018-02-23T03:18:28.451Z\",\"Bucket\":\"bucket-name\",\"RequestId\":\"4C6E56D0BFDD8803\",\"HostId\":\"JisdclAIGovF1dWt956gXZ7qSmrgumSqyEe5PvG9ckdv0VIiw2xXyqnLXlXn9qQUsS3OwRvHO4w=\"}",
    "Timestamp" : "2018-02-23T03:18:28.494Z",
    "SignatureVersion" : "1",
    "Signature" : "hXw5hMvOtlPNyT2sdkbR+j/X+LfJquG/JEQmm9ep3C/Ao+N5Q7FGdNXeTixddWoTA88GKvwHZ20ruJ23EqpyRlmTYwjUkY9NrLJQkLLezVeTsaMCf8Bczp9QQzlFGM9ogJiX7Yx5aiqglEu1fSoJN4HVhYV15AEl51KrH3AOEQOaWEqVLLCGTbTxBQ/ALnWZKBU9B5Ew7FkCu5oruRB2XtdnNgcrNYb1t6DD4LCfxhYmrUrlxxz7B9Z3P1Jm2csnF96waJ8ZCKE0qUQ/CbaJMUvrvylO82bvqvDRUwZ0KHB6fH4qy4zekT9EuYgkbtSBtj1lVe9MhTf/PJj1ewArvg==",
    "SigningCertURL" : "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-433026a4050d206028891664da859041.pem",
    "UnsubscribeURL" : "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-west-2:143032791481:bucket-name-topic:bd435f50-bbc7-464d-b76b-eda1ed5163b8"
  }
  |]

spec :: Spec
spec = describe "App.DecodeSpec" $ do
  it "should parse s3 copy event" $ require $ withTests 1 $ property $ do
    let expected = Just $ SqsMessageOfFileChangeMessage Z.FileChangeMessage
          { Z.eventName   = "ObjectCreated:Copy"
          , Z.eventTime   = "2018-02-23T03:54:35.970Z"
          , Z.bucketName  = "bucket-name"
          , Z.objectKey   = "1.2.3.4-1514864593.00"
          , Z.objectSize  = 336
          , Z.objectTag   = ""
          }
    decodeSqsNotificationBody exampleS3CopyMessage === expected

  it "should parse s3 copy event" $ require $ withTests 1 $ property $ do
    let expected = Just $ SqsMessageOfFileChangeMessage Z.FileChangeMessage
          { Z.eventName   = "ObjectCreated:Put"
          , Z.eventTime   = "2018-02-26T00:08:07.000Z"
          , Z.bucketName  = "bucket-name"
          , Z.objectKey   = "1.2.3.4-1514864593.00"
          , Z.objectSize  = 336
          , Z.objectTag   = "9e30708dc09064bb76d8460c08cbabcb"
          }
    decodeSqsNotificationBody exampleS3PutMessage === expected

  it "should parse s3 complete multipart upload event" $ require $ withTests 1 $ property $ do
    let expected = Just $ SqsMessageOfFileChangeMessage Z.FileChangeMessage
          { Z.eventName   = "ObjectCreated:CompleteMultipartUpload"
          , Z.eventTime   = "2018-02-26T00:31:34.009Z"
          , Z.bucketName  = "bucket-name"
          , Z.objectKey   = "1.2.3.4-1514864593.00"
          , Z.objectSize  = 6442450944
          , Z.objectTag   = "767e7a8379c0f62c39e0ceeea0e13de9-768"
          }
    decodeSqsNotificationBody exampleS3CompleteMultipartUploadMessage === expected

  it "should parse s3 object removed delete event" $ require $ withTests 1 $ property $ do
    let expected = Just $ SqsMessageOfFileChangeMessage Z.FileChangeMessage
          { Z.eventName   = "ObjectRemoved:Delete"
          , Z.eventTime   = "2018-02-26T03:10:47.522Z"
          , Z.bucketName  = "bucket-name"
          , Z.objectKey   = "1.2.3.4-1514864593.00"
          , Z.objectSize  = 0
          , Z.objectTag   = ""
          }
    decodeSqsNotificationBody exampleS3ObjectRemovedMessage === expected

  it "should parse s3 test event" $ require $ withTests 1 $ property $ do
    let expected = Just SqsMessageOfS3TestEvent
    decodeSqsNotificationBody exampleTestMessage === expected
