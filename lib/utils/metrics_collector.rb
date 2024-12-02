require 'singleton'
require 'json'

class MetricsCollector
  include Singleton

  def initialize
    reset_metrics
  end

  def record_timing(operation, duration)
    @metrics[:timings][operation] ||= []
    @metrics[:timings][operation] << duration
  end

  def record_memory_usage(implementation)
    memory_usage = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
    @metrics[:memory_usage][implementation] << memory_usage
  end

  def record_error(implementation, error)
    @metrics[:errors][implementation] << {
      time: Time.now.iso8601,
      message: error.message,
      backtrace: error.backtrace&.first(5)
    }
  end

  def calculate_statistics
    {
      timings: calculate_timing_stats,
      memory_usage: calculate_memory_stats,
      error_rates: calculate_error_rates,
      summary: generate_summary
    }
  end

  def reset_metrics
    @metrics = {
      timings: {},
      memory_usage: Hash.new { |h, k| h[k] = [] },
      errors: Hash.new { |h, k| h[k] = [] }
    }
  end

  private

  def calculate_timing_stats
    @metrics[:timings].transform_values do |durations|
      {
        min: durations.min,
        max: durations.max,
        avg: durations.sum / durations.size,
        p95: percentile(durations, 95),
        p99: percentile(durations, 99)
      }
    end
  end

  def calculate_memory_stats
    @metrics[:memory_usage].transform_values do |usages|
      {
        min: usages.min,
        max: usages.max,
        avg: usages.sum / usages.size
      }
    end
  end

  def calculate_error_rates
    @metrics[:errors].transform_values do |errors|
      {
        count: errors.size,
        rate: errors.size.to_f / (@metrics[:timings].values.first&.size || 1)
      }
    end
  end

  def percentile(array, percentile)
    return 0 if array.empty?
    sorted = array.sort
    k = (percentile / 100.0) * (sorted.length - 1)
    f = k.floor
    c = k.ceil
    
    if f == c
      sorted[f]
    else
      (sorted[f] * (c - k) + sorted[c] * (k - f))
    end
  end

  def generate_summary
    {
      total_operations: @metrics[:timings].values.first&.size || 0,
      total_errors: @metrics[:errors].values.map(&:size).sum,
      total_duration: @metrics[:timings].values.first&.sum || 0
    }
  end
end