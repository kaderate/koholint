require 'fileutils'
require 'json'
require 'time'
require_relative 'measure'
require_relative 'run'

module Scoreboard
  # The stall-start paired fork: forks of one run at one frame, each resumed at `max_dollars` under the run supervisor. The candidate is this
  # checkout, or the git ref `variant` checked out in a throwaway worktree, in which case this checkout plays the baseline forks; without a
  # variant the baseline is the parent's own recorded segment from the same frame, cut at the same dollar horizon. Its spend goes to the
  # history, even when a fork fails, so the daily cap counts it. It prints the numbers; it judges nothing.
  module Pair
    module_function

    def play(parent:, at_frame:, max_dollars:, root:, koholint:, repo:, history:, forks: 2, variant: nil, day: Time.now.strftime('%Y%m%d'), out: $stdout, **options)
      settings = Run::DEFAULTS.merge(options)
      cap = (max_dollars * forks * (variant ? 2 : 1)).round(2)
      Run.daily_cap!(history, day, cap, settings[:daily_cap])
      out.puts "pair: #{forks} fork(s) per arm of #{File.basename(parent)} at frame #{at_frame}, #{max_dollars} USD each, #{cap} USD at most " \
               '(soft: a fork stops after the call that crosses its cap)'
      worktree = File.join(repo, 'tmp', 'pair', "variant-#{Process.pid}") if variant
      arms = variant ? { 'baseline' => koholint, 'candidate' => checkout(repo, variant, worktree) } : { 'candidate' => koholint }
      prefix = "pair-#{File.basename(parent)[-4..]}-#{at_frame}"
      started = []
      dirs = []
      runs = Run.parallel(arms.flat_map { |arm, bin| (1..forks).map { |k| [arm, bin, k] } }, settings[:jobs]) do |arm, bin, k|
        tag = "#{prefix}-#{arm}-#{k}"
        shared = Run.flags(tag:, root:, budget: max_dollars, frames: settings[:frames], minutes: settings[:minutes])
        dir, pid = Run.fork_and_resume(parent, at_frame, tag:, root:, koholint: bin, shared:, started:)
        dirs << dir
        out.puts "#{tag}: #{dir} (pid #{pid})"
        reason = Run.supervise(dir, pid, settings)
        Measure.run(dir).merge(arm:, stop_request: reason)
      rescue StandardError => e
        { arm:, run: tag, error: "#{e.class}: #{e.message}" }
      end
      recorded = Measure.run(parent, start: at_frame, upto: horizon(parent, at_frame, max_dollars)).merge(arm: variant ? 'recorded' : 'baseline')
      out.puts table([recorded, *runs], at_frame)
      [recorded, *runs]
    ensure
      started&.each { |pid| Run.stop(pid, settings) }
      record(history, parent, at_frame, dirs) if dirs&.any?
      system('git', '-C', repo, 'worktree', 'remove', '--force', worktree, %i[out err] => File::NULL) if worktree && Dir.exist?(worktree)
    end

    def record(history, parent, at_frame, dirs)
      usd = dirs.sum { |dir| Measure.run(dir)[:cost][:usd] }.round(4)
      FileUtils.mkdir_p(File.dirname(history))
      File.open(history, 'a') { |file| file.puts(JSON.generate(date: Time.now.utc.iso8601, kind: 'pair', parent: File.basename(parent), at_frame:, usd:)) }
    end

    # The frame of the parent's decision that brought its spend from `at_frame` to `dollars`, as the engine's soft cap would stop a fork; nil if never.
    def horizon(parent, at_frame, dollars)
      spent = 0.0
      Koholint::Trace.read(File.join(parent, 'trace.jsonl')).each do |event|
        next unless event['type'] == 'decision' && event['frame'].to_i >= at_frame

        spent += event['cost_usd'].to_f
        return event['frame'].to_i if spent >= dollars
      end
      nil
    end

    def checkout(repo, ref, path)
      system('git', '-C', repo, 'worktree', 'add', '--detach', path, ref, %i[out err] => File::NULL) or raise ArgumentError, "cannot check out #{ref}"
      FileUtils.cp(File.join(repo, '.env'), path) if File.file?(File.join(repo, '.env'))
      File.join(path, 'bin', 'koholint')
    end

    def table(rows, at_frame)
      lines = ['| arm | run | from | frames | usd | calls | new_places | longest_stall | stop |', '|---|---|---|---|---|---|---|---|---|']
      rows.each do |r|
        next lines << "| #{r[:arm]} | #{r[:run]} | #{at_frame} | error: #{r[:error]} |" if r[:error]

        lines << "| #{r[:arm]} | #{r[:run]} | #{at_frame} | #{r[:frames]} | #{r[:cost][:usd]} | #{r[:cost][:calls]} | #{r[:new_places]} | #{r[:stalls][:longest_frames]} | #{r[:stop_request] || '-'} |"
      end
      lines.join("\n")
    end
  end
end
