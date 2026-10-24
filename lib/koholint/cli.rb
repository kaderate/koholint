require 'json'
require 'optparse'
require 'koholint'
require 'koholint/archive'
require 'koholint/budget'
require 'koholint/engine'
require 'koholint/agents/claude_cli'
require 'koholint/leads'
require 'koholint/explore_log'
require 'koholint/ledger'
require 'koholint/talk_log'
require 'koholint/triggers'
require 'koholint/objectives'
require 'koholint/policies/delegated'
require 'koholint/skills/registry'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/place_shots'
require 'koholint/replay'
require 'koholint/pacer'
require 'koholint/run'
require 'koholint/summary'
require 'koholint/viewer'

module Koholint
  module CLI
    USAGE = 'usage: koholint run|resume <run_dir>|fork <run_dir> --at-frame N|verify <run_dir>|summary <run_dir>|screens <run_dir>|watch <run_dir>|' \
            'archive|star <run_dir> WHY|prune-heavy|census boot|<run_dir> FRAME...|entities <run_dir> FRAME...|ready <run_dir>|npcs ' \
            '[--frames N --minutes N --steps N --dollars X --root DIR --runs-root DIR --tag NAME --realtime --grid --port N --host H --from live|start|DIR ' \
            '--speed X --agent --model M --max-dollars X --claude-command PATH --commit --full --keep N --yes]'.freeze

    DEFAULT_MODEL = 'sonnet'.freeze
    DEFAULT_MAX_DOLLARS = 1.5

    module_function

    def run(argv, out: $stdout, err: $stderr)
      command, *rest = argv
      options = {}
      parser = OptionParser.new do |o|
        o.on('--frames N', Integer) { |v| options[:frames] = v }
        o.on('--minutes N', Float) { |v| options[:active_seconds] = v * 60 }
        o.on('--steps N', Integer) { |v| options[:steps] = v.positive? ? v : raise(OptionParser::InvalidArgument, v.to_s) }
        o.on('--dollars X', Float) { |v| options[:dollars] = v }
        o.on('--flow-version V') { |v| options[:flow_version] = v }
        o.on('--root DIR') { |v| options[:root] = v }
        o.on('--runs-root DIR') { |v| options[:runs_root] = v }
        o.on('--tag NAME') { |v| options[:tag] = v }
        o.on('--at-frame N', Integer) { |v| options[:at_frame] = v }
        o.on('--realtime') { options[:realtime] = true }
        o.on('--grid') { options[:grid] = true }
        o.on('--agent') { options[:agent] = true }
        o.on('--model M') { |v| options[:model] = v }
        o.on('--max-dollars X', Float) { |v| options[:dollars] = v }
        o.on('--claude-command PATH') { |v| options[:claude_command] = v }
        o.on('--port N', Integer) { |v| options[:port] = v }
        o.on('--host H') { |v| options[:host] = v }
        o.on('--from MODE') { |v| options[:from] = v }
        o.on('--commit') { options[:commit] = true }
        o.on('--full') { options[:full] = true }
        o.on('--yes') { options[:yes] = true }
        o.on('--keep N', Integer) { |v| options[:keep] = v.negative? ? raise(OptionParser::InvalidArgument, v.to_s) : v }
        o.on('--speed X', Float) { |v| options[:speed] = v.positive? ? v : raise(OptionParser::InvalidArgument, v.to_s) }
      end
      args = parser.parse(rest)
      dispatch(command, args, options, out)
    rescue OptionParser::ParseError
      err.puts USAGE
      2
    rescue Koholint::Error => e
      err.puts "koholint: #{e.message}"
      1
    end

    def dispatch(command, args, options, out)
      flow = options.fetch(:flow_version, Koholint::FLOW_VERSION)
      options = options.merge(dollars: options.fetch(:dollars, DEFAULT_MAX_DOLLARS), grid: true) if options[:agent]
      limits = options.slice(:frames, :steps, :active_seconds, :dollars)
      budget = Budget.new(**limits)
      case command
      when 'run'
        factory = policy_factory(options, budget, probe: true)
        run = Run.create(root: options.fetch(:root, 'runs'), flow_version: flow, budget: limits, tag: options[:tag],
                         model: options[:agent] ? options.fetch(:model, DEFAULT_MODEL) : nil)
        play(Engine.new(run:, policy: factory.call(run), budget:, **engine_options(options)), run, out)
      when 'resume'
        factory = policy_factory(options, budget)
        run = Run.open(run_dir(args), flow_version: flow)
        engine = Engine.resume(run.dir, policy_factory: factory, budget:, flow_version: flow, **engine_options(options))
        play(engine, run, out)
      when 'fork'
        at_frame = options.fetch(:at_frame) { raise OptionParser::MissingArgument, '--at-frame' }
        child = Run.open(run_dir(args), flow_version: flow).fork(at_frame: at_frame, flow_version: flow)
        out.puts "run #{child.dir}"
        0
      when 'watch'
        Viewer.watch(run_dir(args), **options.slice(:port, :host, :speed, :runs_root), **watch_from(options), out: out)
      when 'archive'
        root = options.fetch(:root, 'runs')
        Archive.archive(root:, from: options.fetch(:from, root), **options.slice(:commit, :full), out:)
      when 'star'
        Archive.star(run_dir(args), args[1] || raise(OptionParser::MissingArgument, 'why'), out:)
      when 'prune-heavy' then Archive.prune_heavy(root: options.fetch(:root, 'runs'), **options.slice(:keep, :yes), out:)
      when 'census' then census(args, out)
      when 'npcs'
        require 'koholint/npc_catalogue'
        out.print NpcCatalogue.markdown(options.fetch(:root, 'runs'))
        0
      when 'screens'
        PlaceShots.backfill(run_dir(args), out:)
        0
      when 'verify' then verify(Run.open(run_dir(args), flow_version: flow), out)
      when 'summary'
        out.puts JSON.pretty_generate(Summary.for(Run.open(run_dir(args), flow_version: flow)))
        0
      else
        raise OptionParser::InvalidOption, command.to_s
      end
    end

    def census(args, out)
      return census_entities(args.drop(1), out) if args.first == 'entities'
      return census_ready(args.drop(1), out) if args.first == 'ready'

      require 'koholint/probes/mode_census'
      raise OptionParser::MissingArgument, 'boot or <run_dir> FRAME...' unless args.first == 'boot' || args.size > 1

      census = Probes::ModeCensus
      paths = args.first == 'boot' ? [census.census_boot] : census.census(run_dir(args), args.drop(1).map { |frame| Integer(frame) })
      paths.each { |path| out.puts "census #{path}" }
      0
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, e.message
    end

    def census_entities(args, out)
      require 'koholint/probes/entity_census'
      raise OptionParser::MissingArgument, 'entities <run_dir> FRAME...' unless args.size > 1

      Probes::EntityCensus.census(run_dir(args), args.drop(1).map { |frame| Integer(frame) }).each { |path| out.puts "census #{path}" }
      0
    rescue ArgumentError => e
      raise OptionParser::InvalidArgument, e.message
    end

    def census_ready(args, out)
      require 'koholint/probes/readiness_census'
      raise OptionParser::MissingArgument, 'ready <run_dir>' unless args.size == 1

      out.puts "census #{Probes::ReadinessCensus.census(run_dir(args))}"
      0
    end

    def watch_from(options)
      return {} unless options.key?(:from)
      raise OptionParser::InvalidArgument, options[:from] unless %w[live start].include?(options[:from])

      { from: options[:from].to_sym }
    end

    def engine_options(options) = options.slice(:grid).merge(options[:realtime] ? { pacer: Pacer.new } : {})

    def run_dir(args) = args.first || raise(OptionParser::MissingArgument, 'run_dir')

    def policy_factory(options, budget, probe: false)
      return ->(_run) { Policies::StartGame.new(Policies::WalkAndTalk.new) } unless options[:agent]

      command = options.fetch(:claude_command, 'claude')
      command = File.expand_path(command) if command.include?(File::SEPARATOR)
      raise Koholint::Error, "claude executable not found: #{command}" unless executable?(command)

      client = Agents::ClaudeCli.new(model: options.fetch(:model, DEFAULT_MODEL), command:, lenient: %w[plan])
      manual = manual_text
      lambda do |run|
        events = events_for(run)
        delegated = Policies::Delegated.new(client:, registry: Skills::Registry.default, objectives: objectives_for(run, events), ledger: ledger_for(run, events),
                                            triggers: Triggers.from_events(events), talk_log: TalkLog.from_events(events), explore_log: ExploreLog.from_events(events), leads: Leads.from_events(events), manual:, on_step: budget.method(:step_done), budget:,
                                            on_activity: run.method(:write_activity))
        Policies::StartGame.new(delegated, ready: ->(state) { %i[playing dialogue].include?(state.phase) }, probe:, played: GameState.played?(events))
      end
    end

    def objectives_for(run, events = events_for(run))
      Objectives.resume(trace: run.trace, events:, frame: run.inputs.frames, visited: Summary.visited_places(events))
    end

    def events_for(run) = Trace.read(File.join(run.dir, 'trace.jsonl'))

    def ledger_for(run, events = events_for(run)) = Ledger.from_events(events)

    def executable?(command)
      return File.executable?(command) && !File.directory?(command) if command.include?(File::SEPARATOR)

      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, command)) }
    end

    def manual_text
      root = File.expand_path('../..', __dir__)
      %w[docs/AGENT_MANUAL.md manual/notice.txt].filter_map do |file|
        path = File.join(root, file)
        File.read(path) if File.file?(path)
      end.join("\n\n")
    end

    def play(engine, run, out)
      previous = %w[INT TERM].to_h { |sig| [sig, Signal.trap(sig) { engine.request_stop }] }
      out.puts "run #{run.dir}"
      reason = engine.run
      out.puts "stopped: #{reason}"
      0
    ensure
      previous&.each { |sig, handler| Signal.trap(sig, handler) }
    end

    def verify(run, out)
      results = Replay.verify(run)
      bad = results.reject(&:last)
      out.puts "verified #{results.size} checkpoints, #{bad.size} diverged"
      bad.empty? ? 0 : 1
    end
  end
end
