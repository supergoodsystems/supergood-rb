module Supergood
  module Vendor
    module HTTPrb
      if defined?(::HTTP)
        HTTP::Client.class_eval {
          alias original_perform perform
          def perform(original_request_payload, original_options)
            request = {
              headers: original_request_payload.headers.to_hash,
              method: original_request_payload.verb.upcase.to_s,
              body: Supergood::Utils.safe_parse_json(original_request_payload.body.source),
              url: original_request_payload.uri.to_s,
              path: original_request_payload.uri.path,
              search: original_request_payload.uri.query,
              domain: original_request_payload.uri.host
            }
            Supergood.intercept(request) do
              original_response = original_perform(original_request_payload, original_options)
              status, statusText = original_response.status.to_s.split(' ')
              {
                headers: original_response.headers.to_hash,
                status: status,
                statusText: statusText,
                body: Supergood::Utils.safe_parse_json(original_response),
                original_response: original_response
              }
            end
          end
        }
      end
    end
  end
end

