require 'koholint/boot_script'
require 'koholint/decision'

module Koholint
  module Policies
    class StartGame
      def initialize(after, ready: nil)
        @after = after
        @settle = !ready.nil?
        @ready = ready || :controllable?.to_proc
        @handed = !@settle
        @position = nil
      end

      def observe(state, frame:)
        @handed ||= ready_state?(state) && @position == [state.x, state.y]
        @position = [state.x, state.y]
        @after.observe(state, frame:) if @after.respond_to?(:observe)
      end

      def cancel = (@after.cancel if @after.respond_to?(:cancel))

      def decision_point_for(state)
        return DecisionPoint.macro(:boot) unless ready?(state)

        @after.respond_to?(:decision_point_for) ? @after.decision_point_for(state) : DecisionPoint.move
      end

      def after_action(**result) = (@after.after_action(**result) if @after.respond_to?(:after_action))

      def decide(decision_point, state, context)
        return @after.decide(decision_point, state, context) if ready?(state)

        { choice: BootScript.macro_for(state), justification: 'boot script', confidence: 1.0, agent: 'start_game' }
      end

      private

      def ready_state?(state) = @ready.call(state)

      def ready?(state) = @handed && ready_state?(state)
    end
  end
end
