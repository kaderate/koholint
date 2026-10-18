module Koholint
  module Vision
    module ScreenDiff
      module_function

      def between(before, after)
        return nil if before.overlay || after.overlay || before.place != after.place || before.scroll != after.scroll
        return [] if before.terrain_hash == after.terrain_hash

        before.cells.each_with_index.flat_map do |row, r|
          row.each_with_index.filter_map do |cell, c|
            to = after.cells[r][c].appearance
            { row: r, col: c, from: cell.appearance, to: } if cell.appearance != to
          end
        end
      end
    end
  end
end
