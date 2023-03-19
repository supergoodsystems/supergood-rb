require 'json'
require 'securerandom'
require 'dotenv'
require 'base64'
require 'uri'

require_relative 'vendors/http'
require_relative 'vendors/net-http'

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

    def intercept(request)
      request_id = SecureRandom.uuid
      requested_at = Time.now
      if !ignored?(request[:domain])
        cache_request(request_id, requested_at, request)
      end

      response = yield

      if !ignored?(request[:domain]) && defined?(response)
        cache_response(request_id, requested_at, response)
      end

      return response[:original_response]
    end

    def cache_request(request_id, requested_at, request)
      begin
        request_payload = {
          id: request_id,
          headers: request[:headers],
          method: request[:method],
          url: request[:url],
          path: request[:path],
          search: request[:search],
          body: Supergood::Utils.safe_parse_json(request[:body]),
          requestedAt: requested_at
        }
        @request_cache[request_id] = {
          request: request_payload
        }
      rescue => e
        log.error({ request: request }, e, ERRORS[:CACHING_REQUEST])
      end
    end

    def cache_response(request_id, requested_at, response)
      begin
        responded_at = Time.now
        duration = (responded_at - requested_at) * 1000
        request_payload = @request_cache[request_id]
        response_payload = {
          headers: response[:headers],
          status: response[:status],
          statusText: response[:statusText],
          body: Supergood::Utils.safe_parse_json(response[:body]),
          respondedAt: responded_at,
          duration: duration,
        }
        @response_cache[request_id] = Supergood::Utils.hash_values_from_keys(request_payload.merge({
          response: response_payload
        }), @keys_to_hash)
        @request_cache.delete(request_id)
      rescue => e
        puts e
        log.error(
          { request: request_payload, response: response_payload },
          e, ERRORS[:CACHING_RESPONSE]
        )
      end
    end

    def ignored?(domain)
      base_domain = URI.parse(@base_url).hostname
      if domain == base_domain
        return true
      else
        @ignored_domains.any? do |ignored_domain|
          pattern = URI.parse(ignored_domain).hostname
          domain =~ pattern
        end
      end
    end
  end
end
