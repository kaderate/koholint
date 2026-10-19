require 'koholint/skills/goto'

module Koholint
  module Skills
    class TalkTo
      FACE_FRAMES = 8
      FACE_MIN_FRAMES = 3
      PRESS_FRAMES = 3
      RESPONSE_FRAMES = 30

      class Run < Goto::Run
        def initialize(person:, **rest)
          @person = person
          @phase = :walk
          @standing = nil
          @talked = false
          @face_frames = 0
          @face_origin = nil
          @face_last = nil
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

        def initial_plan
          from = @start.cell
          options = Navigation::Planner::DELTAS.keys.filter_map do |direction|
            cell = [@person[0] + Navigation::Planner::DELTAS[direction][0], @person[1] + Navigation::Planner::DELTAS[direction][1]]
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

        def turns(path)
          directions = path.each_cons(2).map { |a, b| Navigation::Planner.direction_between(a, b) }
          directions.each_cons(2).count { |a, b| a != b }
        end

        def no_standing_cause(from)
          return 'no grid' unless @planner
          return 'no current cell' unless from

          reasons = Navigation::Planner::DELTAS.map do |direction, (dr, dc)|
            cell = [@person[0] + dr, @person[1] + dc]
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
          position = [state.x, state.y]
          @face_origin ||= position
          moved = (position[0] - @face_origin[0]).abs + (position[1] - @face_origin[1]).abs
          stopped = @face_frames >= FACE_MIN_FRAMES && position == @face_last
          return finish(:target_free) if moved > Geometry::CELL / 2 || (@face_frames >= FACE_FRAMES && !stopped && moved > Geometry::ALIGN_TOLERANCE)

          if stopped || @face_frames >= FACE_FRAMES
            @phase = :talk
            return talk(state)
          end

          @face_last = position
          @face_frames += 1
          [@facing]
        end

        def talk(state)
          if state.dialog_open?
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
