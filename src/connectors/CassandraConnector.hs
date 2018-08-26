{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
module CassandraConnector where

import Data.Text (Text,pack,unpack)
import Data.Functor.Identity
import Database.CQL.IO as Client
import qualified System.Logger as Logger
import Control.Monad.IO.Class (liftIO)
import System.Logger (eval)
import Database.CQL.Protocol( ColumnType( IntColumn ) )
import Database.CQL.Protocol( ColumnType( VarCharColumn ) )
import Data.Int (Int64,Int32)
import ModelTypes

-- | User
-- -------------

getVersion:: IO [Identity Text]
getVersion = do
                logger <- Logger.new Logger.defSettings
                conn <- createConnection logger
                let versionQuery = "SELECT cql_version from system.local" :: QueryString R () (Identity Text)
                let queryParam = defQueryParams One ()
                runClient conn (query versionQuery queryParam)

selectAllUser :: IO [User]
selectAllUser = do
                  logger <- Logger.new Logger.defSettings
                  conn <- createConnection logger
                  let selectAllQuery = "SELECT * from haskell_cassandra.haskell_users;" :: QueryString R () ((Int32, Text))
                  let queryParam = defQueryParams One ()
                  array <- runClient conn (query selectAllQuery queryParam)
                  users <- transformArrayToUsers array
                  return users

selectUserById :: Int32 -> IO (Either UserNotFound User)
selectUserById userId = do
                  logger <- Logger.new Logger.defSettings
                  conn <- createConnection logger
                  let selectQuery = "SELECT * from haskell_cassandra.haskell_users  WHERE userid=?" :: PrepQuery R (Identity Int32) ((Int32, Text))
                  let queryParam = defQueryParams One (Identity userId)
                  do maybe <- runClient conn (query1 selectQuery queryParam)
                     response <- transformTupleToUser maybe
                     return response


-- | Utils
-- -------------
{- | As usual using [map] operator we transform the Tuple into User data type-}
transformArrayToUsers :: [(Int32, Text)] -> IO [User]
transformArrayToUsers array =   return $ map (\tuple -> User 1 "change me") array

{- | Using [Either] operator we define the possibility that we have two possible effects. We can return a User
     in case the id is correct, or if is not we will return an UserNotFound.-}
transformTupleToUser :: Maybe((Int32, Text)) -> IO (Either UserNotFound User)
transformTupleToUser maybe = case maybe of
                               Just value -> return $ Right $ User (getFirstElement value) (getLastElement value)
                               Nothing -> return $ Left $ UserNotFound "User not found"

{- | Using [fst] operator we are able to get first element in a Tuple -}
getFirstElement ::(Int32, Text) -> Int
getFirstElement tuple = int32ToInt(fst tuple)

{- | Using [snd] operator we are able to get last element in a Tuple -}
getLastElement ::(Int32, Text) -> String
getLastElement tuple = unpack(snd tuple)

-- | Connection
-- -------------
{-| In here we use the cql-io API to create the [ClientState] data type which contains the connection to the backend -}
createConnection :: Logger.Logger -> IO ClientState
createConnection logger = Client.init logger createConnectionSettings

createConnectionSettings :: Settings
createConnectionSettings = addRetryStrategy $
                           addMaxTimeout $
                           addMaxConnections $
                           addPortNumber defSettings

addPortNumber :: Settings -> Settings
addPortNumber settings =  (setPortNumber 9042) settings

addMaxConnections :: Settings -> Settings
addMaxConnections settings = (setMaxConnections 100) settings

addMaxTimeout :: Settings -> Settings
addMaxTimeout settings = (setMaxTimeouts 10000) settings

addRetryStrategy :: Settings -> Settings
addRetryStrategy settings = (setRetrySettings retryForever) settings



--insertUser :: Client ()
--insertUser = do
--             let user = ( 4835637638, "hello world")
--             write ins1 (params a)
--             where
--                 ins1 :: PrepQuery W Ty1 ()
--                 ins1 = [r| insert into cqltest.test1 (a,b) values (?,?) |]