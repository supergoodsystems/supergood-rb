require 'rspec'
require 'dotenv'
require 'faraday'
require 'webmock/rspec'
require 'stringio'
require 'zlib'
require 'json'

require 'rest-client'
require 'httparty'
require 'http'

require_relative '../lib/supergood/api'
require_relative '../lib/supergood/logger'
require_relative '../lib/supergood/client'
require_relative '../lib/supergood/utils'
require_relative '../lib/supergood/constants'

Dotenv.load

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
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end

    it 'captures non-success status and errors' do
      http_error_codes = [400, 401, 403, 404, 500, 501, 502, 503, 504]
      Supergood.init()

      for http_error_code in http_error_codes do
        stub_request(:get, OUTBOUND_URL + '/' + http_error_code.to_s).
        to_return(status: http_error_code)
        Faraday.get(OUTBOUND_URL + '/' + http_error_code.to_s)
      end

      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length() == http_error_codes.length() &&
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end

    it 'post requests successfully' do
      stub_request(:post, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init()
      conn = Faraday.new(url: OUTBOUND_URL)
      response = conn.post('/')
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:request][:method] == 'POST' &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end
  end

  describe 'local development' do
    it 'does not post requests externally when keys are local' do
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      config = { client_id: 'local-client-id', client_secret: 'local-client-secret' }

      Supergood.init(config)
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')).
      to have_not_been_made
    end
  end

  describe 'initialization' do
    it 'does not install multiple interceptors' do
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init()
      Supergood.init()
      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end

    it 'does not fail when close is called multiple times' do
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()
      Supergood.close()
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end
  end


  describe 'teardown' do
    it 'closes the client and does not intercept subsequent requests' do
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      Faraday.get(OUTBOUND_URL)
      Faraday.get(OUTBOUND_URL)
      Faraday.get(OUTBOUND_URL)

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).
      to have_been_made.once
    end
  end

  describe 'error requests' do
    it 'reports timeout properly' do
      stub_request(:get, OUTBOUND_URL).to_timeout
      Supergood.init()

      begin
        Faraday.get(OUTBOUND_URL)
      rescue => e
        puts e
      end

      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:request] != nil &&
        req.body[0][:response] == nil
      }).
      to have_been_made.once
    end

    it 'reports errors properly' do
      WebMock.reset!

      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/errors').to_return(status: 200, body: { message: 'Success' }.to_json, headers: {})
      stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/events').to_raise(SupergoodException.new ERRORS[:POSTING_EVENTS])

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/errors').
      with { | req |
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[:error] != nil
      }).to have_been_made.once
      WebMock.reset!
    end
  end

  describe 'config specifications' do
    it 'hashes the entire body from the config' do
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      Supergood.init(config={ keysToHash: ['response.body']})
      Faraday.get(OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body][:hashed] == 'ODFhZjA0MTdmOTY5ZjkzODQ4YjFjZjMwZmNlMWRiOTM4ODRmYWNjMQ=='
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).to have_been_made.once
    end

    it 'hashes single key from config' do
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      Supergood.init(config={ keysToHash: ['response.body.message'] })
      Faraday.get(OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body][:message] == 'MTFmMzc2NTRkYTJkNWM5MmMzODU2MjM4ZmJlYmNkZjY0NGQ3NjEwNw=='
        req.body[0][:request] != nil &&
        req.body[0][:response] != nil
      }).to have_been_made.once
    end

    it 'ignores caching specified domains' do
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      Supergood.init(config={ ignoredDomains: ['example.com'] })
      Faraday.get(OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')).
      to have_not_been_made
    end

    it 'only allows allowed domains, ignores ignored' do
      SECOND_OUTBOUND_URL = 'https://www.example-2.com/'
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:get, SECOND_OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init(config={ allowedDomains: ['example-2.com'] })
      Faraday.get(OUTBOUND_URL)
      Faraday.get(SECOND_OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:request][:url] == SECOND_OUTBOUND_URL
      }).to have_been_made.once
    end

    it 'allowed domains override ignored' do
      SECOND_OUTBOUND_URL = 'https://www.example-2.com/'
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:get, SECOND_OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init(config={ allowedDomains: ['example-2.com'], ignoredDomains: ['example-2.com'] })
      Faraday.get(OUTBOUND_URL)
      Faraday.get(SECOND_OUTBOUND_URL)
      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:request][:url] == SECOND_OUTBOUND_URL
      }).to have_been_made.once
    end

  end

  describe 'gzipped and large payloads' do
    it 'automatically hashes payloads bigger than 500kb' do
      PAYLOAD_SIZE_500kb = 500000
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: { payload: 'X' * PAYLOAD_SIZE_500kb }.to_json, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body][:hashed] == 'ZTg2YjZhNjhjNTM5NGRmN2UyNGRhNGQzZjQxNzEyNmE2OTBlMDI3Nw==' &&
        req.body[0][:request] != nil
      }).to have_been_made.once
    end

    it 'does not automatically hash payloads smaller than 500kb, but large nonetheless' do
      PAYLOAD_SIZE_300kb = 300000
      payload = { payload: 'X' * PAYLOAD_SIZE_300kb }.to_json
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: payload, headers: {})

      Supergood.init()
      Faraday.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        req.body[0][:request] != nil
      }).to have_been_made.once
    end
  end

  describe 'other http clients' do
    it 'tests rest-client' do
      payload = { message: 'success' }.to_json
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: payload, headers: {})

      Supergood.init()
      RestClient.get(OUTBOUND_URL)
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        req.body[0][:request] != nil
      }).to have_been_made.once
    end

    it 'tests HTTParty' do
      payload = { message: 'success' }.to_json
      stub_request(:get, OUTBOUND_URL).
      to_return(status: 200, body: payload, headers: {})

      Supergood.init()
      HTTParty.get(OUTBOUND_URL, { :headers => { 'Accept': 'application/json' }})
      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        req.body[0][:request] != nil
      }).to have_been_made.once
    end

    it 'tests http.rb' do
      WebMock.allow_net_connect!
      payload = { message: 'success' }.to_json
      stub_request(:post, OUTBOUND_URL + '?params=1').
      to_return(status: 200, body: payload, headers: { 'Content-type' => 'application/json'})

      Supergood.init()

      http = HTTP.accept(:json)
      response = http.post(OUTBOUND_URL + '?params=1', :body => 'test=123')

      Supergood.close()

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        req.body[0][:request] != nil
      }).to have_been_made.once
    end
  end
end
