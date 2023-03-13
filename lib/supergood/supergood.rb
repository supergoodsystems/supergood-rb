require 'webmock'
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'
require 'dotenv'
require 'base64'

Dotenv.load

module Supergood

  DEFAULT_SUPERGOOD_BASE_URL = 'https://dashboard.supergood.ai'

  class << self
    def init(supergood_client_id=nil, supergood_client_secret=nil, base_url=nil)

      supergood_client_id = supergood_client_id || ENV['SUPERGOOD_CLIENT_ID']
      supergood_client_secret = supergood_client_secret || ENV['SUPERGOOD_CLIENT_SECRET']
      base_url = base_url || ENV['SUPERGOOD_BASE_URL'] || DEFAULT_SUPERGOOD_BASE_URL
      puts "Initializing Supergood with client_id: #{supergood_client_id}, client_secret: #{supergood_client_secret}, base_url: #{base_url}"
      header_options = {
        'headers' => {
          'Content-Type' => 'application/json',
          'Authorization' => 'Basic ' + Base64.encode64(supergood_client_id + ':' + supergood_client_secret)
        }
      }

      @api = Supergood::Api.new(header_options, base_url)
      @logger = Supergood::Logger.new(@api, header_options, base_url)

      config = api.fetch_config()

      @ignored_domains = config[:ignored_domains]
      @keys_to_hash = config[:keys_to_hash]

      api.set_error_sink_url(base_url + config[:error_sink_endpoint])
      api.set_event_sink_url(base_url + config[:event_sink_endpoint])
      api.set_logger(@logger)

      @request_cache = {}
      @response_cache = {}

      set_interval(config[:flush_interval]) { flush_cache }
    end

    def log
      @logger
    end

    def api
      @api
    end

    def flush_cache(force = false)
      # If there's notthing in the response cache, and we're not forcing a flush, then return
      if @response_cache.empty? && !force
        return
      elsif force && @response_cache.empty? && @request_cache.empty?
        return
      end

      data = @response_cache.values

      if force
        data += @request_cache.values
      end

      begin
        log.debug(data)
        # api.post_events(data)
      rescue => e
        #TODO Add error posting to Supergood
        puts "Error posting events: #{e}"
        api.post_errors(e)
      ensure
        @response_cache.clear
        @request_cache.clear if force
      end

    end

    def set_interval(delay)
      Thread.new do
        loop do
          sleep delay
          yield # call passed block
        end
      end
    end

    def self.intercept(*args, &block)
      instance.intercept(*args, &block)
    end

    def self.instance
      @instance ||= Supergood.new
    end

    def intercept(http, request, request_body)
      request_id = SecureRandom.uuid
      start_time = Time.now
      response = yield
    ensure
      if log_event?(http, request)
        time = ((Time.now - start_time) * 1000)
        url_payload = parse_url(http, request)
        @request_cache[request_id] = {
          request: {
            id: request_id,
            method: request.method,
            url: url_payload[:url],
            protocol: url_payload[:protocol],
            domain: url_payload[:domain],
            path: url_payload[:path],
            search: url_payload[:search],
            body: hash_specified_keys(request.body),
            header: hash_specified_keys(get_header(request)),
          }
        }
        if defined?(response) && response
          request_payload = @request_cache[request_id]
          @response_cache[request_id] = {
            request: request_payload,
            response: {
              status: response.code,
              status_text: response.message,
              header: hash_specified_keys(get_header(response)),
              body: hash_specified_keys(response.body),
            }
          }
          @request_cache.delete(request_id)
        end
      end
    end

    def log_event?(http, request)
      !ignored?(http, request) && (http.started? || webmock?(http, request))
    end

    def ignored?(http, request)
      url = request_url(http, request)
      @ignored_domains.any? do |pattern|
        url =~ pattern
      end
    end

    def webmock?(http, request)
      return false unless defined?(::WebMock)
      uri = request_uri_as_string(http, request)
      method = request.method.downcase.to_sym
      signature = WebMock::RequestSignature.new(method, uri)
      ::WebMock.registered_request?(signature)
    end

    # TODO: Hash keys, move to Utils?
    def hash_specified_keys(body_or_header)
      body_or_header
    end

    def get_header(request_or_response)
      header = {}
      request_or_response.each_header do |k,v|
        header[k] = v
      end
      header
    end

    def parse_url(http, request)
      url = request_url(http, request)
      uri = URI.parse(url)
      {
        url: url,
        protocol: uri.scheme,
        domain: uri.host,
        path: uri.path,
        search: uri.query,
      }
    end

    def request_url(http, request)
      URI::DEFAULT_PARSER.unescape("http#{"s" if http.use_ssl?}://#{http.address}:#{http.port}#{request.path}")
    end
  end
end


# Attach library to Net::HTTP and WebMock
block = lambda do |a|
  # raise instance_methods.inspect
  alias request_without_net_http_logger request
  def request(request, body = nil, &block)
    Supergood.intercept(self, request, body) do
      request_without_net_http_logger(request, body, &block)
    end
  end
end

if defined?(::WebMock)
  klass = WebMock::HttpLibAdapters::NetHttpAdapter.instance_variable_get("@webMockNetHTTP")
  # raise klass.instance_methods.inspect
  klass.class_eval(&block)
end

Net::HTTP.class_eval(&block)
