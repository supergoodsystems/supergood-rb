require 'rspec'
require 'dotenv'
require 'faraday'
require 'webmock/rspec'

require_relative '../lib/supergood/api'
require_relative '../lib/supergood/logger'
require_relative '../lib/supergood/client'
require_relative '../lib/supergood/utils'
require_relative '../lib/supergood/constants'

Dotenv.load

def get_config(additional_keys = {})
  return {
    flushInterval: 1000,
    cacheTtl: 0,
    eventSinkEndpoint: '/api/events',
    errorSinkEndpoint: '/api/errors',
    keysToHash: [],
    ignoredDomains: []
  }.merge(additional_keys)
end

def get_request_format(match_keys = {})
  {
    id: /.*/,
    headers: /.*/,
    method: /.*/,
    url: /.*/,
    path: /.*/,
    search: /.*/,
    body: /.*/,
    requestedAt: /.*/,
  }.match(match_keys)
end

def get_response_format(match_keys = {})
  {
    headers: /.*/,
    status: /.*/,
    statusText: /.*/,
    body: /.*/,
    respondedAt: /.*/,
    duration: /.*/,
  }.match(match_keys)
end

HEADERS = {
  'Accept' => '*/*',
  'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
  'Authorization' => /Basic .*/,
  'Content-Type' => 'application/json',
  'User-Agent' => /.*/
}

OUTBOUND_URL = 'https://www.example.com'

describe Supergood do
  describe 'successful requests' do
    it 'captures all outgoing 200 http requests' do
      config_response = get_config()
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
      to_return(status: 200, body: config_response.to_json, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/events').
      with { |req|
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end
  end

  #   it 'captures non-success status and errors' do
  #     config_response = get_config()
  #     stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
  #     to_return(status: 200, body: config_response.to_json, headers: {})
  #     http_error_codes = [400, 401, 403, 404, 500, 501, 502, 503, 504]
  #     Supergood.init()

  #     for http_error_code in http_error_codes do
  #       stub_request(:get, OUTBOUND_URL + '/' + http_error_code.to_s).
  #       to_return(status: http_error_code)
  #       Faraday.get(OUTBOUND_URL + '/' + http_error_code.to_s)
  #     end

  #     Supergood.close()
  #     expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/events').
  #     with { |req|
  #       req.body.length() == http_error_codes.length() &&
  #       req.body[0][:request] != nil &&
  #       req.body[0][:response] != nil
  #     }).
  #     to have_been_made.once
  #   end

  #   it 'post requests successfully' do
  #     config_response = get_config()
  #     stub_request(:post, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
  #     stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
  #     to_return(status: 200, body: config_response.to_json, headers: {})
  #     Supergood.init()
  #     conn = Faraday.new(url: OUTBOUND_URL)
  #     response = conn.post('/')
  #     Supergood.close()
  #     expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/events').
  #     with { |req|
  #       req.body[0][:request] != nil &&
  #       req.body[0][:request][:method] == 'POST' &&
  #       req.body[0][:response] != nil
  #     }).
  #     to have_been_made.once
  #   end
  # end

  # describe 'error requests' do
  #   it 'reports timeout properly' do
  #     config_response = get_config()
  #     stub_request(:get, OUTBOUND_URL).to_timeout
  #     stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
  #     to_return(status: 200, body: config_response.to_json, headers: {})
  #     Supergood.init()

  #     begin
  #       Faraday.get(OUTBOUND_URL)
  #     rescue => e
  #       # puts e
  #     end

  #     Supergood.close()
  #     expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/events').
  #     with { |req|
  #       req.body[0][:request] != nil &&
  #       req.body[0][:response] == nil
  #     }).
  #     to have_been_made.once
  #   end

  #   it 'reports errors properly' do
  #     WebMock.reset!
  #     config_response = get_config()
  #     stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
  #     stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/api/errors').to_return(status: 200, body: { message: 'Success' }.to_json, headers: {})
  #     stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/api/events').to_raise(SupergoodException.new ERRORS[:POSTING_EVENTS])
  #     stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
  #     to_return(status: 200, body: config_response.to_json, headers: {})
  #     Supergood.init()
  #     Faraday.get(OUTBOUND_URL)
  #     Supergood.close()
  #     expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/errors').
  #     with { | req |
  #       req.body[:error] != nil
  #     }).to have_been_made.once
  #     WebMock.reset!
  #   end
  # end

  # describe 'config specifications' do
  #   it 'hashes the entire body from the config' do
  #     config_response = get_config({ keysToHash: ['response.body'] })
  #     stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/api/config').with(headers: HEADERS).
  #     to_return(status: 200, body: config_response.to_json, headers: {})
  #     stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
  #     Supergood.init()
  #     Faraday.get(OUTBOUND_URL)
  #     Supergood.close()
  #     expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/api/events').
  #     with { |req|
  #       req.body[0][:response][:body][:hashed] != nil
  #       req.body[0][:request] != nil &&
  #       req.body[0][:response] != nil
  #     }).to have_been_made.once
  #   end
  # end
end
