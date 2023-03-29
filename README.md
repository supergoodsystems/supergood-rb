# Supergood

Monitor the cost and performance of your external API's with two lines of code. 

Interested in learning more? Check us out at https://supergood.ai or Reach out to alex@supergood.ai .

Not built on Ruby? We've got a node client, python client and golang client as well.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'supergood'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install supergood

## Usage

1. Head over to https://dashboard.supergood.ai and make an account, make sure to use your work email address!
2. Click on the tab labeled "API Keys" and generate a client id and client secret.
3. Head back to your code and initialize the Supergood client one of two ways:

```
require 'supergood'

Supergood.init(<client_id>, <client_secret>)
```
OR

set `SUPERGOOD_CLIENT_ID` and `SUPERGOOD_CLIENT_SECRET` as environment variables and leave the init function as `Supergood.init` 


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/supergoodsystems/supergood-rb.

