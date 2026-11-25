require 'koholint/geometry'

module Koholint
  module Vision
    class Grid
      ROWS = Geometry::ROWS
      COLS = Geometry::COLS
      SPRITE_WIDTH = 8
      SPRITE_HEIGHT = 16

      def initialize(cells:, static_sprites:, beliefs:, capabilities:, hole_objects: [], link: nil)
        @cells = cells
        @hole_objects = hole_objects
        @beliefs = beliefs
        @capabilities = capabilities
        @sprites = {}
        static_sprites.each { |sprite| (self.class.sprite_cells(sprite) - [link]).each { |cell| @sprites[cell] ||= sprite['pattern'] } }
      end

      # Half of the sprite each way, so a few pixels poking into a cell do not wall it off.
      def self.sprite_cells(sprite)
        height = sprite['height'] || SPRITE_HEIGHT
        rows = halves(sprite['y'] - 16, height).select { |row| row.between?(0, ROWS - 1) }
        cols = halves(sprite['x'] - 8, SPRITE_WIDTH).select { |col| col.between?(0, COLS - 1) }
        rows.product(cols)
      end

      def self.halves(start, size) = (start.div(16)..(start + size - 1).div(16)).select { |cell| ([start + size, (cell + 1) * 16].min - [start, cell * 16].max) * 2 >= size }

      def appearance(row, col)
        check(row, col)
        @cells[row][col]
      end

      def static_sprite(row, col)
        check(row, col)
        @sprites[[row, col]]
      end

      def passable(row, col, direction)
        check(row, col)
        return :no if @hole_objects.include?([row, col])

        @beliefs.query(appearance: static_sprite(row, col) || appearance(row, col), action: :walk, direction:, context: @capabilities)
      end

      def hole?(row, col) = holes.include?([row, col])

      # Walkable floor by the background tile alone, whatever sprite stands on it.
      def floor?(row, col) = Geometry::DIRECTIONS.any? { |direction| @beliefs.query(appearance: appearance(row, col), action: :walk, direction:, context: @capabilities) == :yes }

      # A hole pulls Link in from the cell beside it when his sprite overlaps its edge.
      def hole_margin
        @hole_margin ||= holes.flat_map { |row, col| [[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]] }
                              .select { |row, col| Geometry.in_grid?([row, col]) }.uniq - holes
      end

      private

      def holes
        @holes ||= begin
          looks = @cells.flatten.uniq.select { |look| @beliefs.hole?(look) }
          ROWS.times.to_a.product(COLS.times.to_a).select { |row, col| looks.include?(@cells[row][col]) } | @hole_objects
        end
      end

      def check(row, col)
        raise ArgumentError, "cell out of range: #{row}, #{col}" unless Geometry.in_grid?([row, col])
      end
    end
  end
end
