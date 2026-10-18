require 'koholint/vision/beliefs'
require 'koholint/vision/grid'

module Koholint
  module Vision
    class World
      def self.from_events(events, at_frame: nil)
        kept = at_frame ? events.select { |event| event['frame'] <= at_frame } : events
        new(kept)
      end

      attr_reader :beliefs

      def initialize(events)
        @beliefs = Beliefs.from_events(events)
        @places = {}
        events.each { |event| add_screen(event) if event['type'] == 'screen' }
      end

      # visits counts the screen events recorded for the place, not distinct arrivals
      def places = @places.transform_values(&:dup)

      def grid_for(place, capabilities)
        info = @places[place] or return nil
        Grid.new(cells: info[:grid], static_sprites: info[:static_sprites], beliefs: @beliefs, capabilities:)
      end

      private

      def add_screen(event)
        place = event['place']
        frame = event['frame']
        first = @places.dig(place, :first_frame) || frame
        visits = (@places.dig(place, :visits) || 0) + 1
        @places[place] = { visits:, grid: event['grid'], terrain_hash: event['terrain_hash'], first_frame: [first, frame].min,
                           last_frame: frame, static_sprites: event['static_sprites'] || [] }
      end
    end
  end
end
