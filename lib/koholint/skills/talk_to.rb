require 'koholint/skills/goto'

module Koholint
  module Skills
    class TalkTo
      FACE_FRAMES = 16
      CONTACT_FRAMES = 3
      FREE_PIXELS = 12
      PRESS_FRAMES = 3
      RESPONSE_FRAMES = 30

      class Run < Goto::Run
        def initialize(person:, **rest)
          @person = person
          @phase = :walk
          @standing = nil
          @grid = nil
          @talked = false
          @face_frames = 0
          @face_origin = nil
          @face_last = nil
          @face_still = 0
          @press_frames = 0
          @response_frames = 0
          super(target: nil, **rest)
          @facing = Navigation::Planner.direction_between(@standing, @person) if @standing
        end

        def next_input(state)
          buttons = super
          return buttons unless buttons.nil? && @stopped_by == :done && @phase == :walk

          @stopped_by = nil
          @phase = :face
          super(state)
        end

        def result(state = @last)
          super.merge(talked: @talked, standing_cell: (@standing && { row: @standing[0], col: @standing[1] }), facing: @facing)
        end

        private

        def centres? = @phase == :walk

        def planner_for(context)
          @grid = context[:grid]
          super
        end

        def initial_plan
          from = @start.cell
          options = neighbours.filter_map do |cell|
            path = from && @planner&.path(from:, to: cell)
            [path.size, turns(path), cell] if path
          end
          best = options.min_by { |size, turns, _| [size, turns] }
          unless best
            @cause = no_standing_cause(from)
            @initial_length = 0
            return nil
          end

          @standing = @target = best.last
          plan(from)
        end

        def neighbours
          Navigation::Planner::DELTAS.values.filter_map do |dr, dc|
            cell = [@person[0] + dr, @person[1] + dc]
            cell if cell[0].between?(0, Geometry::ROWS - 1) && cell[1].between?(0, Geometry::COLS - 1) && !@grid&.static_sprite(*cell)
          end
        end

        def turns(path)
          directions = path.each_cons(2).map { |a, b| Navigation::Planner.direction_between(a, b) }
          directions.each_cons(2).count { |a, b| a != b }
        end

        def no_standing_cause(from)
          return 'no grid' unless @planner
          return 'no current cell' unless from

          reasons = neighbours.map do |cell|
            "(#{cell[0]},#{cell[1]}) #{@planner.why_not(from:, to: cell)}"
          end
          "no reachable cell next to the target: #{reasons.join('; ')}"
        end

        def input_for(state)
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
          return finish(:target_free) if @face_frames.zero? && believed_free?

          position = [state.x, state.y]
          @face_origin ||= position
          @face_still = position == @face_last ? @face_still + 1 : 0
          return begin_talk(state) if @face_still >= CONTACT_FRAMES

          axis = %i[left right].include?(@facing) ? 0 : 1
          return finish(:target_free) if (position[axis] - @face_origin[axis]).abs >= FREE_PIXELS || @face_frames >= FACE_FRAMES

          @face_last = position
          @face_frames += 1
          [@facing]
        end

        def believed_free?
          @grid && !@grid.static_sprite(*@person) && @grid.passable(*@person, @facing) == :yes
        end

        def begin_talk(state)
          @phase = :talk
          talk(state)
        end

        def talk(state)
          if state.dialog_open? && !@start.dialog_open?
            @talked = true
            return finish(:done)
          end
          if @press_frames < PRESS_FRAMES
            @press_frames += 1
            return [:a]
          end
          return finish(:no_response) if @response_frames >= RESPONSE_FRAMES

          @response_frames += 1
          []
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
