require 'koholint/navigation/planner'
require 'koholint/skills/execution'

module Koholint
  module Skills
    class Walk
      MAX_CELLS = 5
      STILL_FRAMES = 8
      FRAMES_PER_CELL = 90

      class Run < Execution
        def initialize(direction:, cells:, context: {}, **rest)
          super(**rest)
          @direction = direction
          @cells = cells
          @danger = low_health? ? danger_of(context) : nil
          @away = away_of(context)
          @position = [@start.x, @start.y]
          @still = 0
          @room_objects = context[:room_objects]
        end

        private

        def centres? = true

        def waits_through_doors? = true

        def blocked_direction = @direction

        def input_for(state)
          track(state) if @frames.positive?
          return finish(:room_change) if state.place != @start.place
          return finish(:damage) if state.health < @start.health
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?
          return finish(:done) if moved_cells(state) >= @cells
          return finish(:danger) if danger_ahead?(state)
          return finish(:blocked) if @still >= STILL_FRAMES && @still >= still_limit(state, @direction, STILL_FRAMES)
          return finish(:frame_cap) if @frames >= FRAMES_PER_CELL * @cells

          [@direction]
        end

        def danger_ahead?(state)
          return false unless @danger && state.cell

          dr, dc = Geometry::DELTAS.fetch(@direction)
          ahead = [state.cell[0] + dr, state.cell[1] + dc]
          zones = Array(@danger.call)
          zones.include?(ahead) && !(zones.include?(state.cell) && @away.call(state.cell, ahead))
        end

        def track(state)
          position = [state.x, state.y]
          @still = position == @position ? @still + 1 : 0
          @position = position
        end
      end

      def name = 'walk'

      def params_schema
        { type: 'object', title: name,
          properties: { direction: { type: 'string', enum: Geometry::DIRECTIONS.map(&:to_s) },
                        cells: { type: 'integer', minimum: 1, maximum: MAX_CELLS } },
          required: %w[direction cells], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[direction cells])
        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "walk: direction must be one of #{Geometry::DIRECTIONS.join(', ')}" unless Geometry::DIRECTIONS.include?(direction)
        raise ArgumentError, "walk: cells must be 1..#{MAX_CELLS}" unless params[:cells].is_a?(Integer) && params[:cells].between?(1, MAX_CELLS)

        { direction:, cells: params[:cells] }
      end

      def start(state, params, context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, direction: params[:direction], cells: params[:cells], context:)
      end
    end
  end
end
