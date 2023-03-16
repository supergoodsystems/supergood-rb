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

      if !supergood_client_id
        raise SupergoodException.new ERRORS[:NO_CLIENT_ID]
      end

      if !supergood_client_secret
        raise SupergoodException.new ERRORS[:NO_CLIENT_SECRET]
      end

      @base_url = base_url || ENV['SUPERGOOD_BASE_URL'] || DEFAULT_SUPERGOOD_BASE_URL
      header_options = {
        'Content-Type' => 'application/json',
        'Authorization' => 'Basic ' + Base64.encode64(supergood_client_id + ':' + supergood_client_secret).gsub(/\n/, '')
      }

      @api = Supergood::Api.new(header_options, @base_url)
      @config = @api.fetch_config
      @ignored_domains = @config[:ignoredDomains]
      @keys_to_hash = @config[:keysToHash]
      @logger = Supergood::Logger.new(@api, @config, header_options)

      @api.set_error_sink_endpoint(@config[:errorSinkEndpoint])
      @api.set_event_sink_endpoint(@config[:eventSinkEndpoint])
      @api.set_logger(@logger)

      @request_cache = {}
      @response_cache = {}

      @interval_thread = set_interval(@config[:flushInterval]) { flush_cache }
      self
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
        api.post_events(data)
      rescue => e
        log.error(data, e, e.message)
      ensure
        @response_cache.clear
        @request_cache.clear if force
      end

    end

    def close(force = true)
      log.debug('Cleaning up, flushing cache gracefully.')
      @interval_thread.kill
      flush_cache(force)
    end

    def set_interval(delay)
      Thread.new do
        loop do
          sleep delay / 1000.0
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
      if log_event?(http, request)
        requested_at = Time.now
        cache_request(request_id, request, parse_url(http, request), requested_at)
        if defined?(response) && response
          cache_response(request_id, response, requested_at)
        end
      end
      ## Need to return the response when you intercept... duh.
      response
    end

    def cache_request(request_id, request, url_payload, requested_at)
      begin
        request_payload = {
          id: request_id,
          headers: get_header(request),
          method: request.method,
          url: url_payload[:url],
          path: url_payload[:path],
          search: url_payload[:search],
          body: {}.to_json, # request.body,
          requestedAt: requested_at.utc.iso8601
        }
        @request_cache[request_id] = {
          request: request_payload
        }
      rescue => e
        log.error({ request: request }, e, e.message)
      end
    end

    def cache_response(request_id, response, requested_at)
      begin
        responded_at = Time.now
        duration = (responded_at - requested_at) * 1000
        request_payload = @request_cache[request_id]
        response_payload = {
          headers: get_header(response),
          status: response.code,
          statusText: response.message,
          body: {}.to_json, # response.body,
          respondedAt: responded_at,
          duration: duration,
        }
        @response_cache[request_id] = request_payload.merge({
          response: response_payload
        })
        @request_cache.delete(request_id)
      rescue => e
        log.error(
          { request: request_payload, response: response_payload },
          e, e.message
        )
      end
    end

    def log_event?(http, request)
      !ignored?(http, request) && (http.started? || webmock?(http, request))
    end

    def ignored?(http, request)
      url = parse_url(http, request)
      base_domain = URI.parse(@base_url).hostname
      if url[:domain] == base_domain
        return true
      else
        @ignored_domains.any? do |ignored_domain|
          pattern = URI.parse(ignored_domain).hostname
          url[:domain] =~ pattern
        end
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
