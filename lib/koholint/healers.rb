require 'set'

module Koholint
  # Places where Link's health rose after someone there spoke, before he walked a cell (so no heart he walked onto): where to heal, from observed facts only.
  # Also the largest single hp drop seen (the measured hit), overall and per place, the places seen, and the heal detours sent since the last heal.
  class Healers
    attr_reader :places, :hit, :hits, :detours

    def self.from_events(events)
      healers = new
      events.each do |event|
        case event['type']
        when 'decision'
          input = event['input']
          next unless input.is_a?(Hash)

          place = [input['room_id'], input['map_id']]
          healers.saw(place:, health: input['hp'])
          healers.heard(place) if input['dialog_state'].to_i != 0
        when 'action' then healers.moved if event.dig('result', 'moved_cells').to_i.positive?
        when 'objective' then healers.detoured if event['status'] == 'started' && event.dig('target', 'heal_below')
        end
      end
      healers
    end

    def initialize
      @places = []
      @spoke = nil
      @health = nil
      @hit = nil
      @hits = {}
      @seen = Set.new
      @detours = 0
    end

    # A place Link was seen in where no measured hit reaches health: a place never seen is unknown, so unsafe.
    def dangerous(health) = @hits.filter_map { |place, hit| place if hit >= health }

    def safe?(place, health) = @seen.include?(place) && @hits.fetch(place, 0) < health

    def detoured = @detours += 1

    def heard(place)
      @spoke = { place:, health: @health } if place && @health && @spoke&.dig(:place) != place
    end

    def saw(place:, health:)
      return unless health

      @spoke = nil if @spoke && @spoke[:place] != place
      if @spoke && health > @spoke[:health]
        @places |= [place]
        @spoke = nil
        @detours = 0
      end
      if @health && health < @health
        @hit = [@hit.to_i, @health - health].max
        @hits[place] = [@hits[place].to_i, @health - health].max
      end
      @seen << place
      @health = health
    end

    def moved = @spoke = nil
  end
end
