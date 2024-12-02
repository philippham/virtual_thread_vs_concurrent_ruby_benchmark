require 'concurrent-ruby'
require_relative '../utils/benchmark_logger'
require_relative '../clients/mock_api_client'

class ConcurrentRubyImplementation
  def initialize(logger: BenchmarkLogger.logger)
    @logger = logger
    setup_executor
    setup_clients
  end

  def process_feed_units(units)
    start_time = Time.now
    
    begin
      futures = units.map { |unit| submit_unit_processing(unit) }
      results = futures.map { |f| f.value!(2) } # 2 seconds timeout
      log_performance_metrics(start_time, units.size)
      results
    rescue => e
      @logger.error("Error processing feed units: #{e.message}")
      []
    end
  end

  def shutdown
    return unless @executor
    @executor.shutdown
    @executor.wait_for_termination(5)
  rescue => e
    @logger.error("Error during shutdown: #{e.message}")
  end

  private

  def setup_executor
    @executor = Concurrent::ThreadPoolExecutor.new(
      min_threads: 2,
      max_threads: processor_count * 2,
      max_queue: processor_count * 4,
      fallback_policy: :caller_runs,
      idletime: 60,
      auto_terminate: true,
      max_memory: max_memory
    )
  end

  def setup_clients
    @naver_client = MockApiClient.new('Naver', latency: 0.1, error_rate: 0.01)
    @ads_client = MockApiClient.new('Ads', latency: 0.15, error_rate: 0.01)
  end

  def processor_count
    if RUBY_PLATFORM == 'java'
      java.lang.Runtime.getRuntime.availableProcessors
    else
      4
    end
  end

  def max_memory
    if RUBY_PLATFORM == 'java'
      java.lang.Runtime.getRuntime.maxMemory
    else
      2_147_483_648 # 2GB default
    end
  end

  def submit_unit_processing(unit)
    Concurrent::Promise.new(executor: @executor) do
      process_single_unit(unit)
    end.execute
  end

  def process_single_unit(unit)
    naver_promise = Concurrent::Promise.new(executor: @executor) do 
      fetch_naver_data(unit)
    end.execute

    ads_promise = Concurrent::Promise.new(executor: @executor) do
      fetch_ads_data(unit)
    end.execute

    begin
      results = {
        naver: naver_promise.value!(1), # 1 second timeout
        ads: ads_promise.value!(1)      # 1 second timeout
      }
      merge_results(results)
    rescue Concurrent::TimeoutError => e
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
      avg_duration_ms: (duration * 1000 / unit_count).round(2),
      executor_stats: {
        completed_tasks: @executor.completed_task_count,
        queue_length: @executor.queue_length,
        pool_size: @executor.length,
        active_threads: @executor.active_count
      }
    }.to_json)
  end
end