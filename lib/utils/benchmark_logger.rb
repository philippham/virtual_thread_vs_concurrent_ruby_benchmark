require 'logger'
require 'json'
require 'fileutils'

class BenchmarkLogger
  class << self
    def logger
      @logger ||= create_logger
    end

    private

    def create_logger
      ensure_log_directory
      logger = Logger.new(STDOUT)
      logger.level = Logger::INFO
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{severity}: #{msg}\n"
      end
      logger
    end

    def ensure_log_directory
      FileUtils.mkdir_p('log')
    end
  end
end