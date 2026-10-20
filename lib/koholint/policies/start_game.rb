require 'koholint/boot_script'
require 'koholint/decision'

module Koholint
  module Policies
    class StartGame
      READY_TICK_LIMIT = 24
      PROBE_PLAYING_TICK_LIMIT = 120
      PROBE_OFF_AXIS_TOLERANCE = 2
      PROBE_MIN_PIXELS = 2
      PROBE_MAX_PIXELS = 16
      PROBE_AXES = { up: [:y, -1], down: [:y, 1], left: [:x, -1], right: [:x, 1] }.freeze

      def initialize(after, ready: nil, probe: false)
        @probe = probe && !ready.nil?
        @probe_step = 0
        @probe_ticks = 0
        @pending = nil
        @stable = false
        @after = after
        @settle = !ready.nil?
        @ready = ready || :controllable?.to_proc
        @handed = !@settle
        @position = nil
        @ready_ticks = 0
      end

      def observe(state, frame:)
        return observe_probing(state, frame:) if @probe && !@handed

        ready = ready_state?(state)
        @ready_ticks += 1 if ready
        @handed ||= ready && (@position == [state.x, state.y] || @ready_ticks >= READY_TICK_LIMIT)
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

        { choice: boot_choice(state), justification: 'boot script', confidence: 1.0, agent: 'start_game' }
      end

      private

      def observe_probing(state, frame:)
        position = [state.x, state.y]
        @handed = true if state.phase == :dialogue || demonstrated_movement?(state)
        @pending = nil
        if state.phase == :playing
          @probe_ticks += 1
          @handed = true if @probe_ticks > PROBE_PLAYING_TICK_LIMIT
        end
        @stable = @position == position
        @position = position
        @after.observe(state, frame:) if @after.respond_to?(:observe)
      end

      def demonstrated_movement?(state)
        return false unless @pending && state.phase == :playing

        axis, sign = PROBE_AXES.fetch(@pending[:direction])
        other = axis == :x ? :y : :x
        along = (state[axis] - @pending[:start][axis]) * sign
        along.between?(PROBE_MIN_PIXELS, PROBE_MAX_PIXELS) && (state[other] - @pending[:start][other]).abs <= PROBE_OFF_AXIS_TOLERANCE
      end

      def boot_choice(state)
        return BootScript.macro_for(state) unless @probe && state.phase == :playing && @stable

        choice = BootScript.probe_free(@probe_step)
        @pending = { direction: choice[:buttons].first, start: { x: state.x, y: state.y } } unless choice[:buttons].empty?
        @probe_step += 1
        choice
      end

      def ready_state?(state) = @ready.call(state)

      def ready?(state) = @handed && ready_state?(state)
    end
  end
end
