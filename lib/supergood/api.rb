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
      uri = URI(@base_url + @event_sink_endpoint)
      response = Net::HTTP.post(uri, payload.to_json, @header_options)
      if response.code == '200'
        return JSON.parse(response.body, symbolize_names: true)
      elsif response.code == '401'
        raise SupergoodException.new ERRORS[:UNAUTHORIZED]
      elsif response.code != '200' && response.code != '201'
        raise SupergoodException.new ERRORS[:POSTING_EVENTS]
      end
    end

    def post_errors(payload)
      uri = URI(@base_url + @error_sink_endpoint)
      response = Net::HTTP.post(uri, payload.to_json, @header_options)
      if response.code == '200'
        return JSON.parse(response.body, symbolize_names: true)
      else
        @log.warn(ERRORS[:POSTING_ERRORS])
      end
    end

    def fetch_config
      uri = URI(@base_url + '/api/config')
      request = Net::HTTP::Get.new(uri)
      response = Net::HTTP.start(uri.hostname, uri.port) do |http|
        request['Content-Type'] = 'application/json'
        request['Authorization'] = @header_options['Authorization']
        http.request(request)
      end
      if response.code == '200'
        return JSON.parse(response.body, symbolize_names: true)
      elsif response.code == '401'
        raise SupergoodException.new ERRORS[:UNAUTHORIZED]
      elsif response.code != '200' && response.code != '201'
        raise SupergoodException.new ERRORS[:FETCHING_CONFIG]
      end
    end
  end
end
