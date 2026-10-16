require 'digest'
require 'koholint/budget'
require 'koholint/canonical_save'
require 'koholint/decision'
require 'koholint/emulator'
require 'koholint/keyframes'
require 'koholint/perception'
require 'koholint/replay'
require 'koholint/run'

module Koholint
  class Engine
    SAVE_CHECK_EVERY = 60

    def self.resume(run_path, policy:, budget:, flow_version: Koholint::FLOW_VERSION, **options)
      run = Run.open(run_path, flow_version: flow_version)
      run.lock!
      run.truncate_trace!(run.inputs.frames)
      new(run: run, policy: policy, budget: budget, emulator: Replay.to(run, run.inputs.frames), **options)
    end

    def initialize(run:, policy:, budget:, keyframe_every: 1800, point: DecisionPoint.move, emulator: nil)
      @run = run
      @policy = policy
      @budget = budget
      @keyframe_every = keyframe_every
      @point = point
      @emulator = emulator || Emulator.boot
      @keyframes = Keyframes.new(File.join(run.dir, 'keyframes'))
      @ram_hash = Digest::SHA256.hexdigest(@emulator.cartridge_ram)
    end

    def request_stop = @budget.stop!

    def run
      @run.lock!
      @run.status = 'running'
      @budget.tick
      begin
        iterate until @budget.exhausted
      rescue StandardError
        stop(:error)
        raise
      end
      stop(@budget.exhausted)
    ensure
      @run.unlock!
    end

    private

    def iterate
      state = Perception.read(@emulator)
      @run.trace.emit(:perception, frame: state.frame, state: state.to_h, state_hash: @emulator.state_hash)
      point = @policy.respond_to?(:point_for) ? @policy.point_for(state) : @point
      result = @policy.decide(point, state, {})
      choice = point.validate(result[:choice])
      @run.trace.emit(:decision, frame: state.frame, point: point.name.to_s, input: state.to_h, options: point.options || [],
                                 choice: choice, justification: result[:justification], confidence: result[:confidence],
                                 agent: result[:agent], latency_ms: 0, cost_usd: 0.0, fallback: result[:fallback] || false)
      frames = press(choice)
      @run.trace.emit(:action, frame: @emulator.frame, skill: 'press', params: choice, result: { frames: frames })
    end

    def press(choice)
      done = 0
      choice[:frames].times do
        break if @budget.exhausted

        @emulator.step(choice[:buttons])
        @run.inputs.append(choice[:buttons])
        @budget.tick(frames: 1)
        done += 1
        after_frame
      end
      done
    end

    def after_frame
      frame = @emulator.frame
      checkpoint_keyframe if (frame % @keyframe_every).zero?
      detect_game_save if (frame % SAVE_CHECK_EVERY).zero?
    end

    def checkpoint_keyframe
      @run.inputs.flush
      return if @last_keyframe == @emulator.frame

      @last_keyframe = @emulator.frame
      path = @keyframes.save(@emulator)
      @run.trace.emit(:keyframe, frame: @emulator.frame, path: File.basename(path))
    end

    def detect_game_save
      hash = Digest::SHA256.hexdigest(@emulator.cartridge_ram)
      return if hash == @ram_hash

      @ram_hash = hash
      emit_save('game')
    end

    def emit_save(source)
      path, sha = CanonicalSave.write(@emulator, @run)
      @run.trace.emit(:save, frame: @emulator.frame, path: File.basename(path), sav_sha256: sha, source: source)
    end

    def stop(reason)
      @run.inputs.flush
      @run.trace.emit(:budget_stop, frame: @emulator.frame, kind: reason.to_s) unless %i[stopped error].include?(reason)
      emit_save('stop')
      checkpoint_keyframe
      @run.trace.emit(:stop, frame: @emulator.frame, reason: reason.to_s)
      @run.status = reason == :error ? 'crashed' : 'stopped'
      reason
    end
  end
end
