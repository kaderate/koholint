require 'digest'
require 'fileutils'
require 'koholint/budget'
require 'koholint/canonical_save'
require 'koholint/decision'
require 'koholint/emulator'
require 'koholint/keyframes'
require 'koholint/perception'
require 'koholint/replay'
require 'koholint/run'
require 'koholint/vision/dialogue_shot'
require 'koholint/vision/grid_builder'

module Koholint
  class Engine
    SAVE_CHECK_EVERY = 60
    AGENT_FAILURE_LIMIT = 5

    def self.resume(run_path, budget:, policy: nil, policy_factory: nil, flow_version: Koholint::FLOW_VERSION, **options)
      run = Run.open(run_path, flow_version: flow_version)
      run.lock!
      run.truncate_trace!(run.inputs.frames)
      run.truncate_prompts!(run.inputs.frames)
      policy = policy_factory.call(run) if policy_factory
      new(run: run, policy: policy, budget: budget, emulator: Replay.to(run, run.inputs.frames), **options)
    end

    def initialize(run:, policy:, budget:, keyframe_every: 1800, decision_point: DecisionPoint.move, emulator: nil, pacer: nil, grid: false)
      @run = run
      @policy = policy
      @budget = budget
      @keyframe_every = keyframe_every
      @decision_point = decision_point
      @pacer = pacer
      @fallbacks = 0
      @emulator = emulator || Emulator.boot
      @keyframes = Keyframes.new(File.join(run.dir, 'keyframes'))
      @builder = Vision::GridBuilder.new(trace: run.trace, beliefs: known_beliefs(run)) if grid
      @ram_hash = Digest::SHA256.hexdigest(@emulator.cartridge_ram)
    end

    def request_stop
      @budget.stop!
      @policy.cancel if @policy.respond_to?(:cancel)
    end

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

    def known_beliefs(run) = Vision::Beliefs.from_events(Trace.read(File.join(run.dir, 'trace.jsonl')))

    def iterate
      state = Perception.read(@emulator)
      @run.trace.emit(:perception, frame: state.frame, state: state.to_h, state_hash: @emulator.state_hash)
      grid = @builder&.observe(@emulator, state)
      @policy.observe(state, frame: state.frame) if @policy.respond_to?(:observe)
      return if @budget.exhausted

      decision_point = @policy.respond_to?(:decision_point_for) ? @policy.decision_point_for(state) : @decision_point
      result = @policy.decide(decision_point, state, context_for(grid))
      @budget.tick(cost: result[:cost_usd].to_f)
      chosen = result[:fallback] && result[:decision_point] || decision_point
      choice = chosen.validate(result[:choice])
      note_fallback(result)
      emit_dialogue(result[:transcription], state)
      seen = record_prompt(result, state.frame, chosen.name)
      @run.trace.emit(:decision, frame: state.frame, decision_point: chosen.name.to_s, input: state.to_h, options: chosen.options || [],
                                 choice: choice, justification: result[:justification], confidence: result[:confidence],
                                 agent: result[:agent], latency_ms: result[:latency_ms].to_i, cost_usd: result[:cost_usd].to_f, fallback: result[:fallback] || false,
                                 **seen)
      if choice.key?(:skill)
        outcome = execute(choice, state, chosen.registry)
        @run.trace.emit(:action, frame: @emulator.frame, skill: choice[:skill], params: choice[:params], result: outcome)
        @policy.after_action(choice:, outcome:, state: Perception.read(@emulator), frame: @emulator.frame) if @policy.respond_to?(:after_action)
      elsif chosen.name != :choose_objective
        frames = press(choice)
        @run.trace.emit(:action, frame: @emulator.frame, skill: 'press', params: choice, result: { frames: frames })
      end
    end

    def context_for(grid)
      context = @builder ? { grid: } : {}
      context.merge(dialogue_shot: -> { Vision::DialogueShot.crop(@emulator) })
    end

    def record_prompt(result, frame, name)
      prompt = result[:prompt]
      return {} unless prompt

      dir = File.join(@run.dir, 'prompts')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{frame}-#{name}.txt"), prompt)
      File.binwrite(File.join(dir, "#{frame}-#{name}.png"), result[:image]) if result[:image]
      { prompt_sha: Digest::SHA256.hexdigest(prompt), image: !result[:image].nil? }
    end

    def emit_dialogue(transcription, state)
      return unless transcription

      @run.trace.emit(:dialogue, frame: state.frame, place: [state.room_id, state.map_id], text: transcription[:text],
                                 source: 'agent', page: transcription[:page])
    end

    def note_fallback(result)
      return if @budget.exhausted

      @fallbacks = result[:fallback] ? @fallbacks + 1 : 0
      @budget.stop!(:agent_failures) if @fallbacks >= AGENT_FAILURE_LIMIT
    end

    def press(choice)
      done = 0
      choice[:frames].times do
        break if @budget.exhausted

        step(choice[:buttons])
        done += 1
      end
      finish_frames(done)
    end

    def execute(choice, state, registry)
      execution = registry.start(choice[:skill], state, choice[:params])
      current = state
      loop do
        buttons = execution.next_input(current)
        break unless buttons

        if @budget.exhausted
          execution.abort(:budget)
          break
        end

        step(buttons)
        current = Perception.read(@emulator)
      end
      finish_frames(execution.frames)
      execution.result(current)
    end

    def step(buttons)
      @emulator.step(buttons)
      @run.inputs.append(buttons)
      @budget.tick(frames: 1)
      after_frame
    end

    def finish_frames(done)
      @run.inputs.flush
      @pacer&.pace(done)
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
