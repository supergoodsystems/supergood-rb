require 'logger'
require 'dotenv'

Dotenv.load

module Supergood
  class Logger < Logger
    def initialize(post_errors, config, header_options)
      super(STDOUT)
      @post_errors = post_errors
      @config = config
      @header_options = header_options
    end

    def post_errors
      @post_errors
    end

    def warn(payload, error, msg)
      super
      post_errors({ error: error, message: msg, payload: payload })
    end

    def debug(payload)
      if(ENV['SUPERGOOD_LOG_LEVEL'] == 'debug')
        super
      end
    end

  end
end
