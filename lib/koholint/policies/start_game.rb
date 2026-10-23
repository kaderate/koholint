require 'koholint/boot_script'
require 'koholint/decision'
require 'koholint/game_state'

module Koholint
  module Policies
    class StartGame
      READY_TICK_LIMIT = 24
      PROBE_PLAYING_TICK_LIMIT = 120
      PROBE_OFF_AXIS_TOLERANCE = 2
      PROBE_MIN_PIXELS = 2
      PROBE_MAX_PIXELS = 16
      PROBE_AXES = { up: [:y, -1], down: [:y, 1], left: [:x, -1], right: [:x, 1] }.freeze
      LOCKED_WAIT = { buttons: [], frames: 30 }.freeze
      AGENT_PHASES = %i[menu map save game_over cutscene unknown].freeze
      BOOT_LOCK_LIMIT_FRAMES = 1200 # counts consecutive locked observations: one free tick resets it

      def initialize(after, ready: nil, probe: false, played: false)
        @played = played
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
        @locked_ticks = 0
      end

      def observe(state, frame:)
        @played ||= state.game_mode == PLAY_MODE
        @locked_ticks = state.phase == :locked ? @locked_ticks + 1 : 0
        return observe_probing(state, frame:) if @probe && !@handed

        ready = ready_state?(state) && !locked_wait?(state)
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
        if playing?(state)
          @probe_ticks += 1
          @handed = true if @probe_ticks > PROBE_PLAYING_TICK_LIMIT
        end
        @stable = @position == position
        @position = position
        @after.observe(state, frame:) if @after.respond_to?(:observe)
      end

      def demonstrated_movement?(state)
        return false unless @pending && playing?(state)

        axis, sign = PROBE_AXES.fetch(@pending[:direction])
        other = axis == :x ? :y : :x
        along = (state[axis] - @pending[:start][axis]) * sign
        along.between?(PROBE_MIN_PIXELS, PROBE_MAX_PIXELS) && (state[other] - @pending[:start][other]).abs <= PROBE_OFF_AXIS_TOLERANCE
      end

      def boot_choice(state)
        return LOCKED_WAIT if locked_wait?(state)

        return BootScript.macro_for(state) unless @probe && playing?(state) && @stable

        choice = BootScript.probe_free(@probe_step)
        @pending = { direction: choice[:buttons].first, start: { x: state.x, y: state.y } } unless choice[:buttons].empty?
        @probe_step += 1
        choice
      end

      def ready_state?(state) = @ready.call(state) || boot_lock_capped?(state)

      def boot_lock_capped?(state) = @settle && state.phase == :locked && @locked_ticks * LOCKED_WAIT[:frames] >= BOOT_LOCK_LIMIT_FRAMES

      def playing?(state) = state.phase == :playing || boot_lock_capped?(state)

      def locked_wait?(state) = @settle && state.phase == :locked && !boot_lock_capped?(state)

      def ready?(state) = handed_screen?(state) || (@handed && (ready_state?(state) || locked_wait?(state)))

      def handed_screen?(state) = @played && AGENT_PHASES.include?(state.phase(booted: true))
    end
  end
end
