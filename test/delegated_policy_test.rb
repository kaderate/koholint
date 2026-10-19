require_relative 'test_helper'
require 'tmpdir'
require 'digest'
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

    def call(system:, prompt:, schema:, image: nil, images: nil)
      @calls << { system:, prompt:, schema:, image:, images: }
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

  def test_a_predicate_already_true_or_a_leave_of_another_place_is_rejected
    cell = { 'kind' => 'reach_cell', 'place' => [163, 16], 'row' => 3, 'col' => 4 }
    bad = [objective(kind: 'leave_place', place: [1, 2]), objective(kind: 'reach_place', place: [163, 16]),
           ok('title' => 'go', 'predicate' => cell)]
    bad.each do |reply|
      p = policy(ScriptedClient.new(objective: reply))
      _point, result = decide(p)
      assert result[:fallback], reply.output.inspect
      assert_equal 'wait', result[:choice][:skill]
      assert_match(/leave_place must name|already true/, result[:justification])
      assert_nil @objectives.current
    end
    elsewhere = ok('title' => 'go', 'predicate' => cell.merge('col' => 5))
    [elsewhere, objective(kind: 'reach_place', place: [1, 2])].each do |reply|
      p = policy(ScriptedClient.new(objective: reply))
      refute decide(p).last[:fallback]
      assert @objectives.current
    end
  end

  def test_results_carry_the_prompt_and_the_image_sent
    client = ScriptedClient.new(objective: objective, skill: talk)
    p = policy(client)
    first = decide_with_shot(p, state)
    assert_equal client.calls.first[:prompt], first[:prompt]
    assert_nil first[:image]
    second = decide_with_shot(p, state(dialog_state: 130))
    assert_equal [nil, nil, nil], second.values_at(:prompt, :image, :images)
    assert_equal 1, client.calls.size
  end

  def test_leave_place_is_achieved_at_the_first_loaded_observation_without_a_client_call
    steps = 0
    p = policy(ScriptedClient.new(objective: objective, skill: walk))
    p.instance_variable_set(:@on_step, -> { steps += 1 })
    decide(p)
    p.observe(state(frame: 110, game_submode: 3, room_id: 5), frame: 110)
    assert @objectives.current
    p.observe(state(frame: 130, room_id: 5), frame: 130)
    assert_nil @objectives.current
    assert_equal :achieved, @objectives.history.last[:outcome]
    assert_equal [1, 1], [steps, p.instance_variable_get(:@client).calls.size]
  end

  def with_plan(reply, plan) = Koholint::Agents::Reply.new(reply.output.merge('plan' => plan), reply.cost_usd, 200, {}, nil)

  def test_the_plan_is_stored_cleaned_capped_and_shown_in_the_next_prompt
    client = ScriptedClient.new(objective: with_plan(objective, "go\e talk\nto him #{'x' * 300}"), skill: [walk, walk])
    p = policy(client)
    _point, first = decide(p)
    assert_equal 200, first[:plan].size
    assert_match(/\Ago talk to him x+\z/, first[:plan])
    refute_includes client.calls[0][:prompt], 'Your plan'
    decide(p)
    assert_includes client.calls[1][:prompt], "follow it unless the situation changed): #{first[:plan]}"
    _point, second = decide(p)
    refute second.key?(:plan)
    assert_includes client.calls[2][:prompt], first[:plan]
  end

  def test_a_new_plan_replaces_the_old_one_and_a_fallback_keeps_it
    client = ScriptedClient.new(objective: with_plan(objective, 'first'), skill: [with_plan(walk, 'second'), failing('boom'), walk])
    p = policy(client)
    decide(p)
    decide(p)
    assert_includes client.calls[1][:prompt], 'follow it unless the situation changed): first'
    _point, fallback = decide(p)
    assert fallback[:fallback]
    assert_includes client.calls[2][:prompt], 'follow it unless the situation changed): second'
    decide(p)
    assert_includes client.calls[3][:prompt], 'follow it unless the situation changed): second'
  end

  def test_the_plan_is_cleared_when_an_objective_ends
    client = ScriptedClient.new(objective: [with_plan(objective, 'leave'), objective], skill: walk)
    p = policy(client)
    decide(p)
    p.observe(state(frame: 110, game_submode: 3, room_id: 5), frame: 110)
    p.observe(state(frame: 130, room_id: 5), frame: 130)
    assert_nil @objectives.current
    decide(p, state(room_id: 5))
    refute_includes client.calls[1][:prompt], 'Your plan'
  end

  def blocked_walk(p, direction, pos: [68, 60], frame: 101)
    outcome = { skill: 'walk', params: { direction:, cells: 1 }, frames: 8, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked' }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state: state(x: pos[0], y: pos[1]), frame:)
  end

  def hemmed(p, directions = %w[up right down left])
    decide(p)
    directions.each { |d| blocked_walk(p, d) }
  end

  def test_hemmed_in_waits_deterministically_without_calling_the_client
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk)
    p = policy(client)
    hemmed(p)
    calls = client.calls.size
    2.times do
      point, result = decide(p)
      assert_equal :choose_skill, point.name
      assert_equal({ skill: 'wait', params: { frames: 120 } }, result[:choice])
      assert_equal ['delegated', false, 0.0], result.values_at(:agent, :fallback, :cost_usd)
      assert_match(/deterministic/, result[:justification])
      p.after_action(choice: result[:choice], outcome: { stopped_by: 'done', moved_cells: 0 }, state:, frame: 300)
      p.observe(state, frame: 300)
    end
    assert_equal calls, client.calls.size
    assert_equal 4, @objectives.current[:attempts].size
  end

  def test_hemmed_in_waits_are_capped_to_one_stall_window_then_the_agent_is_called
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk)
    p = policy(client)
    hemmed(p)
    15.times { assert_equal 'delegated', decide(p).last[:agent] }
    assert_equal 'claude', decide(p).last[:agent]
  end

  def test_a_new_objective_clears_the_hemmed_latch
    client = ScriptedClient.new(objective: [objective(kind: 'reach_place', place: [1, 2])] * 2, skill: [walk] * 2)
    p = policy(client)
    hemmed(p)
    @objectives.abandon(frame: 200, reason: 'stall')
    _point, result = decide(p)
    assert_equal 'claude', result[:agent]
    assert @objectives.current
    assert_equal 'claude', decide(p).last[:agent]
  end

  def test_dialogue_closed_is_rejected_while_no_dialogue_is_open
    closed = ok('title' => 'close', 'predicate' => { 'kind' => 'dialogue_closed' })
    p = policy(ScriptedClient.new(objective: closed))
    result = decide(p).last
    assert result[:fallback]
    assert_match(/needs an open dialogue/, result[:justification])
    refute decide(policy(ScriptedClient.new(objective: closed)), state(dialog_state: 3)).last[:fallback]
  end

  def test_hemmed_in_releases_when_the_position_the_dialogue_or_the_place_changes
    [state(x: 69), state(room_id: 4), state(dialog_state: 3)].each do |moved|
      client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk)
      p = policy(client)
      hemmed(p)
      p.observe(moved, frame: 400)
      assert_equal 'claude', p.decide(p.decision_point_for(moved), moved, { grid: })[:agent]
    end
  end

  def test_fewer_than_four_distinct_blocked_directions_do_not_trigger_the_wait
    [%w[up up down left], %w[up right down]].each do |directions|
      p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
      hemmed(p, directions)
      assert_equal 'claude', decide(p).last[:agent]
    end
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    decide(p)
    %w[up right down].each { |d| blocked_walk(p, d) }
    blocked_walk(p, 'left', pos: [70, 60])
    assert_equal 'claude', decide(p).last[:agent]
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

  PAGE = ("\x10".b * (640 * 384 * 3)).freeze
  OPEN = { dialog_state: 130 }.freeze

  def decide_with_shot(policy, state)
    policy.decide(policy.decision_point_for(state), state, { grid:, dialogue_shot: -> { SHOT }, dialogue_rgb: -> { PAGE } })
  end

  def advance(policy, result, state, frame = 1)
    policy.after_action(choice: result[:choice], outcome: { stopped_by: 'done' }, state:, frame:)
  end

  def pages(policy, count, from: 100)
    count.times.map do |i|
      at = state(frame: from + (i * 30), **OPEN)
      result = decide_with_shot(policy, at)
      advance(policy, result, at, at.frame + 30)
      result
    end
  end

  def flush(policy, frame)
    waited = decide_with_shot(policy, state(frame:))
    assert_equal [{ skill: 'wait', params: { frames: 10 } }, 'delegated', 0.0, false], waited.values_at(:choice, :agent, :cost_usd, :fallback)
    advance(policy, waited, state(frame: frame + 10), frame + 10)
    decide_with_shot(policy, state(frame: frame + 10))
  end

  def test_a_dialogue_advances_by_itself_and_is_read_once_when_it_closes
    client = ScriptedClient.new(objective: objective, skill: [ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "One\n\nTwo\n\nThree"), ok('skill' => 'wait', 'params' => { 'frames' => 3 })])
    p = policy(client)
    decide_with_shot(p, state)
    results = pages(p, 3)
    assert_equal 1, client.calls.size
    results.each do |r|
      assert_equal [{ skill: 'advance_dialogue', params: {} }, 'automatic dialogue advance', 'delegated', 0.0, false, nil, nil],
                   r.values_at(:choice, :justification, :agent, :cost_usd, :fallback, :prompt, :image)
    end
    result = flush(p, 300)
    assert_equal 2, client.calls.size
    assert_nil client.calls.last[:image]
    assert_equal 1, client.calls.last[:images].size
    assert client.calls.last[:images].first.start_with?("\x89PNG".b)
    assert_equal [{ text: 'One', page: 1, frame: 100, place: [163, 16] }, { text: 'Two', page: 2, frame: 100, place: [163, 16] },
                  { text: 'Three', page: 3, frame: 100, place: [163, 16] }], result[:transcription]
    assert_equal 1, result[:images].size
    assert_nil decide_with_shot(p, state(frame: 320))[:transcription]
  end

  def test_automatic_pages_never_run_the_hemmed_or_attempt_logic
    p = policy(ScriptedClient.new(objective: objective, skill: walk))
    decide_with_shot(p, state)
    hemmed(p)
    pages(p, 2)
    assert_equal 0, @objectives.attempts_for_prompt.to_s.scan('advance_dialogue').size
  end

  def test_a_dialogue_that_reopens_counts_as_the_same_sequence
    client = ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "A\n\nB\n\nC\n\nD"))
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 2)
    waited = decide_with_shot(p, state(frame: 200))
    assert_equal [{ skill: 'wait', params: { frames: 10 } }, 'automatic dialogue advance: waiting for the dialogue to reopen', 'delegated', 0.0, false, nil],
                 waited.values_at(:choice, :justification, :agent, :cost_usd, :fallback, :prompt)
    advance(p, waited, state(frame: 210), 210)
    assert_equal 1, client.calls.size
    pages(p, 2, from: 215)
    result = flush(p, 400)
    assert_equal 2, client.calls.size
    assert_equal (1..4).to_a, result[:transcription].map { |t| t[:page] }
  end

  def test_the_page_cap_asks_once_then_the_agent_drives_until_the_dialogue_closes
    client = ScriptedClient.new(objective: objective, skill: [ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Early'),
                                                              ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Driven'),
                                                              ok('skill' => 'wait', 'params' => { 'frames' => 3 })])
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 40, from: 100)
    assert_equal 1, client.calls.size
    capped = decide_with_shot(p, state(frame: 1299, **OPEN))
    assert_equal 5, capped[:images].size
    assert_includes client.calls.last[:prompt], '40 pages'
    assert_includes client.calls.last[:system], 'stacked vertically in sheets'
    assert_equal 'Early', capped[:transcription].first[:text]
    advance(p, capped, state(frame: 1300, **OPEN), 1300)
    driven = decide_with_shot(p, state(frame: 1330, **OPEN))
    assert_equal SHOT, client.calls.last[:image]
    assert_equal 'claude', driven[:agent]
    refute_includes client.calls.last[:system], 'stacked vertically in sheets'
    advance(p, driven, state(frame: 1360), 1360)
    decide_with_shot(p, state(frame: 1361))
    again = decide_with_shot(p, state(frame: 1400, **OPEN))
    assert_equal 'automatic dialogue advance', again[:justification]
  end

  def test_a_dialogue_does_not_stall_the_objective_and_a_stuck_one_is_still_bounded
    p = policy(ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 })), stall_frames: 1800)
    decide_with_shot(p, state(frame: 100))
    @objectives.update(state(frame: 100), frame: 100)
    at = state(frame: 1899, **OPEN)
    @objectives.update(at, frame: 1899)
    result = decide_with_shot(p, at)
    advance(p, result, at, 1929)
    assert @objectives.current
    pages(p, 39, from: 1929)
    capped = state(frame: 3100, **OPEN)
    decide_with_shot(p, capped)
    @objectives.update(capped, frame: 3100)
    assert @objectives.current
    @objectives.update(capped, frame: 3100 + 1799)
    assert @objectives.current
    @objectives.update(capped, frame: 3100 + 1800)
    assert_nil @objectives.current
  end

  def test_pages_pending_at_an_objective_tour_are_kept_for_the_next_skill_tour
    client = ScriptedClient.new(objective: [objective, objective], skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "One\n\nTwo\n\nFresh"))
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 2)
    @objectives.instance_variable_set(:@current, nil)
    decide_with_shot(p, state(frame: 200))
    assert_equal 2, client.calls.size
    p.decide(Koholint::DecisionPoint.choose_skill(Koholint::Skills::Registry.default), state(frame: 210), { grid: })
    pages(p, 1, from: 300)
    result = flush(p, 400)
    assert_includes client.calls.last[:prompt], '3 pages'
    assert_equal %w[One Two Fresh], result[:transcription].map { |t| t[:text] }
  end

  def test_a_stale_sequence_or_one_from_another_place_is_dropped
    reply = ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => 'Fresh')
    p = policy(ScriptedClient.new(objective: objective, skill: reply, default: reply))
    decide_with_shot(p, state)
    pages(p, 2)
    decide_with_shot(p, state(frame: 131 + 601))
    assert_nil p.instance_variable_get(:@sequence)
    pages(p, 1, from: 800)
    decide_with_shot(p, state(frame: 850, room_id: 5))
    assert_nil p.instance_variable_get(:@sequence)
  end

  def test_the_transcription_keeps_every_paragraph_and_splits_long_blocks
    long = 'y' * 1100
    client = ScriptedClient.new(objective: objective, skill: [ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => long),
                                                              ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "a\n\nb\n\nc")])
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 1)
    result = flush(p, 200)
    assert_equal [500, 500, 100], result[:transcription].map { |t| t[:text].length }
    assert_equal [1, 2, 3], result[:transcription].map { |t| t[:page] }
    pages(p, 1, from: 300)
    assert_equal %w[a b c], flush(p, 400)[:transcription].map { |t| t[:text] }
  end

  def test_the_frame_guard_also_asks_the_model
    client = ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }))
    p = policy(client)
    decide_with_shot(p, state)
    decide_with_shot(p, state(frame: 100, **OPEN))
    result = decide_with_shot(p, state(frame: 1900, **OPEN))
    assert_equal 'wait', result[:choice][:skill]
    assert_equal 2, client.calls.size
  end

  def test_a_transcription_is_ignored_when_no_text_comes_back
    client = ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => ' '))
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 1)
    assert_nil flush(p, 200)[:transcription]
  end

  def test_the_transcription_is_capped_and_stripped_of_control_characters
    long = "A\u0000B\a\nC#{'x' * 600}"
    p = policy(ScriptedClient.new(objective: objective, skill: talk(long)))
    decide_with_shot(p, state)
    pages(p, 1)
    text = flush(p, 200)[:transcription].first[:text]
    assert_equal 500, text.length
    assert text.start_with?("AB\nCxxx")
  end

  def test_a_transcription_outside_the_dialogue_phase_is_ignored
    p = policy(ScriptedClient.new(objective: objective, skill: ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => 'ghost')))
    decide_with_shot(p, state)
    assert_nil decide_with_shot(p, state)[:transcription]
  end

  def test_a_failing_image_call_falls_back_to_wait
    p = policy(ScriptedClient.new(objective: objective, skill: failing('claude error: image'), default: failing('again')))
    decide_with_shot(p, state)
    pages(p, 2)
    result = flush(p, 200)
    assert result[:fallback]
    assert_equal 'wait', result[:choice][:skill]
    assert_nil result[:transcription]
    again = decide_with_shot(p, state(frame: 200))
    assert_nil again[:images]
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
    2.times { |i| wrapper.observe(state, frame: i) }
    assert_equal :boot, wrapper.decision_point_for(state(game_mode: 1)).name
    assert_equal :choose_objective, wrapper.decision_point_for(state).name
    assert_equal :choose_objective, wrapper.decision_point_for(state(dialog_state: 3)).name
    wrapper.after_action(choice: { buttons: [:a], frames: 1 }, outcome: {}, state:, frame: 1)
  end
