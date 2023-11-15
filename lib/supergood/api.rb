require 'dotenv'

Dotenv.load

module Supergood
  class Api
    def initialize(client_id, client_secret, base_url)
      @base_url = base_url
      @header_options = {
        'Content-Type' => 'application/json',
        'Authorization' => 'Basic ' + Base64.encode64(client_id + ':' + client_secret).gsub(/\n/, ''),
        'supergood-api' => 'supergood-rb',
        'supergood-api-version' => VERSION
      }
      @local_only = client_id == LOCAL_CLIENT_ID && client_secret == LOCAL_CLIENT_SECRET
    end

    def header_options
      @header_options
    end

    def log
      @log
    end

    def set_logger(logger)
      @log = logger
    end

    def post_events(payload)
      if @local_only
        @log.debug(payload)
      else
        uri = URI(@base_url + '/events')
        response = Net::HTTP.post(uri, payload.to_json, @header_options)
        if response.code == '200'
          return JSON.parse(response.body, symbolize_names: true)
        elsif response.code == '401'
          raise SupergoodException.new ERRORS[:UNAUTHORIZED]
        elsif response.code != '200' && response.code != '201'
          raise SupergoodException.new ERRORS[:POSTING_EVENTS]
        end
      end
    end

    def post_errors(payload)
      if @local_only
        @log.debug(payload)
      else
        uri = URI(@base_url + '/errors')
        response = Net::HTTP.post(uri, payload.to_json, @header_options)
        if response.code == '200'
          return JSON.parse(response.body, symbolize_names: true)
        else
          @log.warn(ERRORS[:POSTING_ERRORS])
        end
      end
    end
  end
end
