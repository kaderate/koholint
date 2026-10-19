require 'koholint/skills/execution'

module Koholint
  module Skills
    class Walk
      DIRECTIONS = %i[up right down left].freeze
      MAX_CELLS = 5
      STILL_FRAMES = 8
      FRAMES_PER_CELL = 90

      class Run < Execution
        def initialize(direction:, cells:, **rest)
          super(**rest)
          @direction = direction
          @cells = cells
          @position = [@start.x, @start.y]
          @still = 0
        end

        private

        def centres? = true

        def blocked_direction = @direction

        def input_for(state)
          track(state) if @frames.positive?
          return finish(:room_change) if room(state) != room(@start)
          return finish(:damage) if state.hp.to_i < @start.hp.to_i
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?
          return finish(:done) if moved_cells(state) >= @cells
          return finish(:blocked) if @still >= STILL_FRAMES
          return finish(:frame_cap) if @frames >= FRAMES_PER_CELL * @cells

          [@direction]
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
          properties: { direction: { type: 'string', enum: DIRECTIONS.map(&:to_s) },
                        cells: { type: 'integer', minimum: 1, maximum: MAX_CELLS } },
          required: %w[direction cells], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[direction cells])
        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "walk: direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)
        raise ArgumentError, "walk: cells must be 1..#{MAX_CELLS}" unless params[:cells].is_a?(Integer) && params[:cells].between?(1, MAX_CELLS)

        { direction:, cells: params[:cells] }
      end

      def start(state, params)
        params = normalize(params)
        Run.new(skill: name, params:, state:, direction: params[:direction], cells: params[:cells])
      end
    end
  end
end
