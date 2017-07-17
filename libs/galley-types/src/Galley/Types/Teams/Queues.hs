{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE StrictData                 #-}
{-# LANGUAGE TemplateHaskell            #-}

module Galley.Types.Teams.Queues
    ( QEvent (..)
    , qEventType
    , qEventTime
    , qEventTeam
    , qEventData

    , QEventType (..)
    , QEventData (..)

    , QTeamData (..)
    , memberCount
    , billingEmail

    ) where

import Data.Misc (Email)
import Control.Lens (makeLenses)
import Control.Monad (when)
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Id (TeamId)
import Data.Json.Util
import Data.Maybe (isNothing)
import Data.Monoid
import Data.Time (UTCTime)
import Data.Word

import qualified Data.HashMap.Strict as HashMap

data QEvent = QEvent
    { _qEventType :: QEventType
    , _qEventTeam :: TeamId
    , _qEventTime :: UTCTime
    , _qEventData :: Maybe QEventData
    } deriving (Eq, Show)

data QEventType =
      QTeamCreate
    | QTeamUpdate
    | QTeamDelete
    deriving (Eq, Show)

data QEventData =
      EdQTeamCreate QTeamData
    | EdQTeamUpdate QTeamData
    deriving (Eq, Show)

data QTeamData = QTeamData
    { _memberCount  :: Maybe Word64
    , _billingEmail :: Maybe Email
    } deriving (Eq, Show)

makeLenses ''QEvent
makeLenses ''QTeamData

instance ToJSON QEventType where
    toJSON QTeamCreate   = String "team.create"
    toJSON QTeamUpdate   = String "team.update"
    toJSON QTeamDelete   = String "team.delete"

instance FromJSON QEventType where
    parseJSON (String "team.create")   = pure QTeamCreate
    parseJSON (String "team.update")   = pure QTeamUpdate
    parseJSON (String "team.delete")   = pure QTeamDelete
    parseJSON other                    = fail $ "Unknown event type: " <> show other

instance ToJSON QEvent where
    toJSON = Object . toJSONObject

instance ToJSONObject QEvent where
    toJSONObject e = HashMap.fromList
        [ "type" .= _qEventType e
        , "team" .= _qEventTeam e
        , "time" .= _qEventTime e
        , "data" .= _qEventData e
        ]

instance FromJSON QEvent where
    parseJSON = withObject "event" $ \o -> do
        ty <- o .:  "type"
        dt <- o .:? "data"
        QEvent ty <$> o .: "team"
                 <*> o .: "time"
                 <*> parseEventData ty dt

instance ToJSON QEventData where
    toJSON (EdQTeamCreate   tem) = toJSON tem
    toJSON (EdQTeamUpdate   upd) = toJSON upd

parseEventData :: QEventType -> Maybe Value -> Parser (Maybe QEventData)

parseEventData QTeamUpdate Nothing  = fail "missing event data for type 'team.update'"
parseEventData QTeamUpdate (Just j) = Just . EdQTeamUpdate <$> parseJSON j

parseEventData _ Nothing  = pure Nothing
parseEventData t (Just _) = fail $ "unexpected event data for type " <> show t

instance ToJSON QTeamData where
    toJSON u = object
        $ "member_count"  .= _memberCount u
        # "billing_email" .= _billingEmail u
        # []

instance FromJSON QTeamData where
    parseJSON = withObject "team data" $ \o -> do
        x <- QTeamData <$> o .:? "member_count" <*> o .:? "billing_email"
        when (isNothing (_memberCount x) && isNothing (_billingEmail x)) $
            fail "no update data specified"
        pure x
