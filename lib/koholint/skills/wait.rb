require 'koholint/skills/execution'

module Koholint
  module Skills
    class Wait
      MAX_FRAMES = 120

      class Run < Execution
        def initialize(duration:, **rest)
          super(**rest)
          @duration = duration
        end

        private

        def input_for(_state) = @frames >= @duration ? finish(:done) : []
      end

      def name = 'wait'

      def params_schema
        { type: 'object', title: name, properties: { frames: { type: 'integer', minimum: 1, maximum: MAX_FRAMES } },
          required: %w[frames], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[frames])
        raise ArgumentError, "wait: frames must be 1..#{MAX_FRAMES}" unless params[:frames].is_a?(Integer) && params[:frames].between?(1, MAX_FRAMES)

        { frames: params[:frames] }
      end

      def start(state, params)
        params = normalize(params)
        Run.new(skill: name, params:, state:, duration: params[:frames])
      end
    end
  end
end
