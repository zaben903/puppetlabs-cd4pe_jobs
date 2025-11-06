# frozen_string_literal: true

require 'time'
require 'json'
require 'net/http'

# Class to track logs and timestamps. To be returned as part of the Bolt log output
#
# @attr_reader logs [Array<Hash<Symbol => String>>] logs that haven't been flushed yet
# @attr_writer cd4pe_client [CD4PEClient] client to send logs to CD4PE
class Logger
  attr_reader :logs
  attr_writer :cd4pe_client

  def initialize
    @logs = []
  end

  # Log a new message
  #
  # @param log [String] log message
  def log(log)
    @logs.push({ timestamp: Time.now.getutc, message: log })
  end

  # Attempt to flush logs to CD4PE
  def flush!
    return if @logs.empty?
    if @cd4pe_client.nil?
      puts @logs.to_json
      @logs = []
      return
    end

    begin
      logs_to_send = @logs.dup
      response = @cd4pe_client.send_logs(logs_to_send)
      unless response.is_a?(Net::HTTPSuccess)
        log "Unable to send logs directly to CD4PE. Printing logs to std out. #{response.code} #{response.body}"
        puts @logs.to_json
      end

      @logs = []
    rescue StandardError => e
      log "Problem sending logs to CD4PE. Printing logs to std out. Error message: #{e.message} Backtrace: #{e.backtrace}"
      puts @logs.to_json
    end
  end
end
