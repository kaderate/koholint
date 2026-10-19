require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/agents/claude_cli'
require 'koholint/policies/delegated'
require 'koholint/policies/start_game'
require 'koholint/skills/registry'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/policies/walk_and_talk'
require 'support/emulator_cache'

module DelegatedHelpers
  Reply = Koholint::Agents::Reply

  class ScriptedClient
    attr_reader :calls

    def initialize(objective: nil, skill: nil, default: nil)
      @objective = [objective].flatten(1).compact
      @skill = [skill].flatten(1).compact
      @default = default
      @calls = []
    end

    def call(system:, prompt:, schema:, image: nil)
      @calls << { system:, prompt:, schema:, image: }
      queue = system.include?('choose the next objective') ? @objective : @skill
      step = queue.empty? ? @default : queue.shift
      raise step if step.is_a?(Exception)

      step.respond_to?(:call) ? step.call : step
    end
  end

  def ok(output = nil, cost: 0.01, **fields) = Reply.new((output || fields).merge('justification' => 'because', 'confidence' => 0.5), cost, 200, {}, nil)
  def failing(message) = Reply.new(nil, 0.02, nil, nil, message)
  def objective(kind: 'leave_place', place: [163, 16]) = ok('title' => 'go', 'predicate' => { 'kind' => kind, 'place' => place })
  def walk(direction = 'up') = ok('skill' => 'walk', 'params' => { 'direction' => direction, 'cells' => 1 })

  def state(**over)
    Koholint::GameState.new(frame: 100, room_id: 163, map_id: 16, x: 68, y: 60, direction: :up, hp: 24, max_hp: 24,
                            milestone: :none, game_mode: 0x0B, game_submode: 7, dialog_state: 0, **over)
  end

  def grid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
  end

  def trace
    @dir ||= Dir.mktmpdir
    Koholint::Trace.new(File.join(@dir, 'trace.jsonl'))
  end

  def teardown = (FileUtils.rm_rf(@dir) if @dir)

  def policy(client, **opts)
    @objectives = Koholint::Objectives.new(trace: trace, **opts)
    Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: 'notes')
  end

  def decide(policy, state = self.state)
    point = policy.decision_point_for(state)
    [point, policy.decide(point, state, { grid: })]
  end
end

