require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/vision/screen_diff'
require 'koholint/vision/screen_vision'

module Koholint
  module Vision
    class GridBuilder
      # Link is drawn as two 8x16 sprites at his HRAM position and 8 px to the right, measured within 1 px.
      LINK_SPRITE_OFFSETS = [0, 8].freeze
      LINK_SPRITE_TOLERANCE = 2

      def self.link_sprite?(sprite, state)
        (sprite[:y] - state.y).abs <= LINK_SPRITE_TOLERANCE &&
          LINK_SPRITE_OFFSETS.any? { |offset| (sprite[:x] - state.x - offset).abs <= LINK_SPRITE_TOLERANCE }
      end

      def initialize(trace:, capabilities: Capabilities.new)
        @trace = trace
        @capabilities = capabilities
        @beliefs = Beliefs.new
        @previous = nil
        @emitted = nil
      end

      def observe(emulator, state)
        place = [state.room_id, state.map_id]
        snapshot = ScreenVision.snapshot(emulator, place:)
        if snapshot.overlay
          @previous = nil
          return nil
        end

        current = snapshot.sprites.reject { |sprite| self.class.link_sprite?(sprite, state) }.map { |s| s.slice(:x, :y, :pattern) }
        statics = static_sprites(place, current)
        @previous = { place:, sprites: current }
        emit(state.frame, snapshot, statics) if changed?(snapshot, statics)
        Grid.new(cells: grid_of(snapshot), static_sprites: statics.map { |s| s.transform_keys(&:to_s) }, beliefs: @beliefs,
                 capabilities: @capabilities)
      end

      private

      def static_sprites(place, current)
        return [] unless @previous && @previous[:place] == place

        (current & @previous[:sprites]).sort_by { |s| [s[:y], s[:x], s[:pattern]] }
      end

      def changed?(snapshot, statics)
        @emitted.nil? || @emitted[:snapshot].place != snapshot.place ||
          @emitted[:snapshot].terrain_hash != snapshot.terrain_hash || @emitted[:statics] != statics
      end

      def emit(frame, snapshot, statics)
        before = @emitted&.fetch(:snapshot)
        @trace.emit(:screen, frame:, place: snapshot.place, terrain_hash: snapshot.terrain_hash, objects_hash: snapshot.objects_hash,
                             grid: grid_of(snapshot), static_sprites: statics)
        cells = before && ScreenDiff.between(before, snapshot)
        @trace.emit(:screen_changed, frame:, place: snapshot.place, cells:) if cells && !cells.empty?
        @emitted = { snapshot:, statics: }
      end

      def grid_of(snapshot) = snapshot.cells.map { |row| row.map(&:appearance) }
    end
  end
end
