require 'etc'
require 'rake/testtask'
require 'tempfile'

desc 'Run every test file in its own process, in parallel (E2E=1 adds the full-boot tests)'
task :test do
  files = Dir['test/**/*_test.rb'].sort
  queue = files.dup
  running = {}
  results = {}
  until queue.empty? && running.empty?
    while running.size < Etc.nprocessors && (file = queue.shift)
      log = Tempfile.new(File.basename(file))
      pid = Process.spawn(RbConfig.ruby, '--yjit', '-Ilib', '-Itest', file, %i[out err] => log.path)
      running[pid] = [file, log]
    end
    pid, status = Process.wait2
    file, log = running.delete(pid)
    results[file] = [status.success?, File.read(log.path)]
    log.close!
  end
  failed = results.reject { |_, (ok, _)| ok }
  failed.each { |file, (_, output)| puts "== #{file}", output.lines.reject { |l| l.include?('warning:') }.join }
  total = results.values.sum { |_, out| out[/(\d+) runs, /, 1].to_i }
  puts "#{files.size} files, #{total} runs, #{failed.size} failing file(s)"
  abort unless failed.empty?
end

namespace :test do
  desc 'Run the tests including the full-boot end-to-end ones'
  task :e2e do
    ENV['E2E'] = '1'
    Rake::Task[:test].invoke
  end
end

task default: :test
