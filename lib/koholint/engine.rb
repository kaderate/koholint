require 'digest'
require 'set'
require 'fileutils'
require 'koholint/budget'
require 'koholint/canonical_save'
require 'koholint/entities'
require 'koholint/decision'
require 'koholint/emulator'
require 'koholint/keyframes'
require 'koholint/leads'
require 'koholint/modes'
require 'koholint/perception'
require 'koholint/place_shots'
require 'koholint/readiness'
require 'koholint/replay'
require 'koholint/run'
require 'koholint/summary'
require 'koholint/vision/dialogue_shot'
require 'koholint/vision/grid_builder'

module Koholint
  class Engine
    SAVE_CHECK_EVERY = 60
    AGENT_FAILURE_LIMIT = 5
    AGENT_REFUSAL_LIMIT = 10
    STUCK_BOOT_FRAMES = 900
    STUCK_BOOT_ANY_FRAMES = 3600
    STUCK_UNKNOWN_FRAMES = 600
    NOT_READY_STUCK_FRAMES = 600
    NOT_READY_NOTABLE_FRAMES = 5

    def self.resume(run_path, budget:, policy: nil, policy_factory: nil, flow_version: Koholint::FLOW_VERSION, **options)
      run = Run.open(run_path, flow_version: flow_version)
      run.lock!
      run.truncate_trace!(run.inputs.frames)
      run.truncate_prompts!(run.inputs.frames)
      policy = policy_factory.call(run) if policy_factory
      frames = run.inputs.frames
      emulator = Replay.to(run, [frames - 1, 0].max)
      previous = Perception.read(emulator)
      emulator.step(run.inputs.each_frame.to_a.last) if frames.positive?
      new(run: run, policy: policy, budget: budget, emulator:, previous:, **options)
    end

    def initialize(run:, policy:, budget:, keyframe_every: 1800, decision_point: DecisionPoint.move, emulator: nil, pacer: nil, grid: false,
                   previous: nil)
      @run = run
      @policy = policy
      @budget = budget
      @keyframe_every = keyframe_every
      @decision_point = decision_point
      @pacer = pacer
      @fallbacks = 0
      @refusals = 0
      @emulator = emulator || Emulator.boot
      @readiness = Readiness.new
      @readiness.observe(previous) if previous
      @keyframes = Keyframes.new(File.join(run.dir, 'keyframes'))
      @builder = Vision::GridBuilder.new(trace: run.trace, beliefs: known_beliefs(run)) if grid
      @shots = PlaceShots.new(run.dir)
      @ram_hash = Digest::SHA256.hexdigest(@emulator.cartridge_ram)
      events = Trace.read(File.join(run.dir, 'trace.jsonl'))
      @played = GameState.played?(events)
      @unknown_modes = events.filter_map { |event| event['detail'] if event['type'] == 'notable' && event['kind'] == 'unknown_mode' }.to_set
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
      state, waited = await_ready(Perception.read(@emulator))
      return if @budget.exhausted

      @run.trace.emit(:perception, frame: state.frame, state: state.to_h, state_hash: @emulator.state_hash,
                                   **(waited.positive? ? { not_ready_frames: waited } : {}))
      @played ||= state.game_mode == PLAY_MODE
      @shots.capture(@emulator, state)
      note_unknown_mode(state)
      if @builder
        activity(:mapping, 'mapping the screen')
        grid = @builder.observe(@emulator, state) if Readiness.signals_ready?(state)
      end
      @policy.observe(state, frame: state.frame) if @policy.respond_to?(:observe)
      return if @budget.exhausted

      decision_point = @policy.respond_to?(:decision_point_for) ? @policy.decision_point_for(state) : @decision_point
      context = context_for(grid)
      activity(:deciding, 'deciding what to do', decision_point: decision_point.name.to_s)
      result = @policy.decide(decision_point, state, context)
      @budget.tick(cost: result[:cost_usd].to_f)
      chosen = result[:fallback] && result[:decision_point] || decision_point
      choice = chosen.validate(result[:choice])
      note_fallback(result)
      note_boot(result, state)
      emit_dialogue(result[:transcription], state)
      emit_notes(result, state)
      seen = record_prompt(result, state.frame, chosen.name)
      @run.trace.emit(:decision, frame: state.frame, decision_point: chosen.name.to_s, input: state.to_h, options: chosen.options || [],
                                 choice: choice, justification: result[:justification], confidence: result[:confidence],
                                 agent: result[:agent], latency_ms: result[:latency_ms].to_i, cost_usd: result[:cost_usd].to_f, fallback: result[:fallback] || false,
                                 **seen, **(result[:plan] ? { plan: result[:plan] } : {}))
      if choice.key?(:skill)
        activity(:acting, "acting: #{choice[:skill]}", skill: choice[:skill], params: choice[:params])
        outcome = execute(choice, state, chosen.registry, context)
        @run.trace.emit(:action, frame: @emulator.frame, skill: choice[:skill], params: choice[:params], result: outcome)
        @policy.after_action(choice:, outcome:, state: Perception.read(@emulator), frame: @emulator.frame) if @policy.respond_to?(:after_action)
      elsif chosen.name != :choose_objective
        activity(:acting, 'acting: press', skill: 'press', params: choice)
        frames = press(choice)
        @run.trace.emit(:action, frame: @emulator.frame, skill: 'press', params: choice, result: { frames: frames })
      end
      activity(:idle, 'between decisions')
    end

    def activity(kind, label, **detail)
      @acting = kind == :acting ? [label, detail] : nil
      @run.write_activity(kind:, label:, frame: @emulator.frame, detail:)
    end

    def context_for(grid)
      context = @builder ? { grid: } : {}
      context.merge(dialogue_shot: -> { Vision::DialogueShot.crop(@emulator) }, dialogue_rgb: -> { Vision::DialogueShot.rgb(@emulator) },
                    entities: -> { Entities.read(@emulator) })
    end

    def record_prompt(result, frame, name)
      prompt = result[:prompt]
      return {} unless prompt

      dir = File.join(@run.dir, 'prompts')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{frame}-#{name}.txt"), prompt)
      File.binwrite(File.join(dir, "#{frame}-#{name}.png"), result[:image]) if result[:image]
      Array(result[:images]).each_with_index { |png, n| File.binwrite(File.join(dir, "#{frame}-#{name}-#{n + 1}.png"), png) }
      { prompt_sha: Digest::SHA256.hexdigest(prompt), image: !result[:image].nil? || !Array(result[:images]).empty? }
    end

    def emit_dialogue(transcription, state)
      [transcription].flatten(1).compact.each do |entry|
        @run.trace.emit(:dialogue, frame: entry[:frame] || state.frame, place: entry[:place] || [state.room_id, state.map_id], text: entry[:text],
                                   source: 'agent', page: entry[:page], **entry.slice(:conversation, :speaker, :cached))
      end
    end

    def emit_notes(result, state)
      Array(result[:leads]).each { |lead| @run.trace.emit(:lead, frame: state.frame, **lead) }
      rejected = result[:leads_rejected].to_i
      @run.trace.emit(:notable, frame: state.frame, kind: 'lead_rejected', detail: "#{rejected} leads whose quote is not in the transcription") if rejected.positive?
      @run.trace.emit(:goal, frame: state.frame, text: result[:goal]) if result[:goal]
      Array(result[:notables]).each { |note| @run.trace.emit(:notable, frame: state.frame, kind: note[:kind], detail: note[:detail]) }
    end

    def note_unknown_mode(state)
      return @unknown_since = nil unless @played && state.phase(booted: true) == :unknown

      @unknown_since ||= state.frame
      @budget.stop!(:unknown_mode_stuck) if state.frame - @unknown_since > STUCK_UNKNOWN_FRAMES
      detail = Modes.tuple(state).map { |field, value| "#{field}=#{value}" }.join(' ')
      @run.trace.emit(:notable, frame: state.frame, kind: 'unknown_mode', detail:) if @unknown_modes.add?(detail)
    end

    def note_fallback(result)
      return if @budget.exhausted

      if result[:refused]
        @refusals += 1
        @budget.stop!(:agent_refusals) if @refusals >= AGENT_REFUSAL_LIMIT
        return
      end

      @refusals = 0
      @fallbacks = result[:fallback] ? @fallbacks + 1 : 0
      @budget.stop!(:agent_failures) if @fallbacks >= AGENT_FAILURE_LIMIT
    end

    def note_boot(result, state)
      return @boot_since = nil unless result[:agent] == 'start_game'

      @boot_since ||= state.frame
      limit = @played && state.game_mode != PLAY_MODE ? STUCK_BOOT_FRAMES : STUCK_BOOT_ANY_FRAMES
      @budget.stop!(:stuck_boot) if state.frame - @boot_since > limit
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

    def execute(choice, state, registry, context = {})
      execution = registry.start(choice[:skill], state, choice[:params], context)
      current = state
      loop do
        buttons = execution.next_input(current)
        break unless buttons

        if @budget.exhausted
          execution.abort(:budget)
          break
        end

        current = step(buttons)
        @shots.capture(@emulator, current)
      end
      finish_frames(execution.frames)
      execution.result(current)
    end

    def step(buttons)
      @emulator.step(buttons)
      @run.inputs.append(buttons)
      @budget.tick(frames: 1)
      after_frame
      Perception.read(@emulator).tap { |state| @readiness.observe(state) }
    end

    # Between decisions only: a skill runs to its end, and the next observation waits here, stepping no input.
    def await_ready(state)
      waited = 0
      reasons = Hash.new(0)
      while (reason = @readiness.reason(state))
        if waited >= NOT_READY_STUCK_FRAMES
          @budget.stop!(:not_ready_stuck)
          break
        end
        break if @budget.exhausted

        reasons[reason] += 1
        state = step([])
        waited += 1
      end
      finish_frames(waited) if waited.positive?
      if waited > NOT_READY_NOTABLE_FRAMES
        @run.trace.emit(:notable, frame: state.frame, kind: 'not_ready_wait', detail: { frames: waited, reason: reasons.max_by(&:last).first })
      end
      [state, waited]
    end

    def finish_frames(done)
      @run.inputs.flush
      if @pacer
        label, detail = @acting
        activity(:acting, "#{label} (paced)", **detail, paced: true) if label
        @pacer.pace(done)
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
      { 'world.json' => -> { Leads.write_world(@run.dir) }, 'summary.json' => -> { Summary.write(@run.dir) } }.each do |file, write|
        write.call
      rescue StandardError => e
        warn "koholint: #{file} not written: #{e.message}"
      end
      activity(:stopped, "stopped: #{reason}", reason: reason.to_s)
      reason
    end
  end
end
