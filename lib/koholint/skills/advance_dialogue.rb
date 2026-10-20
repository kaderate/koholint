require 'koholint/skills/execution'

module Koholint
  module Skills
    class AdvanceDialogue
      PRESS_FRAMES = 3
      CYCLE_FRAMES = 30

      class Run < Execution
        private

        def input_for(state)
          return finish(:done) if @frames.positive? && !state.dialog_open?
          return finish(:done) if @frames >= CYCLE_FRAMES

          @frames < PRESS_FRAMES ? [:a] : []
        end
      end

      def name = 'advance_dialogue'

      def params_schema = { type: 'object', title: name, properties: {}, additionalProperties: false }

      def normalize(params)
        Skills.symbolize(params, [])
        {}
      end

      def start(state, params, _context = {}) = Run.new(skill: name, params: normalize(params), state:)
    end
  end
end
