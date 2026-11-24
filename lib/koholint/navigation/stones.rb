require 'set'
require 'koholint/geometry'

module Koholint
  module Navigation
    # Pushes in one room whose stones slide one cell and land fixed: a breadth-first search over stone positions from the cells Link reaches,
    # so the order of pushes that opens a cell is found before any stone moves.
    module Stones
      LIMIT = 1000

      module_function

      # step: ->(from, to, direction) Link walks from one cell to the next, stones aside; slide: ->(cell, direction) a stone may land in cell;
      # refused: [stone cell, direction] pushes known to leave the stone in place.
      # Returns the fewest pushes ({ stand:, stone:, direction: } each) for each cell reachable after some pushes and not before, and whether
      # the search ended before LIMIT states.
      def plans(link:, stones:, fixed:, step:, slide:, refused: [])
        steps = Hash.new { |memo, key| memo[key] = step.(*key) }
        slides = Hash.new { |memo, key| memo[key] = slide.(*key) }
        start = { stones: stones.to_set, blocked: fixed.to_set, open: Set.new, link: }
        before = region(start, steps)
        found = {}
        seen = Set.new
        queued = Set[[start[:stones], start[:blocked], link]]
        queue = [[start, []]]
        until queue.empty?
          return { plans: found, complete: false } if seen.size >= LIMIT

          state, pushes = queue.shift
          reach = region(state, steps)
          next unless seen.add?([state[:stones], state[:blocked], reach.min])

          (reach - before).each { |cell| found[cell] ||= pushes } unless pushes.empty?
          state[:stones].each do |stone|
            Geometry::DIRECTIONS.each do |direction|
              next if refused.include?([stone, direction])

              stand = Geometry.step(stone, Geometry::OPPOSITE.fetch(direction))
              far = Geometry.step(stone, direction)
              next unless stand && far && reach.include?(stand) && free?(state, far) && (state[:open].include?(far) || slides[[far, direction]])

              moved = { stones: state[:stones] - [stone], blocked: state[:blocked] | [far], open: state[:open] | [stone], link: stand }
              next unless queued.add?([moved[:stones], moved[:blocked], stand])

              queue << [moved, pushes + [{ stand:, stone:, direction: }]]
            end
          end
        end
        { plans: found, complete: true }
      end

      def region(state, steps)
        cells = Set[state[:link]]
        queue = [state[:link]]
        until queue.empty?
          cell = queue.shift
          Geometry::DIRECTIONS.each do |direction|
            ahead = Geometry.step(cell, direction)
            next unless ahead && !cells.include?(ahead) && free?(state, ahead) && (state[:open].include?(ahead) || steps[[cell, ahead, direction]])

            cells << ahead
            queue << ahead
          end
        end
        cells
      end

      def free?(state, cell) = !state[:stones].include?(cell) && !state[:blocked].include?(cell)
    end
  end
end
