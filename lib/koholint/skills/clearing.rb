require 'koholint/geometry'

module Koholint
  module Skills
    # Runs the published capability that clears the object ahead of Link when a moving skill is blocked by it, once per cell.
    class Clearing
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze

      attr_reader :uses

      def self.of(context)
        registry = context[:registry]
        new(context) if !context[:composite] && context[:room_objects] && registry.respond_to?(:composites) && registry.composites.any? { |skill| skill.usable?(context[:held]) }
      end

      def initialize(context)
        @context = context
        @registry = context[:registry]
        @objects = context[:room_objects]
        @tried = []
        @uses = []
        @run = nil
      end

      def cells
        grid = @objects.call
        @registry.composites.select { |skill| skill.usable?(@context[:held]) }.each_with_object({}) do |skill, found|
          grid.each_with_index { |row, r| row.each_index { |c| found[[r, c]] ||= skill if row[c] == skill.entry['target']['object'] } }
        end
      end

      def active? = !@run.nil?

      def start(state, direction)
        cell = state.cell
        dr, dc = DELTAS.fetch(direction) { return nil }
        ahead = cell && [cell[0] + dr, cell[1] + dc]
        skill = ahead && cells[ahead]
        return nil unless skill && !@tried.include?(ahead)

        @tried << ahead
        @run = @registry.start(skill.name, state, { row: cell[0], col: cell[1], direction: direction.to_s }, @context)
        step(state)
      end

      def step(state)
        buttons = @run.next_input(state)
        return buttons if buttons

        @uses << @run.result(state)
        @run = nil
        []
      end
    end
  end
end
