require 'koholint/skills/goto'
require 'koholint/talk_log'

module Koholint
  module Skills
    class Explore
      DIRECTIONS = %i[up right down left].freeze
      BUDGET_FRAMES = 600
      OUTWARD_FRAMES = 48
      STILL_FRAMES = 8
      LOCK_FRAMES = 16
      STALLED_ATTEMPTS = 3
      OBJECT_RANGE = 3
      UNKNOWN = %i[unknown stale].freeze

      class Known
        def initialize(grid, walked)
          @grid = grid
          @walked = walked
        end

        def static_sprite(row, col) = @grid.static_sprite(row, col)

        def passable(row, col, direction)
          belief = @grid.passable(row, col, direction)
          belief != :no && @walked.include?([row, col]) ? :yes : belief
        end

        def known?(cell) = !static_sprite(*cell) && (@walked.include?(cell) || DIRECTIONS.any? { |d| @grid.passable(*cell, d) == :yes })
      end

      class Leg < Goto::Run
        def initialize(planner:, **rest)
          @shared = planner
          super(context: {}, **rest)
        end

        private

        def planner_for(_context) = @shared
      end

      class Run < Execution
        def initialize(direction:, context:, **rest)
          super(**rest)
          @hint = direction
          @place = room(@start)
          @ledger = context[:ledger]
          @talk_log = context[:talk_log]
          @log = context[:explore_log]
          @walked = (@log ? @log.walked(@place) : []) | [@start.cell].compact
          grid = context[:grid]
          @known = grid && Known.new(grid, @walked)
          @planner = @known && Navigation::Planner.new(grid: @known, ledger: @ledger, place: @place, triggers: context[:triggers], mode: :free_only)
          @objects = grid ? TalkLog.objects(grid) : []
          @cell = @start.cell
          @offered = near_objects(@cell)
          @untried = []
          @exits = []
          @blocked = []
          @crossed = []
          @excluded = []
          @walls = @log ? @log.walls(@place) : []
          @new_walls = []
          @cells_walked = 0
          @stalled = 0
          @legs = 0
          @locked = 0
          @leg = @outward = @target = @stop = @heading = nil
        end

        def result(state = @last)
          merged = super.merge(place_changed: room(state) != @place, cells_walked: @cells_walked, legs: @legs, target: target_summary,
                               crossed: @crossed.map(&:dup), walls: @new_walls.map { |row, col| { row:, col: } }, blocked_edges: @blocked.map(&:dup), exits: @exits.map(&:dup),
                               offered: @offered.map { |row, col| { row:, col: } })
          merged[:untried_objects] = @untried.map { |row, col| { row:, col: } } if @stopped_by == :untried_object
          merged[:tried_exits] = @log ? @log.tried_exits(@place) : [] if @stopped_by == :no_frontier
          merged[:cause] = @planner ? 'no current cell' : 'no grid' if @stopped_by == :no_frontier && !(@planner && @attempt_from)
          merged
        end

        private

        def hard_cap = Float::INFINITY

        def blocked_at_for(_state) = @blocked.last&.dup

        def input_for(state)
          return depart if room(state) != @place
          return finish(:damage) if state.hp.to_i < @start.hp.to_i
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?

          @locked = state.locked? ? @locked + 1 : 0
          return finish(:locked) if @locked >= LOCK_FRAMES

          enter(state)
          return finish(:untried_object) if @untried.any?
          return finish(:budget) if @frames >= BUDGET_FRAMES

          loop do
            buttons = if @leg then lead(state)
                      elsif @outward then outward(state)
                      else begin_attempt(state)
                      end
            return heading(buttons) if buttons
            return finish(@stop) if @stop
          end
        end

        def heading(buttons)
          direction = (buttons & DIRECTIONS).first
          @heading = direction if direction
          buttons
        end

        def depart
          @exits << { row: @cell[0], col: @cell[1], direction: @heading, outcome: :left } if @cell && @heading
          finish(:new_place)
        end

        def enter(state)
          cell = state.cell
          return if cell.nil? || cell == @cell

          @cell = cell
          @cells_walked += 1
          @walked << cell unless @walked.include?(cell)
          @untried = near_objects(cell) - @offered
          @offered.concat(@untried)
        end

        def near_objects(cell)
          return [] unless cell

          @objects.filter_map do |cells|
            near = cells.map { |r, c| (r - cell[0]).abs + (c - cell[1]).abs }.min <= OBJECT_RANGE
            cells.first if near && !@talk_log&.tried?(@objects, @place, cells) && !@log&.offered?(@place, cells.first)
          end
        end

        def begin_attempt(state)
          @attempt_from = state.cell
          target = @planner && @attempt_from && candidates(@attempt_from).first
          unless target
            @stop = :no_frontier
            return nil
          end

          @target = target

          @legs += 1
          if @target[:path].size < 2
            outward_from(state)
          else
            row, col = @target[:cell]
            @leg = Leg.new(skill: 'goto', params: { row:, col: }, state:, target: @target[:cell], planner: @planner)
            @leg.triggers = @triggers
          end
          nil
        end

        def lead(state)
          buttons = @leg.next_input(state)
          return buttons if buttons

          outcome = @leg.result(state)
          @crossed.concat(outcome[:crossed])
          @leg = nil
          return outward_from(state) if outcome[:stopped_by] == :done

          block(outcome[:blocked_at]) if outcome[:blocked_at]
          @excluded << @target.values_at(:cell, :direction)
          attempt_over(state)
        end

        def outward_from(state)
          @outward = { frames: 0, still: 0, position: [state.x, state.y] }
          nil
        end

        def outward(state)
          cell, direction = @target.values_at(:cell, :direction)
          if state.cell && state.cell != cell
            @crossed << [*cell, direction] if state.cell == neighbour(cell, direction)
            @outward = nil
            return attempt_over(state)
          end
          position = [state.x, state.y]
          @outward[:still] = @outward[:frames].positive? && position == @outward[:position] ? @outward[:still] + 1 : 0
          @outward[:position] = position
          return outward_blocked(state, cell, direction) if @outward[:still] >= STILL_FRAMES || @outward[:frames] >= OUTWARD_FRAMES

          @outward[:frames] += 1
          [direction]
        end

        def outward_blocked(state, cell, direction)
          edge = { row: cell[0], col: cell[1], direction: }
          block(edge)
          @exits << edge.merge(outcome: :blocked) if @target[:kind] == :exit
          @new_walls << neighbour(cell, direction) if @target[:kind] == :frontier
          @walls << neighbour(cell, direction) if @target[:kind] == :frontier
          @outward = nil
          attempt_over(state)
        end

        def block(edge)
          @blocked << edge.dup
          @planner.avoid([edge[:row], edge[:col]], edge[:direction])
        end

        def attempt_over(state)
          @stalled = state.cell == @attempt_from ? @stalled + 1 : 0
          @stop = :blocked if @stalled >= STALLED_ATTEMPTS
          nil
        end

        def candidates(from)
          paths = {}
          found = (0...Geometry::ROWS).to_a.product((0...Geometry::COLS).to_a).flat_map do |cell|
            next [] unless cell == from || @known.known?(cell)

            DIRECTIONS.filter_map do |direction|
              kind = kind_of(cell, direction)
              next unless kind && open?(cell, direction)

              path = paths.fetch(cell) { paths[cell] = @planner.path(from:, to: cell) } or next
              { kind:, cell:, direction:, path: }
            end
          end
          found.sort_by do |c|
            [@hint.nil? || c[:direction] == @hint ? 0 : 1, c[:path].size, c[:kind] == :exit ? 0 : 1, *c[:cell], DIRECTIONS.index(c[:direction])]
          end
        end

        def kind_of(cell, direction)
          ahead = neighbour(cell, direction)
          return (@log&.tried?(@place, cell, direction) ? nil : :exit) unless ahead

          :frontier if !@walls.include?(ahead) && !@known.static_sprite(*ahead) && UNKNOWN.include?(@known.passable(*ahead, direction))
        end

        def open?(cell, direction)
          edge = { row: cell[0], col: cell[1], direction: }
          !@excluded.include?([cell, direction]) && !@blocked.include?(edge) && !@ledger&.doubtful?(@place, cell, direction) &&
            !Array(@triggers&.forbidden(@place, cell)).include?(direction)
        end

        def neighbour(cell, direction)
          dr, dc = Navigation::Planner::DELTAS.fetch(direction)
          row = cell[0] + dr
          col = cell[1] + dc
          [row, col] if row.between?(0, Geometry::ROWS - 1) && col.between?(0, Geometry::COLS - 1)
        end

        def target_summary
          return nil unless @target

          { kind: @target[:kind], row: @target[:cell][0], col: @target[:cell][1], direction: @target[:direction] }
        end
      end

      def name = 'explore'

      def params_schema
        { type: 'object', title: name, properties: { direction: { type: 'string', enum: DIRECTIONS.map(&:to_s) } },
          additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[direction])
        return {} unless params.key?(:direction)

        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "explore: direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)

        { direction: }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, direction: params[:direction], context:)
      end
    end
  end
end
