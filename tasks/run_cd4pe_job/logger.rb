# frozen_string_literal: true

require 'time'
require 'json'
require 'net/http'

# Class to track logs and timestamps. To be returned as part of the Bolt log output
#
# @attr_reader logs [Array<Hash<Symbol => String>>] logs that haven't been flushed yet
class Logger
  attr_writer :cd4pe_client
  attr_reader :logs

  # @param cd4pe_client [CD4PEClient, nil] client to send logs to CD4PE
  def initialize(cd4pe_client: nil)
    @logs = []
    @mutex = Mutex.new
    self.cd4pe_client = cd4pe_client unless cd4pe_client.nil?
  end

  # @param cd4pe_client [CD4PEClient] client to send logs to CD4PE
  def cd4pe_client=(cd4pe_client)
    @cd4pe_client = cd4pe_client
    @flush_thread = Thread.new do
      loop do
        sleep 10
        flush!
      end
    end
  end

  # Log a new message
  #
  # @param log [String] log message
  def log(log)
    @mutex.synchronize do
      @logs.push({ timestamp: Time.now.getutc, message: log })
    end
  end

  # Attempt to flush logs to CD4PE
  def flush!
    return if @logs.empty?
    if @cd4pe_client.nil?
      puts @logs.to_json
      @logs = []
      return
    end

    @mutex.synchronize do
      response = @cd4pe_client.send_logs(@logs)
      if (!response.is_a?(Net::HTTPSuccess))
        @logs.push("Unable to send logs directly to CD4PE. Printing logs to std out. #{response.code} #{response.body}")
        puts @logs.to_json
      end
      @logs = []
    rescue => e
      @logs.push("Problem sending logs to CD4PE. Printing logs to std out. Error message: #{e.message}")
      puts @logs.to_json
    end
  end
end
