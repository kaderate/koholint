require 'koholint/geometry'

module Koholint
  module Vision
    class Grid
      ROWS = Geometry::ROWS
      COLS = Geometry::COLS
      SPRITE_WIDTH = 8
      SPRITE_HEIGHT = 16

      def initialize(cells:, static_sprites:, beliefs:, capabilities:)
        @cells = cells
        @beliefs = beliefs
        @capabilities = capabilities
        @sprites = {}
        static_sprites.each do |sprite|
          left = sprite['x'] - 8
          top = sprite['y'] - 16
          rows = (top.div(16)..(top + (sprite['height'] || SPRITE_HEIGHT) - 1).div(16)).select { |row| row.between?(0, ROWS - 1) }
          cols = (left.div(16)..(left + SPRITE_WIDTH - 1).div(16)).select { |col| col.between?(0, COLS - 1) }
          rows.product(cols).each { |cell| @sprites[cell] ||= sprite['pattern'] }
        end
      end

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
        @beliefs.query(appearance: static_sprite(row, col) || appearance(row, col), action: :walk, direction:, context: @capabilities)
      end

      def hole?(row, col) = holes.include?([row, col])

      # A hole pulls Link in from the cell beside it when his sprite overlaps its edge.
      def hole_margin
        @hole_margin ||= holes.flat_map { |row, col| [[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]] }
                              .select { |row, col| Geometry.in_grid?([row, col]) }.uniq - holes
      end

      private

      def holes
        @holes ||= begin
          looks = @cells.flatten.uniq.select { |look| @beliefs.hole?(look) }
          ROWS.times.to_a.product(COLS.times.to_a).select { |row, col| looks.include?(@cells[row][col]) }
        end
      end

      def check(row, col)
        raise ArgumentError, "cell out of range: #{row}, #{col}" unless Geometry.in_grid?([row, col])
      end
    end
  end
end
