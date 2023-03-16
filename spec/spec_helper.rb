require 'rspec'
require 'dotenv'
require 'webmock/rspec'

Dotenv.load

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/api/events').
    to_return(status: 200, body: { message: 'Success' }.to_json, headers: {})

    stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/api/errors').
    to_return(status: 200, body: { message: 'Success' }.to_json, headers: {})
  end
end
