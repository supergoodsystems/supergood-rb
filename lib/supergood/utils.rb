require 'rudash'
require 'digest'
require 'uri'
require 'json'

module Supergood
  module Utils

    def self.get_host_without_www(url)
      uri = URI.parse(url)
      uri = URI.parse("http://#{url}") if uri.scheme.nil?
      host = uri.host.downcase
      host.start_with?('www.') ? host[4..-1] : host
    end

    def self.safe_parse_json(input)
      return '' if !input || input == ''
      begin
        JSON.parse(input)
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
      URI::DEFAULT_PARSER.unescape("http#{"s" if http.use_ssl?}://#{http.address}#{request.path}")
    end

    def self.make_config(config)
      DEFAULT_CONFIG.merge(config)
    end

    def self.process_remote_config(remote_config_payload)
      remote_config_payload ||= []
      remote_config_payload.reduce({}) do |remote_config, domain_config|
        domain = domain_config[:domain]
        endpoints = domain_config[:endpoints]
        endpoint_config = endpoints.reduce({}) do |config, endpoint|
          matching_regex = endpoint[:matchingRegex]
          regex = matching_regex[:regex]
          location = matching_regex[:location]

          endpoint_configuration = endpoint[:endpointConfiguration]
          action = endpoint_configuration[:action]
          sensitive_keys = endpoint_configuration[:sensitiveKeys] || []
          sensitive_keys = sensitive_keys.map { |key| key[:keyPath] }

          config[regex] = {
            location: location,
            regex: regex,
            ignored: action == 'Ignore',
            sensitive_keys: sensitive_keys
          }

          config
        end

        remote_config[domain] = endpoint_config
        remote_config
      end
    end

    def self.get_str_representation_from_path(request, location)
      url = URI(request[:url])

      case location
      when 'domain'
        get_host_without_www(url)
      when 'url'
        url.to_s
      when 'path'
        url.path
      when 'requestHeaders'
        request['headers'].to_s
      when 'requestBody'
        request['body'].to_s
      else
        request[location.to_sym].to_s if request.key?(location.to_sym)
      end
    end

    def self.get_endpoint_config(request, remote_config)
      domain = remote_config.keys.find { |d| get_host_without_www(request[:url]).include?(d) }
      return nil unless domain

      endpoint_configs = remote_config[domain]
      endpoint_configs.each_value do |endpoint_config|
        regex = endpoint_config[:regex]
        location = endpoint_config[:location]
        regex_obj = Regexp.new(regex)
        str_representation = get_str_representation_from_path(request, location)
        next unless str_representation
        return endpoint_config if regex_obj.match?(str_representation)
      end
      nil
    end

    def self.expand(parts, obj, key_path)
      path = key_path
      return [path] if parts.empty?

      part = parts.first
      is_property = !part.start_with?('[')
      separator = !path.empty? && is_property ? '.' : ''

      # Check for array notations
      if part.match?(/\[\*?\]/)
        return [] unless obj.is_a?(Array)

        # Expand for each element in the array
        obj.flat_map.with_index do |_, index|
          expand(parts[1..-1], obj[index], "#{path}#{separator}[#{index}]")
        end
      elsif part.start_with?('[') && part.end_with?(']')
        # Specific index in the array
        index = part[1...-1].to_i
        if index.is_a?(Numeric) && index < obj.length
          expand(parts[1..-1], obj[index], "#{path}#{separator}#{part}")
        else
          []
        end
      else
        if obj && obj.is_a?(Hash) && (obj.key?(part.to_sym) || obj.key?(part))
          expand(parts[1..-1], obj.fetch(part.to_sym, obj[part]), "#{path}#{separator}#{part}")
        else
          []
        end
      end
    end

    def self.expand_key(key, obj)
      parts = key.scan(/[^.\[\]]+|\[\d*\]|\[\*\]/) || []
      expand(parts, obj, '')
    end

    def self.expand_sensitive_key_set_for_arrays(obj, sensitive_keys)
      sensitive_keys.flat_map { |key| expand_key(key, obj) }
    end

    def self.marshal_key_path(keypath)
      keypath.gsub(/^requestHeaders/, 'request.headers')
             .gsub(/^requestBody/, 'request.body')
             .gsub(/^responseHeaders/, 'response.headers')
             .gsub(/^responseBody/, 'response.body')
    end

    def self.unmarshal_key_path(keypath)
      keypath.gsub(/^request\.headers/, 'requestHeaders')
             .gsub(/^request\.body/, 'requestBody')
             .gsub(/^response\.headers/, 'responseHeaders')
             .gsub(/^response\.body/, 'responseBody')
    end

    def self.set_value_to_nil(hash, key_path)
      keys = key_path.split('.')
      current_key = keys.first
      index = current_key.match(/\[(\d+)\]/)

      if index
        index = index[1].to_i
      end

      # Convert current_key to symbol if necessary
      if index
        current_key = current_key.gsub(/\[\d+\]/, '')
      elsif hash.keys.include?(current_key.to_sym)
        current_key = current_key.to_sym
      end

      return hash unless hash.keys.include?(current_key)

      if keys.length == 1
        index ? hash[current_key][index] = nil : hash[current_key] = nil
      elsif hash[current_key].is_a?(Hash)
        set_value_to_nil(hash[current_key], keys[1..].join('.'))
      elsif hash[current_key].is_a?(Array)
        set_value_to_nil(hash[current_key][index], keys[1..].join('.'))
      end

      hash
    end

    def self.find_leaf_key_paths(structure, current_path = [])
      key_paths = []

      if structure.is_a?(Hash)
        # Iterate through each key-value pair in the hash
        structure.each do |key, value|
          # Recursively find key paths in the value
          key_paths += find_leaf_key_paths(value, current_path + [key.to_s])
        end
      elsif structure.is_a?(Array)
        # Iterate through each element in the array
        structure.each_with_index do |element, index|
          # Modify how indices are appended to the path
          # Check if the last element in the current_path is a hash key or an array index
          if current_path.last && current_path.last.include?('[')
            new_path = current_path[0...-1] + ["#{current_path.last}[#{index}]"]
          else
            new_path = current_path + ["[#{index}]"]
          end

          # Recursively find key paths in the element
          key_paths += find_leaf_key_paths(element, new_path)
        end
      else
        # Leaf node: construct the key path and add it to the list
        key_path = current_path.join('.').gsub('.[', '[')
        key_paths << key_path unless key_path.empty?
      end

      key_paths
    end

    def self.redact_values_from_keys(event, remote_config, force_redact_all)
      sensitive_key_metadata = []
      endpoint_config = get_endpoint_config(event[:request], remote_config)

      unless (endpoint_config && endpoint_config[:sensitive_keys].any?) || force_redact_all
        return { event: event, sensitive_key_metadata: sensitive_key_metadata }
      end

      if force_redact_all
        # Need response.body in path
        sensitive_keys = find_leaf_key_paths(event[:response][:body], ['response', 'body'])
        sensitive_keys += find_leaf_key_paths(event[:request][:body], ['request', 'body'])
        sensitive_keys += find_leaf_key_paths(event[:request][:headers], ['request', 'headers'])
        sensitive_keys += find_leaf_key_paths(event[:response][:headers], ['response', 'headers'])
      else
        sensitive_keys = endpoint_config[:sensitive_keys]
      end

      sensitive_keys = expand_sensitive_key_set_for_arrays(
        event, sensitive_keys.map { |key| marshal_key_path(key) }
      )

      sensitive_keys.each do |key_path|
        value = R_.get(event, key_path)
        event = set_value_to_nil(event, key_path)
        # Add sensitive key for array expansion
        sensitive_key_metadata << { keyPath: unmarshal_key_path(key_path) }.merge(redact_value(value))
      end

      { event: event, sensitive_key_metadata: sensitive_key_metadata }
    end

    def self.redact_value(input)
      data_length = 0
      data_type = 'null'
      case input
      when Array
        data_length = input.size
        data_type = 'array'
      when Hash
        data_length = input.to_json.bytesize
        data_type = 'object'
      when String
        data_length = input.size
        data_type = 'string'
      when Numeric
        data_length = input.to_s.size
        data_type = input.integer? ? 'integer' : 'float'
      when TrueClass, FalseClass # This is a better way to check for booleans
        data_length = 1
        data_type = 'boolean'
      end
      { length: data_length, type: data_type }
    end

    def self.prepare_data(events, remote_config, force_redact_all)
      events.map do |event|
        redacted_event_with_metadata = redact_values_from_keys(event, remote_config, force_redact_all)
        redacted_event_with_metadata[:event].merge(
          metadata: { sensitiveKeys: redacted_event_with_metadata[:sensitive_key_metadata] }
        )
      end
    end
  end
end
