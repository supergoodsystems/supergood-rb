
require 'net/http'
require 'uri'

module Supergood
  module Vendor
    module NetHTTP
      block = lambda do |x|
        alias original_request_method request
        def request(original_request_payload, body = nil, &block)
          http = self;
          url = Supergood::Utils.request_url(http, original_request_payload)
          uri = URI.parse(url)
          request = {
            headers: Supergood::Utils.get_header(original_request_payload),
            method: original_request_payload.method,
            body: original_request_payload.body,
            url: url,
            path: original_request_payload.path,
            search: uri.query,
            domain: uri.host,
          }
          Supergood.intercept(request) do
            original_response = original_request_method(original_request_payload, body, &block)
            {
              headers: Supergood::Utils.get_header(original_response),
              status: original_response.code,
              statusText: original_response.message,
              body: original_response.body,
              original_response: original_response
            }
          end
        end
      end

      if defined?(Net::HTTP)
        Net::HTTP.class_eval(&block)
      end

      if defined?(::WebMock)
        WebMock::HttpLibAdapters::NetHttpAdapter.instance_variable_get("@webMockNetHTTP").class_eval(&block)
      end
    end
  end
end

