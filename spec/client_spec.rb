require 'rspec'
require 'dotenv'
require 'faraday'
require 'webmock/rspec'
require 'stringio'
require 'zlib'
require 'json'
require 'uri'

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

def stub_remote_config(config = [], status = 200)
  stub_request(:get, ENV['SUPERGOOD_BASE_URL'] + '/config').to_return(status: status, body: config.to_json, headers: {})
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
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_remote_config
      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        !req.body[0][:response].nil?
      })
        .to have_been_made.once
    end

    it 'captures non-success status and errors' do
      http_error_codes = [400, 401, 403, 404, 500, 501, 502, 503, 504]
      stub_remote_config
      Supergood.init({ forceRedactAll: false })

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
      stub_remote_config
      Supergood.init({ forceRedactAll: false })
      conn = Faraday.new(url: OUTBOUND_URL)
      conn.post('/')
      Supergood.close
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        req.body[0][:request][:method] == 'POST' &&
        !req.body[0][:response].nil?
      })
        .to have_been_made.once
    end
  end

  describe 'local development' do
    it 'does not post requests externally when keys are local' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      config = { client_id: 'local-client-id', client_secret: 'local-client-secret', forceRedactAll: false }

      Supergood.init(config)
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')).
      to have_not_been_made
    end
  end

  describe 'initialization' do
    it 'does not install multiple interceptors' do
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_remote_config

      Supergood.init({ forceRedactAll: false })
      Supergood.init({ forceRedactAll: false })
      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        !req.body[0][:response].nil?
      })
        .to have_been_made.once
    end

    it 'does not fail when close is called multiple times' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL)
        .to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close
      Supergood.close
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        !req.body[0][:response].nil?
      })
        .to have_been_made.once
    end
  end

  describe 'teardown' do
    it 'closes the client and does not intercept subsequent requests' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL)
        .to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      Faraday.get(OUTBOUND_URL)
      Faraday.get(OUTBOUND_URL)
      Faraday.get(OUTBOUND_URL)

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        !req.body[0][:response].nil?
      })
        .to have_been_made.once
    end
  end

  describe 'error requests' do
    it 'reports timeout properly' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL).to_timeout
      Supergood.init({ forceRedactAll: false })

      begin
        Faraday.get(OUTBOUND_URL)
      rescue => e
        puts e
      end

      Supergood.close()
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        !req.body[0][:request].nil? &&
        req.body[0][:response].nil?
      })
        .to have_been_made.once
    end

    it 'reports errors properly' do
      WebMock.reset!
      stub_remote_config
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/errors').to_return(status: 200, body: { message: 'Success' }.to_json, headers: {})
      stub_request(:post,  ENV['SUPERGOOD_BASE_URL'] + '/events').to_raise(SupergoodException.new ERRORS[:POSTING_EVENTS])

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/errors').
      with { | req |
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[:error] != nil
      }).to have_been_made.once
      WebMock.reset!
    end
  end

  describe 'config specifications' do
    it 'ignores caching specified domains' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      Supergood.init({ ignoredDomains: ['example.com'], forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')).
      to have_not_been_made
    end

    it 'only allows allowed domains, ignores ignored' do
      stub_remote_config
      SECOND_OUTBOUND_URL = 'https://www.example-2.com/'
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:get, SECOND_OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init({ allowedDomains: ['example-2.com'], forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Faraday.get(SECOND_OUTBOUND_URL)
      Supergood.close
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:request][:url] == SECOND_OUTBOUND_URL
      }).to have_been_made.once
    end

    it 'allowed domains override ignored' do
      stub_remote_config
      SECOND_OUTBOUND_URL = 'https://www.example-2.com/'
      stub_request(:get, OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:get, SECOND_OUTBOUND_URL).to_return(status: 200, body: { message: 'success' }.to_json, headers: {})

      Supergood.init({ forceRedactAll: false, allowedDomains: ['example-2.com'], ignoredDomains: ['example-2.com'] })
      Faraday.get(OUTBOUND_URL)
      Faraday.get(SECOND_OUTBOUND_URL)
      Supergood.close
      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:request][:url] == SECOND_OUTBOUND_URL
      }).to have_been_made.once
    end

  end

  describe 'gzipped and large payloads' do
    it 'does not automatically hash payloads smaller than 500kb, but large nonetheless' do
      stub_remote_config
      PAYLOAD_SIZE_300kb = 300000
      payload = { payload: 'X' * PAYLOAD_SIZE_300kb }.to_json
      stub_request(:get, OUTBOUND_URL)
        .to_return(status: 200, body: payload, headers: {})

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        !req.body[0][:request].nil?
      }).to have_been_made.once
    end
  end

  describe 'redact by default' do
    it 'redacts all data by default when flag set' do
      stub_remote_config
      stub_request(:get, OUTBOUND_URL).to_return(
        status: 200,
        body: {
          message: 'success',
          txns: [
            { user: 'Alex', id: 1 },
            { user: 'Steve', id: 2 }
          ],
          payment_method: {
            type: 'card',
            card: {
              numbers: [1,2,3,4]
            }
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json', 'Content-Encoding' => 'gzip' }
      )
      Supergood.init
      Faraday.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')
        .with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body][:txns][0][:user].nil? &&
        req.body[0][:response][:body][:txns][0][:id].nil? &&
        req.body[0][:response][:body][:txns][1][:user].nil? &&
        req.body[0][:response][:body][:txns][1][:id].nil? &&
        req.body[0][:response][:body][:payment_method][:type].nil? &&
        req.body[0][:response][:body][:payment_method][:card][:numbers][0].nil? &&
        req.body[0][:response][:body][:payment_method][:card][:numbers][1].nil? &&
        req.body[0][:response][:body][:payment_method][:card][:numbers][2].nil? &&
        req.body[0][:response][:body][:payment_method][:card][:numbers][3].nil? &&
        req.body[0][:response][:headers]['content-type'.to_sym].nil? &&
        req.body[0][:response][:headers]['content-encoding'.to_sym].nil?
      }).to have_been_made.once
    end
  end

  describe 'remote config' do
    it 'fetches remote config' do
      stub_remote_config([{
        domain: Supergood::Utils.get_host_without_www(OUTBOUND_URL),
        endpoints: [
          {
            name: '/test_two',
            matchingRegex: { regex: '/test_two', location: 'path' },
            endpointConfiguration: { action: 'Ignore', sensitiveKeys: [{}] }
          }
        ]
      }])
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 && req.body[0][:request][:url] == OUTBOUND_URL + '/test_one'
      }).to have_been_made.once
    end

    it 'fetches remote config and ignores some endpoints' do
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_request(:get, OUTBOUND_URL + '/test_two').to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_remote_config([{
        domain: Supergood::Utils.get_host_without_www(OUTBOUND_URL),
        endpoints: [
          {
            name: '/test_one',
            matchingRegex: { regex: '/test_one', location: 'path' },
            endpointConfiguration: { action: 'Ignore', sensitiveKeys: [{}] }
          }
        ]
      }])

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Faraday.get(OUTBOUND_URL + '/test_two')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 && req.body[0][:request][:url] == OUTBOUND_URL + '/test_two'
      }).to have_been_made.once
    end

    it 'redacts non-array sensitive keys' do
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: { message: 'success', redact_me: 'redact_me' }.to_json, headers: {})
      stub_remote_config([{
        domain: Supergood::Utils.get_host_without_www(OUTBOUND_URL),
        endpoints: [
          {
            name: '/test_one',
            matchingRegex: { regex: '/test_one', location: 'path' },
            endpointConfiguration: {
              action: 'Allow',
              sensitiveKeys: [{
                keyPath: 'response.body.redact_me'
              }]
            }
          }
        ]
      }])

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:response][:body][:redact_me].nil? &&
        req.body[0][:metadata][:sensitiveKeys][0][:keyPath] == 'responseBody.redact_me' &&
        req.body[0][:metadata][:sensitiveKeys][0][:length] == 9 &&
        req.body[0][:metadata][:sensitiveKeys][0][:type] == 'string'
      }).to have_been_made.once
    end

    it 'redacts data types properly' do
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: {
        string: 'string',
        array: [1,2,3],
        object: { a: 1, b: 2 },
        number: 123,
        float: 123.456,
        boolean: true,
        nothing: nil
      }.to_json, headers: {})
      stub_remote_config([{
        domain: Supergood::Utils.get_host_without_www(OUTBOUND_URL),
        endpoints: [
          {
            name: '/test_one',
            matchingRegex: { regex: '/test_one', location: 'path' },
            endpointConfiguration: {
              action: 'Allow',
              sensitiveKeys: [
                {
                  keyPath: 'response.body.string'
                },
                {
                  keyPath: 'response.body.array'
                },
                {
                  keyPath: 'response.body.object'
                },
                {
                  keyPath: 'response.body.number'
                },
                {
                  keyPath: 'response.body.boolean'
                },
                {
                  keyPath: 'response.body.nothing'
                },
                {
                  keyPath: 'response.body.float'
                }
              ]
            }
          }
        ]
      }])

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:metadata][:sensitiveKeys].length == 6 &&
        req.body[0][:metadata][:sensitiveKeys][0][:keyPath] == 'responseBody.string' &&
        req.body[0][:metadata][:sensitiveKeys][0][:length] == 6 &&
        req.body[0][:metadata][:sensitiveKeys][0][:type] == 'string' &&
        req.body[0][:metadata][:sensitiveKeys][1][:keyPath] == 'responseBody.array' &&
        req.body[0][:metadata][:sensitiveKeys][1][:length] == 3 &&
        req.body[0][:metadata][:sensitiveKeys][1][:type] == 'array' &&
        req.body[0][:metadata][:sensitiveKeys][2][:keyPath] == 'responseBody.object' &&
        req.body[0][:metadata][:sensitiveKeys][2][:length] == 13 &&
        req.body[0][:metadata][:sensitiveKeys][2][:type] == 'object' &&
        req.body[0][:metadata][:sensitiveKeys][3][:keyPath] == 'responseBody.number' &&
        req.body[0][:metadata][:sensitiveKeys][3][:length] == 3 &&
        req.body[0][:metadata][:sensitiveKeys][3][:type] == 'integer' &&
        req.body[0][:metadata][:sensitiveKeys][4][:keyPath] == 'responseBody.boolean' &&
        req.body[0][:metadata][:sensitiveKeys][4][:length] == 1 &&
        req.body[0][:metadata][:sensitiveKeys][4][:type] == 'boolean' &&
        req.body[0][:metadata][:sensitiveKeys][5][:keyPath] == 'responseBody.nothing' # &&
        req.body[0][:metadata][:sensitiveKeys][5][:length] == 0 &&
        req.body[0][:metadata][:sensitiveKeys][5][:type] == 'null' &&
        req.body[0][:metadata][:sensitiveKeys][6][:keyPath] == 'responseBody.float' &&
        req.body[0][:metadata][:sensitiveKeys][6][:length] == 7 &&
        req.body[0][:metadata][:sensitiveKeys][6][:type] == 'float'
      }).to have_been_made.once
    end

    it 'redacts sensitive keys as array elements' do
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: {
        message: 'success',
        txns: [{ price: 123, user: 'alex' }, { price: 321, user: 'steve' }]
      }.to_json, headers: {})
      stub_remote_config([{
        domain: Supergood::Utils.get_host_without_www(OUTBOUND_URL),
        endpoints: [
          {
            name: '/test_one',
            matchingRegex: { regex: '/test_one', location: 'path' },
            endpointConfiguration: {
              action: 'Allow',
              sensitiveKeys: [{
                keyPath: 'response.body.txns[].user'
              }]
            }
          }
        ]
      }])

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body.length == 1 &&
        req.body[0][:response][:body][:txns][0][:user].nil? &&
        req.body[0][:response][:body][:txns][1][:user].nil? &&
        !req.body[0][:response][:body][:txns][0][:price].nil? &&
        !req.body[0][:response][:body][:txns][1][:price].nil? &&
        req.body[0][:metadata][:sensitiveKeys][0][:keyPath] == 'responseBody.txns[0].user' &&
        req.body[0][:metadata][:sensitiveKeys][0][:length] == 4 &&
        req.body[0][:metadata][:sensitiveKeys][0][:type] == 'string' &&
        req.body[0][:metadata][:sensitiveKeys][1][:keyPath] == 'responseBody.txns[1].user' &&
        req.body[0][:metadata][:sensitiveKeys][1][:length] == 5 &&
        req.body[0][:metadata][:sensitiveKeys][1][:type] == 'string'
      }).to have_been_made.once
    end

    it 'does not intercept anything if the remote config can not be fetched' do
      stub_request(:get, OUTBOUND_URL + '/test_one').to_return(status: 200, body: { message: 'success' }.to_json, headers: {})
      stub_remote_config([], 500)

      Supergood.init({ forceRedactAll: false })
      Faraday.get(OUTBOUND_URL + '/test_one')
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events')).
      to_not have_been_made
    end

  end

  describe 'other http clients' do
    it 'tests rest-client' do
      stub_remote_config
      payload = { message: 'success' }.to_json
      stub_request(:get, OUTBOUND_URL)
        .to_return(status: 200, body: payload, headers: {})

      Supergood.init({ forceRedactAll: false })
      RestClient.get(OUTBOUND_URL)
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        !req.body[0][:request].nil?
      }).to have_been_made.once
    end

    it 'tests HTTParty' do
      stub_remote_config
      payload = { message: 'success' }.to_json
      stub_request(:get, OUTBOUND_URL)
        .to_return(status: 200, body: payload, headers: {})

      Supergood.init({ forceRedactAll: false })
      HTTParty.get(OUTBOUND_URL, { :headers => { 'Accept': 'application/json' }})
      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        !req.body[0][:request].nil?
      }).to have_been_made.once
    end

    it 'tests http.rb' do
      stub_remote_config
      WebMock.allow_net_connect!
      payload = { message: 'success' }.to_json
      stub_request(:post, OUTBOUND_URL + '?params=1')
        .to_return(status: 200, body: payload, headers: { 'Content-type' => 'application/json'})

      Supergood.init({ forceRedactAll: false })

      http = HTTP.accept(:json)
      http.post(OUTBOUND_URL + '?params=1', :body => 'test=123')

      Supergood.close

      expect(a_request(:post, ENV['SUPERGOOD_BASE_URL'] + '/events').
      with { |req|
        req.body = JSON.parse(req.body, symbolize_names: true)
        req.body[0][:response][:body].to_json == payload &&
        !req.body[0][:request].nil?
      }).to have_been_made.once
    end
  end
end
