require_relative '../utils/benchmark_logger'
require_relative '../clients/mock_api_client'

class VirtualThreadImplementation
  def initialize(logger: BenchmarkLogger.logger)
    @logger = logger
    setup_executor
    setup_clients
  end

  def process_feed_units(units)
    start_time = Time.now

    begin
      futures = units.map { |unit| submit_unit_processing(unit) }
      results = futures.map { |f| f.get(5, java.util.concurrent.TimeUnit::SECONDS) }
      log_performance_metrics(start_time, units.size)
      results
    rescue => e
      @logger.error("Error processing feed units: #{e.message}")
      []
    end
  end

  def shutdown
    @executor&.shutdown
  end

  private

  def setup_executor
    require 'java'
    java_import 'java.util.concurrent.Executors'
    java_import 'java.util.concurrent.CompletableFuture'
    java_import 'java.util.concurrent.TimeUnit'

    # Use the virtual thread executor introduced in Java 19+
    @executor = Executors.newVirtualThreadPerTaskExecutor
  rescue => e
    @logger.error("Failed to create executor: #{e.message}")
    setup_fallback_executor
  end

  def setup_fallback_executor
    thread_count = java.lang.Runtime.getRuntime.availableProcessors * 2
    @executor = java.util.concurrent.Executors.newFixedThreadPool(thread_count)
  end

  def setup_clients
    @naver_client = MockApiClient.new('Naver', latency: 0.1, error_rate: 0.01)
    @ads_client = MockApiClient.new('Ads', latency: 0.15, error_rate: 0.01)
  end

  def submit_unit_processing(unit)
    CompletableFuture.supplyAsync(
      proc { process_single_unit(unit) },
      @executor
    )
  end

  def process_single_unit(unit)
    naver_future = CompletableFuture.supplyAsync(
      proc { fetch_naver_data(unit) },
      @executor
    )

    ads_future = CompletableFuture.supplyAsync(
      proc { fetch_ads_data(unit) },
      @executor
    )

    begin
      results = {
        naver: naver_future.get(2, TimeUnit::SECONDS),
        ads: ads_future.get(2, TimeUnit::SECONDS)
      }
      merge_results(results)
    rescue java.util.concurrent.TimeoutException => e
      handle_timeout_error(unit, e)
    rescue => e
      handle_processing_error(unit, e)
    end
  end

  def fetch_naver_data(unit)
    start_time = Time.now
    result = @naver_client.fetch_data
    log_api_metrics('naver', start_time)
    result
  rescue => e
    log_api_error('naver', e)
    raise
  end

  def fetch_ads_data(unit)
    start_time = Time.now
    result = @ads_client.fetch_data
    log_api_metrics('ads', start_time)
    result
  rescue => e
    log_api_error('ads', e)
    raise
  end

  def merge_results(results)
    {
      naver_data: results[:naver],
      ads_data: results[:ads],
      processed_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
    }
  end

  def handle_timeout_error(unit, error)
    @logger.error({
      event: 'timeout_error',
      unit_id: unit[:id],
      error: error.message
    }.to_json)

    {
      error: 'Processing timeout',
      unit_id: unit[:id]
    }
  end

  def handle_processing_error(unit, error)
    @logger.error({
      event: 'processing_error',
      unit_id: unit[:id],
      error: error.message
    }.to_json)

    {
      error: 'Processing failed',
      unit_id: unit[:id]
    }
  end

  def log_api_metrics(api_name, start_time)
    duration = Time.now - start_time
    @logger.debug({
      event: 'api_call',
      api: api_name,
      duration_ms: (duration * 1000).round(2)
    }.to_json)
  end

  def log_api_error(api_name, error)
    @logger.error({
      event: 'api_error',
      api: api_name,
      error: error.message
    }.to_json)
  end

  def log_performance_metrics(start_time, unit_count)
    duration = Time.now - start_time
    @logger.info({
      event: 'performance_metrics',
      total_units: unit_count,
      total_duration_ms: (duration * 1000).round(2),
      avg_duration_ms: (duration * 1000 / unit_count).round(2)
    }.to_json)
  end
end
