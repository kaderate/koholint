require 'koholint/policies/base'

module Koholint
  module Policies
    class Delegated < Base
      module Waits
        private

        def screen_settling?(state)
          mode = state.mode
          settling = mode && !mode.ready.empty? && !mode.ready?(state)
          @screen_since = settling ? @screen_since || state.frame : nil
          settling && state.frame - @screen_since < SCREEN_WAIT_LIMIT_FRAMES
        end

        def screen_wait(state)
          @locked_wait = true
          DecisionPoint.harness_choice(SCREEN_WAIT, "#{state.mode.name}: waiting for the screen to settle")
        end

        def game_over_continue(state)
          option, text = state.mode.choices.first
          unless @over
            @notes << { kind: 'death', detail: "game over: #{text}" }
            @deaths[state.place] += 1
          end
          @over = @died = @locked_wait = true
          DecisionPoint.harness_choice({ skill: 'choose_option', params: { option: } }, "game over: #{text} (picked by the harness)")
        end

        def note_lock(choice, outcome, state)
          pos = [state.x, state.y]
          @locks.clear if state.dialog_open? || (@locks.any? && @locks.last[:pos] != pos)
          skill = choice[:skill]
          if LOCK_SKILLS.include?(skill)
            stopped = outcome[:stopped_by].to_s
            if stopped == 'blocked' && outcome[:moved_cells].to_i.zero? && outcome[:moved_px].to_i.zero?
              params = choice[:params] || {}
              direction = PATH_SKILLS.include?(skill) ? Ledger.pick(outcome[:blocked_at], :direction)&.to_s : (params[:direction] || params['direction']).to_s
              @locks << { direction:, pos: }
              @locks.shift while @locks.size > LOCK_BUFFER
            elsif stopped != 'no_path' && !(%w[no_frontier nothing_toward].include?(stopped) && outcome[:moved_cells].to_i.zero?)
              @locks.clear
            end
          end
          latch_hemmed(state)
        end

        def latch_hemmed(state)
          return if @hemmed && @hemmed[:waits] < HEMMED_WAIT_LIMIT && hemmed?(state)
          return if state.dialog_open? || @locks.size < HEMMED_ATTEMPTS || @locks.filter_map { |l| l[:direction] }.uniq.size < HEMMED_DIRECTIONS

          @hemmed = { pos: @locks.first[:pos], place: state.place, waits: 0, attempts: @locks.count { |l| l[:direction] } }
        end

        def hemmed?(state) = !!@hemmed && !state.dialog_open? && [state.x, state.y] == @hemmed[:pos] && state.place == @hemmed[:place]

        def release_hemmed(state)
          return unless @hemmed && !state.loading?

          clear_hemmed unless hemmed?(state)
        end

        def clear_hemmed
          @hemmed = nil
          @locks.clear
        end

        def track_locked(state)
          if Modes::HELD.include?(state.phase)
            unless @locked_since
              @locked_since = state.frame
              @scene_since = state.frame unless @released_at && state.frame - @released_at < SETTLE_FRAMES
            end
          elsif @locked_since && !state.loading?
            @settle_until = state.frame + [state.frame - @scene_since, SETTLE_FRAMES].min if state.phase == :playing && locked_frames(state).positive?
            @released_at = state.frame
            @locked_since = nil
          end
        end

        def locked_frames(state) = @locked_since ? state.frame - @locked_since : 0

        def locked_waiting?(state)
          track_locked(state)
          return false unless Modes::HELD.include?(state.phase)
          return true if state.frame - @scene_since < LOCKED_WAIT_LIMIT_FRAMES

          unless @lock_capped == @scene_since
            @lock_capped = @scene_since
            @notes << { kind: 'lock_cap', detail: "#{state.mode&.name || state.phase} held Link for #{state.frame - @scene_since} frames: the model decides from now on" }
          end
          false
        end

        def locked_wait
          @locked_wait = true
          DecisionPoint.harness_choice(LOCKED_WAIT, 'locked: waiting for Link to be free')
        end

        # Scenes release Link for a few frames between two locks (3 in the sword scene of 242/0, 1 after the owl of 128/0, 1 to 12 all through the healing scene of 83/0), so locks less than SETTLE_FRAMES apart are one scene and a release is trusted only after a wait as long as the scene so far, up to SETTLE_FRAMES.
        def settling?(state) = !!@settle_until && state.phase == :playing && state.frame < @settle_until

        def settle_wait(state)
          @locked_wait = true
          frames = @settle_until - state.frame
          DecisionPoint.harness_choice({ skill: 'wait', params: { frames:, until_held: true } }, "locked: Link was just released, waiting #{frames} frames in case the scene goes on")
        end

        # Each wait is followed by a 2-pixel step, so a hold that ends unseen (the healing scene of 83/0 ends about 50 frames after its
        # last lock) hands Link back after one wait instead of the whole window.
        def hemmed_wait
          @waiting = true
          if @hemmed[:probe]
            @hemmed[:probe] = false
            direction = HEMMED_PROBES[@hemmed[:waits] % HEMMED_PROBES.size]
            return DecisionPoint.harness_choice({ skill: 'step', params: { direction:, pixels: HEMMED_PROBE_PIXELS } }, "deterministic hemmed-in probe: a #{HEMMED_PROBE_PIXELS}-pixel step #{direction} to see whether Link is free again")
          end
          @hemmed[:waits] += 1
          @hemmed[:probe] = @hemmed[:waits] < HEMMED_WAIT_LIMIT
          @locks.clear if @hemmed[:waits] >= HEMMED_WAIT_LIMIT
          DecisionPoint.harness_choice(HEMMED_WAIT, 'deterministic hemmed-in wait: blocked in several directions without movement at the same position')
        end
      end
    end
  end
end
