{-# LANGUAGE OverloadedStrings #-}

module App.OptionsSpec
  ( spec
  ) where

import App.Options
import HaskellWorks.Hspec.Hedgehog
import Hedgehog
import Test.Hspec

import qualified App.Options.Types as Z

{-# ANN module ("HLint: ignore Redundant do"  :: String) #-}

spec :: Spec
spec = describe "App.OptionsSpec" $ do
    it "should parse tags" $ require $ withTests 1 $ property $ do
      string2Tags "club_name:indica,deploy_id:manual" ===
          [ Z.StatsTag ("club_name", "indica")
          , Z.StatsTag ("deploy_id", "manual")
          ]
