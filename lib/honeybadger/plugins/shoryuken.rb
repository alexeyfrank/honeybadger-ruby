require 'honeybadger/plugin'
require 'honeybadger'

module Honeybadger
  module Plugins
    module Shoryuken
      class Middleware
        def call(worker, queue, sqs_msg, body)
          begin
            body = JSON.parse(sqs_msg.body)
            params = body.merge(source: "shoryuken")

            Honeybadger.context.clear!
            Honeybadger::Trace.instrument("#{body['job_class']}#perform", params) do
              yield
            end
          rescue Exception => e
            Honeybadger.notify_or_ignore(e, parameters: params)
            raise e
          end
        end
      end

      Plugin.register do
        requirement { defined?(::Shoryuken) }

        execution do
          ::Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.add Middleware
            end
          end
        end
      end
    end
  end
end
