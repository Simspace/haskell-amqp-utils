{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Main
  ( main
  ) where

import Control.Applicative ((<**>), (<|>))
import Control.Exception (bracket)
import Data.String (IsString)
import Data.Text (Text)
import Network.Socket (PortNumber)
import Prelude
import System.IO (Handle)
import qualified Data.ByteString.Lazy as ByteString.Lazy
import qualified Data.Default.Class as Default
import qualified Network.AMQP as AMQP
import qualified Network.Connection as Connection
import qualified Options.Applicative as Options
import qualified System.IO as IO

data Config = Config
  { amqpHostName :: String
  , amqpPort :: PortNumber
  , amqpVirtualHost :: Text
  , amqpLoginName :: Text
  , amqpLoginPassword :: Text
  , amqpExchangeName :: Text
  , amqpExchangeType :: Text
  , amqpRoutingKey :: Text
  , amqpMessageDeliveryMode :: AMQP.DeliveryMode
  , messageSource :: MessageSource
  , tls :: TLS
  } deriving (Show)

data MessageSource
  = MessageSource'Stdin
  | MessageSource'File FilePath
  deriving (Show)

data TLS
  = TLS'Disabled
  | TLS'EnabledWithoutCertValidation
  | TLS'EnabledWithCertValidation
  deriving (Show)

main :: IO ()
main = run =<< parseConfig

run :: Config -> IO ()
run config = do
  messageBytes <- withMessageSourceHandle messageSource $ \handle ->
    ByteString.Lazy.hGetContents handle
  withAMQ config $ \connection -> do
    channel <- AMQP.openChannel connection
    AMQP.declareExchange channel AMQP.newExchange
      { AMQP.exchangeName = amqpExchangeName
      , AMQP.exchangeType = amqpExchangeType
      }
    mSeqNum <- AMQP.publishMsg channel amqpExchangeName amqpRoutingKey AMQP.newMsg
      { AMQP.msgBody = messageBytes
      , AMQP.msgDeliveryMode = Just amqpMessageDeliveryMode
      }
    case mSeqNum of
      Nothing -> putStrLn "Message sent: seqNum not available"
      Just seqNum -> putStrLn $ "Message sent: seqNum=" <> show seqNum

    where
      Config
        { amqpExchangeName
        , amqpExchangeType
        , amqpRoutingKey
        , amqpMessageDeliveryMode
        , messageSource
        } = config

withAMQ :: Config -> (AMQP.Connection -> IO a) -> IO a
withAMQ config = bracket acquire release where
  acquire :: IO AMQP.Connection
  acquire =
    AMQP.openConnection'' $ AMQP.defaultConnectionOpts
      { AMQP.coServers = [(amqpHostName config, amqpPort config)]
      , AMQP.coVHost = amqpVirtualHost config
      , AMQP.coAuth =
          [ AMQP.plain (amqpLoginName config) (amqpLoginPassword config)
          ]
      , AMQP.coTLSSettings = case tls config of
          TLS'Disabled ->
            Nothing
          TLS'EnabledWithoutCertValidation ->
            Just $ AMQP.TLSCustom Default.def
              { Connection.settingDisableCertificateValidation = True
              }
          TLS'EnabledWithCertValidation ->
            Just $ AMQP.TLSCustom Default.def
              { Connection.settingDisableCertificateValidation = False
              }
      }

  release :: AMQP.Connection -> IO ()
  release = AMQP.closeConnection

withMessageSourceHandle :: MessageSource -> (Handle -> IO a) -> IO a
withMessageSourceHandle messageSource f =
  case messageSource of
    MessageSource'Stdin -> f IO.stdin
    MessageSource'File filePath -> IO.withFile filePath IO.ReadMode f

parseConfig :: IO Config
parseConfig = Options.execParser opts where
  opts :: Options.ParserInfo Config
  opts =
    Options.info (configParser <**> Options.helper) . mconcat $
      [ Options.fullDesc
      , Options.progDesc "Publish a message to an AMQ exchange"
      ]

  configParser :: Options.Parser Config
  configParser = fullParser where
    fullParser = do
      amqpHostName <- strOptionParser "host-name" "127.0.0.1"
      amqpPort <- readOptionParser "port" 5672
      amqpVirtualHost <- strOptionParser "virtual-host" "/"
      amqpLoginName <- strOptionParser' "login-name"
      amqpLoginPassword <- strOptionParser' "login-password"
      amqpExchangeName <- strOptionParser' "exchange-name"
      amqpExchangeType <- strOptionParser' "exchange-type"
      amqpRoutingKey <- strOptionParser' "routing-key"
      amqpMessageDeliveryMode <- deliveryModeParser
      messageSource <- messageSourceParser
      tls <- tlsParser
      pure Config
        { amqpHostName
        , amqpPort
        , amqpVirtualHost
        , amqpLoginName
        , amqpLoginPassword
        , amqpExchangeName
        , amqpExchangeType
        , amqpRoutingKey
        , amqpMessageDeliveryMode
        , messageSource
        , tls
        }

    strOptionParser :: (IsString s, Show s) => String -> s -> Options.Parser s
    strOptionParser longName def =
      Options.strOption . mconcat $
        [ Options.long longName
        , Options.value def
        ]

    strOptionParser' :: IsString s => String -> Options.Parser s
    strOptionParser' longName =
      Options.strOption $ Options.long longName

    readOptionParser :: (Read a, Show a) => String -> a -> Options.Parser a
    readOptionParser longName def =
      Options.option Options.auto . mconcat $
        [ Options.long longName
        , Options.value def
        ]

    deliveryModeParser :: Options.Parser AMQP.DeliveryMode
    deliveryModeParser =
          Options.flag
            AMQP.Persistent
            AMQP.Persistent
            (Options.long "persistent-delivery-mode")
      <|> Options.flag
            AMQP.Persistent
            AMQP.NonPersistent
            (Options.long "non-persistent-delivery-mode")

    messageSourceParser :: Options.Parser MessageSource
    messageSourceParser =
          fmap MessageSource'File (strOptionParser' "input-file")
      <|> Options.flag' MessageSource'Stdin (Options.long "stdin")

    tlsParser :: Options.Parser TLS
    tlsParser =
          Options.flag' TLS'EnabledWithCertValidation (Options.long "tls")
      <|> Options.flag' TLS'EnabledWithoutCertValidation (Options.long "tls-no-cert-validation")
      <|> Options.flag' TLS'Disabled (Options.long "no-tls")
