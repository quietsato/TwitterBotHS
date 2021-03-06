module Bot.Twitter
    ( getTweets
    , getUserTweets
    , getMentions
    , getTweetsAfter
    , postTweet
    , postReply
    , createFab) where

import           Bot.Config
import           Data.Aeson
import qualified Data.ByteString.Char8  as B8
import           Data.List
import           Data.Mention
import qualified Data.Text              as T
import           Data.Text.Encoding
import           Data.Tweet
import           Network.HTTP.Conduit
import           Network.HTTP.Types
import           Web.Authenticate.OAuth

getName :: IO String
getName = name <$> getConfig

getKeys :: IO Keys
getKeys = keys <$> getConfig

getAuth = do
  keys <- getKeys
  return
    $ newOAuth { oauthServerName = "api.twitter.com"
               , oauthConsumerKey = (B8.pack . consumerKey) keys
               , oauthConsumerSecret = (B8.pack . consumerKeySecret) keys
               }

getCred = do
  keys <- getKeys
  return
    $ newCredential
      ((B8.pack . accessToken) keys)
      ((B8.pack . accessTokenSecret) keys)

getTweetsAfter :: Integer -> IO [Tweet]
getTweetsAfter minId = dropWhile (\t -> tweetId t <= minId) <$> getTweets

getTweets :: IO [Tweet]
getTweets = do
  res <- do
    signedReq <- createSignedReq
      =<< setQueryString [(B8.pack "count", Just (B8.pack "200"))]
      <$> parseRequest
        "https://api.twitter.com/1.1/statuses/home_timeline.json"
    man <- newManager tlsManagerSettings
    httpLbs signedReq man
  let dc = eitherDecode $ responseBody res
  case dc of
    Left er  -> error er
    Right ts -> (removeByText .) . removeByName <$> getName <*> pure ts

getUserTweets :: String -> IO [Tweet]
getUserTweets user = do
  res <- do
    signedReq <- createSignedReq
      =<< setQueryString
        [ (B8.pack "count", Just (B8.pack "200"))
        , (B8.pack "screen_name", Just (B8.pack user))]
      <$> parseRequest
        "https://api.twitter.com/1.1/statuses/user_timeline.json"
    man <- newManager tlsManagerSettings
    httpLbs signedReq man
  let dc = eitherDecode $ responseBody res
  case dc of
    Left er  -> error er
    Right ts -> return $ removeByText ts

getMentions :: IO [Mention]
getMentions = do
  res <- do
    req <- setQueryString [(B8.pack "count", Just (B8.pack "200"))]
      <$> parseRequest
        "https://api.twitter.com/1.1/statuses/mentions_timeline.json"
    auth <- getAuth
    cred <- getCred
    signedReq <- signOAuth auth cred req
    man <- newManager tlsManagerSettings
    httpLbs signedReq man
  let dc = eitherDecode $ responseBody res
  case dc of
    Left er  -> error er
    Right ts -> (\n -> filter (match n) ts) <$> getName
  where
    match :: String -> Mention -> Bool
    match n m = (isConversation m || isAtMention m)
      && isReplyToMe n m
      && (not . favorited) m

    isAtMention = isInfixOf "会話" . mentionText

    isReplyToMe n m = case replyTo m of
      Just x  -> x == n
      Nothing -> False

    isConversation m = case isReply m of
      Nothing -> False
      Just _  -> True

postTweet :: String -> IO Bool
postTweet s = do
  res <- do
    req <- parseRequest "https://api.twitter.com/1.1/statuses/update.json"
    man <- newManager tlsManagerSettings
    let postReq =
          urlEncodedBody [(B8.pack "status", (encodeUtf8 . T.pack) s)] req
    auth <- getAuth
    cred <- getCred
    signedReq <- signOAuth auth cred postReq
    httpLbs signedReq man
  return $ (statusCode . responseStatus) res == 200

postReply :: Integer -> String -> IO Bool
postReply i s = do
  res <- do
    req <- parseRequest "https://api.twitter.com/1.1/statuses/update.json"
    man <- newManager tlsManagerSettings
    signedReq <- createSignedReq
      $ urlEncodedBody
        [ (B8.pack "status", (encodeUtf8 . T.pack) s)
        , (B8.pack "in_reply_to_status_id", (B8.pack . show) i)]
        req
    httpLbs signedReq man
  return $ (statusCode . responseStatus) res == 200

createFab :: Integer -> IO Bool
createFab i = do
  res <- do
    req <- parseRequest "https://api.twitter.com/1.1/favorites/create.json"
    man <- newManager tlsManagerSettings
    signedReq <- createSignedReq
      $ urlEncodedBody [(B8.pack "id", B8.pack $ show i)] req
    httpLbs signedReq man
  return $ (statusCode . responseStatus) res == 200

removeByName :: String -> [Tweet] -> [Tweet]
removeByName n = filter (\t -> (screen_name . user) t /= n)

removeByText :: [Tweet] -> [Tweet]
removeByText = filter (ok . text)
  where
    ok :: String -> Bool
    ok tw =
      all (\p -> not (p `isInfixOf` tw)) ["https", "http", "RT @", "@", "#"]

createSignedReq req = do
  auth <- getAuth
  cred <- getCred
  signOAuth auth cred req
