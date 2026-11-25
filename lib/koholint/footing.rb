require 'koholint/entities'
require 'koholint/geometry'

module Koholint
  # The cell of floor that gives way under Link's foot point (the link_foot fact) and the frames it has left, from the game's crumble_timer.
  class Footing
    FOOT = Geometry.fact(:link_foot).transform_keys(&:to_sym).freeze

    def self.feet(x, y) = [Geometry.cell_for(x + FOOT[:dx], y + FOOT[:dy])].compact

    def observe(state, objects)
      @objects = objects
      @place = state.place
    end

    def under(state)
      return [] unless state.x && state.place == @place

      Footing.feet(state.x, state.y).filter_map do |cell|
        limit = Entities.object_catalogue.dig(@objects.dig(*cell), :give_way) or next
        { cell:, left: limit - state.crumble_timer.to_i }
      end
    end

    def hole?(state, cell) = state.place == @place && Entities.object_catalogue.dig(@objects&.dig(*cell), :kind) == :hole
  end
end
