require 'etc'
require 'fileutils'
require 'json'
require 'rake/testtask'
require 'tempfile'

SHARDED = %w[
  test/delegated_engine_test.rb test/grid_builder_test.rb test/grid_builder_probe_test.rb test/follower_test.rb test/cli_test.rb
  test/replay_test.rb test/engine_test.rb test/walk_probe_test.rb test/emulator_test.rb test/emulator_cache_test.rb
  test/registry_test.rb test/resilience_test.rb test/start_game_test.rb
].freeze
TIMES = 'tmp/test_times.json'.freeze

desc 'Run every test file in its own process, in parallel (E2E=1 adds the full-boot tests)'
task :test do
  files = Dir['test/**/*_test.rb'].sort
  files -= SHARDED if ENV['FAST']
  jobs = files.flat_map do |file|
    next [[file, []]] unless SHARDED.include?(file)

    File.read(file).scan(/def (test_\w+)/).flatten.map { |name| [file, ['-n', name]] }
  end
  times = File.file?(TIMES) ? JSON.parse(File.read(TIMES)) : {}
  jobs.sort_by! { |file, args| -times.fetch((file + args.join), 0) }
  # The longest jobs set the wall clock: shorter ones yield the cores to them
  critical = times.values.max.to_f / 2
  started = {}
  queue = jobs.dup
  running = {}
  results = {}
  until queue.empty? && running.empty?
    while running.size < Etc.nprocessors && (job = queue.shift)
      file, args = job
      log = Tempfile.new(File.basename(file))
      pid = Process.spawn(RbConfig.ruby, '--yjit', '-Ilib', '-Itest', file, *args, %i[out err] => log.path)
      Process.setpriority(Process::PRIO_PROCESS, pid, 5) if times.fetch(file + args.join, 0) < critical
      running[pid] = [file, log]
      started[pid] = [file + args.join, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
    end
    pid, status = Process.wait2
    file, log = running.delete(pid)
    key, t0 = started.delete(pid)
    times[key] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)
    ok, out = results[file] || [true, '']
    results[file] = [ok && status.success?, out + File.read(log.path)]
    log.close!
  end
  FileUtils.mkdir_p(File.dirname(TIMES))
  File.write(TIMES, JSON.generate(times))
  failed = results.reject { |_, (ok, _)| ok }
  failed.each { |file, (_, output)| puts "== #{file}", output.lines.reject { |l| l.include?('warning:') }.join }
  total = results.values.sum { |_, out| out.scan(/(\d+) runs, /).flatten.sum(&:to_i) }
  puts "#{files.size} files, #{total} runs, #{failed.size} failing file(s)"
  abort unless failed.empty?
end

namespace :test do
  desc 'Run the tests that do not boot the ROM (agents loop; run the full suite before merging)'
  task :fast do
    ENV['FAST'] = '1'
    Rake::Task[:test].invoke
  end

  desc 'Run the tests including the full-boot end-to-end ones'
  task :e2e do
    ENV['E2E'] = '1'
    Rake::Task[:test].invoke
  end
end

task default: :test
