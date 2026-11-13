require 'koholint/skills/goto'
require 'koholint/explore_log'
require 'koholint/talk_log'

module Koholint
  module Skills
    class Explore
      DIRECTIONS = %i[up right down left].freeze
      BUDGET_FRAMES = 600
      OUTWARD_FRAMES = 48
      STILL_FRAMES = 8
      LOCK_FRAMES = 16
      STUCK_ATTEMPTS = 3
      FRUITLESS_ATTEMPTS = 3
      OBJECT_RANGE = 3
      ENTER_FRAMES = 120
      UNKNOWN = %i[unknown stale].freeze
      SIDES = { up: ->(row, _col) { row.zero? }, down: ->(row, _col) { row == Geometry::ROWS - 1 },
                left: ->(_row, col) { col.zero? }, right: ->(_row, col) { col == Geometry::COLS - 1 } }.freeze

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
        def initialize(planner:, clearing: nil, **rest)
          @shared = planner
          @shared_clearing = clearing
          super(context: {}, **rest)
        end

        private

        def planner_for(_context) = @shared

        def clearing_for(_context) = @shared_clearing

        # Explore reroutes a blocked leg itself (it blocks the edge and picks the next target), so the leg reports the block at once.
        def reroute(_state) = nil
      end

      class Run < Execution
        def initialize(direction:, context:, **rest)
          super(**rest)
          @aim = context[:aim] || {}
          @hint = direction || @aim[:direction]
          @place = room(@start)
          @ledger = context[:ledger]
          @talk_log = context[:talk_log]
          @log = context[:explore_log]
          @walked = (@log ? @log.walked(@place) : []) | [@start.cell].compact
          @fresh = @log && !@log.surveyed?(@place)
          grid = context[:grid]
          @known = grid && Known.new(grid, @walked)
          @planner = @known && Navigation::Planner.new(grid: @known, ledger: @ledger, place: @place, triggers: context[:triggers], mode: :free_only, danger: danger_of(context), pushable: pushable_of(context))
          @pushable = Array(pushable_of(context)&.call)
          @clearing = Clearing.of(context)
          @objects = grid ? TalkLog.objects(grid) : []
          @doors = Array(context[:objects]&.call).select { |object| object[:kind].to_s == 'door' && object[:cell][0] < Geometry::ROWS - 1 }.map { |object| object[:cell] }
          @survey = @known && survey
          @route = @unreachable = @dead_end = nil
          @entering = 0
          @cell = @start.cell
          @offered = near_objects(@cell)
          @untried = []
          @exits = []
          @blocked = []
          @crossed = []
          @excluded = []
          # Runs without the capability logged clearable objects as walls.
          @failed = @log ? @log.failed_clears(@place) : []
          @walls = (@log ? @log.walls(@place) : []) - (Array(@clearing&.cells&.keys) - @failed)
          @new_walls = []
          @cells_walked = 0
          @stuck = 0
          @fruitless = 0
          @found = false
          @legs = 0
          @locked = 0
          @leg = @outward = @target = @stop = @heading = @idle = @fail_cause = nil
        end

        def result(state = @last)
          merged = super.merge(place_changed: room(state) != @place, cells_walked: @cells_walked, legs: @legs, target: target_summary,
                               crossed: @crossed.map(&:dup), walls: @new_walls.map { |row, col| { row:, col: } }, blocked_edges: @blocked.map(&:dup), exits: @exits.map(&:dup),
                               offered: @offered.map { |row, col| { row:, col: } })
          merged[:clears] = @clearing.uses if @clearing&.uses&.any?
          merged[:survey] = @survey.merge(pending: pending?) if @survey
          merged[:route] = @route if @route
          merged[:unreachable] = @unreachable if @unreachable
          merged[:dead_end] = true if @dead_end
          merged[:cause] = @fail_cause if @stopped_by == :blocked && @fail_cause
          merged[:untried_objects] = @untried.map { |row, col| { row:, col: } } if @stopped_by == :untried_object
          merged[:tried_exits] = @log ? @log.tried_exits(@place) : [] if @stopped_by == :no_frontier
          merged[:cause] = @planner ? 'no current cell' : 'no grid' if @stopped_by == :no_frontier && !(@planner && @attempt_from)
          merged
        end

        private

        def hard_cap = Float::INFINITY

        def blocked_at_for(_state) = @blocked.last&.dup

        def input_for(state)
          return finish(@idle) if @idle
          return @clearing.step(state) if @clearing&.active? && !@leg
          return depart(state) if room(state) != @place
          return harmed if state.hp.to_i < @start.hp.to_i
          return stop_now(:dialogue) if state.dialog_open?
          return entering if walking_in?(state)

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
            return stop_now(@stop) if @stop
          end
        end

        def stop_now(reason)
          return finish(reason) if @frames.positive?

          @idle = reason
          []
        end

        def harmed
          fail_step(*@target.values_at(:cell, :direction)) if @target && (@leg || @outward)
          finish(:damage)
        end

        def heading(buttons)
          direction = (buttons & DIRECTIONS).first
          @heading = direction if direction
          buttons
        end

        def depart(state)
          to = room(state)
          if @target && @target[:kind] == :door && (@outward || @entering.positive?)
            @exits << { row: @target[:cell][0], col: @target[:cell][1], direction: :up, outcome: :left, to:, kind: :door }
          elsif @cell && @heading && neighbour(@cell, @heading)
            @exits << ExploreLog.door_exit(@cell, neighbour(@cell, @heading), @doors, to)
          elsif @cell && @heading
            @exits << { row: @cell[0], col: @cell[1], direction: @heading, outcome: :left, to:, **(@walked_in ? { walk_in: true } : {}) }
          end
          finish(@log&.known?(to) ? :known_place : :new_place)
        end

        def walking_in?(state) = @entering.positive? || door_walk?(state)

        def entering
          @entering += 1
          return finish(:locked) if @entering > ENTER_FRAMES

          []
        end

        def survey
          sides = SIDES.to_h do |side, border|
            cells = Geometry::ROWS.times.to_a.product(Geometry::COLS.times.to_a).select do |row, col|
              border.(row, col) && @known.known?([row, col]) && DIRECTIONS.any? { |d| @known.passable(row, col, d) == :yes }
            end
            [side, cells.map { |row, col| { row:, col: } }]
          end
          { sides: sides.reject { |_, cells| cells.empty? }, doors: @doors.map { |row, col| { row:, col: } } }
        end

        def enter(state)
          cell = state.cell
          return if cell.nil? || cell == @cell

          @cell = cell
          @cells_walked += 1
          @found = true unless @walked.include?(cell)
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
            @leg = Leg.new(skill: 'goto', params: { row:, col: }, state:, target: @target[:cell], planner: @planner, clearing: @clearing)
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
          row, col = @target[:cell]
          @fail_cause = "goto leg to (#{row},#{col}) stopped #{outcome[:stopped_by]}#{outcome[:cause] ? ": #{outcome[:cause]}" : ''}"
          @excluded << @target.values_at(:cell, :direction)
          attempt_over(state)
        end

        def outward_from(state)
          @outward = { frames: 0, still: 0, position: [state.x, state.y] }
          nil
        end

        def outward(state)
          cell, direction = @target.values_at(:cell, :direction)
          if state.cell && state.cell != cell && @target[:kind] != :door
            @crossed << [*cell, direction] if state.cell == neighbour(cell, direction)
            @outward = nil
            return attempt_over(state)
          end
          position = [state.x, state.y]
          @outward[:still] = @outward[:frames].positive? && position == @outward[:position] ? @outward[:still] + 1 : 0
          @outward[:position] = position
          if @outward[:still] >= STILL_FRAMES || @outward[:frames] >= OUTWARD_FRAMES
            return @clearing&.start(state, direction) || outward_blocked(state, cell, direction)
          end

          @outward[:frames] += 1
          [direction]
        end

        def outward_blocked(state, cell, direction)
          fail_step(cell, direction)
          @fail_cause = "step #{direction} from (#{cell[0]},#{cell[1]}) blocked"
          @outward = nil
          attempt_over(state)
        end

        def fail_step(cell, direction)
          edge = { row: cell[0], col: cell[1], direction: }
          block(edge)
          @exits << edge.merge(outcome: :blocked) if %i[exit door].include?(@target[:kind])
          return unless @target[:kind] == :frontier

          @new_walls << neighbour(cell, direction)
          @walls << neighbour(cell, direction)
        end

        def block(edge)
          @blocked << edge.dup
          @planner.avoid([edge[:row], edge[:col]], edge[:direction])
        end

        def attempt_over(state)
          @stuck = state.cell == @attempt_from ? @stuck + 1 : 0
          @fruitless = @found ? 0 : @fruitless + 1
          @found = false
          @stop = :blocked if @stuck >= STUCK_ATTEMPTS
          @stop ||= :stalled if @fruitless >= FRUITLESS_ATTEMPTS
          nil
        end

        def candidates(from)
          paths = {}
          path_to = ->(cell) { paths.fetch(cell) { paths[cell] = @planner.path(from:, to: cell) } }
          clear = clearable(from, path_to)
          return order(clear) if clear.any?

          frontier = gather(from, path_to) { |cell, direction| frontier_kind(cell, direction) }
          return order(frontier) if frontier.any? && opened?

          if @aim[:place] && @aim[:place] != @place
            aimed = routed(from, path_to)
            return order(aimed) if aimed.any?
          end
          local = untried(from, path_to)
          return order(local) if local.any?

          return order(frontier) if frontier.any? && (@fresh || untried(from, nil).any? || @log&.untried?(@place))

          routed = routed(from, path_to)
          return order(routed) if routed.any?

          order(frontier)
        end

        def untried(from, path_to)
          gather(from, path_to) { |cell, direction| exit_kind(cell, direction) } +
            doors(path_to) { |door| !@log&.door_tried?(@place, door) && @exits.none? { |exit| exit[:kind] == :door && exit[:row] == door[0] + 1 && exit[:col] == door[1] } }
        end

        def pending?
          return false unless @planner && @cell

          path_to = ->(cell) { @planner.path(from: @cell, to: cell) }
          untried(@cell, path_to).any? || clearable(@cell, path_to).any? ||
            ((opened? || untried(@cell, nil).any?) && gather(@cell, path_to) { |cell, direction| frontier_kind(cell, direction) }.any?)
        end

        # A cleared object opens cells no survey has seen, so the frontiers behind it count as work here.
        def opened? = @clearing&.uses&.any? { |use| use[:effect] }

        def clearable(from, path_to)
          cells = @clearing ? @clearing.cells.keys - @walls - @failed : []
          cells.empty? ? [] : gather(from, path_to) { |cell, direction| frontier_kind(cell, direction) if cells.include?(neighbour(cell, direction)) }
        end

        def routed(from, path_to)
          avoid = []
          first = nil
          while (hop = @log&.route(@place, goal: (@aim[:place] if @aim[:place] != @place), avoid:))
            first ||= hop
            via = hop[:via]
            found = if via.is_a?(Array) then doors(path_to) { |door| door == via }
                    else gather(from, path_to) { |cell, direction| :exit if direction == via && neighbour(cell, direction).nil? }
                    end
            if found.any?
              @route = { goal: hop[:goal], next: hop[:next] }
              inferred = @log.surveyed_untried?(hop[:goal]) ? [] : @log.inferred_clearable(hop[:goal])
              @route[:clearable] = inferred if inferred.any?
              return found
            end
            avoid << via
            @unreachable = (@unreachable || []) | [via]
          end
          @route = { goal: first[:goal], next: first[:next] } if first
          @dead_end = true if first
          side = @log&.pocket_side(@place, from) or return []

          gather(from, path_to) { |cell, direction| :exit if direction == side && neighbour(cell, direction).nil? }
        end

        def gather(from, path_to)
          (0...Geometry::ROWS).to_a.product((0...Geometry::COLS).to_a).flat_map do |cell|
            next [] unless cell == from || @known.known?(cell)

            DIRECTIONS.filter_map do |direction|
              kind = yield(cell, direction)
              next unless kind && open?(cell, direction)

              path = path_to ? path_to.(cell) : [] or next
              { kind:, cell:, direction:, path: }
            end
          end
        end

        def doors(path_to)
          @doors.filter_map do |door|
            next unless yield(door)

            below = [door[0] + 1, door[1]]
            next unless open?(below, :up)

            path = path_to ? path_to.(below) : [] or next
            { kind: :door, cell: below, direction: :up, path: }
          end
        end

        def order(found)
          door = @aim[:door] && [@aim[:door][0] + 1, @aim[:door][1]]
          found.sort_by do |c|
            [door && c[:kind] == :door && c[:cell] == door ? 0 : 1, @hint.nil? || c[:direction] == @hint ? 0 : 1, c[:path].size, c[:kind] == :frontier ? 1 : 0, *c[:cell], DIRECTIONS.index(c[:direction])]
          end
        end

        def exit_kind(cell, direction)
          return nil if neighbour(cell, direction) || @log&.tried?(@place, cell, direction) || @log&.side_left?(@place, direction) ||
                        @exits.any? { |exit| exit[:outcome] == :left && exit[:direction] == direction }

          :exit
        end

        def frontier_kind(cell, direction)
          ahead = neighbour(cell, direction) or return nil
          return nil if @doors.include?(ahead) || (direction == :up && @doors.include?(cell))

          :frontier if !@walls.include?(ahead) && (@pushable.include?(ahead) || (!@known.static_sprite(*ahead) && UNKNOWN.include?(@known.passable(*ahead, direction))))
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
