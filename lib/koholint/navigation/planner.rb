require 'koholint/geometry'

module Koholint
  module Navigation
    class Planner
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
      EXPLORE = %i[yes unknown stale].freeze

      def self.direction_between(from, to)
        DELTAS.find { |_, (dr, dc)| [from[0] + dr, from[1] + dc] == to }&.first
      end

      def initialize(grid:, ledger:, place:, triggers: nil, mode: :explore, danger: nil, pushable: nil, contact: nil, closeness: nil)
        @danger = danger
        @contact = contact
        @closeness = closeness
        @pushable = pushable
        @mode = mode
        @triggers = triggers
        @grid = grid
        @ledger = ledger
        @place = place
        @avoided = []
      end

      def avoid(cell, direction)
        @avoided << [cell, direction]
      end

      def path(from:, to:, mode: @mode, doubt: true, forbid: true, cross_margin: true)
        margin = @grid.respond_to?(:hole_margin) ? @grid.hole_margin : []
        zones = Array(@danger&.call)
        kept = Array(@contact&.call)
        pushable = Array(@pushable&.call)
        [([zones, margin] if zones.any?), [kept, margin], ([kept, []] if margin.any? && cross_margin)].compact.each do |danger, beside|
          route = search(from:, to:, mode:, doubt:, forbid:, zones: danger, margin: beside)
          return route if route
        end
        search(from:, to:, mode:, doubt:, forbid:, zones: kept, margin: cross_margin ? [] : margin, push: pushable) if pushable.any?
      end

      def search(from:, to:, mode:, doubt:, forbid:, zones:, margin: [], push: [])
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
            next unless target && (target == to || (!margin.include?(target) && (!zones.include?(target) || away?(cell, target, zones))))
            next unless walkable?(cell, target, direction, allowed, doubt, forbid, push)

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

        free = path(from:, to:, doubt: false) || path(from:, to:, doubt: false, forbid: false)
        unless free
          kept = Array(@contact&.call)
          return 'no route over known cells' unless kept.any? && search(from:, to:, mode: @mode, doubt: false, forbid: false, zones: [])

          return "no route outside the enemy contact zones at one heart or less: #{kept.map { |row, col| "(#{row},#{col})" }.join(' ')}"
        end

        doubtful = []
        triggered = []
        free.each_cons(2) do |a, b|
          direction = self.class.direction_between(a, b)
          label = "(#{a[0]},#{a[1]}) #{direction}"
          doubtful << label if @ledger&.doubtful?(@place, a, direction) && @grid.passable(*b, direction) == :yes
          triggered << label if @triggers&.forbidden(@place, a)&.include?(direction)
        end
        parts = []
        parts << "doubtful edges #{doubtful.join(', ')}" if doubtful.any? || triggered.empty?
        parts << "edges where the game opens a dialogue by itself: #{triggered.join(', ')}; walk or step there explicitly if passing is the goal" if triggered.any?
        "no route: #{parts.join('; ')}"
      end

      private

      # Inside a zone Link may still move, as long as no step takes him closer to an enemy.
      def away?(cell, target, zones) = @closeness && zones.include?(cell) && @closeness.call(target) >= @closeness.call(cell)

      def inside?(cell) = cell.is_a?(Array) && cell[0].between?(0, Geometry::ROWS - 1) && cell[1].between?(0, Geometry::COLS - 1)

      def step(cell, direction)
        dr, dc = DELTAS.fetch(direction)
        target = [cell[0] + dr, cell[1] + dc]
        target if inside?(target)
      end

      def walkable?(cell, target, direction, allowed, doubt, forbid, push = [])
        return false if @avoided.include?([cell, direction])
        return false if forbid && @triggers&.forbidden(@place, cell)&.include?(direction)
        return true if push.include?(target)
        return false if @grid.static_sprite(*target)

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
