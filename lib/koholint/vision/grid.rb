module Koholint
  module Vision
    class Grid
      ROWS = 8
      COLS = 10
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

      private

      def check(row, col)
        raise ArgumentError, "cell out of range: #{row}, #{col}" unless row.between?(0, ROWS - 1) && col.between?(0, COLS - 1)
      end
    end
  end
end
