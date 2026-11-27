require 'fileutils'
require 'koholint/ab'
require_relative 'measure'
require_relative 'run'

module Scoreboard
  # The stall-start paired fork: forks of one run at one frame, each resumed at `max_dollars` under the run supervisor. The candidate is this
  # checkout, or the git ref `variant` checked out in a throwaway worktree, in which case this checkout plays the baseline forks; without a
  # variant the baseline is the parent's own recorded segment from the same frame. It prints the numbers and ab-report; it judges nothing.
  module Pair
    module_function

    def play(parent:, at_frame:, max_dollars:, root:, koholint:, repo:, history:, forks: 2, variant: nil, day: Time.now.strftime('%Y%m%d'), out: $stdout, **options)
      settings = Run::DEFAULTS.merge(options)
      cap = (max_dollars * forks * (variant ? 2 : 1)).round(2)
      Run.daily_cap!(history, day, cap, settings[:daily_cap])
      out.puts "pair: #{forks} fork(s) per arm of #{File.basename(parent)} at frame #{at_frame}, #{max_dollars} USD each, #{cap} USD at most"
      worktree = File.join(repo, 'tmp', 'pair', "variant-#{Process.pid}") if variant
      arms = variant ? { 'baseline' => koholint, 'candidate' => checkout(repo, variant, worktree) } : { 'candidate' => koholint }
      prefix = "pair-#{File.basename(parent)[-4..]}-#{at_frame}"
      started = []
      shared = ->(tag) { Run.flags(tag:, root:, budget: max_dollars, frames: settings[:frames], minutes: settings[:minutes]) }
      runs = Run.parallel(arms.flat_map { |arm, bin| (1..forks).map { |k| [arm, bin, k] } }, settings[:jobs]) do |arm, bin, k|
        tag = "#{prefix}-#{arm}-#{k}"
        dir, pid = Run.fork_and_resume(parent, at_frame, tag:, root:, koholint: bin, shared: shared.(tag), started:)
        out.puts "#{tag}: #{dir} (pid #{pid})"
        reason = Run.supervise(dir, pid, settings)
        Measure.run(dir).merge(arm:, stop_request: reason)
      end
      rows = [Measure.run(parent, start: at_frame).merge(arm: variant ? 'recorded' : 'baseline'), *runs]
      out.puts table(rows, at_frame)
      out.print Koholint::AB.markdown(Koholint::AB.report(prefix:, root:))
      rows
    ensure
      started&.each { |pid| Run.stop(pid, settings) }
      system('git', '-C', repo, 'worktree', 'remove', '--force', worktree, %i[out err] => File::NULL) if worktree && Dir.exist?(worktree)
    end

    def checkout(repo, ref, path)
      system('git', '-C', repo, 'worktree', 'add', '--detach', path, ref, %i[out err] => File::NULL) or raise ArgumentError, "cannot check out #{ref}"
      FileUtils.cp(File.join(repo, '.env'), path) if File.file?(File.join(repo, '.env'))
      File.join(path, 'bin', 'koholint')
    end

    def table(rows, at_frame)
      lines = ['| arm | run | from | frames | usd | calls | new_places | longest_stall | stop |', '|---|---|---|---|---|---|---|---|---|']
      rows.each do |r|
        lines << "| #{r[:arm]} | #{r[:run]} | #{at_frame} | #{r[:frames]} | #{r[:cost][:usd]} | #{r[:cost][:calls]} | #{r[:new_places]} | #{r[:stalls][:longest_frames]} | #{r[:stop_request] || '-'} |"
      end
      lines.join("\n")
    end
  end
end