end

class DelegatedEngineTest < Minitest::Test
  include DelegatedHelpers

  def wait(frames = 30) = ok('skill' => 'wait', 'params' => { 'frames' => frames })
  def leave_house = ok('title' => 'leave', 'predicate' => { 'kind' => 'leave_place', 'place' => [163, 16] })
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
      client = ScriptedClient.new(objective: [ok('title' => 'x')] + [leave_house] * 40, default: wait)
      assert_equal :frames, agent_engine(run, client, frames: 800).run
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
      talk = -> { eng.request_stop; ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Ah! Enfin...') }
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
      assert_equal [], Koholint::Replay.verify(run, every: 600).reject(&:last)
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
      assert_equal :playing, Koholint::GameState.new(**first['input'].transform_keys(&:to_sym)).phase
    end
  end

  def test_a_two_step_budget_stops_after_the_second_terminal_objective
    skip_without_rom!
    with_run do |run|
      budget = Koholint::Budget.new(steps: 2)
      objectives = Koholint::Objectives.new(trace: run.trace, stall_frames: 30)
      far = ok('title' => 'far', 'predicate' => { 'kind' => 'reach_place', 'place' => [0, 0] })
      client = ScriptedClient.new(objective: [far, far, far], default: wait)
      delegated = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives:, on_step: budget.method(:step_done))
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

