require 'rudash'
require 'digest'

module Supergood
  module Utils
    def self.hash_value(input)
      hash = Digest::SHA1.new
      if input == nil
        return ''
      elsif input.class == Array
        return [Base64.strict_encode64(hash.update(input.to_json).to_s)]
      elsif input.class == Hash
        return {'hashed': Base64.strict_encode64(hash.update(input.to_json).to_s)}
      elsif input.class == String
        return Base64.strict_encode64(hash.update(input).to_s)
      end
    end

    # Hash values from specified keys, or hash if the bodies exceed a byte limit
    def self.hash_values_from_keys(obj, keys_to_hash, byte_limit=DEFAULT_SUPERGOOD_BYTE_LIMIT)
      _obj = obj

      if !keys_to_hash.include?('response.body')
        payload = R_.get(_obj, 'response.body')
        payload_size = payload.to_s.length()
        if(payload_size >= byte_limit)
          R_.set(_obj, 'response.body', Supergood::Utils.hash_value(payload))
        end
      end

      if !keys_to_hash.include?('request.body')
        payload = R_.get(_obj, 'request.body')
        payload_size = payload.to_s.length()
        if(payload_size >= byte_limit)
          R_.set(_obj, 'request.body', Supergood::Utils.hash_value(payload))
        end
      end

      keys_to_hash.each { |key|
        value = R_.get(_obj, key)
        if !!value
          R_.set(_obj, key, Supergood::Utils.hash_value(value))
        end
      }

      return _obj
    end

    def self.safe_parse_json(input)
      if !input || input == ''
        return ''
      end

      begin
        return JSON.parse(input)
      rescue => e
        input
      end
    end
    def self.get_header(request_or_response)
      header = {}
      request_or_response.each_header do |k,v|
        header[k] = v
      end
      header
    end

    def self.request_url(http, request)
      URI::DEFAULT_PARSER.unescape("http#{"s" if http.use_ssl?}://#{http.address}:#{http.port}#{request.path}")
    end
  end
end
