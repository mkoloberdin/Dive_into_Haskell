--{-# LANGUAGE OverloadedStrings, DataKinds #-}
module CassandraConnector where

--import Database.Cassandra.CQL
--import Control.Monad
--import Control.Monad.CatchIO
--import Control.Monad.Trans (liftIO)
--import Data.ByteString.Char8 (ByteString)
--import qualified Data.ByteString.Char8 as C
--import Data.Text (Text)
--import qualified Data.Text as T
--import Data.UUID
--import System.Random
--
--data User = User { userId :: Int, userName :: String } deriving (Show, Generic)
--
--
--createUserTable :: Query Schema () ()
--createUserTable = "create table users (userId uuid PRIMARY KEY, userName varchar)"
--
--insertUser :: Query Write (UUID, Text) ()
--insertUser = "insert into users (id, userName) values (?, ?, ?, ?, ?, ?)"
--
--cassandraMain = do
--                let auth = Nothing
--                pool <- newPool [("localhost", "9042")] "test" auth