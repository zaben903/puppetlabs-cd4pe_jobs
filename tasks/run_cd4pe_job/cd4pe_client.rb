# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

class CD4PEClient
  # @param base_uri [String] Base URI of the CD4PE server
  # @param job_token [String] Job token for authentication
  # @param job_instance_id [String] Job instance ID
  # @param logger [Logger] Logger instance for logging
  # @param ca_cert_file [String, nil] Path to CA certificate file for SSL verification
  def initialize(base_uri:, job_token:, job_instance_id:, logger:, ca_cert_file: nil)
    @base_uri = URI.parse(base_uri)
    @job_token = job_token
    @job_instance_id = job_instance_id
    @logger = logger
    @ca_cert_file = ca_cert_file
  end

  # Send log messages to CD4PE
  #
  # @param [Array<String>] messages
  #
  # @return [Net::HTTPResponse] HTTP response
  def send_logs(messages)
    payload = {
      op: 'SavePuppetAgentJobOutput',
      content: {
        jobInstanceId: @job_instance_id,
        output: messages,
      },
    }

    post('/ajax', payload)
  end

  # Get job script and control repository
  #
  # @param job_instance_id [String] Job instance ID
  #
  # @return [Net::HTTPResponse] HTTP response
  def get_job_script_and_control_repo
    parameters = {
      jobInstanceId: @job_instance_id,
    }

    get('/getJobScriptAndControlRepo', parameters)
  end

  private

  # Maximum number of attempts for retrying HTTP requests
  MAX_ATTEMPTS = 3

  # @param path [String] API path to post to
  # @param payload [Hash] JSON payload to send
  #
  # @return [Net::HTTPResponse] HTTP response
  def post(path, payload = {})
    request!(:post, path, payload)
  end

  # @param path [String] API path to get
  # @param parameters [Hash] Query parameters
  #
  # @return [Net::HTTPResponse] HTTP response
  def get(path, parameters = {})
    query_string = parameters.empty? ? '' : "?#{URI.encode_www_form(parameters)}"
    request!(:get, "#{path}#{query_string}")
  end

  # Net::HTTP connection
  #
  # @return [Net::HTTP] HTTP connection
  def http
    return @http if @http

    @http = Net::HTTP.new(@base_uri.host, @base_uri.port)
    if @base_uri.scheme == 'https'
      @http.use_ssl = true
      @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      if !@ca_cert_file.nil?
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        store.add_file(@ca_cert_file)
        @http.cert_store = store
      end
    end
    @http.read_timeout = get_timeout
    @http
  end

  # Make a HTTP request
  #
  # @param type [Symbol] HTTP method
  # @param path [String] API path to request
  # @param payload [Hash] JSON payload to send
  #
  # @return [Net::HTTPResponse] HTTP response
  def request!(type, path, payload = {})
    request_path = URI.parse("#{@base_uri.to_s.delete_suffix('/')}#{path}")
    attempts = 0
    while attempts < MAX_ATTEMPTS
      begin
        @logger.log("cd4pe_client: requesting #{type} #{request_path.path} with read timeout: #{http.read_timeout} seconds")
        attempts += 1
        request = case type
                  when :get
                    http.get(request_path.to_s, headers)
                  when :post
                    http.post(request_path.to_s, payload.to_json, headers)
                  else
                    raise "cd4pe_client#request! called with invalid request type #{type}"
                  end

        case request
        when Net::HTTPSuccess, Net::HTTPRedirection
          return request
        when Net::HTTPInternalServerError
          if attempts < MAX_ATTEMPTS
            sleep(3)
            next
          end

          raise request
        else
          error = "Request error: #{request.code} #{request.body}"
          @logger.log(error)
          raise error
        end
      rescue SocketError => e
        raise "Could not connect to the CD4PE service at #{@base_uri.host}: #{e.inspect}", e.backtrace
      rescue Net::ReadTimeout => e
        @logger.log("Timed out at #{request.read_timeout} seconds waiting for response.")
        raise e
      rescue StandardError => e
        @logger.log("Failed to #{type} #{request_path}. #{e.message}.")
        raise e
      end
    end
  end

  # @return [Integer] HTTP read timeout in seconds
  def get_timeout
    timeout = 600
    timeout_env_var = ENV['HTTP_READ_TIMEOUT_SECONDS']
    unless (timeout_env_var.nil?)
      timeout_override = timeout_env_var.to_i
      if (timeout_override != 0)
        timeout = timeout_override
      else
        @logger.log("Unable to use HTTP_READ_TIMEOUT_SECONDS override: #{timeout_env_var}. Must be integer and non-zero.")
      end
    end
    timeout
  end

  # @return [Hash] HTTP headers
  def headers
    @headers ||= {
      'Content-Type'  => 'application/json',
      'Authorization' => @job_token
    }
  end
end