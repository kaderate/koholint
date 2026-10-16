require 'json'
require 'optparse'
require 'koholint'
require 'koholint/budget'
require 'koholint/engine'
require 'koholint/policies/walk_and_talk'
require 'koholint/replay'
require 'koholint/run'
require 'koholint/summary'

module Koholint
  module CLI
    USAGE = 'usage: koholint run|resume <run_dir>|fork <run_dir> --at-frame N|verify <run_dir>|summary <run_dir> ' \
            '[--frames N --steps N --minutes N --dollars X --root DIR]'.freeze

    module_function

    def run(argv, out: $stdout, err: $stderr)
      command, *rest = argv
      options = {}
      parser = OptionParser.new do |o|
        o.on('--frames N', Integer) { |v| options[:frames] = v }
        o.on('--steps N', Integer) { |v| options[:steps] = v }
        o.on('--minutes N', Float) { |v| options[:active_seconds] = v * 60 }
        o.on('--dollars X', Float) { |v| options[:dollars] = v }
        o.on('--flow-version V') { |v| options[:flow_version] = v }
        o.on('--root DIR') { |v| options[:root] = v }
        o.on('--at-frame N', Integer) { |v| options[:at_frame] = v }
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
      limits = options.slice(:frames, :steps, :active_seconds, :dollars)
      case command
      when 'run'
        run = Run.create(root: options.fetch(:root, 'runs'), flow_version: flow, budget: limits)
        play(Engine.new(run: run, policy: Policies::WalkAndTalk.new, budget: Budget.new(**limits)), run, out)
      when 'resume'
        run = Run.open(args.fetch(0), flow_version: flow)
        engine = Engine.resume(run.dir, policy: Policies::WalkAndTalk.new, budget: Budget.new(**limits), flow_version: flow)
        play(engine, run, out)
      when 'fork'
        child = Run.open(args.fetch(0), flow_version: flow).fork(at_frame: options.fetch(:at_frame), flow_version: flow)
        out.puts "run #{child.dir}"
        0
      when 'verify' then verify(Run.open(args.fetch(0), flow_version: flow), out)
      when 'summary'
        out.puts JSON.pretty_generate(Summary.for(Run.open(args.fetch(0), flow_version: flow)))
        0
      else
        raise OptionParser::InvalidOption, command.to_s
      end
    rescue KeyError, IndexError
      raise OptionParser::MissingArgument
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
