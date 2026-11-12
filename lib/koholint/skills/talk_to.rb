require 'koholint/entities'
require 'koholint/skills/goto'

module Koholint
  module Skills
    class TalkTo
      FACE_FRAMES = 16
      CONTACT_FRAMES = 3
      FREE_PIXELS = 12
      PRESS_FRAMES = 3
      REPRESS_FRAMES = 12
      RESPONSE_FRAMES = 48
      TALK_REPLANS = 3
      TALK_STANDING_CELLS = 3
      TRACK_REPLANS = 6
      OVERLAP_PIXELS = 4
      REACH = Geometry.fact(:talk_reach).transform_keys(&:to_sym).freeze
      HALF = 8
      FREE_CAUSE = 'target cell was walkable: it may not hold a person any more'.freeze
      NOT_A_PERSON_CAUSE = 'only entity type %d is at the target and the entity census found no dialogue for that type'.freeze

      class Run < Goto::Run
        def initialize(person:, context: {}, **rest)
          @person = person
          @tried = []
          @blocked_replans = 0
          @excluded = excluded_cells(context, rest[:state], person)
          @phase = :walk
          @standing = nil
          @grid = nil
          @talked = false
          @face_frames = 0
          @face_origin = nil
          @face_last = nil
          @align_last = nil
          @align_frames = 0
          @face_still = 0
          @press_frames = 0
          @response_frames = 0
          @replans = 0
          @failed = []
          @entities = context[:entities]
          @entity = nil
          @tracks = 0
          @object = object_at(context[:objects], person)
          @who = person_entity(person)
          @cells = @who ? covered(@who) : [person]
          @faces = Array(@object&.dig(:faces)).map(&:to_sym)
          @non_person = !@who && !@object && non_person_at(person)
          super(target: nil, context:, **rest)
          @cause = format(NOT_A_PERSON_CAUSE, @non_person[:type]) if @non_person
          @facing = facing_from(@standing) if @standing
        end

        def next_input(state)
          return walk_to(state, choose(state.cell)) if @phase != :talk && !@stopped_by && moved_away?(state)

          buttons = super
          return buttons unless buttons.nil? && @phase == :walk
          return next_input(state) if @stopped_by == :blocked && replan(state)
          return buttons unless @stopped_by == :done

          @stopped_by = nil
          @phase = :face
          super(state)
        end

        def result(state = @last)
          merged = super.merge(talked: @talked, standing_cell: (@standing && { row: @standing[0], col: @standing[1] }), facing: @facing, replans: @replans, standing_cells_tried: @tried.map(&:dup))
          merged[:cause] = FREE_CAUSE if @stopped_by == :target_free
          merged[:entity] = @entity if @entity
          merged[:person_cells] = @cells.map { |row, col| { row:, col: } } if @who
          merged[:tracked] = @tracks if @tracks.positive?
          merged
        end

        private

        def centres? = @phase == :walk

        def planner_for(context)
          @grid = context[:grid]
          planner = super or return nil
          Array(context[:objects]&.call).select { |object| object[:kind].to_s == 'door' }.each do |door|
            Array(door[:faces]).each do |face|
              dr, dc = Navigation::Planner::DELTAS.fetch(face.to_sym)
              planner.avoid(door[:cell], face.to_sym)
              planner.avoid([door[:cell][0] - dr, door[:cell][1] - dc], face.to_sym)
            end
          end
          planner
        end

        def initial_plan
          return nil if @non_person

          from = @start.cell
          return choose(from) if from && @planner

          @cause = no_standing_cause(from)
          @initial_length = 0
          nil
        end

        def choose(from)
          options = neighbours.reject { |cell| @failed.include?(cell) }.filter_map do |cell|
            path = @planner.path(from:, to: cell)
            [@excluded.include?(cell) ? 1 : 0, path.size, turns(path), cell] if path
          end
          best = options.min_by { |known, size, turns, _| [known, size, turns] }
          unless best
            @cause = no_standing_cause(from)
            @initial_length ||= 0
            return nil
          end

          @standing = @target = best.last
          plan(from)
        end

        def replan(state)
          return false if @blocked_replans >= TALK_REPLANS || !@planner || !@blocked_at

          @planner.avoid([@blocked_at[:row], @blocked_at[:col]], @blocked_at[:direction])
          @failed << @standing
          @replans += 1
          @blocked_replans += 1
          @path = choose(state.cell || @blocked_at.values_at(:row, :col))
          @index = 0
          @arrived_by = nil
          @settle = 0
          @still = 0
          @heading = nil
          @position = [state.x, state.y]
          @facing = facing_from(@standing) if @path
          @stopped_by = @path ? nil : :no_path
          true
        end

        def excluded_cells(context, start, person)
          log = context[:talk_log]
          return [] unless log && start

          log.failed_sides([start.room_id, start.map_id], person)
        end

        def retarget(state)
          return nil if @tried.size >= TALK_STANDING_CELLS || !state.cell

          chosen = choose(state.cell) or return nil
          @replans += 1
          restart(state, chosen)
          input_for(state)
        end

        def walk_to(state, path)
          @tracks += 1
          @last = state
          return restart(state, path) && next_input(state) if path

          @stopped_by = :no_path
          nil
        end

        def restart(state, path)
          super
          @phase = :walk
          @face_frames = @face_still = @press_frames = @response_frames = 0
          @face_origin = @face_last = @align_last = nil
          @align_frames = 0
          @facing = facing_from(@standing)
          true
        end

        def neighbours
          @cells.flat_map do |person|
            Navigation::Planner::DELTAS.values.filter_map do |dr, dc|
              cell = [person[0] + dr, person[1] + dc]
              cell if cell[0].between?(0, Geometry::ROWS - 1) && cell[1].between?(0, Geometry::COLS - 1) && !@cells.include?(cell) &&
                      !@grid&.static_sprite(*cell) && (@faces.empty? || @faces.include?(Navigation::Planner.direction_between(cell, person)))
            end
          end.uniq
        end

        def facing_from(cell)
          person = @cells.find { |c| (c[0] - cell[0]).abs + (c[1] - cell[1]).abs == 1 } || @person
          Navigation::Planner.direction_between(cell, person)
        end

        # A room object answers only to Link pressed against it, so a sprite on or next to it is not what is talked to unless it covers the cell.
        def person_entity(cell)
          near = Array(@entities&.call).select { |entity| entity[:cell] && entity[:kind].to_s != 'enemy' && !non_person?(entity) }
          people = near.select { |entity| entity[:kind].to_s == 'npc' && (entity[:cell][0] - cell[0]).abs <= 1 && (entity[:cell][1] - cell[1]).abs <= 1 }
          people = people.select { |entity| covered(entity).include?(cell) } if @object
          found = people.min_by do |entity|
            [covered(entity).include?(cell) ? 0 : 1, (entity[:cell][0] - cell[0]).abs + (entity[:cell][1] - cell[1]).abs, entity[:moves] ? 1 : 0, entity[:slot]]
          end || (Entities.near(near, cell, within: 0) unless @object)
          found&.slice(:slot, :type, :x, :y, :kind)
        end

        def non_person?(entity)
          known = Entities.catalogue[entity[:type]]
          known && known[:kind] != :npc
        end

        def non_person_at(cell)
          Array(@entities&.call).find { |entity| entity[:cell] == cell && non_person?(entity) }
        end

        def covered(entity)
          span = ->(centre, cell_of) { (centre - HALF..centre + HALF - 1).group_by(&cell_of).select { |_, px| px.size >= OVERLAP_PIXELS }.keys }
          rows = span.(entity[:y], ->(y) { (y - 8).div(Geometry::CELL) }).select { |row| row.between?(0, Geometry::ROWS - 1) }
          cols = span.(entity[:x], ->(x) { x.div(Geometry::CELL) }).select { |col| col.between?(0, Geometry::COLS - 1) }
          rows.product(cols)
        end

        def current_who
          Array(@entities&.call).find { |entity| entity[:slot] == @who[:slot] && entity[:type] == @who[:type] }
        end

        def moved_away?(state)
          return false unless @who && @standing && @tracks < TRACK_REPLANS && state.cell

          now = current_who or return false
          cells = covered(now)
          return false if cells == @cells

          @who = now.slice(:slot, :type, :x, :y, :kind)
          @cells = cells
          @person = cells.first
          adjacent = @cells.any? { |c| (c[0] - @standing[0]).abs + (c[1] - @standing[1]).abs == 1 } && !@cells.include?(@standing)
          !adjacent
        end

        def object_at(objects, person) = objects && Array(objects.call).find { |object| object[:cell] == person }

        def turns(path)
          directions = path.each_cons(2).map { |a, b| Navigation::Planner.direction_between(a, b) }
          directions.each_cons(2).count { |a, b| a != b }
        end

        def no_standing_cause(from)
          return 'no grid' unless @planner
          return 'no current cell' unless from
          return "no reachable cell next to the target: blocked standing cells #{@failed.map { |r, c| "(#{r},#{c})" }.join(', ')}" if @failed.any?

          reasons = neighbours.map do |cell|
            "(#{cell[0]},#{cell[1]}) #{@planner.why_not(from:, to: cell)}"
          end
          "no reachable cell next to the target: #{reasons.join('; ')}"
        end

        def input_for(state)
          return idle(:no_response) if @non_person && @frames.zero?
          return super if @phase == :walk
          return finish(:room_change) if room(state) != room(@start)
          return finish(:damage) if state.hp.to_i < @start.hp.to_i

          if @phase == :face
            return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?

            face(state)
          else
            talk(state)
          end
        end

        def face(state)
          return finish(:target_free) if @face_frames.zero? && (@who ? current_who.nil? : believed_free?)

          position = [state.x, state.y]
          refresh_who
          align = align_with_person(position)
          return align if align

          @face_origin ||= position
          @face_still = position == @face_last ? @face_still + 1 : 0
          return out_of_reach(state) if @face_still >= CONTACT_FRAMES && @who && !within_reach?(position, slack: Geometry::ALIGN_TOLERANCE)
          return begin_talk(state) if @face_still >= CONTACT_FRAMES || (@face_frames.positive? && within_reach?(position))

          return finish(:target_free) if @who ? passed?(position) : drifted?(position)

          @face_last = position
          @face_frames += 1
          [@facing]
        end

        def align_with_person(position)
          return nil unless @who && @align_frames < FACE_FRAMES

          horizontal = %i[left right].include?(@facing)
          off = horizontal ? @who[:y] - position[1] : @who[:x] - position[0]
          return nil if off.abs <= Geometry::ALIGN_TOLERANCE || position == @align_last

          @align_last = position
          @align_frames += 1
          [horizontal ? (off.positive? ? :down : :up) : (off.positive? ? :right : :left)]
        end

        def drifted?(position)
          axis = %i[left right].include?(@facing) ? 0 : 1
          (position[axis] - @face_origin[axis]).abs >= FREE_PIXELS || @face_frames >= FACE_FRAMES
        end

        def out_of_reach(state)
          note_tried(:no_response)
          @failed << @standing
          retarget(state) || finish(:no_response)
        end

        def within_reach?(position, slack: 0)
          return false unless @who

          horizontal = %i[left right].include?(@facing)
          sign = %i[right down].include?(@facing) ? 1 : -1
          along = horizontal ? @who[:x] - position[0] : @who[:y] - position[1]
          cross = horizontal ? @who[:y] - position[1] : @who[:x] - position[0]
          (along * sign).between?(1, REACH.fetch(@facing)) && cross.abs <= HALF + slack
        end

        def refresh_who
          now = @who && current_who or return
          @who = @who.merge(now.slice(:x, :y))
        end

        def passed?(position)
          return true if @face_frames >= FACE_FRAMES + HALF

          axis = %i[left right].include?(@facing) ? 0 : 1
          sign = %i[right down].include?(@facing) ? 1 : -1
          ((position[axis] - [@who[:x], @who[:y]][axis]) * sign) >= 0
        end

        def note_tried(outcome) = @tried << { row: @standing[0], col: @standing[1], outcome: }

        def believed_free?
          @grid && !@grid.static_sprite(*@person) && @grid.passable(*@person, @facing) == :yes
        end

        def faced_entity
          return unless @entities && @standing
          return { type: @who[:type], slot: @who[:slot], kind: @who[:kind].to_s } if @who

          delta = Navigation::Planner::DELTAS.fetch(@facing, [0, 0])
          faced = [@standing[0] + delta[0], @standing[1] + delta[1]]
          found = @entities.call.select { |entity| entity[:cell] == faced && entity[:kind].to_s == 'npc' }.min_by { |entity| entity[:slot] }
          found&.slice(:type, :slot, :kind)&.transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
        end

        def begin_talk(state)
          @phase = :talk
          talk(state)
        end

        def talk(state)
          if state.dialog_open? && !@start.dialog_open?
            @talked = true
            @entity = faced_entity
            note_tried(:done)
            return finish(:done)
          end
          refresh_who
          return out_of_reach(state) if @who && !within_reach?([state.x, state.y], slack: Geometry::ALIGN_TOLERANCE)
          if @response_frames >= RESPONSE_FRAMES
            note_tried(:no_response)
            @failed << @standing
            return retarget(state) || finish(:no_response)
          end

          pressing = @response_frames % REPRESS_FRAMES < PRESS_FRAMES
          @response_frames += 1
          pressing ? [:a] : []
        end
      end

      def name = 'talk_to'

      def params_schema
        { type: 'object', title: name,
          properties: { row: { type: 'integer', minimum: 0, maximum: Geometry::ROWS - 1 },
                        col: { type: 'integer', minimum: 0, maximum: Geometry::COLS - 1 } },
          required: %w[row col], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[row col])
        raise ArgumentError, "talk_to: row must be 0..#{Geometry::ROWS - 1}" unless params[:row].is_a?(Integer) && params[:row].between?(0, Geometry::ROWS - 1)
        raise ArgumentError, "talk_to: col must be 0..#{Geometry::COLS - 1}" unless params[:col].is_a?(Integer) && params[:col].between?(0, Geometry::COLS - 1)

        { row: params[:row], col: params[:col] }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, person: [params[:row], params[:col]], context:)
      end
    end
  end
end
