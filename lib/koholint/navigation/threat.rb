require 'koholint/geometry'

module Koholint
  module Navigation
    # A threat is where a hostile thing is and how far its touch reaches; callers add their own safety margin.
    module Threat
      DEFAULT_REACH = 9

      module_function

      def of(entities)
        entities.select { |entity| entity[:kind].to_s == 'enemy' && entity[:x] && entity[:y] }
                .map { |entity| { type: entity[:type], x: entity[:x], y: entity[:y], reach: entity[:contact] || DEFAULT_REACH } }
      end

      def distance(threat, x, y) = [(threat[:x] - x).abs, (threat[:y] - y).abs].max

      def within?(threats, x, y, margin:) = threats.any? { |threat| distance(threat, x, y) <= threat[:reach] + margin }

      # Cells where Link, anywhere in the cell, may come within reach plus margin.
      def zone(threats, margin:)
        threats.flat_map do |threat|
          reach = threat[:reach] + (Geometry::CELL / 2) + margin
          Geometry::ROWS.times.flat_map { |row| Geometry::COLS.times.map { |col| [row, col] } }.select do |row, col|
            cx, cy = Geometry.center_of(row, col)
            (cx - threat[:x]).abs <= reach && (cy - threat[:y]).abs <= reach
          end
        end.uniq
      end

      def shield_margin = Geometry.fact(:shield_range).fetch('cells') * Geometry::CELL
    end
  end
end
