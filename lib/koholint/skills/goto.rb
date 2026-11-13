require 'koholint/skills/execution'
require 'koholint/navigation/planner'

module Koholint
  module Skills
    class Goto
      STILL_FRAMES = 8
      SETTLE_FRAMES = 16
      SETTLE_STILL = 2
      REPLANS = 3
      BACK = { up: :down, down: :up, left: :right, right: :left }.freeze

      class Run < Execution
        def initialize(target:, context:, **rest)
          super(**rest)
          @target = target
          @planner = planner_for(context)
          @path = initial_plan
          @index = 0
          @arrived_by = nil
          @settle = 0
          @heading = nil
          @position = [@start.x, @start.y]
          @still = 0
          @idle_reason = nil
          @crossed = []
          @replans = 0
          @avoided = []
          @centred = nil
          @exact = false
          @recentre = nil
          @clearing = clearing_for(context)
        end

        def result(state = @last)
          merged = super.merge(path_length: @initial_length.to_i, steps_done: @index, crossed: @crossed.map(&:dup))
          merged[:clears] = @clearing.uses if @clearing&.uses&.any?
          merged[:replans] = @replans if @replans.positive?
          merged[:avoided] = @avoided.map(&:dup) if @avoided.any?
          merged[:cause] = @cause if @cause && !@path
          merged
        end

        private

        def centres? = true

        def waits_through_doors? = true

        def blocked_direction = @heading

        def planner_for(context)
          grid = context[:grid]
          return nil unless grid

          Navigation::Planner.new(grid:, ledger: context[:ledger], place: [@start.room_id, @start.map_id], triggers: context[:triggers], danger: danger_of(context), pushable: pushable_of(context))
        end

        def initial_plan = plan(@start.cell)

        def restart(state, path)
          @path = path
          @index = 0
          @arrived_by = @idle_reason = @centring = @recentre = nil
          @exact = false
          @settle = 0
          @still = 0
          @heading = nil
          @position = [state.x, state.y]
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
          return clearing(state) if @clearing&.active?
          return finish(@idle_reason) if @idle_reason
          return idle(:no_path) unless @path
          return idle(:done) if @path.size < 2 && @frames.zero?
          return finish(:room_change) if room(state) != room(@start)
          return finish(:damage) if state.hp.to_i < @start.hp.to_i
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?
          return recentre(state) if @recentre
          return @clearing&.start(state, @heading) || centre_exactly(state) || reroute(state) || finish(:blocked) if @still >= STILL_FRAMES

          advance(state)
        end

        def clearing_for(context) = Clearing.of(context)

        # Narrow passages (stairs, gaps) take Link only when exactly centred across the move; the tolerance that suffices elsewhere bumps him.
        def centre_exactly(state)
          cell = state.cell
          return nil unless cell && @heading && @centred != [cell, @heading]

          dx, dy = Geometry.offset(state.x, state.y, cell)
          return nil if (%i[left right].include?(@heading) ? dy : dx).zero?

          @centred = [cell, @heading]
          @recentre = @heading
          @still = 0
          recentre(state)
        end

        # Back off to the cell's centre along the move, centre across it, then move on with no tolerance.
        def recentre(state)
          heading = @recentre
          if state.cell == @centred.first
            horizontal = %i[left right].include?(heading)
            dx, dy = Geometry.offset(state.x, state.y, state.cell)
            along, across = horizontal ? [dx, dy] : [dy, dx]
            ahead = Navigation::Planner::DELTAS.fetch(heading)[horizontal ? 1 : 0]
            direction = if (along * ahead).positive? then BACK.fetch(heading)
                        elsif !across.zero? then horizontal ? (across.positive? ? :up : :down) : (across.positive? ? :left : :right)
                        end
          end
          if @still >= STILL_FRAMES || state.cell != @centred.first || (direction && forbidden_at(state).include?(direction))
            @recentre = nil
            return reroute(state) || finish(:blocked)
          end
          return [direction] if direction

          @recentre = nil
          @exact = true
          @arrived_by = nil
          @settle = 0
          @still = 0
          press(heading)
        end

        # A blocked edge the grid believed open: avoid it and plan again from here, like talk_to, up to REPLANS times.
        def reroute(state)
          cell = state.cell
          return nil unless @planner && cell && @heading && @replans < REPLANS

          @planner.avoid(cell, @heading)
          path = @planner.path(from: cell, to: @target) or return nil
          @replans += 1
          @avoided << { row: cell[0], col: cell[1], direction: @heading }
          restart(state, path)
          advance(state)
        end

        def clearing(state)
          @still = 0
          @clearing.step(state)
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
              @exact = false
            end
          else
            @path = plan(cell)
            @index = 0
            @arrived_by = nil
            @settle = 0
          end
        end

        def settle(state, cell, direction)
          @settle = SETTLE_FRAMES if @settle.positive? && @still >= SETTLE_STILL
          return nil if @arrived_by == direction || @settle >= SETTLE_FRAMES

          dx, dy = Geometry.offset(state.x, state.y, cell)
          horizontal = %i[left right].include?(direction)
          off = horizontal ? dy : dx
          return nil if off.abs <= (@exact ? 0 : Geometry::ALIGN_TOLERANCE)

          toward = horizontal ? (off.positive? ? :up : :down) : (off.positive? ? :left : :right)
          return nil if forbidden_at(state).include?(toward)

          @settle += 1
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
