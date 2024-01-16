require 'logger'
require 'dotenv'

Dotenv.load

module Supergood
  class Logger < Logger
    def initialize(api, config, header_options)
      super(STDOUT)
      @api = api
      @config = config
      @header_options = header_options
    end

    def error(data, error, msg)
      if(ENV['SUPERGOOD_LOG_LEVEL'] == 'debug')
        super(error)
      end
      @api.post_errors(
        {
          error: error.backtrace.join('\n'),
          message: msg,
          payload: {
            config: @config,
            data: data,
            packageName: 'supergood-rb',
            packageVersion: Supergood::VERSION
          }
        }
      )
    end

    def debug(payload)
      if(ENV['SUPERGOOD_LOG_LEVEL'] == 'debug')
        super
      end
    end

  end
end
