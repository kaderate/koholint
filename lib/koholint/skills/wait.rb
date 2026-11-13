require 'koholint/modes'
require 'koholint/skills/execution'

module Koholint
  module Skills
    class Wait
      MAX_FRAMES = 120

      class Run < Execution
        def initialize(duration:, until_free: false, **rest)
          super(**rest)
          @duration = duration
          @until_free = until_free
        end

        private

        def input_for(state)
          return finish(:done) if @frames >= @duration
          return finish(:released) if @until_free && @frames.positive? && !Modes::HELD.include?(state.phase)

          []
        end
      end

      def name = 'wait'

      def params_schema
        { type: 'object', title: name,
          properties: { frames: { type: 'integer', minimum: 1, maximum: MAX_FRAMES }, until_free: { type: 'boolean', description: 'end as soon as Link is free to move' } },
          required: %w[frames], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[frames until_free])
        raise ArgumentError, "wait: frames must be 1..#{MAX_FRAMES}" unless params[:frames].is_a?(Integer) && params[:frames].between?(1, MAX_FRAMES)
        raise ArgumentError, 'wait: until_free must be true or false' unless [nil, true, false].include?(params[:until_free])

        params[:until_free] ? params.slice(:frames, :until_free) : { frames: params[:frames] }
      end

      def start(state, params, _context = {})
        params = normalize(params)
        Run.new(skill: name, params:, state:, duration: params[:frames], until_free: params[:until_free] == true)
      end
    end
  end
end
