# Ruby

The Supergood Ruby client connects Supergood to your Ruby application. Follow these steps to integrate with the Ruby client.

## 1. Install the Supergood library

```bash
gem install supergood
```

## 2. Initialize the Supergood Library

**Environment variables**

Set the environment variables `SUPERGOOD_CLIENT_ID` and `SUPERGOOD_CLIENT_SECRET` using the API keys generated in the [getting started instructions](../../getting-started.md).

Initialize the Supergood client at the root of your application, or anywhere you're making API calls with the following code:

```ruby
require 'supergood'

Supergood.init()
```

**Passing keys**

You can also pass the API keys in manually without setting environment variables.\
\
Replace `<CLIENT_ID>` and `<CLIENT_SECRET>` with the API keys you generated in the [getting started instructions](../../getting-started.md).

```ruby
require 'supergood'

Supergood.init({ client_id: "<CLIENT_ID>", client_secret: "<CLIENT_SECRET>" })
```

#### Local development

Setting the `CLIENT_ID` and `CLIENT_SECRET_ID` to `local-client-id` and `local-client-secret`, respectively, will disable making API calls to the supergood.ai server and instead log the payloads to the local console.

## 3. Monitor your API calls

You're all set to use Supergood!

Head back to your [dashboard](https://dashboard.supergood.ai) to start monitoring your API calls and receiving reports.

## Links

* [Supergood RubyGems Project](https://rubygems.org/gems/supergood)
* [Supergood-rb Source Code](https://github.com/supergoodsystems/supergood-rb)
