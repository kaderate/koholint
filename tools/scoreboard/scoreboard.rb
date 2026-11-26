$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'optparse'
require_relative 'alert'
require_relative 'debt'
require_relative 'measure'
require_relative 'run'
require_relative 'runs'

# ruby tools/scoreboard/scoreboard.rb measure RUN_DIR... [--json]
# ruby tools/scoreboard/scoreboard.rb run [--budget USD] [--daily-cap USD] [--from boot|CHECKPOINT]... [--root DIR] [--history FILE]
# ruby tools/scoreboard/scoreboard.rb debt [--window N] [--last N] [--ref REF]
# ruby tools/scoreboard/scoreboard.rb alert [--history FILE]
module Scoreboard
  REPO = File.expand_path('../..', __dir__)
  RUN_ROOT = File.expand_path('~/.capy/work/runs/scoreboard')

  module_function

  def main(argv, out: $stdout)
    command = argv.shift
    options = { roots: [], from: [], history: File.expand_path(Runs::HISTORY), ref: 'origin/main', window: 10, last: 5, root: RUN_ROOT, repo: REPO, koholint: File.join(REPO, 'bin', 'koholint') }
    OptionParser.new do |parser|
      parser.on('--json') { options[:json] = true }
      parser.on('--budget USD', Float) { |value| options[:budget] = value }
      parser.on('--daily-cap USD', Float) { |value| options[:daily_cap] = value }
      parser.on('--from NAME') { |value| options[:from] << value }
      parser.on('--root DIR') { |value| options[:root] = File.expand_path(value) }
      parser.on('--runs-root DIR') { |value| options[:roots] << value }
      parser.on('--history FILE') { |value| options[:history] = File.expand_path(value) }
      parser.on('--repo DIR') { |value| options[:repo] = File.expand_path(value) }
      parser.on('--ref REF') { |value| options[:ref] = value }
      parser.on('--window N', Integer) { |value| options[:window] = value }
      parser.on('--last N', Integer) { |value| options[:last] = value }
      parser.on('--max-seconds N', Integer) { |value| options[:max_seconds] = value }
      parser.on('--max-deaths N', Integer) { |value| options[:max_deaths] = value }
      parser.on('--stall FRAMES', Integer) { |value| options[:stall] = value }
      parser.on('--koholint PATH') { |value| options[:koholint] = File.expand_path(value) }
    end.parse!(argv)
    roots = options[:roots].empty? ? Runs::ROOTS : options[:roots]
    case command
    when 'measure'
      abort 'usage: scoreboard measure RUN_DIR...' if argv.empty?
      results = argv.map { |dir| Measure.run(File.expand_path(dir)) }
      out.puts options[:json] ? JSON.pretty_generate(results) : Measure.table(results)
      0
    when 'run'
      from = options[:from].empty? ? ['boot'] : options[:from]
      begin
        line = Run.play(froms: from, root: options[:root], koholint: options[:koholint], repo: options[:repo], history: options[:history], roots:, out:,
                        **options.slice(:budget, :daily_cap, :max_seconds, :max_deaths, :stall))
      rescue Run::Refused => e
        abort "scoreboard: #{e.message}"
      end
      out.puts JSON.pretty_generate(line.slice('date', 'flow', 'harness_sha', 'usd', 'branches', 'primary'))
      line['runs'].all? { |run| run['error'].nil? } ? 0 : 1
    when 'debt'
      report = Debt.report(repo: options[:repo], ref: options[:ref], window: options[:window], roots:, history: Runs.history(options[:history]), last: options[:last])
      out.puts options[:json] ? JSON.pretty_generate(report) : Debt.text(report)
      0
    when 'alert'
      reasons = Alert.reasons(rows: Runs.rows(roots), history: Runs.history(options[:history]))
      out.puts(reasons.empty? ? 'no guardrail tripped' : reasons.map { |reason| "ALERT: #{reason}" })
      reasons.empty? ? 0 : 1
    else
      abort 'usage: scoreboard measure|run|debt|alert'
    end
  end
end

exit(Scoreboard.main(ARGV)) if $PROGRAM_NAME == __FILE__
