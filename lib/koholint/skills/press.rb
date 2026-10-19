require 'koholint/skills/execution'

module Koholint
  module Skills
    class Press
      BUTTONS = %i[a b start select].freeze
      MAX_FRAMES = 60
      IDLE_FRAMES = 10

      class Run < Execution
        def initialize(button:, hold:, **rest)
          super(**rest)
          @button = button
          @hold = hold
        end

        private

        def input_for(_state)
          return finish(:done) if @frames >= @hold + IDLE_FRAMES

          @frames < @hold ? [@button] : []
        end
      end

      def name = 'press'

      def params_schema
        { type: 'object', title: name,
          properties: { button: { type: 'string', enum: BUTTONS.map(&:to_s) },
                        frames: { type: 'integer', minimum: 1, maximum: MAX_FRAMES } },
          required: %w[button frames], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[button frames])
        button = params[:button].respond_to?(:to_sym) ? params[:button].to_sym : nil
        raise ArgumentError, "press: button must be one of #{BUTTONS.join(', ')}" unless BUTTONS.include?(button)
        raise ArgumentError, "press: frames must be 1..#{MAX_FRAMES}" unless params[:frames].is_a?(Integer) && params[:frames].between?(1, MAX_FRAMES)

        { button:, frames: params[:frames] }
      end

      def start(state, params)
        params = normalize(params)
        Run.new(skill: name, params:, state:, button: params[:button], hold: params[:frames])
      end
    end
  end
end
