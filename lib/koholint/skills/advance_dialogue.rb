require 'koholint/skills/execution'

module Koholint
  module Skills
    class AdvanceDialogue
      PRESS_FRAMES = 3
      CYCLE_FRAMES = 30
      MAX_FRAMES = 90

      class Run < Execution
        private

        def input_for(state)
          return finish(:done) if @frames.positive? && (@frames % CYCLE_FRAMES).zero? && state.dialog_state != @start.dialog_state
          return finish(:done) if @frames.positive? && !state.dialog_open?
          return finish(:frame_cap) if @frames >= MAX_FRAMES

          @frames % CYCLE_FRAMES < PRESS_FRAMES ? [:a] : []
        end
      end

      def name = 'advance_dialogue'

      def params_schema = { type: 'object', title: name, properties: {}, additionalProperties: false }

      def normalize(params)
        raise ArgumentError, 'advance_dialogue takes no params' unless params.nil? || params.empty?

        {}
      end

      def start(state, params) = Run.new(skill: name, params: normalize(params), state:)
    end
  end
end