class DelegatedLedgerTest < Minitest::Test
  include DelegatedHelpers

  PLACE = [163, 16].freeze

  def free_grid(cells: nil)
    beliefs = Koholint::Vision::Beliefs.new
    %i[up down left right].each do |d|
      beliefs.record(appearance: 'floor', action: :walk, direction: d, result: :yes, method: 'test', context: Koholint::Vision::Capabilities.new, frame: 1, source: 'test')
    end
    cells ||= Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs:, capabilities: Koholint::Vision::Capabilities.new)
  end

  def unknown_grid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[1][9] = 'mystery'
    free_grid(cells:)
  end

  def reach_cell(row, col) = ok('title' => 'go', 'predicate' => { 'kind' => 'reach_cell', 'place' => PLACE, 'row' => row, 'col' => col })

  def block(p, direction: 'up', frame: 101, state: self.state)
    place = { room: 163, map: 16, row: 3, col: 4 }
    outcome = { skill: 'walk', params: { direction:, cells: 1 }, frames: 8, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked',
                from: place, to: place, blocked_at: { row: 3, col: 4, direction: direction.to_sym } }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state:, frame:)
  end

  def neighbour_line(client, direction) = client.calls.last[:prompt].lines.find { |l| l =~ /\b#{direction}\b/ && l =~ /blocked|free|unknown/ }

  def test_reach_cell_on_a_known_free_reachable_cell_is_rejected_and_unknown_is_accepted
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    result = p.decide(p.decision_point_for(state), state, { grid: free_grid })
    assert result[:fallback]
    assert_match(/already reachable/, result[:justification])
    assert_equal 'wait', result[:choice][:skill]
    assert_nil @objectives.current

    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[3][6] = 'mystery'
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid(cells:) })[:fallback]
    assert @objectives.current
  end

  def test_reach_cell_is_not_judged_without_a_grid
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    refute p.decide(p.decision_point_for(state), state, {})[:fallback]
  end

  def test_reach_cell_behind_a_doubtful_edge_stays_valid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: { row: 3, col: 4, direction: :right }) }
    cells[2][4] = cells[4][4] = cells[3][3] = 'mystery'
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(3, 5)), registry: Koholint::Skills::Registry.default,
                                          objectives: Koholint::Objectives.new(trace:), ledger:)
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid(cells:) })[:fallback]
  end

  def test_blocked_walks_feed_the_next_context_and_become_doubtful
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk, default: walk)
    p = policy(client)
    context = { grid: free_grid }
    p.decide(p.decision_point_for(state), state, context)
    block(p)
    p.decide(p.decision_point_for(state), state, context)
    assert_includes client.calls.last[:prompt], 'blocked 1 time'
    refute_includes client.calls.last[:prompt], 'blocked 1 times'
    block(p, frame: 102)
    p.decide(p.decision_point_for(state), state, context)
    assert_includes client.calls.last[:prompt], 'blocked 2 times'
    assert_includes neighbour_line(client, 'up'), '!'
  end

  def test_the_policy_hands_its_ledger_to_the_skills_through_the_context
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    context = { grid: free_grid }
    decide_with = ->(c) { p.decide(p.decision_point_for(state), state, c) }
    decide_with.call(context)
    assert_instance_of Koholint::Ledger, context[:ledger]
    2.times { block(p, direction: 'right') }
    run = Koholint::Skills::Registry.default.start('goto', state, { row: 3, col: 5 }, context)
    refute_equal [:right], run.next_input(state)
  end

  def test_unreachable_abandons_the_objective_and_the_next_tour_asks_for_an_objective
    cell = reach_cell(1, 4)
    p = policy(ScriptedClient.new(objective: cell, skill: walk, default: walk))
    context = { grid: free_grid(cells: Array.new(8) { Array.new(10) { 'mystery' } }) }
    p.decide(p.decision_point_for(state), state, context)
    assert @objectives.current
    Koholint::Objectives::UNREACHABLE_PAIRS.times { |i| block(p, frame: 101 + i) }
    assert_nil @objectives.current
    assert_equal 1, @objectives.history.count { |h| h[:outcome] == :abandoned }
    assert_equal 'unreachable', @objectives.history.last[:reason]
    assert_equal :choose_objective, p.decision_point_for(state).name
  end

  def test_a_place_change_clears_the_ledger
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk, default: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    2.times { |i| block(p, frame: 101 + i) }
    assert ledger.doubtful?(PLACE, [3, 4], :up)
    p.observe(state(room_id: 9), frame: 200)
    assert_equal 0, ledger.count(PLACE, [3, 4], :up)
  end

  def test_a_walk_entering_a_cell_undoubts_the_edge
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    2.times { |i| block(p, frame: 101 + i) }
    moved = { skill: 'walk', params: { direction: 'up', cells: 1 }, moved_cells: 1, stopped_by: 'done',
              from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 4 }, blocked_at: nil }
    p.after_action(choice: { skill: 'walk', params: moved[:params] }, outcome: moved, state: state(y: 44), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :up)
  end

  def goto_outcome(crossed:, to:)
    { skill: 'goto', params: { row: to[0], col: to[1] }, moved_cells: crossed.size, stopped_by: 'done', blocked_at: nil, crossed:,
      from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: to[0], col: to[1] } }
  end

  def test_goto_undoubts_only_the_edges_it_crossed
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    [[3, 4, :right], [3, 5, :right], [2, 6, :down]].each { |r, c, d| 2.times { ledger.record(place: PLACE, blocked_at: { row: r, col: c, direction: d }) } }
    outcome = goto_outcome(crossed: [[3, 4, :right], [3, 5, :right]], to: [3, 6])
    p.after_action(choice: { skill: 'goto', params: outcome[:params] }, outcome:, state: state(x: 104), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :right)
    refute ledger.doubtful?(PLACE, [3, 5], :right)
    assert ledger.doubtful?(PLACE, [2, 6], :down)
  end

  def test_talk_to_crossed_edges_are_cleared_like_goto
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    [[3, 4, :right], [2, 6, :down]].each { |r, c, d| 2.times { ledger.record(place: PLACE, blocked_at: { row: r, col: c, direction: d }) } }
    outcome = goto_outcome(crossed: [[3, 4, :right]], to: [3, 5]).merge(skill: 'talk_to', stopped_by: 'no_response', talked: false,
                                                                         standing_cell: { row: 3, col: 5 })
    p.after_action(choice: { skill: 'talk_to', params: outcome[:params] }, outcome:, state: state(x: 104), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :right)
    assert ledger.doubtful?(PLACE, [2, 6], :down)
    assert_equal 0, ledger.count(PLACE, [3, 5], :right)
  end

  def test_talk_to_no_path_counts_but_no_response_does_not_and_the_summary_shows_the_talk
    @objectives = NoPathObjectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(1, 9), skill: walk), registry: Koholint::Skills::Registry.default,
                                          objectives: @objectives)
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    params = { row: 2, col: 5 }
    sealed = { skill: 'talk_to', params:, stopped_by: 'no_path', cause: 'no reachable cell next to the target', moved_cells: 0, talked: false }
    p.after_action(choice: { skill: 'talk_to', params: }, outcome: sealed, state:, frame: 140)
    assert_equal [140], @objectives.no_paths
    quiet = { skill: 'talk_to', params:, stopped_by: 'no_response', moved_cells: 1, talked: false, standing_cell: { row: 1, col: 5 } }
    p.after_action(choice: { skill: 'talk_to', params: }, outcome: quiet, state:, frame: 150)
    assert_equal [140], @objectives.no_paths
    attempt = @objectives.attempts_for_prompt.last
    assert_includes attempt, 'talked false'
    assert_includes attempt, 'standing_cell (1,5)'
  end

  def test_new_place_starts_and_is_achieved_on_a_first_visit
    p = policy(ScriptedClient.new(objective: ok('title' => 'discover', 'predicate' => { 'kind' => 'new_place' }), skill: walk), visited: [PLACE])
    refute decide(p).last[:fallback]
    assert @objectives.current
    p.observe(state(room_id: 9), frame: 200)
    assert_nil @objectives.current
    assert_equal :achieved, @objectives.history.last[:outcome]
  end

  def test_refused_objectives_are_flagged_remembered_three_deep_and_shown_then_cleared
    trivial = reach_cell(3, 6)
    elsewhere = objective(kind: 'leave_place', place: [1, 2])
    good = objective(kind: 'reach_place', place: [1, 2])
    client = ScriptedClient.new(objective: [trivial, elsewhere, trivial, elsewhere, trivial, good], skill: walk)
    p = policy(client)
    results = 5.times.map { p.decide(p.decision_point_for(state), state, { grid: free_grid }) }
    assert(results.all? { |r| r[:refused] && r[:fallback] })
    prompt = client.calls.last[:prompt]
    assert_includes prompt, <<~TEXT.chomp
      Refused objectives:
      - go {"kind":"leave_place","place":[1,2]}: leave_place must name the current place [163, 16], not [1, 2]
      - go {"kind":"reach_cell","place":[163,16],"row":3,"col":6}: reach_cell target is already reachable over cells observed free; choose a goal that needs exploration
      - go {"kind":"leave_place","place":[1,2]}: leave_place must name the current place [163, 16], not [1, 2]
    TEXT
    refute_includes client.calls.first[:prompt], 'Refused objectives'
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid })[:refused]
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    refute_includes client.calls.last[:prompt], 'Refused objectives'
  end

  def test_an_agent_failure_is_not_a_refusal
    p = policy(ScriptedClient.new(objective: failing('down')))
    result = p.decide(p.decision_point_for(state), state, { grid: free_grid })
    assert result[:fallback]
    refute result.key?(:refused)
  end

  def test_a_goto_chosen_on_an_overlay_frame_still_plans
    goto = ok('skill' => 'goto', 'params' => { 'row' => 3, 'col' => 6 })
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: goto))
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    context = { grid: nil }
    result = p.decide(p.decision_point_for(state), state, context)
    assert_same context[:grid], p.instance_variable_get(:@last_grid)
    run = Koholint::Skills::Registry.default.start('goto', state, result[:choice][:params], context)
    refute_empty run.next_input(state)
  end

  def test_no_grid_is_invented_for_a_new_place
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: walk))
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    context = {}
    p.decide(p.decision_point_for(state(room_id: 9)), state(room_id: 9), context)
    assert_nil context[:grid]
  end

  class NoPathObjectives < Koholint::Objectives
    attr_reader :no_paths

    def note_no_path(frame:) = (@no_paths = [*@no_paths, frame]).then { nil }
  end

  def test_no_path_results_are_reported_to_the_objectives_and_summarised_with_their_cause
    @objectives = NoPathObjectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(1, 9), skill: walk), registry: Koholint::Skills::Registry.default,
                                          objectives: @objectives)
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    outcome = { skill: 'goto', params: { row: 1, col: 9 }, stopped_by: 'no_path', cause: 'target is sealed', moved_cells: 0,
                blocked_at: { row: 3, col: 5, direction: :right } }
    p.after_action(choice: { skill: 'goto', params: outcome[:params] }, outcome:, state:, frame: 140)
    assert_equal [140], @objectives.no_paths
    attempt = @objectives.attempts_for_prompt.last
    assert_includes attempt, 'blocked_at (3,5) right'
    assert_includes attempt, 'cause target is sealed'
    walked = { skill: 'walk', params: { direction: 'up', cells: 1 }, stopped_by: 'done', moved_cells: 1 }
    p.after_action(choice: { skill: 'walk', params: walked[:params] }, outcome: walked, state:, frame: 150)
    assert_equal [140], @objectives.no_paths
  end

  def test_a_doubtful_edge_emits_a_grid_contradiction_once_per_crossing
    sink = trace
    @objectives = Koholint::Objectives.new(trace: sink)
    @objectives.define_singleton_method(:trace) { sink }
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk),
                                          registry: Koholint::Skills::Registry.default, objectives: @objectives, ledger: Koholint::Ledger.new)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    3.times { |i| block(p, frame: 101 + i) }
    events = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'grid_contradiction' }
    assert_equal 1, events.size
    assert_equal [102, [163, 16], 3, 4, 'up', 'yes', 'blocked x2'], events.first.values_at('frame', 'place', 'row', 'col', 'direction', 'believed', 'observed')
  end

  def test_a_believed_wall_blocking_twice_is_not_a_contradiction
    sink = trace
    @objectives = Koholint::Objectives.new(trace: sink)
    beliefs = Koholint::Vision::Beliefs.new
    capabilities = Koholint::Vision::Capabilities.new
    %w[floor wall].zip(%i[yes no]).each do |appearance, result|
      %i[up down left right].each do |d|
        beliefs.record(appearance:, action: :walk, direction: d, result:, method: 'test', context: capabilities, frame: 1, source: 'test')
      end
    end
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[3][5] = 'wall'
    grid = Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs:, capabilities:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk),
                                          registry: Koholint::Skills::Registry.default, objectives: @objectives, ledger: Koholint::Ledger.new)
    p.decide(p.decision_point_for(state), state, { grid: })
    2.times { |i| block(p, direction: 'right', frame: 101 + i) }
    events = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'grid_contradiction' }
    assert_empty events
  end

  def test_the_system_prompts_state_the_vocabulary
    objective_system = Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.choose_objective)
    skill_system = Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.choose_skill(Koholint::Skills::Registry.default))
    assert_match(/leave_place means finding a way out/, objective_system)
    assert_match(/new_place .*not yet visited/, objective_system)
    assert_match(/goto walks several cells/, skill_system)
    assert_match(/!.*doubtful.*goto avoids/, skill_system)
  end
end
