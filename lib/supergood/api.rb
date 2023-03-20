require 'faraday'
require 'dotenv'

Dotenv.load

module Supergood
  class Api
    def initialize(header_options, base_url)
      @base_url = base_url
      @header_options = header_options
    end

    def log
      @log
    end

    def set_logger(logger)
      @log = logger
    end

    def set_event_sink_endpoint(endpoint)
      @event_sink_endpoint = endpoint
    end

    def set_error_sink_endpoint(endpoint)
      @error_sink_endpoint = endpoint
    end

    def post_events(payload)
      conn = Faraday.new(url: @base_url, headers: @header_options)
      response = conn.post(@event_sink_endpoint, body = payload.to_json, headers = @header_options)
      if response.status == 200
        return JSON.parse(response.body, symbolize_names: true)
      elsif response.status == 401
        raise SupergoodException.new ERRORS[:UNAUTHORIZED]
      elsif response.status != 200 && response.status != 201
        raise SupergoodException.new ERRORS[:POSTING_EVENTS]
      end
    end

    def post_errors(payload)
      conn = Faraday.new(url: @base_url, headers: @header_options)
      response = conn.post(@error_sink_endpoint, body = payload.to_json, headers = @header_options)
      if response.status == 200
        return JSON.parse(response.body, symbolize_names: true)
      else
        @log.warn(ERRORS[:POSTING_ERRORS])
      end
    end

    def fetch_config
      conn = Faraday.new(url: @base_url, headers: @header_options)
      response = conn.get('/api/config')
      if response.status == 200
        return JSON.parse(response.body, symbolize_names: true)
      elsif response.status == 401
        raise SupergoodException.new ERRORS[:UNAUTHORIZED]
      elsif response.status != 200 && response.status != 201
        raise SupergoodException.new ERRORS[:FETCHING_CONFIG]
      end
    end
  end
end
