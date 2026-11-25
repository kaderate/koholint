require 'koholint/skills/goto'
require 'koholint/explore_log'
require 'koholint/navigation/stones'
require 'koholint/talk_log'

module Koholint
  module Skills
    class Explore
      BUDGET_FRAMES = 600
      OUTWARD_FRAMES = 48
      STILL_FRAMES = 8
      LOCK_FRAMES = 16
      STUCK_ATTEMPTS = 3
      FRUITLESS_ATTEMPTS = 3
      OBJECT_RANGE = 3
      ENTER_FRAMES = 120
      SPEAKERS = %w[npc unknown].freeze
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

        def hole_margin = @grid.respond_to?(:hole_margin) ? @grid.hole_margin : []

        def known?(cell) = !static_sprite(*cell) && (@walked.include?(cell) || Geometry::DIRECTIONS.any? { |d| @grid.passable(*cell, d) == :yes })
      end

      class Leg < Goto::Run
        def initialize(planner:, clearing: nil, cross_margin: true, room_objects: nil, **rest)
          @shared = planner
          @shared_clearing = clearing
          @cross_margin = cross_margin
          super(context: { room_objects: }, **rest)
        end

        private

        def cross_margin? = @cross_margin

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
          @place = @start.place
          @ledger = context[:ledger]
          @talk_log = context[:talk_log]
          @log = context[:explore_log]
          @walked = ((@log ? @log.walked(@place) | @log.stood(@place) : []) - stone_cells(context)) | [@start.cell].compact
          @fresh = @log && !@log.surveyed?(@place)
          grid = context[:grid]
          @known = grid && Known.new(grid, @walked)
          @planner = @known && Navigation::Planner.new(grid: @known, ledger: @ledger, place: @place, triggers: context[:triggers], mode: :free_only, danger: danger_of(context), pushable: pushable_of(context, stones: false), contact: contact_of(context), away: away_of(context))
          @pushable = Array(pushable_of(context)&.call)
          @grid = grid
          @clearing = Clearing.of(context)
          @room_objects = context[:room_objects]
          @fight = context[:fight]
          @objects = grid ? TalkLog.objects(grid) : []
          @entities = context[:entities]
          objects = Array(context[:objects]&.call)
          @object_cells = objects.map { |object| object[:cell] }
          @doors = objects.select { |object| object[:kind].to_s == 'door' && object[:cell][0] < Geometry::ROWS - 1 }.map { |object| object[:cell] }
          @crumbling = objects.select { |object| object[:kind].to_s == 'crumbling' }.map { |object| object[:cell] }
          @survey = @known && survey
          @route = @unreachable = @dead_end = @backs = @routed_off = nil
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
          @still = 0
          @position = nil
          @fruitless = 0
          @found = false
          @legs = 0
          @locked = 0
          @leg = @outward = @target = @stop = @heading = @idle = @fail_cause = nil
        end

        def result(state = @last)
          merged = super.merge(place_changed: state.place != @place, cells_walked: @cells_walked, legs: @legs, target: target_summary,
                               crossed: @crossed.map(&:dup), walls: @new_walls.map { |row, col| { row:, col: } }, blocked_edges: @blocked.map(&:dup), exits: @exits.map(&:dup),
                               offered: @offered.map { |row, col| { row:, col: } })
          merged[:clears] = @clearing.uses if @clearing&.uses&.any?
          merged[:survey] = @survey.merge(pending: pending?) if @survey
          merged[:route] = @route if @route
          merged[:unreachable] = @unreachable if @unreachable
          held = Array(@backs) - Array(@routed_off)
          merged[:held] = held if held.any?
          merged[:dead_end] = true if @dead_end
          merged[:failed_push] = @failed_push if @failed_push
          merged[:too_heavy] = @too_heavy if @too_heavy
          merged[:stone_search] = 'cut short' if @search_cut
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

          @still = [state.x, state.y] == @position ? @still + 1 : 0
          @position = [state.x, state.y]
          return @clearing.step(state) if @clearing&.active? && !@leg
          return depart(state) if state.place != @place
          return stop_now(:fell) if state.falling?
          return harmed if state.health < @start.health
          return stop_now(:enemy) if @fight&.call(state)
          return interrupted(state) if state.dialog_open?
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

        # The room puts its stones back on re-entry, so a stone's cell walked after an earlier push is a stone again.
        def stone_cells(context)
          objects = context[:room_objects]&.call or return []
          objects.each_with_index.flat_map { |row, r| row.each_index.select { |c| Entities.object_catalogue.dig(row[c], :kind) == :stone }.map { |c| [r, c] } }
        end

        def stop_now(reason)
          return finish(reason) if @frames.positive?

          @idle = reason
          []
        end

        # A dialogue that opens as Link stops flush against his cell's edge (a rock too heavy to push) bars that edge, so the survey's pending
        # work leaves it out; one that opens anywhere else (a call-out, a scene, a talking door, a cell just crossed) bars nothing.
        def interrupted(state)
          if pushing?(state)
            edge = { row: @cell[0], col: @cell[1], direction: @heading }
            block(edge)
            @too_heavy = edge if unprompted?(Geometry.step(@cell, @heading))
          end
          stop_now(:dialogue)
        end

        # Only a push with nothing else that could have opened the text (a person or unidentified thing on screen, an object ahead) says the cell ahead pushed back.
        def unprompted?(ahead)
          Array(@entities&.call).none? { |entity| SPEAKERS.include?(entity[:kind].to_s) } && !@object_cells.include?(ahead)
        end

        def pushing?(state)
          return false unless (@leg || @outward) && @heading && @cell && state.cell == @cell && @still.positive?

          dx, dy = Geometry.offset(state.x, state.y, @cell)
          footprint = Geometry.fact(:link_footprint)
          band = footprint['row_band']
          { right: dx >= footprint['width'] / 2, left: dx <= -footprint['width'] / 2, down: dy >= band['max_offset'], up: dy <= band['min_offset'] }.fetch(@heading)
        end

        def harmed
          fail_step(*@target.values_at(:cell, :direction)) if @target && (@leg || @outward)
          finish(:damage)
        end

        def heading(buttons)
          direction = (buttons & Geometry::DIRECTIONS).first
          @heading = direction if direction
          buttons
        end

        def depart(state)
          to = state.place
          if @target && @target[:kind] == :door && (@outward || @entering.positive?)
            @exits << { row: @target[:cell][0], col: @target[:cell][1], direction: :up, outcome: :left, to:, kind: :door }
          elsif @cell && @heading && Geometry.step(@cell, @heading)
            @exits << ExploreLog.door_exit(@cell, Geometry.step(@cell, @heading), @doors, to)
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
              border.(row, col) && @known.known?([row, col]) && Geometry::DIRECTIONS.any? { |d| @known.passable(row, col, d) == :yes }
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
            @leg = Leg.new(skill: 'goto', params: { row:, col: }, state:, target: @target[:cell], planner: @planner, clearing: @clearing,
                           cross_margin: @target[:kind] != :frontier, room_objects: @room_objects)
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
            @crossed << [*cell, direction] if state.cell == Geometry.step(cell, direction)
            @outward = nil
            return attempt_over(state)
          end
          across = across_push(state, cell, direction) and return across
          position = [state.x, state.y]
          @outward[:still] = @outward[:frames].positive? && position == @outward[:position] ? @outward[:still] + 1 : 0
          @outward[:position] = position
          limit = still_limit(state, direction, STILL_FRAMES) if @outward[:still] >= STILL_FRAMES || @outward[:frames] >= OUTWARD_FRAMES
          if limit && (@outward[:still] >= limit || @outward[:frames] >= OUTWARD_FRAMES + limit - STILL_FRAMES)
            return @clearing&.start(state, direction) || outward_blocked(state, cell, direction)
          end

          @outward[:frames] += 1
          [direction]
        end

        # A stone slides after its measured hold only with Link centred across the push: 4 px low the hold doubles, 7 px low it never slides.
        def across_push(state, cell, direction)
          return unless @target[:kind] == :push && @outward[:frames].zero? && @outward[:centring].to_i < Geometry::CELL

          dx, dy = Geometry.offset(state.x, state.y, cell)
          off, toward = %i[left right].include?(direction) ? [dy, %i[up down]] : [dx, %i[left right]]
          return if off.zero?

          @outward[:centring] = @outward[:centring].to_i + 1
          [off.positive? ? toward[0] : toward[1]]
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
          @failed_push = { row: @target[:stone][0], col: @target[:stone][1], direction: } if @target[:kind] == :push
          return unless @target[:kind] == :frontier

          @new_walls << Geometry.step(cell, direction)
          @walls << Geometry.step(cell, direction)
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
          safe = {}
          safe_to = ->(cell) { safe.fetch(cell) { safe[cell] = @planner.path(from:, to: cell, cross_margin: false) } }
          clear = clearable(from, safe_to)
          return order(clear) if clear.any?

          objects = object_cells
          frontier = gather(from, safe_to) { |cell, direction| frontier_kind(cell, direction) unless objects.include?(Geometry.step(cell, direction)) }
          return order(frontier) if frontier.any? && opened?

          if @aim[:place] && @aim[:place] != @place
            aimed = routed(from, path_to)
            return order(aimed) if aimed.any?
          end
          back, local = untried(from, path_to).partition { |candidate| way_back?(candidate) }
          return order(local) if local.any?

          pushed = pushes(untried(from, nil).reject { |candidate| way_back?(candidate) })
          return order(pushed) if pushed.any?

          return order(frontier) if frontier.any? && (@fresh || untried(from, nil).any? || @log&.untried?(@place))
          return order(back) if back.any?

          stranded = @crumbling.any? ? [] : untried(from, nil).reject { |candidate| path_to.(candidate[:cell]) }
          @unreachable = (@unreachable || []) | stranded.map { |candidate| candidate[:kind] == :door ? [candidate[:cell][0] - 1, candidate[:cell][1]] : candidate[:direction] }.uniq if stranded.any?
          @backs = (@backs || []) | stranded.select { |candidate| way_back?(candidate) }.map { |candidate| candidate[:direction] } if stranded.any?
          routed = routed(from, path_to)
          return order(routed) if routed.any?

          order(frontier)
        end

        # A side known only as the assumed way back, never crossed, still counts as untried, after every other reachable piece of work here.
        def way_back?(candidate) = candidate[:kind] == :exit && @log&.side_left?(@place, candidate[:direction]) && !@log.side_crossed?(@place, candidate[:direction])

        def untried(from, path_to)
          gather(from, path_to) { |cell, direction| exit_kind(cell, direction) } +
            doors(path_to) { |door| !@log&.door_tried?(@place, door) && @exits.none? { |exit| exit[:kind] == :door && exit[:row] == door[0] + 1 && exit[:col] == door[1] } }
        end

        def pending?
          return false unless @planner && @cell

          path_to = ->(cell) { @planner.path(from: @cell, to: cell) }
          safe_to = ->(cell) { @planner.path(from: @cell, to: cell, cross_margin: false) }
          untried(@cell, path_to).any? || clearable(@cell, safe_to).any? || pushes(untried(@cell, nil), @cell).any? ||
            ((opened? || untried(@cell, nil).any?) && gather(@cell, safe_to) { |cell, direction| frontier_kind(cell, direction) unless object_cells.include?(Geometry.step(cell, direction)) }.any?)
        end

        def object_cells = @clearing ? @clearing.cells.keys : []

        # A cleared object opens cells no survey has seen, so the frontiers behind it count as work here.
        def opened? = @clearing&.uses&.any? { |use| use[:effect] }

        def clearable(from, path_to)
          cells = @clearing ? @clearing.cells.keys - @walls - @failed : []
          return [] if cells.empty?

          gather(from, path_to) { |cell, direction| frontier_kind(cell, direction) if cells.include?(Geometry.step(cell, direction)) }
            .select { |candidate| leads_on?(Geometry.step(*candidate.values_at(:cell, :direction)), cells, path_to) }
        end

        # Objects are cut only on the way to an untried exit or door or to an unknown cell that is not one, past cells no path reaches.
        def leads_on?(start, cells, path_to)
          patch = [start]
          patch.each do |cell|
            return true if untried_door?([cell[0] - 1, cell[1]])

            Geometry::DIRECTIONS.each do |direction|
              ahead = Geometry.step(cell, direction)
              return true if ahead.nil? ? exit_kind(cell, direction) : unknown?(ahead, direction, cells)
              next if ahead.nil? || patch.include?(ahead)

              patch << ahead if cells.include?(ahead) || (@known.known?(ahead) && !@known.static_sprite(*ahead) && !path_to.(ahead))
            end
          end
          false
        end

        def untried_door?(cell) = @doors.include?(cell) && !@log&.door_tried?(@place, cell)

        def unknown?(cell, direction, cells)
          !cells.include?(cell) && !@walked.include?(cell) && !@walls.include?(cell) && !@known.static_sprite(*cell) &&
            UNKNOWN.include?(@known.passable(*cell, direction))
        end

        def routed(from, path_to)
          avoid = []
          first = nil
          while (hop = @log&.route(@place, goal: (@aim[:place] if @aim[:place] != @place), avoid:))
            first ||= hop
            via = hop[:via]
            way = ->(path) { via.is_a?(Array) ? doors(path, @doors | [via]) { |door| door == via } : gather(from, path) { |cell, direction| :exit if direction == via && Geometry.step(cell, direction).nil? } }
            found = way.(path_to)
            found = pushes(way.(nil)) if found.empty?
            if found.any?
              @route = { goal: hop[:goal], next: hop[:next] }
              inferred = @log.surveyed_untried?(hop[:goal]) ? [] : @log.inferred_clearable(hop[:goal])
              @route[:clearable] = inferred if inferred.any?
              @dead_end = true if avoid.any? && via == @log.landing_side(@place, from) && [nil, @place].include?(@aim[:place])
              return found
            end
            avoid << via
            @unreachable = (@unreachable || []) | [via]
            @routed_off = (@routed_off || []) | [via]
          end
          @route = { goal: first[:goal], next: first[:next] } if first
          @dead_end = true if first
          side = @log&.pocket_side(@place, from) or return []

          gather(from, path_to) { |cell, direction| :exit if direction == side && Geometry.step(cell, direction).nil? }
        end

        # An exit or door that only pushes open: the first of the fewest pushes that open it, from a stand Link walks to without pushing.
        def pushes(found, from = @attempt_from)
          found.filter_map do |candidate|
            push = stone_plans(from)[candidate[:cell]]&.first or next
            next unless open?(push[:stand], push[:direction])

            path = @planner.path(from:, to: push[:stand]) or next
            { kind: :push, cell: push[:stand], direction: push[:direction], stone: push[:stone], path:, opens: candidate.slice(:kind, :cell, :direction) }
          end
        end

        # A push that left its stone in place this visit is never planned again in it.
        def stone_plans(from)
          objects = @room_objects&.call
          return {} unless objects && @grid && from

          @stone_plans ||= {}
          @stone_plans[[from, objects]] ||= begin
            cells = objects.each_with_index.flat_map { |row, r| row.each_index.filter_map { |c| [r, c] if Entities.object_catalogue.dig(row[c], :kind) == :stone } }
            stones, fixed = cells.partition { |cell| Entities.object_catalogue.dig(objects.dig(*cell), :push) }
            failed = @log ? @log.failed_pushes(@place) : []
            found = stones.empty? ? { plans: {}, complete: true } : Navigation::Stones.plans(link: from, stones:, fixed:, step: @planner.method(:step?), slide: ->(cell, direction) { lands?(objects, @grid, cell, direction) }, refused: failed)
            @search_cut = true unless found[:complete]
            found[:plans]
          end
        end

        def gather(from, path_to)
          (0...Geometry::ROWS).to_a.product((0...Geometry::COLS).to_a).flat_map do |cell|
            next [] unless cell == from || @known.known?(cell)

            Geometry::DIRECTIONS.filter_map do |direction|
              kind = yield(cell, direction)
              next unless kind && open?(cell, direction)

              path = path_to ? path_to.(cell) : [] or next
              { kind:, cell:, direction:, path: }
            end
          end
        end

        def doors(path_to, cells = @doors)
          cells.filter_map do |door|
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
            aim = c[:opens] || c
            [door && aim[:kind] == :door && aim[:cell] == door ? 0 : 1, @hint.nil? || aim[:direction] == @hint ? 0 : 1, c[:path].size, c[:kind] == :frontier ? 1 : 0, *c[:cell], Geometry::DIRECTIONS.index(c[:direction])]
          end
        end

        def exit_kind(cell, direction)
          return nil if Geometry.step(cell, direction) || @log&.tried?(@place, cell, direction) || @log&.side_crossed?(@place, direction) ||
                        @exits.any? { |exit| exit[:outcome] == :left && exit[:direction] == direction }

          :exit
        end

        def frontier_kind(cell, direction)
          ahead = Geometry.step(cell, direction) or return nil
          return nil if @doors.include?(ahead) || (direction == :up && @doors.include?(cell))
          return nil if direction == :up && [cell, ahead].any? { |at| @log&.door_edge?(@place, at) }
          return nil if @walked.include?(ahead) || [cell, ahead].any? { |at| @known.hole_margin.include?(at) }

          :frontier if !@walls.include?(ahead) && (@pushable.include?(ahead) || @pushable.include?([ahead, direction]) ||
                                                  (!@known.static_sprite(*ahead) && UNKNOWN.include?(@known.passable(*ahead, direction))))
        end

        def open?(cell, direction)
          edge = { row: cell[0], col: cell[1], direction: }
          !@excluded.include?([cell, direction]) && !@blocked.include?(edge) && !@ledger&.doubtful?(@place, cell, direction) &&
            !Array(@triggers&.forbidden(@place, cell)).include?(direction)
        end

        def target_summary
          return nil unless @target

          { kind: @target[:kind], row: @target[:cell][0], col: @target[:cell][1], direction: @target[:direction] }
        end
      end

      def name = 'explore'

      def params_schema
        { type: 'object', title: name, properties: { direction: { type: 'string', enum: Geometry::DIRECTIONS.map(&:to_s) } },
          additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[direction])
        return {} unless params.key?(:direction)

        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "explore: direction must be one of #{Geometry::DIRECTIONS.join(', ')}" unless Geometry::DIRECTIONS.include?(direction)

        { direction: }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, direction: params[:direction], context:)
      end
    end
  end
end
