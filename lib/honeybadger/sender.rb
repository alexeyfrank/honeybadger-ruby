module Honeybadger
  class Sender
    NOTICES_URI = '/v1/notices/'.freeze
    HTTP_ERRORS = [Timeout::Error,
                   Errno::EINVAL,
                   Errno::ECONNRESET,
                   EOFError,
                   Errno::ECONNREFUSED].freeze

    def initialize(options = {})
      [ :api_key,
        :proxy_host,
        :proxy_port,
        :proxy_user,
        :proxy_pass,
        :protocol,
        :host,
        :port,
        :secure,
        :use_system_ssl_cert_chain,
        :http_open_timeout,
        :http_read_timeout
      ].each do |option|
        instance_variable_set("@#{option}", options[option])
      end
    end

    # Public: Sends the notice data off to Honeybadger for processing.
    #
    # notice - The notice data to be sent (Hash or JSON string)
    #
    # Returns error id from successful response
    def send_to_honeybadger(notice)
      if !Honeybadger.configuration.features['notices']
        log(:error, "Can't send error report -- the gem has been deactivated by the remote service.  Try restarting your app or contacting support@honeybadger.io.")
        return nil
      end

      return nil unless api_key_ok?

      data = notice.is_a?(String) ? notice : notice.to_json

      response = begin
                   client.post do |p|
                     p.url NOTICES_URI
                     p.body = data
                   end
                 rescue *HTTP_ERRORS => e
                   log(:error, "Unable to contact the Honeybadger server. HTTP Error=#{e}")
                   nil
                 end

      if response.success?
        log(Honeybadger.configuration.debug ? :info : :debug, "Success: #{response.class}", response, data)
        JSON.parse(response.body).fetch('id')
      else
        log(:error, "Failure: #{response.class}", response, data)
      end

    rescue => e
      log(:error, "[Honeybadger::Sender#send_to_honeybadger] Error: #{e.class} - #{e.message}\nBacktrace:\n#{e.backtrace.join("\n\t")}")
      nil
    end

    def ping(data = {})
      return nil unless api_key_ok?

      response = client.post do |p|
        p.url "/v1/ping"
        p.body = data.to_json
      end

      if response.success?
        JSON.parse(response.body)
      else
        log(:error, "Ping Failure", response, data)
        nil
      end

    rescue => e
      log(:error, "[Honeybadger::Sender#ping] Error: #{e.class} - #{e.message}\nBacktrace:\n#{e.backtrace.join("\n\t")}")
      nil
    end

    attr_reader :api_key,
      :proxy_host,
      :proxy_port,
      :proxy_user,
      :proxy_pass,
      :protocol,
      :host,
      :port,
      :secure,
      :use_system_ssl_cert_chain,
      :http_open_timeout,
      :http_read_timeout

    alias_method :secure?, :secure
    alias_method :use_system_ssl_cert_chain?, :use_system_ssl_cert_chain

    private

    def api_key_ok?
      if api_key.nil? || api_key == ''
        log(:error, "API key not found.")
        return nil
      end
      true
    end

    def client
      request_options = { :timeout => http_read_timeout, :open_timeout => http_open_timeout }
      request_options.merge!({ :proxy => { :uri => "#{protocol}://#{proxy_host}:#{proxy_port || port}", :user => proxy_user, :password => proxy_pass } }) if proxy_host

      @client ||= Faraday.new(:request => request_options) do |conn|
        conn.adapter Faraday.default_adapter
        conn.url_prefix = "#{protocol}://#{host}:#{port}"
        conn.headers['User-agent'] = "HB-Ruby #{Honeybadger::VERSION}; #{RUBY_VERSION}; #{RUBY_PLATFORM}"
        conn.headers['X-API-Key'] = api_key.to_s
        conn.headers['Content-Type'] = 'application/json'
        conn.headers['Accept'] = 'text/json, application/json'

        if secure?
          conn.ssl[:verify_mode] = OpenSSL::SSL::VERIFY_PEER
          conn.ssl[:ca_file] = Honeybadger.configuration.ca_bundle_path
        end
      end
    rescue => e
      log(:error, "[Honeybadger::Sender#client] Failure initializing the HTTP connection.\nError: #{e.class} - #{e.message}\nBacktrace:\n#{e.backtrace.join("\n\t")}")
      raise e
    end

    def log(level, message, response = nil, data = nil)
      # Log result:
      Honeybadger.write_verbose_log(message, level)

      # Log debug information:
      Honeybadger.report_environment_info
      Honeybadger.report_response_body(response.body) if response && response.body =~ /\S/
      Honeybadger.write_verbose_log("Notice: #{data}", :debug) if data && Honeybadger.configuration.debug
    end
  end
end
