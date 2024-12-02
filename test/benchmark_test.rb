require 'json'
require 'benchmark'
require_relative '../lib/implementations/virtual_thread_implementation'
require_relative '../lib/implementations/concurrent_ruby_implementation'

class BenchmarkTest
  class << self
    def run
      setup
      warm_up
      run_comparative_benchmarks
      print_results
    ensure
      cleanup
    end

    private

    def setup
      @test_data = generate_test_data
      print_configuration
    end

    def generate_test_data
      puts "Generating test data..."
      1000.times.map do |i|
        {
          id: i.to_s,
          type: 'test_unit',
          timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'),
          metadata: {
            sequence: i,
            batch: "test_#{i / 100}"
          }
        }
      end
    end

    def print_configuration
      puts "\nBenchmark Configuration:"
      puts "- Test data size: #{@test_data.size} units"
      puts "- Iterations: 3"
      puts "- JRuby version: #{JRUBY_VERSION}"
      puts "- Java version: #{java.lang.System.getProperty('java.version')}"
      puts "- Available processors: #{java.lang.Runtime.getRuntime.availableProcessors}"
      puts "- Max memory: #{java.lang.Runtime.getRuntime.maxMemory / 1024 / 1024}MB"
      puts
    end

    def warm_up
      puts "Warming up implementations..."
      sample_data = @test_data.first(10)
      
      implementations.each do |impl|
        print "- Warming up #{impl.class.name}..."
        begin
          Timeout.timeout(5) do
            impl.process_feed_units(sample_data)
          end
          puts " done"
        rescue => e
          puts " failed (#{e.message})"
        end
      end
      puts
    end

    def run_comparative_benchmarks
      @results = {}
      
      implementations.each do |impl|
        name = impl.class.name
        puts "Running benchmark for #{name}..."
        
        stats = benchmark_implementation(impl)
        @results[name] = stats
      end
    end

    def benchmark_implementation(implementation)
      memory_stats = []
      durations = []
      gc_counts = []
      
      3.times do |i|
        print "  Run #{i + 1}/3: "
        stats = run_single_benchmark(implementation)
        
        durations << stats[:duration]
        memory_stats << stats[:memory]
        gc_counts << stats[:gc_count]
        
        puts "#{stats[:duration].round(2)}ms (Memory: #{(stats[:memory] / 1024.0 / 1024.0).round(2)}MB, GC: #{stats[:gc_count]})"
      end
      
      {
        durations: durations,
        memory: memory_stats,
        gc_counts: gc_counts
      }
    end

    def run_single_benchmark(implementation)
      gc_count_before = GC.count
      memory_before = current_memory
      
      start_time = Time.now
      implementation.process_feed_units(@test_data)
      duration = (Time.now - start_time) * 1000
      
      memory_after = current_memory
      gc_count_after = GC.count
      
      {
        duration: duration,
        memory: memory_after - memory_before,
        gc_count: gc_count_after - gc_count_before
      }
    rescue => e
      puts "Error: #{e.message}"
      {
        duration: -1,
        memory: 0,
        gc_count: 0
      }
    end

    def current_memory
      java.lang.Runtime.getRuntime.totalMemory - java.lang.Runtime.getRuntime.freeMemory
    rescue
      0
    end

    def print_results
      puts "\nBenchmark Results:"
      puts "=================="
      
      @results.each do |name, stats|
        puts "\n#{name}:"
        print_implementation_stats(stats)
      end
      
      print_comparison
      save_results
    end

    def print_implementation_stats(stats)
      durations = stats[:durations].reject { |d| d < 0 }
      return puts "  All runs failed" if durations.empty?
      
      puts "  Duration:"
      puts "    Average: #{(durations.sum / durations.size).round(2)}ms"
      puts "    Min: #{durations.min.round(2)}ms"
      puts "    Max: #{durations.max.round(2)}ms"
      puts "  Memory:"
      puts "    Average: #{(stats[:memory].sum / stats[:memory].size / 1024.0 / 1024.0).round(2)}MB"
      puts "  GC runs: #{stats[:gc_counts].sum}"
    end

    def print_comparison
      return unless @results.size == 2
      
      vt_stats = @results['VirtualThreadImplementation']
      cr_stats = @results['ConcurrentRubyImplementation']
      
      return unless vt_stats && cr_stats
      
      vt_avg = average_duration(vt_stats[:durations])
      cr_avg = average_duration(cr_stats[:durations])
      
      return if vt_avg == 0 || cr_avg == 0
      
      improvement = ((cr_avg - vt_avg) / cr_avg * 100)
      
      puts "\nPerformance Comparison:"
      puts "======================"
      puts "Virtual Threads vs Concurrent Ruby:"
      puts "  Speed improvement: #{improvement.round(2)}%"
      puts "  Memory difference: #{((average_memory(cr_stats[:memory]) - average_memory(vt_stats[:memory])) / 1024.0 / 1024.0).round(2)}MB"
      puts "  GC runs difference: #{cr_stats[:gc_counts].sum - vt_stats[:gc_counts].sum}"
    end

    def average_duration(durations)
      valid_durations = durations.reject { |d| d < 0 }
      valid_durations.empty? ? 0 : valid_durations.sum / valid_durations.size
    end

    def average_memory(memory_stats)
      memory_stats.sum / memory_stats.size
    end

    def save_results
      FileUtils.mkdir_p('results')
      filename = "benchmark_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      
      File.write(
        File.join('results', filename),
        JSON.pretty_generate({
          configuration: {
            timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'),
            jruby_version: JRUBY_VERSION,
            java_version: java.lang.System.getProperty('java.version'),
            processors: java.lang.Runtime.getRuntime.availableProcessors,
            max_memory: java.lang.Runtime.getRuntime.maxMemory / 1024 / 1024
          },
          results: @results
        })
      )
      
      puts "\nDetailed results saved to: results/#{filename}"
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
  end
end

if __FILE__ == $0
  BenchmarkTest.run
end