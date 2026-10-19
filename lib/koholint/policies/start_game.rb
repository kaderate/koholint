require 'koholint/boot_script'
require 'koholint/decision'

module Koholint
  module Policies
    class StartGame
      def initialize(after) = @after = after

      def decision_point_for(state) = state.controllable? ? DecisionPoint.move : DecisionPoint.macro(:boot)

      def decide(decision_point, state, context)
        return @after.decide(decision_point, state, context) if state.controllable?

        { choice: BootScript.macro_for(state), justification: 'boot script', confidence: 1.0, agent: 'start_game' }
      end
    end
  end
end
