{-# LANGUAGE OverloadedStrings #-} -- Mandatory language overload to overload String
{-# LANGUAGE DeriveGeneric #-}
module AppleAPI where

--Server
import Web.Scotty
import Data.Monoid ((<>))
import GHC.Generics
import Web.Scotty.Internal.Types (ScottyT, ActionT, Param, RoutePattern, Options, File)
import Web.Scotty (ScottyM,scotty,ActionM,get,text)
import qualified Data.Text.Lazy as LazyText
--Http client
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)
import Data.ByteString (pack,unpack)
import Data.ByteString.Lazy.Char8 (ByteString)
import Control.Exception (SomeException,try,evaluate)
import Network.HTTP.Client (Response)
import Data.IORef (newIORef,IORef,readIORef)
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (ToJSON,FromJSON,parseJSON,FromJSON,decode)
import Data.Char (toUpper)
import Data.List.Split

appleAPI :: [Char] -> String
appleAPI entry = "http://itunes.apple.com/search?term=" ++ entry

servicePort = 5000 :: Int

{-| ----------------------------------------------}
{-|                    SERVER                    -}
{-| ----------------------------------------------}
{-| Using [scotty] passing [port] and [routes] we define the http server-}
appleServer :: IO ()
appleServer = do
    print ("Starting Apple Server at port " ++ show servicePort)
    manager <- newManager defaultManagerSettings
    ioRefManager <- newIORef manager
    scotty servicePort (routes ioRefManager)

{-| We define the routes thanks to REST operators [get, post, put, delete, patch] which expect to
    receive a [RoutePattern] as a path and a [ActionM] as the action of the request. Then we return a [ScottyM]-}
routes :: IORef Manager -> ScottyM()
routes ioRefManager = do get "/service" responseService
                         get "/author" responseName
                         get "/product/:product" $ responseProduct ioRefManager
                         get "/products/:products" $ responseProducts ioRefManager
                         get "/product/:product/min/:minPrice/max/:maxPrice" $ responseProductByPrice ioRefManager
                         get "/band/:band/album/:album" $ responseBandAndAlbum ioRefManager


{-| We use [text] operator from scotty we render the response in text/plain-}
responseService :: ActionM ()
responseService = text "Apple API Haskell server 1.0"

responseName :: ActionM ()
responseName = text "Pablo Perez Garcia"

responseProduct :: IORef Manager -> ActionM ()
responseProduct ioRefManager = do product <- extractUriParam "product"
                                  products <- liftAndCatchIO $ findProduct ioRefManager product
                                  json products

responseProducts :: IORef Manager -> ActionM ()
responseProducts ioRefManager = do products <- extractUriParam "products"
                                   products <- lift $ splitPrograms products
                                   products <- lift $ findProducts ioRefManager Products{ results = []} products
                                   json products

responseBandAndAlbum :: IORef Manager -> ActionM ()
responseBandAndAlbum ioRefManager = do band <- extractUriParam "band"
                                       album <- extractUriParam "album"
                                       products <- liftAndCatchIO $ findProduct ioRefManager band
                                       filterProducts <- lift $ filterByAlbum album products
                                       json filterProducts

{-| Function to find apple product by name and then filter by min and max price.
    we embrace Type system so we transform the primitive type String from the uri param into Double usinng [read] function
    Then we wrap into data types MinPrice MaxPrice-}
responseProductByPrice :: IORef Manager -> ActionM ()
responseProductByPrice ioRefManager = do product <- extractUriParam "product"
                                         minPriceStr <- extractUriParam "minPrice"
                                         maxPriceStr <- extractUriParam "maxPrice"
                                         minPrice <- lift $ return $ MinPrice (read minPriceStr)
                                         maxPrice <- lift $ return $ MaxPrice (read maxPriceStr)
                                         products <- liftAndCatchIO $ findProduct ioRefManager product
                                         filterProducts <- lift $ filterByMinAndMaxPrice products minPrice maxPrice
                                         json filterProducts

{-| Recursive function where we pass a empty vessel of [Products] a list of [String] products to search
    and we end up with the vessel [Products] not empty anymore but filled with all search-}
findProducts :: IORef Manager -> Products -> [String] -> IO Products
findProducts ioRefManager vesselProduct (product:products) = do newProducts <- findProduct ioRefManager product
                                                                appendProducts <- appendProducts vesselProduct newProducts
                                                                findProducts ioRefManager appendProducts products
findProducts ioRefManager vesselProduct [] = return vesselProduct

{-| Function that receive the IORef manager and the product to find. We obtain the response and we transform into
    Products data type record  -}
findProduct :: IORef Manager -> String -> IO Products
findProduct ioRefManager product = do print("Finding apple product:" ++ product)
                                      bsResponse <- requestToAppleAPI ioRefManager (appleAPI product)
                                      products <- decodeJsonToDataType bsResponse
                                      products <- setGenreInUpper products
                                      return products

{-| Function to create a [Products] data type and append the list [Product] from old and new iteration-}
appendProducts :: Products -> Products -> IO Products
appendProducts oldProducts newProducts = return $ Products { results = (results oldProducts) ++ (results newProducts) }

{-| Using [splitOn] function we pass the delimiter [,] and the String to be split-}
splitPrograms :: String -> IO [String]
splitPrograms programs = return $ splitOn "|" programs

{-| Function to extract uri params by name-}
extractUriParam :: LazyText.Text -> ActionM String
extractUriParam param = Web.Scotty.param param

{-| Function that receive a ByteString in json format and we decode using [decode] operator into a [Maybe T] where
   T is the type that thanks to the the type classes defined  at the bottom of the module can bee inference. -}
decodeJsonToDataType :: ByteString -> IO Products
decodeJsonToDataType json = case decode json of
                                 Just products -> return products
                                 Nothing ->  return emptyProducts

{-| Filter function that using [filter] operator we create a new Products record with a filter list of products by collectionName-}
filterByAlbum :: [Char] -> Products -> IO Products
filterByAlbum album products = return Products { results = filter (\product -> collectionName product == album) (results products) }

filterByMinAndMaxPrice ::Products-> MinPrice -> MaxPrice -> IO Products
filterByMinAndMaxPrice products (MinPrice min) (MaxPrice max) = do let newProducts = filter(\product -> (trackPrice product) > min && (trackPrice product) < max ) (results products)
                                                                   return Products { results = newProducts}

{-| Function to map the list of Products and set [primaryGenreName] in upper case-}
setGenreInUpper :: Products -> IO Products
setGenreInUpper products = return Products {results = map (\product -> product { primaryGenreName = map toUpper $ primaryGenreName product }) (results products) }


lift :: IO any -> ActionM any
lift any = liftAndCatchIO any

{-| ----------------------------------------------}
{-|                 HTTP CLIENTS                 -}
{-| ----------------------------------------------}

{-| Function to make a request to Apple API. We extract first the manager created to open the request since
   it's quite expensive create the manager per request.-}
requestToAppleAPI :: IORef Manager -> String -> IO ByteString
requestToAppleAPI ioRefManager uri = do manager <- liftIO (readIORef ioRefManager)
                                        request <- parseRequest uri
                                        response <- makeRequest manager request
                                        return $ responseBody response

{-| Function that receive the Manager of Http connection, a Request and using [httpLbs] function we make the request,
    Receiving a [Response] with [ByteString] as T of the body response -}
makeRequest :: Manager -> Request -> IO (Response ByteString)
makeRequest manager request =  httpLbs request manager


{-| ----------------------------------------------}
{-|                    MODEL                     -}
{-| ----------------------------------------------}
data Products = Products { results :: [Product]} deriving (Show, Generic)

data Product = Product {
     artistName:: [Char],
     trackName:: [Char],
     collectionName:: [Char],
     primaryGenreName:: [Char],
     trackPrice:: Double,
     trackViewUrl:: [Char],
     releaseDate:: [Char],
     previewUrl:: [Char],
     artworkUrl100:: [Char]
} deriving (Show, Generic)

{-| We define Aeson instance of TypeClass ToJSON to serialize and FromJSON to deserialize-}
instance ToJSON Products
instance FromJSON Products
instance ToJSON Product
instance FromJSON Product

data MinPrice = MinPrice Double
data MaxPrice = MaxPrice Double

emptyProducts = Products [Product {
               artistName="",
               trackName="",
               collectionName="",
               primaryGenreName="",
               trackPrice=0.0,
               trackViewUrl="",
               releaseDate="",
               previewUrl="",
               artworkUrl100=""
               }] :: Products
