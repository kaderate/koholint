require 'koholint/skills/execution'

module Koholint
  module Skills
    class Step
      DIRECTIONS = %i[up right down left].freeze
      MAX_PIXELS = 16
      STILL_FRAMES = 8
      FRAME_LIMIT = 80

      class Run < Execution
        def initialize(direction:, pixels:, **rest)
          super(**rest)
          @direction = direction
          @pixels = pixels
          @position = [@start.x, @start.y]
          @still = 0
        end

        def result(state = @last) = super.merge(moved_px: moved_px(state))

        private

        def blocked_direction = @direction

        def input_for(state)
          track(state) if @frames.positive?
          return finish(:room_change) if room(state) != room(@start)
          return finish(:damage) if state.hp.to_i < @start.hp.to_i
          return finish(:dialogue) if state.dialog_open? && !@start.dialog_open?
          return finish(:done) if moved_px(state) >= @pixels
          return finish(:blocked) if @still >= STILL_FRAMES
          return finish(:frame_cap) if @frames >= FRAME_LIMIT

          [@direction]
        end

        def moved_px(state)
          return 0 unless @start.x && @start.y && state.x && state.y

          case @direction
          when :up then @start.y - state.y
          when :down then state.y - @start.y
          when :left then @start.x - state.x
          else state.x - @start.x
          end
        end

        def track(state)
          position = [state.x, state.y]
          @still = position == @position ? @still + 1 : 0
          @position = position
        end
      end

      def name = 'step'

      def params_schema
        { type: 'object', title: name,
          properties: { direction: { type: 'string', enum: DIRECTIONS.map(&:to_s) },
                        pixels: { type: 'integer', minimum: 1, maximum: MAX_PIXELS } },
          required: %w[direction pixels], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[direction pixels])
        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "step: direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)
        raise ArgumentError, "step: pixels must be 1..#{MAX_PIXELS}" unless params[:pixels].is_a?(Integer) && params[:pixels].between?(1, MAX_PIXELS)

        { direction:, pixels: params[:pixels] }
      end

      def start(state, params, _context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, direction: params[:direction], pixels: params[:pixels])
      end
    end
  end
end
