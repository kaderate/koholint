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
    p = policy(ScriptedClient.new(objective: objective))
    decide(p)
    8.times do |i|
      p.after_action(choice: { skill: 'wait', params: { frames: i + 1 } },
                     outcome: { skill: 'wait', params: { frames: i + 1 }, frames: i + 1, moved_cells: 0 }, state:, frame: 101 + i)
    end
    assert_equal 6, p.instance_variable_get(:@last_results).size
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

  def agent_engine(run, client, **limits)
    delegated = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default,
                                                  objectives: Koholint::Objectives.new(trace: run.trace), manual: '')
    policy = Koholint::Policies::StartGame.new(delegated, ready: ->(s) { %i[playing dialogue].include?(s.phase) })
    Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new(**limits), grid: true)
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
      client = ScriptedClient.new(objective: [ok('title' => 'x'), leave_unreachable, leave_unreachable], default: wait)
      assert_equal :frames, agent_engine(run, client, frames: 800).run
      agent = events(run, :decision).select { |d| d['agent'] == 'claude' }
      assert_equal %w[choose_objective choose_objective choose_skill], agent.first(3).map { |d| d['decision_point'] }
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
      assert_equal :dollars, agent_engine(run, client, dollars: 0.005).run
      assert_equal 1, client.calls.size
      assert_equal ['dollars'], events(run, :budget_stop).map { |e| e['kind'] }
      assert_equal 1, events(run, :stop).size
    end
  end
end
