require 'koholint/boot_script'
require 'koholint/decision'

module Koholint
  module Policies
    class StartGame
      def initialize(after, ready: :controllable?.to_proc)
        @after = after
        @ready = ready
      end

      def decision_point_for(state)
        return DecisionPoint.macro(:boot) unless @ready.call(state)

        @after.respond_to?(:decision_point_for) ? @after.decision_point_for(state) : DecisionPoint.move
      end

      def after_action(**result) = (@after.after_action(**result) if @after.respond_to?(:after_action))

      def decide(decision_point, state, context)
        return @after.decide(decision_point, state, context) if @ready.call(state)

        { choice: BootScript.macro_for(state), justification: 'boot script', confidence: 1.0, agent: 'start_game' }
      end
    end
  end
end
