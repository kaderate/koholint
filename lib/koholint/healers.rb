module Koholint
  # Places where Link's health rose after someone there spoke, before he walked a cell (so no heart he walked onto): where to heal, from observed facts only.
  class Healers
    attr_reader :places

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
        end
      end
      healers
    end

    def initialize
      @places = []
      @spoke = nil
      @health = nil
    end

    def heard(place)
      @spoke = { place:, health: @health } if place && @health && @spoke&.dig(:place) != place
    end

    def saw(place:, health:)
      return unless health

      @spoke = nil if @spoke && @spoke[:place] != place
      if @spoke && health > @spoke[:health]
        @places |= [place]
        @spoke = nil
      end
      @health = health
    end

    def moved = @spoke = nil
  end
end
