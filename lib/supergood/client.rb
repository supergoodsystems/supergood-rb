require 'json'
require 'securerandom'
require 'dotenv'
require 'base64'
require 'uri'

require_relative 'vendors/http'
require_relative 'vendors/net-http'

Dotenv.load

module Supergood

  DEFAULT_SUPERGOOD_BASE_URL = 'https://api.supergood.ai'
  class << self
    def init(config={})
      supergood_client_id = config[:client_id] || ENV['SUPERGOOD_CLIENT_ID']
      supergood_client_secret = config[:client_secret] || ENV['SUPERGOOD_CLIENT_SECRET']

      if !supergood_client_id
        raise SupergoodException.new ERRORS[:NO_CLIENT_ID]
      end

      if !supergood_client_secret
        raise SupergoodException.new ERRORS[:NO_CLIENT_SECRET]
      end

      @base_url = ENV['SUPERGOOD_BASE_URL'] || DEFAULT_SUPERGOOD_BASE_URL
      @api = Supergood::Api.new(supergood_client_id, supergood_client_secret, @base_url)
      @config = Supergood::Utils.make_config(config)

      @allowed_domains = @config[:allowedDomains]
      @ignored_domains = @config[:ignoredDomains]
      @logger = Supergood::Logger.new(@api, @config, @api.header_options)

      @api.set_logger(@logger)

      @request_cache = {}
      @response_cache = {}

      @interval_thread = set_interval(@config[:flushInterval]) { flush_cache }
      @remote_config_thread = set_interval(@config[:remoteConfigFetchInterval]) { fetch_and_process_remote_config }

      @http_clients = [
        Supergood::Vendor::NetHTTP,
        Supergood::Vendor::HTTPrb
      ]

      fetch_and_process_remote_config
      patch_all
      self
    end

    def log
      @logger
    end

    def api
      @api
    end

    def fetch_and_process_remote_config
      begin
        remote_config = @api.get_remote_config
        @config = @config.merge({ :remote_config => Supergood::Utils.process_remote_config(remote_config) })
      rescue => e
        log.error({}, e, ERRORS[:CONFIG_FETCH_ERROR])
      end
    end

    def flush_cache(force = false)
      # If there's notthing in the response cache, and we're not forcing a flush, then return

      if @response_cache.empty? && !force
        return
      elsif force && @response_cache.empty? && @request_cache.empty?
        return
      end

      data = Supergood::Utils.prepare_data(@response_cache.values, @config[:remote_config], @config[:forceRedactAll])
      data += Supergood::Utils.prepare_data(@request_cache.values, @config[:remote_config], @config[:forceRedactAll]) if force

      begin
        api.post_events(data)
      rescue => e
        log.error(data, e, e.message)
      ensure
        @response_cache.clear
        @request_cache.clear if force
      end

    end

    def cleanup()
      @interval_thread.kill
      @remote_config_thread.kill
      unpatch_all()
    end

    def close(force = true)
      log.debug('Cleaning up, flushing cache gracefully.')
      flush_cache(force)
      cleanup()
    end

    def patch_all
      @http_clients.each do |client|
        client.patch
      end
    end

    def unpatch_all
      @http_clients.each do |client|
        client.unpatch
      end
    end

    def set_interval(delay)
      Thread.new do
        loop do
          sleep delay / 1000.0
          yield # call passed block
        end
      end
    end

    def intercept(request)
      remote_config = @config[:remote_config]

      if remote_config.nil?
        response = yield
        return response[:original_response]
      end

      request_id = SecureRandom.uuid
      requested_at = Time.now

      endpoint_config = Supergood::Utils.get_endpoint_config(request.transform_keys(&:to_s), remote_config)
      ignore_endpoint = endpoint_config ? endpoint_config['ignored'] : false

      if !ignore_endpoint && !ignored?(request[:domain])
        cache_request(request_id, requested_at, request)
      end

      response = yield
      if !ignore_endpoint && !ignored?(request[:domain]) && defined?(response)
        cache_response(request_id, requested_at, response)
      end

      return response[:original_response]
    end

    def cache_request(request_id, requested_at, request)
      if !@config[:remote_config]
        return
      end

      begin
        request_payload = {
          'id' => request_id,
          'headers' => Supergood::Utils.safe_parse_json(request[:headers]),
          'method' => request[:method],
          'url' => request[:url],
          'path' => request[:path],
          'search' => request[:search] || '',
          'body' => Supergood::Utils.safe_parse_json(request[:body]),
          'requestedAt' => requested_at
        }
        @request_cache[request_id] = {
          'request' => request_payload
        }
      rescue => e
        log.error({ 'request' => request }, e, ERRORS[:CACHING_REQUEST])
      end
    end

    def cache_response(request_id, requested_at, response)
      if !@config[:remote_config]
        return
      end

      begin
        responded_at = Time.now
        duration = (responded_at - requested_at) * 1000
        request_payload = @request_cache[request_id]
        response_payload = {
          'headers' => Supergood::Utils.safe_parse_json(response[:headers]),
          'status' => response[:status],
          'statusText' => response[:statusText],
          'body' => Supergood::Utils.safe_parse_json(response[:body]),
          'respondedAt' => responded_at,
          'duration' => duration.round
        }
        @response_cache[request_id] = request_payload.merge({ 'response' => response_payload })
        @request_cache.delete(request_id)
      rescue => e
        log.error(
          { request: request_payload, response: response_payload },
          e, ERRORS[:CACHING_RESPONSE]
        )
      end
    end

    def ignored?(domain)
      base_domain = Supergood::Utils.get_host_without_www(@base_url)
      if domain == base_domain
        return true
      elsif @allowed_domains.any?
        @allowed_domains.all? do |allowed_domain|
          !domain.include? allowed_domain
        end
      else
        @ignored_domains.any? do |ignored_domain|
          domain.include? ignored_domain
        end
      end
    end
  end
end
