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

      # A look Link fell through more often than he walked onto it; each fall records four directions on one frame.
      def hole?(row, col)
        evidence = @beliefs.evidence_for(appearance(row, col), :walk)
        falls = evidence.select { |entry| entry[:method] == 'fall' }.map { |entry| entry[:frame] }.uniq.size
        falls > evidence.count { |entry| entry[:result] == :yes }
      end

      # A hole pulls Link in from the cell beside it when his sprite overlaps its edge.
      def hole_margin
        cells = ROWS.times.to_a.product(COLS.times.to_a)
        holes = cells.select { |row, col| hole?(row, col) }
        holes.flat_map { |row, col| [[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]] }
             .select { |row, col| row.between?(0, ROWS - 1) && col.between?(0, COLS - 1) }.uniq - holes
      end

      private

      def check(row, col)
        raise ArgumentError, "cell out of range: #{row}, #{col}" unless row.between?(0, ROWS - 1) && col.between?(0, COLS - 1)
      end
    end
  end
end
