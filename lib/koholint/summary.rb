require 'koholint/trace'

module Koholint
  module Summary
    STALL_FRAMES = 3600
    HP_PER_HEART = 8.0
    TERMINAL = %w[achieved abandoned failed].freeze

    module_function

    def for(run) = from_events(Trace.read(File.join(run.dir, 'trace.jsonl')))

    def from_events(events)
      frames = events.map { |e| e['frame'] }.max || 0
      state = events.reverse_each.find { |e| e['type'] == 'perception' }&.fetch('state')
      {
        health: health(events, state, frames),
        hearts: state && state['hp'] / HP_PER_HEART,
        max_hearts: state && state['max_hp'] / HP_PER_HEART,
        objective: current_objective(events),
        last_notable: events.reverse_each.find { |e| e['type'] == 'notable' }&.slice('kind', 'detail'),
        highest_milestone: state && state['milestone'],
        frames: frames,
        cost_usd: events.select { |e| e['type'] == 'decision' }.sum { |e| e['cost_usd'] }
      }
    end

    def health(events, state, frames)
      return 'stopped' if events.last && events.last['type'] == 'stop'
      return 'dead' if state && state['max_hp'].positive? && state['hp'].zero?

      last_progress = events.select { |e| %w[notable objective].include?(e['type']) }.map { |e| e['frame'] }.max || 0
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
