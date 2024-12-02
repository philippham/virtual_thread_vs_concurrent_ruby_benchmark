require 'json'
require 'benchmark'
require 'concurrent-ruby'
require 'securerandom'
require_relative '../lib/implementations/virtual_thread_implementation'
require_relative '../lib/implementations/concurrent_ruby_implementation'
require_relative '../lib/utils/time_formatter'
require_relative '../lib/utils/metrics_collector'

class LoadTest
  class << self
    LOAD_PROFILES = {
      light: { users: 10, duration: 30, ramp_up: 5 },
      medium: { users: 50, duration: 60, ramp_up: 10 },
      heavy: { users: 100, duration: 120, ramp_up: 20 }
    }

    def run
      setup
      LOAD_PROFILES.each do |profile_name, profile|
        run_profile(profile_name, profile)
      end
      print_final_results
    ensure
      cleanup
    end

    private

    def setup
      @results = {}
      @metrics = MetricsCollector.instance
      @metrics.reset_metrics
      print_configuration
    end

    def print_configuration
      puts "\nLoad Test Configuration:"
      puts "- JRuby version: #{JRUBY_VERSION}"
      puts "- Java version: #{java.lang.System.getProperty('java.version')}"
      puts "- Available processors: #{available_processors}"
      puts "- Max memory: #{max_memory_mb}MB"
      puts "\nLoad Profiles:"
      LOAD_PROFILES.each do |name, profile|
        puts "  #{name}:"
        puts "    - Concurrent users: #{profile[:users]}"
        puts "    - Duration: #{profile[:duration]}s"
        puts "    - Ramp-up time: #{profile[:ramp_up]}s"
      end
      puts
    end

    def run_profile(profile_name, profile)
      puts "\nRunning #{profile_name} load profile..."
      
      implementations.each do |impl|
        name = impl.class.name
        puts "\nTesting #{name}..."
        results = run_implementation(impl, profile)
        @results[profile_name] ||= {}
        @results[profile_name][name] = results
        print_profile_results(profile_name, name, results)
      end
    end

    def run_implementation(implementation, profile)
      users = create_users(profile[:users])
      results = Concurrent::Hash.new
      stop_flag = Concurrent::AtomicBoolean.new(false)
      error_count = Concurrent::AtomicFixnum.new(0)
      request_count = Concurrent::AtomicFixnum.new(0)

      start_time = Time.now
      user_threads = start_users(users, implementation, results, stop_flag, error_count, request_count, profile)
      
      # Monitor progress
      monitor_execution(start_time, profile[:duration], request_count, error_count)
      
      # Signal stop and wait for completion
      stop_flag.make_true
      user_threads.each(&:join)
      
      analyze_results(results, error_count.value, request_count.value, profile)
    end

    def create_users(count)
      count.times.map do |i|
        {
          id: "user_#{i}",
          feed_units: generate_feed_units(10) # 10 units per user
        }
      end
    end

    def generate_feed_units(count)
      count.times.map do |i|
        {
          id: SecureRandom.uuid,
          type: 'test_unit',
          timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'),
          metadata: { sequence: i }
        }
      end
    end

    def start_users(users, implementation, results, stop_flag, error_count, request_count, profile)
      users.map.with_index do |user, index|
        Thread.new do
          # Ramp up delay
          sleep(profile[:ramp_up] * (index.to_f / users.size))
          
          while !stop_flag.true?
            process_user_request(user, implementation, results, error_count, request_count)
            sleep(rand * 0.5) # Random think time between requests
          end
        end
      end
    end

    def process_user_request(user, implementation, results, error_count, request_count)
      start_time = Time.now
      
      begin
        implementation.process_feed_units(user[:feed_units])
        duration = Time.now - start_time
        record_success(results, duration)
      rescue => e
        error_count.increment
        record_error(results, e)
      ensure
        request_count.increment
      end
    end

    def record_success(results, duration)
      results[:durations] ||= Concurrent::Array.new
      results[:durations] << duration
    end

    def record_error(results, error)
      results[:errors] ||= Concurrent::Array.new
      results[:errors] << {
        message: error.message,
        time: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
      }
    end

    def monitor_execution(start_time, duration, request_count, error_count)
      while Time.now - start_time < duration
        throughput = request_count.value / (Time.now - start_time)
        error_rate = error_count.value.to_f / request_count.value * 100 rescue 0
        
        print "\rRequests: #{request_count.value} | " \
              "Throughput: #{throughput.round(2)} req/s | " \
              "Errors: #{error_rate.round(2)}% | " \
              "Time remaining: #{(duration - (Time.now - start_time)).round}s"
        
        sleep 1
      end
      puts
    end

    def analyze_results(results, total_errors, total_requests, profile)
      durations = results[:durations] || []
      return {} if durations.empty?

      durations_ms = durations.map { |d| d * 1000 }
      sorted_durations = durations_ms.sort
      
      {
        throughput: total_requests.to_f / profile[:duration],
        error_rate: (total_errors.to_f / total_requests * 100),
        latency: {
          min: durations_ms.min.round(2),
          max: durations_ms.max.round(2),
          avg: (durations_ms.sum / durations_ms.size).round(2),
          p50: percentile(sorted_durations, 50).round(2),
          p90: percentile(sorted_durations, 90).round(2),
          p95: percentile(sorted_durations, 95).round(2),
          p99: percentile(sorted_durations, 99).round(2)
        },
        total_requests: total_requests,
        total_errors: total_errors,
        duration: profile[:duration]
      }
    end

    def percentile(sorted_values, p)
      return 0 if sorted_values.empty?
      k = (sorted_values.length - 1) * p / 100.0
      f = k.floor
      c = k.ceil
      if f == c
        sorted_values[f]
      else
        sorted_values[f] * (c - k) + sorted_values[c] * (k - f)
      end
    end

    def print_profile_results(profile_name, implementation_name, results)
      return if results.empty?
      
      puts "\n#{implementation_name} results for #{profile_name} profile:"
      puts "  Throughput: #{results[:throughput].round(2)} req/s"
      puts "  Error rate: #{results[:error_rate].round(2)}%"
      puts "  Latency (ms):"
      puts "    Min: #{results[:latency][:min]}"
      puts "    Avg: #{results[:latency][:avg]}"
      puts "    Max: #{results[:latency][:max]}"
      puts "    P90: #{results[:latency][:p90]}"
      puts "    P95: #{results[:latency][:p95]}"
      puts "    P99: #{results[:latency][:p99]}"
      puts "  Total requests: #{results[:total_requests]}"
      puts "  Total errors: #{results[:total_errors]}"
    end

    def print_final_results
      puts "\nFinal Comparison:"
      puts "================="
      
      LOAD_PROFILES.each do |profile_name, _|
        puts "\n#{profile_name} profile:"
        vt_results = @results[profile_name]['VirtualThreadImplementation']
        cr_results = @results[profile_name]['ConcurrentRubyImplementation']
        
        if vt_results && cr_results
          throughput_improvement = ((vt_results[:throughput] - cr_results[:throughput]) / 
                                  cr_results[:throughput] * 100).round(2)
          
          latency_improvement = ((cr_results[:latency][:avg] - vt_results[:latency][:avg]) /
                                cr_results[:latency][:avg] * 100).round(2)
          
          puts "  Throughput improvement: #{throughput_improvement}%"
          puts "  Average latency improvement: #{latency_improvement}%"
          puts "  Error rate difference: #{(vt_results[:error_rate] - cr_results[:error_rate]).round(2)}%"
        end
      end
    end

    def save_results
      FileUtils.mkdir_p('results')
      file_path = File.join('results', "load_test_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
      
      File.write(file_path, JSON.pretty_generate({
        configuration: test_configuration,
        results: @results,
        timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
      }))
      
      puts "\nDetailed results saved to: #{file_path}"
    end

    def test_configuration
      {
        ruby_engine: RUBY_ENGINE,
        ruby_version: RUBY_VERSION,
        java_version: java.lang.System.getProperty('java.version'),
        processors: available_processors,
        max_memory: max_memory_mb,
        profiles: LOAD_PROFILES
      }
    end

    def implementations
      @implementations ||= [
        VirtualThreadImplementation.new,
        ConcurrentRubyImplementation.new
      ]
    end

    def cleanup
      implementations.each do |impl|
        impl.shutdown if impl.respond_to?(:shutdown)
      end
    end

    def available_processors
      java.lang.Runtime.getRuntime.availableProcessors
    end

    def max_memory_mb
      java.lang.Runtime.getRuntime.maxMemory / 1024 / 1024
    end
  end
end

if __FILE__ == $0
  LoadTest.run
end