require 'connection_pool'
require_relative 'mock_api_client'

class ApiClientPool
  def initialize(name, size: 5, timeout: 5, latency: 0.1)
    @pool = ConnectionPool.new(size: size, timeout: timeout) do
      MockApiClient.new(name, latency: latency)
    end
  end

  def with_client
    @pool.with do |client|
      begin
        yield client
      rescue => e
        BenchmarkLogger.logger.error("Error in #{client.class}: #{e.message}")
        raise
      end
    end
  end

  def shutdown
    @pool.shutdown { |client| client.close if client.respond_to?(:close) }
  end

  def status
    {
      size: @pool.size,
      available: @pool.available,
      in_use: @pool.size - @pool.available
    }
  end
end