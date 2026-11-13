require 'koholint/ledger'

module Koholint
  # Identical results (same place, skill and stop) of at most one frame come back without the game moving; past LIMIT the
  # harness answers instead of the model. Its own answer keeps the count, so each further instant repeat costs one model call.
  class ZeroWatch
    LIMIT = 3
    MARK = 'in at most one frame'

    attr_reader :key, :count

    def self.from_events(events)
      watch = new
      events.each do |event|
        case event['type']
        when 'decision' then watch.capping(event.dig('choice', 'skill')) if event['justification'].to_s.include?(MARK)
        when 'action'
          result = event['result'].is_a?(Hash) ? event['result'] : {}
          watch.note(place: Ledger.place_of(result['from']), skill: event['skill'], stop: result['stopped_by'], frames: result['frames'])
        end
      end
      watch
    end

    def initialize
      @key = @acting = nil
      @count = 0
      @fresh = @spent = false
    end

    def capping(skill) = @acting = skill.to_s

    def note(place:, skill:, stop:, frames:)
      instant = !frames.nil? && frames.to_i <= 1
      if @acting
        @spent ||= @acting == 'explore' && instant
        @fresh = false
        @acting = nil
        return
      end
      key = [place, skill.to_s, stop.to_s]
      return (@key = nil) && (@count = 0) unless instant

      same = key == @key
      @count = same ? @count + 1 : 1
      @spent &&= same
      @key = key
      @fresh = true
    end

    def due?(place) = @fresh && @count >= LIMIT && @key&.first == place

    # A harness explore that came back instantly too is not offered again for this streak.
    def explore? = !@spent
  end
end
