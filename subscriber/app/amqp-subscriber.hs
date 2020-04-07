{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Main
  ( main
  ) where

import Control.Applicative ((<**>), (<|>))
import Control.Exception (bracket)
import Control.Monad (void)
import Data.String (IsString)
import Data.Text (Text)
import Network.Socket (PortNumber)
import Prelude
import qualified Data.ByteString.Lazy.Char8 as ByteString.Lazy.Char8
import qualified Data.Default.Class as Default
import qualified Network.AMQP as AMQP
import qualified Network.Connection as Connection
import qualified Options.Applicative as Options

data Config = Config
  { amqpHostName :: String
  , amqpPort :: PortNumber
  , amqpVirtualHost :: Text
  , amqpLoginName :: Text
  , amqpLoginPassword :: Text
  , amqpExchangeName :: Text
  , amqpExchangeType :: Text
  , amqpRoutingKey :: Text
  , amqpQueueName :: Text
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
  withAMQ config $ \connection -> do
    channel <- AMQP.openChannel connection
    AMQP.declareExchange channel AMQP.newExchange
      { AMQP.exchangeName = amqpExchangeName
      , AMQP.exchangeType = amqpExchangeType
      }
    AMQP.declareQueue channel AMQP.newQueue
      { AMQP.queueName = amqpQueueName
      , AMQP.queueExclusive = True
      }
    AMQP.bindQueue channel amqpQueueName amqpExchangeName amqpRoutingKey

    let consumer :: (AMQP.Message, AMQP.Envelope) -> IO ()
        consumer (message, envelope) = do
          ByteString.Lazy.Char8.putStrLn $ AMQP.msgBody message
          AMQP.ackEnv envelope

    void $ withConsumerTag_ config channel AMQP.Ack consumer $ do
      putStrLn $
        "Awaiting messages. Enter any input to terminate the program..."
      getLine

    where
      Config
        { amqpExchangeName
        , amqpExchangeType
        , amqpRoutingKey
        , amqpQueueName
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

withConsumerTag
  :: Config
  -> AMQP.Channel
  -> AMQP.Ack
  -> ((AMQP.Message, AMQP.Envelope) -> IO ())
  -> (AMQP.ConsumerTag -> IO a)
  -> IO a
withConsumerTag config channel ack consumer = bracket acquire release where
  acquire = AMQP.consumeMsgs channel amqpQueueName ack consumer
  release = AMQP.cancelConsumer channel
  Config { amqpQueueName } = config

withConsumerTag_
  :: Config
  -> AMQP.Channel
  -> AMQP.Ack
  -> ((AMQP.Message, AMQP.Envelope) -> IO ())
  -> IO a
  -> IO a
withConsumerTag_ config channel ack consumer =
  withConsumerTag config channel ack consumer . const

parseConfig :: IO Config
parseConfig = Options.execParser opts where
  opts :: Options.ParserInfo Config
  opts =
    Options.info (configParser <**> Options.helper) . mconcat $
      [ Options.fullDesc
      , Options.progDesc "Subscribe to an AMQ queue and print incoming messages"
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
      amqpQueueName <- strOptionParser' "queue-name"
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
        , amqpQueueName
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

    tlsParser :: Options.Parser TLS
    tlsParser =
          Options.flag' TLS'EnabledWithCertValidation (Options.long "tls")
      <|> Options.flag' TLS'EnabledWithoutCertValidation (Options.long "tls-no-cert-validation")
      <|> Options.flag' TLS'Disabled (Options.long "no-tls")
