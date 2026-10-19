require 'koholint/trace'
require 'koholint/perception'

module Koholint
  module Summary
    STALL_FRAMES = 3600
    HP_PER_HEART = Perception::HP_PER_HEART.to_f
    DIAGNOSTIC_NOTABLE_KINDS = %w[grid_overlay_stuck].freeze
    TERMINAL = %w[achieved abandoned failed].freeze

    module_function

    def progress?(event)
      case event['type']
      when 'notable' then !DIAGNOSTIC_NOTABLE_KINDS.include?(event['kind'])
      when 'objective' then true
      else false
      end
    end

    def for(run) = from_events(Trace.read(File.join(run.dir, 'trace.jsonl')))

    def from_events(events)
      frames = events.map { |e| e['frame'] }.max || 0
      state = events.reverse_each.find { |e| e['type'] == 'perception' }&.fetch('state')
      {
        health: health(events, state, frames),
        hearts: state && state['hp'] / HP_PER_HEART,
        max_hearts: state && state['max_hp'] / HP_PER_HEART,
        objective: current_objective(events),
        last_notable: events.reverse_each.find { |e| e['type'] == 'notable' && progress?(e) }&.slice('kind', 'detail'),
        highest_milestone: state && state['milestone'],
        frames: frames,
        cost_usd: events.select { |e| e['type'] == 'decision' }.sum { |e| e['cost_usd'] }
      }
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
