require 'set'
require 'koholint/geometry'

module Koholint
  module Navigation
    # Pushes in one room whose stones slide one cell and land fixed: a breadth-first search over stone positions from the cells Link reaches,
    # so the order of pushes that opens a cell is found before any stone moves.
    module Stones
      LIMIT = 4000

      module_function

      # step: ->(from, to, direction) Link walks from one cell to the next, stones aside; slide: ->(cell, direction) a stone may land in cell.
      # Returns, for each cell reachable after some pushes and not before, the fewest pushes that reach it ({ stand:, stone:, direction: } each).
      def plans(link:, stones:, fixed:, step:, slide:)
        start = { stones: stones.to_set, blocked: fixed.to_set, open: Set.new, link: }
        before = region(start, step)
        found = {}
        seen = Set.new
        queue = [[start, []]]
        until queue.empty? || seen.size >= LIMIT
          state, pushes = queue.shift
          reach = region(state, step)
          next unless seen.add?([state[:stones], state[:blocked], reach.min])

          (reach - before).each { |cell| found[cell] ||= pushes } unless pushes.empty?
          state[:stones].each do |stone|
            Geometry::DIRECTIONS.each do |direction|
              stand = Geometry.step(stone, Geometry::OPPOSITE.fetch(direction))
              far = Geometry.step(stone, direction)
              next unless stand && far && reach.include?(stand) && free?(state, far) && (state[:open].include?(far) || slide.(far, direction))

              moved = { stones: state[:stones] - [stone], blocked: state[:blocked] | [far], open: state[:open] | [stone], link: stand }
              queue << [moved, pushes + [{ stand:, stone:, direction: }]]
            end
          end
        end
        found
      end

      def region(state, step)
        cells = [state[:link]]
        cells.each do |cell|
          Geometry::DIRECTIONS.each do |direction|
            ahead = Geometry.step(cell, direction)
            next unless ahead && !cells.include?(ahead) && free?(state, ahead) && (state[:open].include?(ahead) || step.(cell, ahead, direction))

            cells << ahead
          end
        end
        cells.to_set
      end

      def free?(state, cell) = !state[:stones].include?(cell) && !state[:blocked].include?(cell)
    end
  end
end