class DelegatedPolicyTest < Minitest::Test
  include DelegatedHelpers

  def test_asks_for_an_objective_first_then_for_skills
    p = policy(ScriptedClient.new(objective: objective, skill: walk))
    point, result = decide(p)
    assert_equal :choose_objective, point.name
    assert_equal 'go', result[:choice][:title]
    assert_equal 'claude', result[:agent]
    assert_equal 'obj-1', @objectives.current[:id]
    point, result = decide(p)
    assert_equal :choose_skill, point.name
    assert_equal 'walk', result[:choice][:skill]
    assert_equal %i[skill params], result[:choice].keys
    assert_equal 'because', result[:justification]
    assert_equal 200, result[:latency_ms]
    assert_in_delta 0.01, result[:cost_usd]
  end

  def test_overlay_frames_reuse_the_last_grid_or_a_blank_one
    client = ScriptedClient.new(objective: objective, skill: [walk, walk])
    p = policy(client)
    results = [{ grid: nil }, { grid: }, { grid: nil }].map { |context| p.decide(p.decision_point_for(state), state, context) }
    refute(results.any? { |r| r[:fallback] }, results.map { |r| r[:justification] }.inspect)
    assert_includes client.calls.first[:prompt], '? ? ? ?'
  end

  def test_prompt_carries_system_schema_and_manual
    client = ScriptedClient.new(objective: objective)
    decide(policy(client))
    call = client.calls.first
    assert_includes call[:system], 'choose the next objective'
    assert_includes call[:prompt], 'notes'
    assert_equal 'object', call[:schema][:type]
  end

  def test_invalid_output_falls_back_to_wait
    p = policy(ScriptedClient.new(objective: ok('title' => '', 'predicate' => { 'kind' => 'nope' })))
    point, result = decide(p)
    assert_equal :choose_objective, point.name
    assert result[:fallback]
    assert_equal({ skill: 'wait', params: { frames: 30 } }, result[:choice])
    assert_match(/title|predicate/, result[:justification])
    assert_nil @objectives.current
    assert_equal :choose_skill, result[:decision_point].name
  end

  def test_error_reply_exception_and_garbage_never_raise
    [failing('timeout after 90s'), RuntimeError.new('boom'), Reply.new('nope', 0.0, 1, {}, nil)].each do |step|
      p = policy(ScriptedClient.new(objective: objective, skill: step))
      decide(p)
      _point, result = decide(p)
      assert result[:fallback], step.inspect
      assert_equal 'wait', result[:choice][:skill]
      refute_empty result[:justification]
    end
  end

  def test_failed_reply_still_reports_its_cost
    p = policy(ScriptedClient.new(objective: failing('claude error: x')))
    _point, result = decide(p)
    assert_in_delta 0.02, result[:cost_usd]
  end

  def test_after_action_records_attempt_and_achieved_objective_asks_again
    p = policy(ScriptedClient.new(objective: [objective(kind: 'reach_place', place: [1, 2]), objective], skill: walk))
    decide(p)
    decide(p)
    outcome = { skill: 'walk', params: { direction: 'up', cells: 1 }, frames: 16, moved_cells: 1, room_changed: true, hp_delta: 0, stopped_by: 'done' }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state: state(room_id: 1, map_id: 2), frame: 116)
    assert_nil @objectives.current
    assert_equal :achieved, @objectives.history.last[:outcome]
    assert_equal :choose_objective, p.decision_point_for(state).name
  end

  def test_attempts_and_last_results_reach_the_next_prompt
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    outcome = { skill: 'walk', params: { direction: 'up', cells: 1 }, frames: 16, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked' }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state:, frame: 116)
    decide(p)
    assert_includes client.calls.last[:prompt], 'Attempts on this objective'
    assert_includes client.calls.last[:prompt], 'stopped_by blocked'
  end

  def test_repeated_no_op_choices_abandon_the_objective
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2])), loop_window: 3)
    decide(p)
    outcome = { skill: 'walk', params: { direction: 'up', cells: 1 }, frames: 1, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked' }
    5.times { |i| p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state:, frame: 101 + i) }
    assert_nil @objectives.current
    assert_equal 'loop', @objectives.history.last[:reason]
  end

  def test_keeps_only_the_last_six_results
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    8.times do |i|
      p.after_action(choice: { skill: 'wait', params: { frames: i + 1 } },
                     outcome: { skill: 'wait', params: { frames: i + 1 }, frames: i + 1, moved_cells: 0 }, state:, frame: 101 + i)
    end
    decide(p)
    prompt = client.calls.last[:prompt]
    assert_equal 6, prompt.scan(/^- wait \{"frames":\d+\}: stopped_by/).size
    refute_includes prompt, 'wait {"frames":2}: stopped_by'
    assert_includes prompt, '{"frames":8}: stopped_by'
  end

  def test_programming_errors_propagate
    p = policy(ScriptedClient.new(objective: -> { nil.missing }))
    assert_raises(NoMethodError) { decide(p) }
  end

  def test_unexpected_errors_name_their_class
    p = policy(ScriptedClient.new(objective: ArgumentError.new('odd')))
    assert_equal 'ArgumentError: odd', decide(p).last[:justification]
  end

  def test_grid_is_dropped_when_the_room_changes
    client = ScriptedClient.new(objective: [objective, objective])
    p = policy(client)
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    marked = Koholint::Vision::Grid.new(cells:, static_sprites: [{ 'x' => 36, 'y' => 24, 'pattern' => 'p' }],
                                        beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
    point = Koholint::DecisionPoint.choose_objective
    p.decide(point, state, { grid: marked })
    p.decide(point, state(room_id: 1), { grid: nil })
    refute_equal client.calls.first[:prompt][/Grid.*Legend/m], client.calls.last[:prompt][/Grid.*Legend/m]
  end

  SHOT = 'PNGBYTES'.b
  def talk(text = nil) = ok({ 'skill' => 'advance_dialogue', 'params' => {} }.merge(text ? { 'transcription' => text } : {}))

  def decide_with_shot(policy, state)
    policy.decide(policy.decision_point_for(state), state, { grid:, dialogue_shot: -> { SHOT } })
  end

  def test_the_crop_is_sent_only_in_the_dialogue_phase_with_a_skill_choice
    client = ScriptedClient.new(objective: objective, skill: [walk, walk, walk])
    p = policy(client)
    decide_with_shot(p, state(dialog_state: 130))
    decide_with_shot(p, state)
    decide_with_shot(p, state(dialog_state: 130))
    decide_with_shot(p, state(game_submode: 3, dialog_state: 130))
    assert_equal [nil, nil, SHOT, nil], client.calls.map { |c| c[:image] }
  end

  def test_a_transcription_is_returned_with_the_page_counted_since_the_dialogue_opened
    client = ScriptedClient.new(objective: objective, skill: [talk('Hello'), talk(' '), talk('Next'), talk('Again')])
    p = policy(client)
    decide_with_shot(p, state)
    open = state(dialog_state: 130)
    first = decide_with_shot(p, open)
    assert_equal({ text: 'Hello', page: 0 }, first[:transcription])
    p.after_action(choice: first[:choice], outcome: { stopped_by: 'done' }, state: open, frame: 1)
    assert_nil decide_with_shot(p, open)[:transcription]
    p.after_action(choice: first[:choice], outcome: { stopped_by: 'done' }, state: open, frame: 2)
    assert_equal({ text: 'Next', page: 2 }, decide_with_shot(p, open)[:transcription])
    p.after_action(choice: first[:choice], outcome: { stopped_by: 'done' }, state: state, frame: 3)
    assert_equal({ text: 'Again', page: 0 }, decide_with_shot(p, open)[:transcription])
  end

  def test_the_transcription_is_capped_and_stripped_of_control_characters
    long = "A\u0000B\a\nC#{'x' * 600}"
    p = policy(ScriptedClient.new(objective: objective, skill: talk(long)))
    decide_with_shot(p, state)
    text = decide_with_shot(p, state(dialog_state: 130))[:transcription][:text]
    assert_equal 500, text.length
    assert text.start_with?("AB\nCxxx")
  end

  def test_closing_with_advance_dialogue_resets_the_page_count
    p = policy(ScriptedClient.new(objective: objective, skill: [talk('one'), talk('two')]))
    decide_with_shot(p, state)
    open = state(dialog_state: 130)
    first = decide_with_shot(p, open)
    p.after_action(choice: first[:choice], outcome: { dialog_after: false }, state: state, frame: 1)
    assert_equal 0, decide_with_shot(p, open)[:transcription][:page]
  end

  def test_a_transcription_outside_the_dialogue_phase_is_ignored
    p = policy(ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => 'ghost')))
    decide_with_shot(p, state)
    assert_nil decide_with_shot(p, state)[:transcription]
  end

  def test_a_failing_image_call_falls_back_to_wait
    p = policy(ScriptedClient.new(objective: objective, skill: failing('claude error: image')))
    decide_with_shot(p, state)
    result = decide_with_shot(p, state(dialog_state: 130))
    assert result[:fallback]
    assert_equal 'wait', result[:choice][:skill]
    assert_nil result[:transcription]
  end

  def test_malformed_params_fall_back_instead_of_crashing
    [5, 'x', nil, [1]].each do |bad|
      p = policy(ScriptedClient.new(objective: objective, skill: ok('skill' => 'advance_dialogue', 'params' => bad)))
      decide(p)
      result = decide(p).last
      assert result[:fallback], bad.inspect
      assert_equal 'wait', result[:choice][:skill]
    end
  end

  def test_boot_wrapper_forwards_after_boot_only
    delegated = policy(ScriptedClient.new(objective: objective))
    wrapper = Koholint::Policies::StartGame.new(delegated, ready: ->(s) { %i[playing dialogue].include?(s.phase) })
    assert_equal :boot, wrapper.decision_point_for(state(game_mode: 1)).name
    assert_equal :choose_objective, wrapper.decision_point_for(state).name
    assert_equal :choose_objective, wrapper.decision_point_for(state(dialog_state: 3)).name
    wrapper.after_action(choice: { buttons: [:a], frames: 1 }, outcome: {}, state:, frame: 1)
  end
