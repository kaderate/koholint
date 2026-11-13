require_relative 'support/delegated_helpers'

class DelegatedEngineTest < Minitest::Test
  include DelegatedHelpers

  def wait(frames = 30) = ok('skill' => 'wait', 'params' => { 'frames' => frames })
  def leave_house = ok('title' => 'leave', 'predicate' => { 'kind' => 'leave_place', 'place' => [163, 16] })
  def down = Reply.new(nil, 0.0, nil, nil, 'transport down')

  QuietRevisit = Class.new(Koholint::Revisit) { def candidate(**) = nil }

  def agent_engine(run, client, emulator: nil, revisit: QuietRevisit, **limits)
    delegated = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default,
                                                  objectives: Koholint::Objectives.new(trace: run.trace), manual: '',
                                                  revisit: revisit.new(talk_log: Koholint::TalkLog.new))
    policy = Koholint::Policies::StartGame.new(delegated, ready: ->(s) { %i[playing dialogue].include?(s.phase) })
    Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new(**limits), grid: true, emulator:)
  end

  def with_run
    Dir.mktmpdir do |dir|
      yield Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
    end
  end

  def events(run, type) = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).select { |e| e['type'] == type.to_s }

  def test_scripted_run_traces_cost_objectives_and_replays_bit_exact
    skip_without_rom!
    with_run do |run|
      client = ScriptedClient.new(objective: [ok('title' => 'x')] + [leave_house] * 40, default: wait)
      assert_equal :frames, agent_engine(run, client, frames: 4200).run
      agent = events(run, :decision).select { |d| d['agent'] == 'claude' }
      assert_equal %w[choose_skill choose_objective choose_skill], agent.first(3).map { |d| d['decision_point'] }
      assert agent.first['fallback']
      assert_match(/title|predicate/, agent.first['justification'])
      assert_equal 'wait', agent.first['choice']['skill']
      assert_equal [200, 0.01], [agent[1]['latency_ms'], agent[1]['cost_usd']]
      statuses = events(run, :objective).map { |e| e['status'] }
      assert_includes statuses, 'abandoned'
      assert_equal [], Koholint::Replay.verify(run, every: 600).reject(&:last)
    end
  end

  def test_cap_smaller_than_one_reply_stops_cleanly_on_dollars
    skip_without_rom!
    with_run do |run|
      client = ScriptedClient.new(default: leave_house)
      assert_equal :dollars, agent_engine(run, client, emulator: EmulatorCache.interactive, dollars: 0.005).run
      assert_equal 1, client.calls.size
      assert_equal ['dollars'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 1, events(run, :stop).size
    end
  end

  def test_a_cancel_after_four_failures_keeps_the_stopped_reason
    skip_without_rom!
    with_run do |run|
      engine = nil
      client = ScriptedClient.new(default: down)
      client.define_singleton_method(:call) do |**kw|
        engine.request_stop if calls.size == 4
        super(**kw)
      end
      engine = agent_engine(run, client, emulator: EmulatorCache.interactive)
      assert_equal :stopped, engine.run
      assert_equal 5, client.calls.size
    end
  end

  def test_engine_errors_stop_as_engine_errors_and_never_as_agent_failures
    skip_without_rom!
    broken = Class.new(QuietRevisit) { def next_action(**) = raise(ArgumentError, 'cell out of range: -1, 7') }
    with_run do |run|
      client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), default: walk)
      assert_equal :engine_errors, agent_engine(run, client, emulator: EmulatorCache.interactive, revisit: broken).run
      assert_equal 1, client.calls.size
      failed = events(run, :decision).select { |e| e['fallback'] }
      assert_equal 5, failed.size
      assert(failed.all? { |e| e['engine_error'] && e['agent'] == 'engine' && e['cost_usd'].zero? })
      assert_match(/\AArgumentError: cell out of range: -1, 7 at .+delegated_engine_test\.rb:\d+/, failed.first['justification'])
      assert_equal ['engine_errors'], events(run, :budget_stop).map { |e| e['kind'] }
    end
  end

  def test_five_consecutive_failures_stop_the_run
    skip_without_rom!
    with_run do |run|
      client = ScriptedClient.new(default: down)
      assert_equal :agent_failures, agent_engine(run, client, emulator: EmulatorCache.interactive).run
      assert_equal 5, client.calls.size
      assert_equal ['agent_failures'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 'agent_failures', events(run, :stop).last['reason']
    end
  end

  def test_a_success_resets_the_failure_count
    skip_without_rom!
    with_run do |run|
      script = [down] * 4 + [leave_house, wait] + [down] * 4 + [wait]
      client = eng = nil
      stopper = -> { client.calls.size >= 10 ? eng.request_stop : nil; down }
      client = ScriptedClient.new(objective: script.first(5), skill: script.drop(5), default: stopper)
      eng = agent_engine(run, client, emulator: EmulatorCache.interactive)
      assert_equal :stopped, eng.run
      assert_operator client.calls.size, :>=, 10
    end
  end

  def test_a_dialogue_crop_goes_to_the_agent_and_only_its_text_to_the_trace
    skip_without_rom!
    emulator = EmulatorCache.at(700)
    emulator.step until Koholint::Perception.read(emulator).dialog_open?
    with_run do |run|
      eng = nil
      leads = [{ 'quote' => 'ah! enfin', 'claim' => 'someone waited', 'importance' => 'normal' }, { 'quote' => 'nope', 'claim' => 'c', 'importance' => 'low' }]
      talk = -> { eng.request_stop; ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Ah! Enfin...', 'leads' => leads, 'goal' => 'wake up') }
      client = ScriptedClient.new(objective: leave_house, skill: talk)
      eng = agent_engine(run, client, emulator:)
      assert_equal :stopped, eng.run
      image = client.calls.find { |c| c[:images] }[:images].first
      assert image.start_with?("\x89PNG".b)
      assert_operator events(run, :decision).count { |d| d['justification'] == 'automatic dialogue advance' }, :>=, 1
      event = events(run, :dialogue).first
      assert_equal 'Ah! Enfin...', event['text']
      assert_equal 'agent', event['source']
      assert_equal 1, event['page']
      assert_equal 2, event['place'].size
      refute_includes File.read(File.join(run.dir, 'trace.jsonl')), 'PNG'
      assert_equal [['lead-1', 'ah! enfin', 'normal']], events(run, :lead).map { |e| e.values_at('id', 'quote', 'importance') }
      assert_equal ['wake up'], events(run, :goal).map { |e| e['text'] }
      assert_equal ['lead_rejected'], events(run, :notable).map { |e| e['kind'] }
      world = JSON.parse(File.read(File.join(run.dir, 'world.json')))
      assert_equal ['wake up', ['lead-1']], [world['goal'], world['leads'].map { |l| l['id'] }]
    end
  end

  def prompt_files(run) = Dir.glob(File.join(run.dir, 'prompts', '*')).map { |f| File.basename(f) }.sort

  def test_the_engine_writes_prompts_and_images_and_traces_their_hash
    skip_without_rom!
    emulator = EmulatorCache.at(700)
    emulator.step until Koholint::Perception.read(emulator).dialog_open?
    with_run do |run|
      eng = nil
      talk = -> { eng.request_stop; ok('skill' => 'advance_dialogue', 'params' => {}) }
      client = ScriptedClient.new(objective: leave_house, skill: talk)
      eng = agent_engine(run, client, emulator:)
      eng.run
      agent = events(run, :decision).select { |d| d['agent'] == 'claude' }
      assert_equal [false, true], agent.map { |d| d['image'] }
      auto = events(run, :decision).select { |d| d['agent'] == 'delegated' && d['justification'] == 'automatic dialogue advance' }
      assert_operator auto.size, :>=, 1
      auto.each { |d| assert_nil d['prompt_sha'] }
      agent.zip(client.calls).each do |event, call|
        base = "#{event['frame']}-#{event['decision_point']}"
        assert_equal call[:prompt], File.read(File.join(run.dir, 'prompts', "#{base}.txt"))
        assert_equal Digest::SHA256.hexdigest(call[:prompt]), event['prompt_sha']
      end
      png = Dir.glob(File.join(run.dir, 'prompts', '*.png'))
      assert_operator png.size, :>=, 1
      assert_operator png.size, :<=, 5
      png.each { |f| assert_match(/-choose_skill-\d\.png\z/, f) }
      assert File.binread(png.first).start_with?("\x89PNG".b)
      refute_includes File.read(File.join(run.dir, 'trace.jsonl')), 'PNG'
    end
  end

  class Spy
    attr_reader :observed, :cancelled

    def initialize = (@observed = []; @cancelled = false)
    def observe(state, frame:) = @observed << [state.phase, frame]
    def cancel = @cancelled = true
    def decision_point_for(_state) = Koholint::DecisionPoint.macro(:spy)
    def decide(*) = { choice: { buttons: [], frames: 5 }, justification: 'x', confidence: 1.0, agent: 'spy' }
  end

  def test_observe_runs_on_every_tour_and_request_stop_cancels_the_policy
    skip_without_rom!
    with_run do |run|
      spy = Spy.new
      eng = Koholint::Engine.new(run:, policy: spy, budget: Koholint::Budget.new(frames: 400))
      eng.run
      assert_equal events(run, :perception).map { |e| e['frame'] }, spy.observed.map(&:last)
      eng.request_stop
      assert spy.cancelled
    end
  end

  def test_the_agent_gets_control_only_once_link_has_stopped_moving
    skip_without_rom!
    with_run do |run|
      eng = nil
      client = ScriptedClient.new(default: -> { eng.request_stop; leave_house })
      eng = agent_engine(run, client)
      eng.run
      first = events(run, :decision).find { |d| d['agent'] == 'claude' }
      earlier = events(run, :perception).select { |p| p['frame'] <= first['frame'] }.last(2).map { |p| p['state'].values_at('x', 'y', 'game_mode') }
      assert_equal earlier.first, earlier.last
      assert_includes %i[playing dialogue], Koholint::GameState.new(**first['input'].transform_keys(&:to_sym)).phase
    end
  end

  def test_a_two_step_budget_stops_after_the_second_terminal_objective
    skip_without_rom!
    with_run do |run|
      budget = Koholint::Budget.new(steps: 2)
      objectives = Koholint::Objectives.new(trace: run.trace, stall_frames: 30)
      far = ok('title' => 'far', 'predicate' => { 'kind' => 'reach_place', 'place' => [0, 0] })
      client = ScriptedClient.new(objective: [far, far, far], default: wait)
      delegated = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives:, on_step: budget.method(:step_done),
                                                    revisit: QuietRevisit.new(talk_log: Koholint::TalkLog.new))
      policy = Koholint::Policies::StartGame.new(delegated, ready: ->(s) { %i[playing dialogue].include?(s.phase) })
      eng = Koholint::Engine.new(run:, policy:, budget:, grid: true, emulator: EmulatorCache.interactive)
      assert_equal :steps, eng.run
      assert_equal ['steps'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 1, events(run, :stop).size
      assert_equal %w[abandoned abandoned], events(run, :objective).map { |e| e['status'] }.select { |s| s != 'started' }
    end
  end

  class TitledMacroPolicy
    def decision_point_for(_state) = Koholint::DecisionPoint.macro(:test)

    def decide(*)
      { choice: { buttons: [:a], frames: 3, title: 'extra' }, justification: 'x', confidence: 1.0, agent: 'test' }
    end
  end

  def test_a_macro_choice_with_a_title_key_still_presses
    skip_without_rom!
    with_run do |run|
      eng = Koholint::Engine.new(run:, policy: TitledMacroPolicy.new, budget: Koholint::Budget.new(frames: 3), emulator: EmulatorCache.interactive)
      eng.run
      assert_equal 3, Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
      assert_equal ['press'], events(run, :action).map { |a| a['skill'] }
    end
  end

  class RefusingPolicy
    def initialize(script) = (@script = script.dup; @point = Koholint::DecisionPoint.choose_skill(Koholint::Skills::Registry.default))
    def decision_point_for(_state) = @point

    def decide(_point, _state, _context)
      refused = @script.shift
      if refused == :autopilot
        return { choice: { skill: 'wait', params: { frames: 1 } }, justification: 'autopilot', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0,
                 fallback: false, autopilot: true }
      end

      { choice: { skill: 'wait', params: { frames: 1 } }, justification: 'x', confidence: 0.0, agent: 'claude', latency_ms: 0, cost_usd: 0.0,
        fallback: refused != :ok, decision_point: @point, **(refused == :refused ? { refused: true } : {}) }
    end
  end

  def refusal_run(script, limit_calls: nil)
    skip_without_rom!
    with_run do |run|
      policy = RefusingPolicy.new(script)
      engine = Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new(frames: 400), emulator: EmulatorCache.interactive)
      yield engine.run, run
    end
  end

  def test_ten_consecutive_refusals_stop_the_run_five_do_not
    refusal_run([:refused] * 5 + [:ok] * 400) { |reason, _| assert_equal :frames, reason }
    refusal_run([:refused] * 10 + [:ok] * 400) do |reason, run|
      assert_equal :agent_refusals, reason
      assert_equal ['agent_refusals'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 10, events(run, :decision).size
    end
  end

  def test_refusals_neither_reset_nor_count_as_failures_and_a_success_resets_them
    refusal_run([:failed] * 4 + [:refused] * 9 + [:ok] + [:refused] * 9 + [:ok] * 400) { |reason, _| assert_equal :frames, reason }
    refusal_run([:failed] * 4 + [:refused] * 9 + [:failed] + [:ok] * 400) { |reason, _| assert_equal :agent_failures, reason }
  end

  def test_autopilot_decisions_are_traced_and_reset_neither_failures_nor_refusals
    refusal_run([:failed] * 4 + [:autopilot] * 3 + [:failed] + [:ok] * 400) do |reason, run|
      assert_equal :agent_failures, reason
      assert_equal [true] * 3, events(run, :decision).filter_map { |e| e['autopilot'] }
    end
    refusal_run([:refused] * 9 + [:autopilot] + [:refused] + [:ok] * 400) { |reason, _| assert_equal :agent_refusals, reason }
  end

  def test_resume_abandons_dangling_objectives_and_does_not_reuse_ids
    skip_without_rom!
    with_run do |run|
      Koholint::Engine.new(run:, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new(frames: 300)).run
      predicate = { 'kind' => 'dialogue_closed' }
      run.trace.emit(:objective, frame: 100, id: 'obj-1', status: 'started', title: 'a', predicate:)
      run.trace.emit(:objective, frame: 120, id: 'obj-1', status: 'achieved', predicate:)
      run.trace.emit(:objective, frame: 130, id: 'obj-2', status: 'started', title: 'b', predicate:)
      run.trace.emit(:objective, frame: 9999, id: 'obj-3', status: 'started', title: 'c', predicate:)
      made = nil
      factory = lambda do |reopened|
        made = Koholint::Objectives.resume(trace: reopened.trace, events: Koholint::Trace.read(File.join(reopened.dir, 'trace.jsonl')),
                                           frame: reopened.inputs.frames)
        Koholint::Policies::WalkAndTalk.new
      end
      Koholint::Engine.resume(run.dir, policy_factory: factory, budget: Koholint::Budget.new(frames: 30)).run
      abandoned = events(run, :objective).select { |e| e['status'] == 'abandoned' }
      assert_equal [['obj-2', 'resume']], abandoned.map { |e| [e['id'], e['reason']] }
      assert_equal 'obj-3', made.start(frame: 330, title: 'n', predicate:)
    end
  end

  def test_a_fresh_agent_boot_waits_through_the_bed_lock_and_never_asks_before_the_dialogue
    skip_without_rom!
    with_run do |run|
      eng = nil
      client = ScriptedClient.new(objective: leave_house, default: -> { eng.request_stop; wait })
      eng = agent_engine(run, client)
      eng.run
      trace = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl'))
      opened = trace.find { |e| e['type'] == 'perception' && e['state']['dialog_state'].to_i.positive? }
      asked = trace.find { |e| e['type'] == 'decision' && e['agent'] == 'claude' }
      assert opened
      assert_operator asked['frame'], :>=, opened['frame']
      waits = trace.select { |e| e['type'] == 'decision' && e['justification'] == 'locked: waiting for Link to be free' }
      assert_operator waits.size, :>, 0
      assert_equal [], Koholint::Replay.verify(run, every: 600).reject(&:last)
    end
  end
end
