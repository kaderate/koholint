module Koholint
  module Policies
    class Delegated
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
          { choice: SCREEN_WAIT, justification: "#{state.mode.name}: waiting for the screen to settle", confidence: 1.0, agent: 'delegated',
            latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
        end

        def game_over_continue(state)
          option, text = state.mode.choices.first
          unless @over
            @notes << { kind: 'death', detail: "game over: #{text}" }
            @deaths[[state.room_id, state.map_id]] += 1
          end
          @over = @died = @locked_wait = true
          { choice: { skill: 'choose_option', params: { option: } }, justification: "game over: #{text} (picked by the harness)", confidence: 1.0,
            agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
        end

        def note_lock(choice, outcome, state)
          pos = [state.x, state.y]
          @locks.clear if state.dialog_open? || (@locks.any? && @locks.last[:pos] != pos)
          skill = choice[:skill]
          if LOCK_SKILLS.include?(skill)
            stopped = outcome[:stopped_by].to_s
            if stopped == 'blocked' && outcome[:moved_cells].to_i.zero? && outcome[:moved_px].to_i.zero?
              params = choice[:params] || {}
              direction = PATH_SKILLS.include?(skill) ? nil : (params[:direction] || params['direction']).to_s
              @locks << { direction:, pos: }
              @locks.shift while @locks.size > LOCK_BUFFER
            elsif stopped != 'no_path'
              @locks.clear
            end
          end
          latch_hemmed(state)
        end

        def latch_hemmed(state)
          return if @hemmed && @hemmed[:waits] < HEMMED_WAIT_LIMIT && hemmed?(state)
          return if state.dialog_open? || @locks.size < HEMMED_ATTEMPTS || @locks.filter_map { |l| l[:direction] }.uniq.size < HEMMED_DIRECTIONS

          @hemmed = { pos: @locks.first[:pos], place: [state.room_id, state.map_id], waits: 0, attempts: @locks.count { |l| l[:direction] } }
        end

        def hemmed?(state) = !!@hemmed && !state.dialog_open? && [state.x, state.y] == @hemmed[:pos] && [state.room_id, state.map_id] == @hemmed[:place]

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
              @objectives.touch(frame: state.frame)
            end
          elsif @locked_since && !state.loading?
            @settle_until = state.frame + [locked_frames(state), SETTLE_FRAMES].min if state.phase == :playing && locked_frames(state).positive?
            @locked_since = nil
            @objectives.touch(frame: state.frame)
          end
        end

        def locked_frames(state) = @locked_since ? state.frame - @locked_since : 0

        def locked_waiting?(state)
          track_locked(state)
          return false unless Modes::HELD.include?(state.phase)
          return true if locked_frames(state) < LOCKED_WAIT_LIMIT_FRAMES

          unless @lock_capped == @locked_since
            @lock_capped = @locked_since
            @notes << { kind: 'lock_cap', detail: "#{state.mode&.name || state.phase} held Link for #{locked_frames(state)} frames: the model decides from now on" }
          end
          false
        end

        def locked_wait
          @locked_wait = true
          { choice: LOCKED_WAIT, justification: 'locked: waiting for Link to be free', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
            fallback: false, prompt: nil, image: nil }
        end

        # Scenes release Link for a few frames between two locks (3 in the sword scene of 242/0, 1 after the owl of 128/0), so a lock is trusted over only after a wait as long as itself, up to SETTLE_FRAMES.
        def settling?(state) = !!@settle_until && state.phase == :playing && state.frame < @settle_until

        def settle_wait(state)
          @locked_wait = true
          frames = @settle_until - state.frame
          { choice: { skill: 'wait', params: { frames: } }, justification: "locked: Link was just released, waiting #{frames} frames in case the scene goes on",
            confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
        end

        def hemmed_wait
          @waiting = true
          @hemmed[:waits] += 1
          @locks.clear if @hemmed[:waits] >= HEMMED_WAIT_LIMIT
          { choice: HEMMED_WAIT, justification: 'deterministic hemmed-in wait: blocked in several directions without movement at the same position',
            confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
        end
      end
    end
  end
end
