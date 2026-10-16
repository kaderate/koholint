require 'koholint/boot_script'
require 'koholint/decision'

module Koholint
  module Policies
    class StartGame
      def initialize(after) = @after = after

      def point_for(state) = state.controllable? ? DecisionPoint.move : DecisionPoint.macro(:boot)

      def decide(point, state, context)
        return @after.decide(point, state, context) if state.controllable?

        { choice: BootScript.macro_at(state.frame), justification: 'boot script', confidence: 1.0, agent: 'start_game' }
      end
    end
  end
end
