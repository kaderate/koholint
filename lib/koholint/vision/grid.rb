module Koholint
  module Vision
    class Grid
      ROWS = 8
      COLS = 10

      def initialize(cells:, static_sprites:, beliefs:, capabilities:)
        @cells = cells
        @beliefs = beliefs
        @capabilities = capabilities
        @sprites = {}
        static_sprites.each do |sprite|
          row = (sprite['y'] - 8) / 16
          col = (sprite['x'] - 4) / 16
          next unless row.between?(0, ROWS - 1) && col.between?(0, COLS - 1)

          @sprites[[row, col]] ||= sprite['pattern']
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
