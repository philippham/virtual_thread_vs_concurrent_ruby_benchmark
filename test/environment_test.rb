require 'json'

def check_environment
  puts "Ruby Environment:"
  puts "  Engine: #{RUBY_ENGINE}"
  puts "  Version: #{RUBY_VERSION}"
  
  if RUBY_ENGINE == 'jruby'
    require 'java'
    puts "\nJava Environment:"
    puts "  Version: #{java.lang.System.getProperty('java.version')}"
    puts "  Vendor: #{java.lang.System.getProperty('java.vendor')}"
    puts "  VM Name: #{java.lang.System.getProperty('java.vm.name')}"
    
    puts "\nJRuby Options:"
    puts "  JRUBY_OPTS: #{ENV['JRUBY_OPTS']}"
    
    puts "\nAvailable Processors:"
    puts "  Count: #{java.lang.Runtime.getRuntime.availableProcessors}"
    
    puts "\nMemory Info:"
    runtime = java.lang.Runtime.getRuntime
    puts "  Max Memory: #{runtime.maxMemory / 1024 / 1024}MB"
    puts "  Total Memory: #{runtime.totalMemory / 1024 / 1024}MB"
    puts "  Free Memory: #{runtime.freeMemory / 1024 / 1024}MB"
  end
end

if __FILE__ == $0
  check_environment
end