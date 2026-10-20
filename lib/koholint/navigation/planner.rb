require 'koholint/geometry'

module Koholint
  module Navigation
    class Planner
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
      EXPLORE = %i[yes unknown stale].freeze

      def self.direction_between(from, to)
        DELTAS.find { |_, (dr, dc)| [from[0] + dr, from[1] + dc] == to }&.first
      end

      def initialize(grid:, ledger:, place:)
        @grid = grid
        @ledger = ledger
        @place = place
        @avoided = []
      end

      def avoid(cell, direction)
        @avoided << [cell, direction]
      end

      def path(from:, to:, mode: :explore, doubt: true)
        return nil unless inside?(from) && inside?(to)
        return [from] if from == to

        allowed = mode == :free_only ? %i[yes] : EXPLORE
        best = { [from, nil] => [0, 0] }
        parents = {}
        queue = [[0, 0, from, nil]]
        until queue.empty?
          steps, turns, cell, heading = queue.shift
          next if best[[cell, heading]] != [steps, turns]
          return rebuild(parents, [cell, heading]) if cell == to

          DELTAS.each_key do |direction|
            target = step(cell, direction)
            next unless target && walkable?(cell, target, direction, allowed, doubt)

            cost = [steps + 1, turns + (heading && heading != direction ? 1 : 0)]
            key = [target, direction]
            next if best[key] && (best[key] <=> cost) <= 0

            best[key] = cost
            parents[key] = [cell, heading]
            queue << [*cost, target, direction]
          end
          queue.sort_by! { |entry| entry.first(2) }
        end
        nil
      end

      def why_not(from:, to:)
        return 'no current cell' unless inside?(from) && inside?(to)
        return 'target is current cell' if from == to
        return 'target covered by an object' if @grid.static_sprite(*to)
        return 'target believed blocked' if DELTAS.each_key.all? { |direction| @grid.passable(*to, direction) == :no }

        free = path(from:, to:, doubt: false)
        return 'no route over known cells' unless free

        edges = free.each_cons(2).filter_map do |a, b|
          direction = self.class.direction_between(a, b)
          "(#{a[0]},#{a[1]}) #{direction}" if @ledger&.doubtful?(@place, a, direction) && @grid.passable(*b, direction) == :yes
        end
        "no route: doubtful edges #{edges.join(', ')}"
      end

      private

      def inside?(cell) = cell.is_a?(Array) && cell[0].between?(0, Geometry::ROWS - 1) && cell[1].between?(0, Geometry::COLS - 1)

      def step(cell, direction)
        dr, dc = DELTAS.fetch(direction)
        target = [cell[0] + dr, cell[1] + dc]
        target if inside?(target)
      end

      def walkable?(cell, target, direction, allowed, doubt)
        return false if @grid.static_sprite(*target)
        return false if @avoided.include?([cell, direction])

        belief = @grid.passable(*target, direction)
        return false if doubt && belief == :yes && @ledger&.doubtful?(@place, cell, direction)

        allowed.include?(belief)
      end

      def rebuild(parents, key)
        cells = [key[0]]
        while (key = parents[key])
          cells.unshift(key[0])
        end
        cells
      end
    end
  end
end
