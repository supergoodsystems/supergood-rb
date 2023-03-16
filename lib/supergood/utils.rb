require 'rudash'
require 'digest'

def hash_value(input)
  hash = Digest::SHA1.new
  if input == nil
    return ''
  elsif input.class == Array
    return [Base64.encode64(hash.update(input.to_json))]
  elsif input.class == Hash
    return {'hashed': Base64.encode64(hash.update(input.to_json))}
  elsif input.class == String
    return Base64.encode64(hash.update(input.to_json))
  end
end

# Hash values from specified keys, or hash if the bodies exceed a byte limit
def hash_values_from_keys(obj, keys_to_hash, byte_limit=DEFAULT_SUPERGOOD_BYTE_LIMIT)
  _obj = obj

  if !keys_to_hash.include?('response.body')
    payload = R_.get(_obj, 'response.body')
    payload_size = payload.to_s.length()
    if(payload_size >= byte_limit)
      R_.set(_obj, 'response.body', hash_value(payload))
    end
  end

  if !keys_to_hash.include?('request.body')
    payload = R_.get(_obj, 'request.body')
    payload_size = payload.to_s.length()
    if(payload_size >= byte_limit)
      R_.set(_obj, 'request.body', hash_value(payload))
    end
  end

  keys_to_hash.each { |key|
    value = R_.get(_object, key)
    if !!value
      R_.set(_object, key, hash_value(value))
    end
  }

  return _obj
end

def safe_parse_json(input)
  if !input || input == ''
    return ''
  end

  begin
    return input.to_json
  rescue => e
    input
  end
end
