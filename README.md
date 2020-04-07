# [haskell-amqp-utils][]

## Synopsis

This repo provides executables for use in testing RabbitMQ via the
[amqp][] Haskell package.

### `amqp-subscriber`

`amqp-subscriber` prints the incoming messages on a particular queue
bound to a particular exchange.

```
$ amqp-subscriber --help
Usage: amqp-subscriber [--host-name ARG] [--port ARG] [--virtual-host ARG]
                       --login-name ARG --login-password ARG --exchange-name ARG
                       --exchange-type ARG --routing-key ARG --queue-name ARG
                       (--tls | --tls-no-cert-validation | --no-tls)
  Subscribe to an AMQ queue and print incoming messages

Available options:
  -h,--help                Show this help text
```

If using `amqp-subscriber` in tandem with `amqp-publisher`, make sure to
use the same exchange/routing info!

### `amqp-publisher`

`amqp-publisher` supports sending arbitrary data - either from a file or
from `stdin` - to a particular exchange.

```
$ amqp-publisher --help
Usage: amqp-publisher [--host-name ARG] [--port ARG] [--virtual-host ARG]
                      --login-name ARG --login-password ARG --exchange-name ARG
                      --exchange-type ARG --routing-key ARG
                      ([--persistent-delivery-mode] |
                      [--non-persistent-delivery-mode]) (--input-file ARG |
                      --stdin) (--tls | --tls-no-cert-validation | --no-tls)
  Publish a message to an AMQ exchange

Available options:
  -h,--help                Show this help text
```

If using `amqp-publisher` in tandem with `amqp-subscriber`, make sure to
use the same exchange/routing info!

When publishing JSON messages, using [`jq`][] can be useful to minify a
JSON file before piping it into `amqp-publisher`:

```bash
jq -c < file.json | tr -d '\n' | amqp-publisher \
  --host-name 127.0.0.1 \
  --login-name some-login-name \
  --login-password some-login-password \
  --exchange-name some-exchange \
  --exchange-type fanout \
  --routing-key some-routing-key \
  --stdin
```

[haskell-amqp-utils]: https://www.github.com/Simspace/haskell-amqp-utils
[amqp]: https://www.stackage.org/haddock/lts-14.12/amqp-0.18.3/Network-AMQP.html
[`jq`]: https://stedolan.github.io/jq/
