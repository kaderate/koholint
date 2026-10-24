require 'koholint/game_state'
require 'koholint/modes'

module Koholint
  # Whether the engine may map the screen or decide: fed every frame, it needs the play mode's ready signals for STABLE_FRAMES in a row.
  class Readiness
    # The BG tilemap is final 2 frames after the signals clear (readiness census of run 20261024-184627-b97e).
    STABLE_FRAMES = 2
    GATED_PHASES = %i[playing loading].freeze
    REASONS = { room_transition: 'transition', link_airborne: 'airborne', link_z: 'airborne', link_knockback: 'knockback',
                link_motion_state: 'forced' }.freeze

    def self.gated?(state) = GATED_PHASES.include?(state.phase(booted: true))

    def self.blocking(state)
      return 'loading' if state.phase(booted: true) == :loading

      field = Modes.for(state)&.ready_sets&.find { |name, values| !values.include?(state[name].to_i) }&.first
      field && REASONS.fetch(field, field.to_s)
    end

    def self.signals_ready?(state) = blocking(state).nil?

    def initialize(stable_frames: STABLE_FRAMES)
      @stable_frames = stable_frames
      @streak = 0
      @frame = nil
    end

    def observe(state)
      return if state.frame == @frame

      clear = self.class.signals_ready?(state)
      @streak = clear ? (@frame == state.frame - 1 ? @streak + 1 : 1) : 0
      @frame = state.frame
    end

    def reason(state)
      return nil unless self.class.gated?(state)

      observe(state)
      self.class.blocking(state) || (@streak < @stable_frames ? 'settling' : nil)
    end

    def ready?(state) = reason(state).nil?
  end
end
