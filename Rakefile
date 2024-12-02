
require 'rake'
require 'fileutils'

namespace :setup do
  desc 'Create necessary directories'
  task :dirs do
    %w[log results tmp].each do |dir|
      FileUtils.mkdir_p(dir)
    end
  end
end

namespace :test do
  desc 'Check environment'
  task :env => ['setup:dirs'] do
    ruby 'test/environment_test.rb'
  end

  desc 'Run benchmark tests'
  task :benchmark => ['setup:dirs'] do
    ruby 'test/benchmark_test.rb'
  end

  desc 'Run load tests'
  task :load => ['setup:dirs'] do
    ruby 'test/load_test.rb'
  end

  desc 'Clean up generated files'
  task :cleanup do
    %w[log results tmp].each do |dir|
      FileUtils.rm_rf(dir)
    end
  end
end

task :setup => ['setup:dirs']
task default: ['test:benchmark']

# Ensure cleanup on interrupt
trap('INT') do
  Rake::Task['test:cleanup'].invoke if Rake::Task.task_defined?('test:cleanup')
  exit 1
end