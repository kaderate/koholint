require 'koholint/skills/execution'
require 'koholint/navigation/planner'

module Koholint
  module Skills
    class Goto
      STILL_FRAMES = 8
      SETTLE_FRAMES = 16

      class Run < Execution
        def initialize(target:, context:, **rest)
          super(**rest)
          @target = target
          @planner = planner_for(context)
          @path = plan(@start.cell)
          @index = 0
          @arrived_by = nil
          @settle = 0
          @heading = nil
          @position = [@start.x, @start.y]
          @still = 0
          @idle_reason = nil
          @crossed = []
        end

        def result(state = @last)
          merged = super.merge(path_length: @initial_length.to_i, steps_done: @index, crossed: @crossed.map(&:dup))
          merged[:cause] = @cause if @cause && !@path
          merged
        end

        private

        def centres? = true

        def blocked_direction = @heading

        def planner_for(context)
          grid = context[:grid]
          return nil unless grid

          Navigation::Planner.new(grid:, ledger: context[:ledger], place: [@start.room_id, @start.map_id])
        end

        def plan(cell)
          path = cell && @planner&.path(from: cell, to: @target)
          @cause = path ? nil : why_not(cell)
          @initial_length ||= path ? path.size - 1 : 0
          path
        end

        def why_not(cell)
          return 'no grid' unless @planner

          cell ? @planner.why_not(from: cell, to: @target) : 'no current cell'
        end

        def input_for(state)
          track(state) if @frames.positive?
          return finish(@idle_reason) if @idle_reason
          return idle(:no_path) unless @path
          return idle(:done) if @path.size < 2 && @frames.zero?
          return finish(:room_change) if room(state) != room(@start)
          return finish(:damage) if state.hp.to_i < @start.hp.to_i
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?
          return finish(:blocked) if @still >= STILL_FRAMES

          advance(state)
        end

        def idle(reason)
          @idle_reason = reason
          []
        end

        def advance(state)
          cell = state.cell
          return press(@heading) if cell.nil? && @heading

          sync(cell)
          return finish(:no_path) unless @path
          return finish(:done) if cell == @target

          direction = Navigation::Planner.direction_between(@path[@index], @path[@index + 1])
          settle(state, cell, direction) || press(direction)
        end

        def sync(cell)
          return unless cell

          at = @path.index(cell)
          if at
            if at > @index
              (@index...at).each do |i|
                @crossed << [*@path[i], Navigation::Planner.direction_between(@path[i], @path[i + 1])]
              end
              @index = at
              @arrived_by = Navigation::Planner.direction_between(@path[at - 1], cell)
              @settle = 0
            end
          else
            @path = plan(cell)
            @index = 0
            @arrived_by = nil
            @settle = 0
          end
        end

        def settle(state, cell, direction)
          return nil if @arrived_by == direction || @settle >= SETTLE_FRAMES

          dx, dy = Geometry.offset(state.x, state.y, cell)
          horizontal = %i[left right].include?(direction)
          off = horizontal ? dy : dx
          return nil if off.abs <= Geometry::ALIGN_TOLERANCE

          @settle += 1
          toward = horizontal ? (off.positive? ? :up : :down) : (off.positive? ? :left : :right)
          press(toward)
        end

        def press(direction)
          @heading = direction
          [direction]
        end

        def track(state)
          position = [state.x, state.y]
          @still = position == @position ? @still + 1 : 0
          @position = position
        end
      end

      def name = 'goto'

      def params_schema
        { type: 'object', title: name,
          properties: { row: { type: 'integer', minimum: 0, maximum: Geometry::ROWS - 1 },
                        col: { type: 'integer', minimum: 0, maximum: Geometry::COLS - 1 } },
          required: %w[row col], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[row col])
        raise ArgumentError, "goto: row must be 0..#{Geometry::ROWS - 1}" unless params[:row].is_a?(Integer) && params[:row].between?(0, Geometry::ROWS - 1)
        raise ArgumentError, "goto: col must be 0..#{Geometry::COLS - 1}" unless params[:col].is_a?(Integer) && params[:col].between?(0, Geometry::COLS - 1)

        { row: params[:row], col: params[:col] }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, target: [params[:row], params[:col]], context:)
      end
    end
  end
end