end

class DelegatedEngineTest < Minitest::Test
  include DelegatedHelpers

  def wait(frames = 30) = ok('skill' => 'wait', 'params' => { 'frames' => frames })
  def leave_unreachable = ok('title' => 'leave', 'predicate' => { 'kind' => 'leave_place', 'place' => [0, 0] })
  def down = Reply.new(nil, 0.0, nil, nil, 'transport down')

  def agent_engine(run, client, emulator: nil, **limits)
    delegated = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default,
                                                  objectives: Koholint::Objectives.new(trace: run.trace), manual: '')
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
      client = ScriptedClient.new(objective: [ok('title' => 'x')] + [leave_unreachable] * 40, default: wait)
      assert_equal :frames, agent_engine(run, client, frames: 800).run
      agent = events(run, :decision).select { |d| d['agent'] == 'claude' }
      assert_equal %w[choose_skill choose_objective choose_skill], agent.first(3).map { |d| d['decision_point'] }
      assert agent.first['fallback']
      assert_match(/title|predicate/, agent.first['justification'])
      assert_equal 'wait', agent.first['choice']['skill']
      assert_equal [200, 0.01], [agent[1]['latency_ms'], agent[1]['cost_usd']]
      statuses = events(run, :objective).map { |e| e['status'] }
      assert_includes statuses, 'achieved'
      assert_equal [], Koholint::Replay.verify(run, every: 600).reject(&:last)
    end
  end

  def test_cap_smaller_than_one_reply_stops_cleanly_on_dollars
    skip_without_rom!
    with_run do |run|
      client = ScriptedClient.new(default: leave_unreachable)
      assert_equal :dollars, agent_engine(run, client, emulator: EmulatorCache.interactive, dollars: 0.005).run
      assert_equal 1, client.calls.size
      assert_equal ['dollars'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 1, events(run, :stop).size
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
      script = [down] * 4 + [leave_unreachable, wait] + [down] * 4 + [wait]
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
      talk = -> { eng.request_stop; ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Ah! Enfin...') }
      client = ScriptedClient.new(objective: leave_unreachable, skill: talk)
      eng = agent_engine(run, client, emulator:)
      assert_equal :stopped, eng.run
      image = client.calls.find { |c| c[:image] }[:image]
      assert image.start_with?("\x89PNG".b)
      event = events(run, :dialogue).first
      assert_equal 'Ah! Enfin...', event['text']
      assert_equal 'agent', event['source']
      assert_equal 0, event['page']
      assert_equal 2, event['place'].size
      refute_includes File.read(File.join(run.dir, 'trace.jsonl')), 'PNG'
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
end
