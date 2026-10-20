require 'fileutils'
require 'json'
require 'koholint/trace'
require 'koholint/game_state'
require 'koholint/perception'

module Koholint
  module Summary
    STALL_FRAMES = 3600
    HP_PER_HEART = Perception::HP_PER_HEART.to_f
    DIAGNOSTIC_NOTABLE_KINDS = %w[grid_overlay_stuck].freeze
    TERMINAL = %w[achieved abandoned failed].freeze
    DETERMINISTIC_AGENTS = %w[start_game walk_and_talk].freeze
    FILE = 'summary.json'.freeze
    MANIFEST_KEYS = %w[flow_version tag harness_sha prompts_sha model].freeze

    module_function

    def progress?(event)
      case event['type']
      when 'notable' then !DIAGNOSTIC_NOTABLE_KINDS.include?(event['kind'])
      when 'objective' then true
      else false
      end
    end

    def for(run) = from_events(Trace.read(File.join(run.dir, 'trace.jsonl')))

    def model_call?(event)
      event['type'] == 'decision' && !DETERMINISTIC_AGENTS.include?(event['agent']) &&
        !(event['agent'] == 'delegated' && !event['prompt_sha'] && event['cost_usd'].to_f.zero?)
    end

    def write(dir)
      path = File.join(dir, FILE)
      File.write("#{path}.tmp", "#{JSON.pretty_generate(record(dir))}\n")
      File.rename("#{path}.tmp", path)
    rescue StandardError
      FileUtils.rm_f("#{path}.tmp")
      raise
    end

    def record(dir)
      manifest = read_json(File.join(dir, 'manifest.json'))
      events = Trace.read(File.join(dir, 'trace.jsonl'))
      base = from_events(events)
      frames = base[:frames]
      calls = events.select { |e| model_call?(e) }
      latencies = latencies(events)
      objectives = events.select { |e| e['type'] == 'objective' }
      {
        run_id: File.basename(dir), **MANIFEST_KEYS.to_h { |key| [key.to_sym, manifest[key]] },
        frames:, dollars: base[:cost_usd].round(6), calls: calls.size,
        calls_per_1000f: per_1000(calls.size, frames), usd_per_1000f: per_1000(base[:cost_usd], frames),
        latency_ms: { median: percentile(latencies, 0.5), p90: percentile(latencies, 0.9) },
        highest_milestone: base[:highest_milestone], places_seen: visited_places(events).size,
        objectives: { count: objectives.map { |e| e['id'] }.uniq.size, achieved: objectives.select { |e| e['status'] == 'achieved' }.map { |e| e['id'] }.uniq.size },
        stop_reason: events.reverse_each.find { |e| e['type'] == 'stop' }&.fetch('reason'),
        symptoms: [], starred: File.exist?(File.join(dir, 'star.json'))
      }
    end

    def visited_places(events) = events.filter_map { |event| perceived_place(event) }.uniq

    def perceived_place(event)
      state = event['state']
      return nil unless event['type'] == 'perception' && state.is_a?(Hash)

      game = GameState.new(game_mode: state['game_mode'], game_submode: state['game_submode'])
      [state['room_id'], state['map_id']] unless %i[loading boot].include?(game.phase)
    end

    def per_1000(value, frames) = frames.positive? ? (value * 1000.0 / frames).round(6) : nil

    def latencies(events)
      events.select { |e| e['type'] == 'decision' && e['agent'] == 'claude' && e['latency_ms'].is_a?(Numeric) && e['latency_ms'].positive? }.map { |e| e['latency_ms'] }
    end

    def percentile(samples, fraction) = samples.empty? ? nil : samples.sort[((samples.size - 1) * fraction).ceil]

    def read_json(path)
      value = JSON.parse(File.read(path))
      value.is_a?(Hash) ? value : {}
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def from_events(events)
      frames = events.map { |e| e['frame'] }.max || 0
      state = events.reverse_each.find { |e| e['type'] == 'perception' }&.fetch('state')
      {
        health: health(events, state, frames),
        hearts: state && state['hp'] / HP_PER_HEART,
        max_hearts: state && state['max_hp'] / HP_PER_HEART,
        objective: current_objective(events),
        last_notable: events.reverse_each.find { |e| e['type'] == 'notable' && progress?(e) }&.slice('kind', 'detail'),
        highest_milestone: highest_milestone(events),
        frames: frames,
        cost_usd: events.select { |e| e['type'] == 'decision' }.sum { |e| e['cost_usd'] }
      }
    end

    def highest_milestone(events)
      seen = events.filter_map { |e| e['state']&.fetch('milestone', nil) if e['type'] == 'perception' }
      seen.max_by { |m| Perception::MILESTONES.index(m.to_sym) || 0 }
    end

    def health(events, state, frames)
      return 'stopped' if events.last && events.last['type'] == 'stop'
      return 'dead' if state && state['max_hp'].positive? && state['hp'].zero?

      last_progress = events.select { |e| progress?(e) }.map { |e| e['frame'] }.max || 0
      frames - last_progress >= STALL_FRAMES ? 'stalled' : 'progressing'
    end

    def current_objective(events)
      current = nil
      events.each do |event|
        next unless event['type'] == 'objective'

        current = event['status'] == 'started' ? event['id'] : (current == event['id'] ? nil : current)
      end
      current
    end
  end
end
