require 'faraday'

module Supergood
  class Api
    DEFAULT_SUPERGOOD_BASE_URL = 'https://staging.dashboard.supergood.ai'
    DEFAULT_SUPERGOOD_CONFIG = {
      flush_interval: 1,
      event_sink_endpoint: DEFAULT_SUPERGOOD_BASE_URL + '/api/events',
      error_sink_endpoint: DEFAULT_SUPERGOOD_BASE_URL + '/api/errors',
      keys_to_hash: ['request.body', 'response.body'],
      ignored_domains: []
    }

    def initialize(header_options, base_url)
      @header_options = header_options
      @config_fetch_url = base_url + '/api/config'
    end

    def log
      @log
    end

    def set_logger(logger)
      @log = logger
    end

    def set_event_sink_url(url)
      @event_sink_url = url
    end

    def set_error_sink_url(url)
      @error_sink_url = url
    end

    def post_events(payload)
      Faraday.post(@event_sink_url, payload, @header_options)
    end

    def post_errors(payload)
      Faraday.post(@event_sink_url, payload, @header_options)
    end

    def fetch_config
      # Faraday.get(config_fetch_url, @header_options)
      DEFAULT_SUPERGOOD_CONFIG
    end
  end
end
