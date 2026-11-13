require 'etc'
require 'fileutils'
require 'json'
require 'rake/testtask'
require 'tempfile'

HEAVY = %w[
  test/delegated_engine_test.rb test/grid_builder_test.rb test/grid_builder_probe_test.rb test/follower_test.rb test/cli_test.rb
  test/replay_test.rb test/engine_test.rb test/walk_probe_test.rb test/emulator_test.rb test/emulator_cache_test.rb
  test/registry_test.rb test/resilience_test.rb test/start_game_test.rb test/readiness_test.rb test/object_census_test.rb
  test/screens_test.rb test/dialogue_shot_test.rb
].freeze
# Emulated frames above which a file belongs in HEAVY; the heaviest light file emulates about 1500
HEAVY_FRAMES = 2000
TIMES = 'tmp/test_times.json'.freeze

desc 'Run every test file in its own process, in parallel'
task :test do
  files = Dir['test/**/*_test.rb'].sort
  files -= HEAVY if ENV['FAST']
  jobs = files.flat_map do |file|
    next [[file, []]] unless HEAVY.include?(file)

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
  frames = Hash.new(0)
  until queue.empty? && running.empty?
    while running.size < Etc.nprocessors && (job = queue.shift)
      file, args = job
      log = Tempfile.new(File.basename(file))
      count = Tempfile.new("#{File.basename(file)}-frames")
      pid = Process.spawn({ 'KOHOLINT_FRAMES_LOG' => count.path }, RbConfig.ruby, '--yjit', '-Ilib', '-Itest', file, *args,
                          %i[out err] => log.path)
      Process.setpriority(Process::PRIO_PROCESS, pid, 5) if times.fetch(file + args.join, 0) < critical
      running[pid] = [file, log, count]
      started[pid] = [file + args.join, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
    end
    pid, status = Process.wait2
    file, log, count = running.delete(pid)
    frames[file] += File.read(count.path).to_i
    count.close!
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
  counts = results.values.flat_map { |_, out| out.scan(/^(\d+) runs, .* (\d+) skips$/) }
  total, skips = counts.transpose.map { |column| column.sum(&:to_i) }
  puts "#{files.size} files, #{total} runs, #{skips} skips, #{failed.size} failing file(s)"
  light = frames.select { |file, count| count > HEAVY_FRAMES && !HEAVY.include?(file) }
  light.each { |file, count| puts "#{file} emulated #{count} frames (over #{HEAVY_FRAMES}): add it to HEAVY in the Rakefile" }
  abort unless failed.empty? && light.empty?
end

namespace :test do
  desc 'Run the tests that do not boot the ROM (agents loop; run the full suite before merging)'
  task :fast do
    ENV['FAST'] = '1'
    Rake::Task[:test].invoke
  end

  desc 'Run every test with the ROM hidden, as CI does: ROM tests skip'
  task :ci do
    ENV['KOHOLINT_ROM'] = ''
    Rake::Task[:test].invoke
  end
end

task default: :test
