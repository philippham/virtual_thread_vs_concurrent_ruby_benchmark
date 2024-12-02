Enhanced Concurrency Implementation Proposal

Server Engineer: Phi Pham (Philip)
Git repo: https://github.com/philippham/virtual_thread_vs_concurrent_ruby_benchmark
Concurrent Ruby Deep Dive
Architecture & Core Concepts
- Built on traditional thread pool model using OS-level threads
- Each thread consumes significant system resources (~2MB per thread)
- Uses a fixed thread pool to manage concurrent operations
- Implements producer-consumer pattern for task queuing

Advantages
1. Resource Predictability
   - Fixed thread pool size ensures consistent resource usage
   - Predictable memory footprint
   - Built-in backpressure mechanisms

2. Platform Independence
   - Works across all Ruby implementations
   - No JVM dependency
   - Consistent behavior across platforms

3. Rich Feature Set
  
 # Built-in concurrent primitives
   future = Concurrent::Future.execute { api_call() }
   promise = Concurrent::Promise.new { process_data() }

Limitations
1. Scalability Issues
   - OS thread limitations (typically few thousand threads max)
   - High memory overhead per thread
   - Performance degradation with many threads
   # Memory usage grows linearly with threads
   # 1000 threads ≈ 2GB memory
   # 10000 threads ≈ 20GB memory

2. Context Switching Overhead
   - Heavy context switches between OS threads
   - CPU overhead increases with thread count
   - Can lead to performance degradation

3. Queuing Delays

 # Tasks queue up when pool is saturated
   pool.post(task) # May block or reject if queue is full
 
  
Virtual Threads Deep Dive
Architecture & Core Concepts
- Lightweight threads managed by JVM
- Minimal memory overhead (~1KB per thread)
- Can create millions of virtual threads
- Automatically mounted/unmounted from carrier threads

# Virtual Thread Creation
executor = java.util.concurrent.Executors.new_virtual_thread_per_task_executor


Advantages
1. Scalability
   - Support for millions of concurrent operations
   - Minimal memory footprint
   - Efficient scheduling by JVM
   
# Can handle large number of concurrent operations
   10_000.times do
     executor.submit { process_task() }  # ≈ 10MB total memory
   end

2. Performance
   - Automatic yielding during blocking operations
   - Efficient thread scheduling
   - Reduced context switching overhead

3. Resource Utilization
   - Better CPU utilization
   - Automatic thread management
   - Efficient I/O operations

Limitations
1. JVM Dependency
   - Requires JRuby and Java 21+
   - Platform specific implementation
   
# Version check required
   if RUBY_PLATFORM == 'java' && java_version >= 21
     # Use Virtual Threads
   else
     # Fallback implementation
   end

2. Memory Management Complexity
   - More GC pressure due to thread creation
   - Needs careful batch processing
   - Memory usage can spike with many threads

3. Learning Curve
   - New programming model
   - Different debugging approaches
   - JVM-specific optimization required

Performance Comparison
Benchmark Configuration:
- Test data size: 1000 units
- Iterations: 3
- JRuby version: 9.4.3.0
- Java version: 21.0.5
- Available processors: 12
- Max memory: 2048MB

VirtualThreadImplementation:
  Duration:
    Average: 765.25ms
    Min: 191.04ms
    Max: 1365.63ms
  Memory:
    Average: 71.06MB
  GC runs: 13

ConcurrentRubyImplementation:
  Duration:
    Average: 44805.62ms
    Min: 43340.47ms
    Max: 45888.81ms
  Memory:
    Average: -15.58MB
  GC runs: 6

Performance Comparison:
======================
Virtual Threads vs Concurrent Ruby:
  Speed improvement: 98.29%
  Memory difference: -86.65MB
  GC runs difference: -7

Resource Usage Analysis
Memory Pattern
Virtual Threads:
- Higher initial memory
- More GC activity
- Better throughput

Concurrent Ruby:
- Lower memory usage
- Fewer GC runs
- Lower throughput

CPU Utilization
Virtual Threads:
- Better CPU utilization
- Less context switching
- More efficient I/O handling

Concurrent Ruby:
- More context switching
- OS thread scheduling overhead
- I/O blocking impacts
System Impact
1. Virtual Threads
   - Higher throughput
   - More memory usage
   - More frequent GC
   - Better scaling with load

2. Concurrent Ruby
   - More predictable memory
   - Limited scaling
   - Higher latency under load
   - Better platform compatibility

Decision Making Guidelines
When to Use Virtual Threads
1. High concurrency requirements (1000+ concurrent operations)
2. I/O-bound operations
3. JRuby/Java environment available
4. Memory can be traded for throughput

When to Use Concurrent Ruby
1. Platform independence required
2. Limited concurrency needs (<1000 concurrent operations)
3. Memory constraints are strict
4. Simpler debugging requirements
Migration Strategy
Phase 1: Assessment
- Evaluate current load patterns
- Measure memory constraints
- Analyze throughput requirements

Phase 2: Implementation

def choose_implementation
  if jruby? && high_concurrency_needed?
    VirtualThreadImplementation.new
  else
    ConcurrentRubyImplementation.new
  end
end

Phase 3: Monitoring
- Track performance metrics
- Monitor resource usage
- Adjust configurations



