require 'fileutils'
require 'json'
require 'rbconfig'
require 'set'
require 'time'
require_relative 'debt'
require_relative 'measure'
require_relative 'runs'

module Scoreboard
  # The standard run: a from-boot run at a dollar cap, plus optional forks of data/checkpoints.json entries, at most two emulator processes
  # at a time, each stopped cleanly (SIGINT, as Ctrl-C) on a wall-time limit, on deaths, or on a stall.
  module Run
    MAX_JOBS = 2
    DEFAULTS = { budget: 4.0, frames: 80_000, minutes: 180, max_seconds: 14_400, max_deaths: 3, stall: 4000, jobs: MAX_JOBS, poll: 15 }.freeze

    # Reads a run's trace as it grows and says when it should stop.
    class Supervisor
      attr_reader :frame, :deaths, :places

      def initialize(trace:, max_seconds:, max_deaths:, stall:, now: 0.0)
        @trace = trace
        @limits = { max_seconds:, max_deaths:, stall: }
        @started = now
        @position = 0
        @frame = @deaths = @last_new = 0
        @places = Set.new
      end

      def poll(now)
        read
        return 'deaths' if @limits[:max_deaths] && @deaths >= @limits[:max_deaths]
        return 'stall' if @limits[:stall] && !@places.empty? && @frame - @last_new >= @limits[:stall]

        'wall' if now - @started > @limits[:max_seconds]
      end

      def read
        return unless File.file?(@trace)

        data = File.open(@trace, 'rb') { |file| file.seek(@position) && file.read }.to_s
        complete = (data.rindex("\n") || -1) + 1
        @position += complete
        data.byteslice(0, complete).each_line { |line| observe(JSON.parse(line)) rescue nil }
      end

      def observe(event)
        @frame = [@frame, event['frame'].to_i].max
        place = Measure.place_of(event)
        @last_new = event['frame'].to_i if place && @places.add?(place)
        @deaths += 1 if event['type'] == 'notable' && event['kind'] == 'death'
      end
    end

    module_function

    def command(koholint, *args) = [RbConfig.ruby, '--yjit', koholint, *args]

    def flags(tag:, root:, budget:, frames:, minutes:) = ['--agent', '--root', root, '--tag', tag, '--max-dollars', budget.to_s, '--frames', frames.to_s, '--minutes', minutes.to_s]

    def play(froms:, root:, koholint:, repo:, history:, day: Time.now.strftime('%Y%m%d'), roots: Runs::ROOTS, out: $stdout, **options)
      settings = DEFAULTS.merge(options)
      queue = Queue.new
      froms.each { |from| queue << from }
      results = Queue.new
      workers = Array.new([settings[:jobs], MAX_JOBS].min) do
        Thread.new do
          while (from = (queue.pop(true) rescue nil))
            results << once(from, root:, koholint:, day:, roots:, settings:, out:)
          end
        end
      end
      workers.each(&:join)
      runs = Array.new(results.size) { results.pop }.sort_by { |run| froms.index(run[:from]) }
      line = entry(runs, repo:, budget: settings[:budget], froms:)
      FileUtils.mkdir_p(File.dirname(history))
      File.open(history, 'a') { |file| file.puts(JSON.generate(line)) }
      line
    end

    def once(from, root:, koholint:, day:, roots:, settings:, out:)
      tag = "scoreboard-#{from}-#{day}"
      shared = flags(tag:, root:, budget: settings[:budget], frames: settings[:frames], minutes: settings[:minutes])
      dir, pid = start(from, tag:, root:, koholint:, roots:, shared:)
      out.puts "#{from}: #{dir} (pid #{pid})"
      reason = supervise(dir, pid, settings)
      out.puts "#{from}: stopped (#{reason || 'ended'})"
      Measure.run(dir).merge(from:, stop_request: reason)
    rescue StandardError => e
      { from:, error: "#{e.class}: #{e.message}" }
    end

    def start(from, tag:, root:, koholint:, roots:, shared:)
      FileUtils.mkdir_p(root)
      return start_boot(tag:, root:, koholint:, shared:) if from == 'boot'

      require 'koholint/checkpoints'
      point = Koholint::Checkpoints.catalogue.fetch(from) { raise ArgumentError, "no checkpoint #{from}" }
      parent = Runs.dirs(roots).find { |dir| File.basename(dir) == point['run'] } or raise ArgumentError, "run #{point['run']} of #{from} not found"
      forked = IO.popen(command(koholint, 'fork', parent, '--at-frame', point['frame'].to_s, '--tag', tag, '--root', root), &:read)
      dir = forked[/^run (.+)$/, 1] or raise "fork of #{from} failed: #{forked}"
      [dir, spawn_run(command(koholint, 'resume', dir, *shared))]
    end

    def start_boot(tag:, root:, koholint:, shared:)
      pid = spawn_run(command(koholint, 'run', *shared))
      dir = nil
      200.times do
        dir = Dir.glob(File.join(root, '*')).find { |path| Runs.read_json(File.join(path, 'manifest.json'))['tag'] == tag }
        break if dir || !alive?(pid)

        sleep 0.1
      end
      dir or raise "the boot run did not start under #{root}"
      [dir, pid]
    end

    def spawn_run(argv)
      pid = Process.spawn(*argv, %i[out err] => File::NULL)
      Process.detach(pid)
      Process.spawn('caffeinate', '-dims', '-w', pid.to_s, %i[out err] => File::NULL) if system('command -v caffeinate >/dev/null 2>&1')
      pid
    end

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue SystemCallError
      false
    end

    def supervise(dir, pid, settings)
      watcher = Supervisor.new(trace: File.join(dir, 'trace.jsonl'), **settings.slice(:max_seconds, :max_deaths, :stall), now: clock)
      reason = nil
      while alive?(pid)
        sleep settings[:poll]
        reason = watcher.poll(clock) or next
        Process.kill('INT', pid)
        40.times { break unless alive?(pid) && sleep(3) }
        warn "scoreboard: #{pid} still alive after SIGINT; leaving it to the operator" if alive?(pid)
        break
      end
      reason
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def entry(runs, repo:, budget:, froms:)
      good = runs.reject { |run| run[:error] }
      primary = good.find { |run| run[:from] == 'boot' } || good.first
      JSON.parse(JSON.generate({
        date: Time.now.utc.iso8601, kind: 'daily', budget:, froms:, flow: primary&.dig(:flow), harness_sha: Debt.git(repo, 'rev-parse', '--short', 'HEAD').strip,
        branches: Debt.branches(repo, 'HEAD'), usd: good.sum { |run| run[:cost][:usd] }.round(4),
        primary: primary && { run: primary[:run], from: primary[:from], deaths_per_1000f: primary[:deaths_per_1000f], calls_per_1000f: primary[:cost][:calls_per_1000f],
                              new_places_per_usd: primary[:new_places_per_usd], progress: primary[:progress] },
        runs:
      }))
    end
  end
end
