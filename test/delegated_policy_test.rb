require_relative 'support/delegated_helpers'

class DelegatedPolicyTest < Minitest::Test
  include DelegatedHelpers

  def test_reports_activity_before_the_model_call
    seen = []
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: (@objectives = Koholint::Objectives.new(trace: trace)),
                                          manual: 'notes', on_activity: ->(a) { seen << a })
    decide(p)
    assert_equal :deciding, seen.last[:kind]
    assert_equal 'choose_objective', seen.last[:detail][:decision_point]
    assert_equal 0, seen.last[:detail][:images]
    assert_kind_of Integer, seen.last[:frame]
  end

  def test_an_error_while_building_the_context_is_an_engine_error_with_its_origin
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    p.instance_variable_get(:@ledger).define_singleton_method(:doubtful?) { |*| raise ArgumentError, 'cell out of range: -1, 7' }
    _, result = decide(p)
    assert result[:fallback]
    assert result[:engine_error]
    assert_equal 'engine', result[:agent]
    assert_match(/\AArgumentError: cell out of range: -1, 7 at .+:\d+/, result[:justification])
    assert_equal 1, client.calls.size
  end

  def test_a_client_failure_stays_an_agent_failure
    p = policy(ScriptedClient.new(objective: objective, default: failing('transport down')))
    decide(p)
    _, result = decide(p)
    assert result[:fallback]
    refute result[:engine_error]
    assert_equal 'transport down', result[:justification]
  end

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

  def test_an_answer_without_a_plan_is_accepted_and_keeps_the_previous_plan
    client = ScriptedClient.new(objective: with_plan(objective, 'first'), skill: [walk, walk])
    p = policy(client)
    decide(p)
    _point, answer = decide(p)
    refute answer[:fallback]
    refute answer.key?(:plan)
    decide(p)
    assert_includes client.calls[2][:prompt], 'follow it unless the situation changed): first'
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
    assert_equal :choose_skill, policy(ScriptedClient.new(objective: closed)).decision_point_for(state(dialog_state: 3)).name
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

  def blocked(p, skill, params, pos: [68, 60], **extra)
    outcome = { skill:, params:, frames: 8, moved_cells: 0, moved_px: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked', **extra }
    p.after_action(choice: { skill:, params: }, outcome:, state: state(x: pos[0], y: pos[1]), frame: 101)
  end

  def idle(p, skill, params, pos: [68, 60], stopped_by: 'done')
    p.after_action(choice: { skill:, params: }, outcome: { stopped_by:, moved_cells: 0 }, state: state(x: pos[0], y: pos[1]), frame: 102)
  end

  def new_policy = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk)).tap { |p| decide(p) }

  def test_a_movement_lock_survives_interleaved_press_wait_and_step_and_shows_one_line
    p = new_policy
    blocked(p, 'walk', { direction: 'left', cells: 1 })
    idle(p, 'press', { button: 'b', frames: 3 })
    blocked(p, 'walk', { direction: 'right', cells: 1 })
    idle(p, 'wait', { frames: 30 })
    blocked(p, 'walk', { direction: 'down', cells: 1 })
    idle(p, 'press', { button: 'a', frames: 3 })
    idle(p, 'advance_dialogue', {})
    blocked(p, 'step', { direction: 'up', pixels: 4 })
    result = decide(p).last
    assert_equal({ skill: 'wait', params: { frames: 120 } }, result[:choice])
    assert_equal 'delegated', result[:agent]
  end

  def test_the_waits_are_capped_then_the_agent_is_called_with_the_lock_line
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: [walk, walk])
    p = policy(client)
    decide(p)
    %w[left right down up].each { |d| blocked(p, 'walk', { direction: d, cells: 1 }) }
    waits = 0
    loop do
      result = decide(p).last
      break unless result[:agent] == 'delegated'

      waits += 1
      flunk 'waits never end' if waits > 100
      p.after_action(choice: result[:choice], outcome: { stopped_by: 'done', moved_cells: 0 }, state:, frame: 300)
    end
    assert_equal Koholint::Policies::Delegated::HEMMED_WAIT_LIMIT, waits
    assert_includes client.calls.last[:prompt], 'Link has not moved in the last 4 attempts in different directions and no dialogue is open'
  end

  def test_goto_and_talk_to_blocks_count_as_attempts_but_add_no_direction
    p = new_policy
    blocked(p, 'goto', { row: 1, col: 1 })
    blocked(p, 'talk_to', { row: 1, col: 1 })
    %w[left up down].each { |d| blocked(p, 'walk', { direction: d, cells: 1 }) }
    assert_equal 'claude', decide(p).last[:agent]
    blocked(p, 'step', { direction: 'right', pixels: 2 })
    assert_equal 'delegated', decide(p).last[:agent]
  end

  def test_movement_or_a_dialogue_resets_the_lock_count
    p = new_policy
    3.times { |i| blocked(p, 'walk', { direction: %w[left right up][i], cells: 1 }) }
    p.after_action(choice: { skill: 'walk', params: { direction: 'down', cells: 1 } }, outcome: { stopped_by: 'done', moved_cells: 1 }, state: state, frame: 103)
    blocked(p, 'walk', { direction: 'up', cells: 1 })
    assert_equal 'claude', decide(p).last[:agent]
    p = new_policy
    3.times { |i| blocked(p, 'walk', { direction: %w[left right up][i], cells: 1 }) }
    idle(p, 'press', { button: 'b', frames: 3 }, pos: [70, 60])
    blocked(p, 'walk', { direction: 'down', cells: 1 }, pos: [70, 60])
    assert_equal 'claude', decide(p, state(x: 70)).last[:agent]
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

  def scripted_walk(p, direction, input)
    outcome = { skill: 'walk', params: { direction:, cells: 1 }, moved_cells: 0, stopped_by: 'dialogue', dialog_before: false, dialog_after: true,
                from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 3, col: 4 }, trigger_input: input }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state: state, frame: 110)
  end

  def test_an_explicit_press_of_the_forbidden_input_without_a_dialogue_clears_the_memory
    triggers = Koholint::Triggers.new
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk), triggers:)
    decide(p)
    scripted_walk(p, 'right', [:down])
    assert_equal [:down], triggers.forbidden([163, 16], [3, 4])
    spot = { room: 163, map: 16, row: 3, col: 4 }
    quiet = { moved_cells: 1, frames: 8, stopped_by: 'done', dialog_before: false, dialog_after: false, from: spot, to: spot, trigger_input: nil }
    p.after_action(choice: { skill: 'walk', params: { direction: 'up', cells: 1 } }, outcome: quiet, state: state, frame: 120)
    assert_equal [:down], triggers.forbidden([163, 16], [3, 4])
    p.after_action(choice: { skill: 'walk', params: { direction: 'down', cells: 1 } }, outcome: quiet.merge(dialog_after: true), state: state, frame: 121)
    assert_equal [:down], triggers.forbidden([163, 16], [3, 4])
    [{ stopped_by: 'damage' }, { stopped_by: 'room_change' }, { stopped_by: 'blocked', moved_cells: 0, frames: 2 }].each do |bad|
      p.after_action(choice: { skill: 'walk', params: { direction: 'down', cells: 1 } }, outcome: quiet.merge(bad), state: state, frame: 122)
      assert_equal [:down], triggers.forbidden([163, 16], [3, 4]), bad.inspect
    end
    p.after_action(choice: { skill: 'step', params: { direction: 'down', pixels: 4 } }, outcome: quiet, state: state, frame: 123)
    assert_equal [], triggers.forbidden([163, 16], [3, 4])
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
    result = decide(p).last
    assert_match(/\AArgumentError: odd at .+delegated_helpers\.rb:\d+/, result[:justification])
    refute result[:engine_error]
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

  def talk(text = nil) = ok({ 'skill' => 'advance_dialogue', 'params' => {} }.merge(text ? { 'transcription' => text } : {}))


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

  def test_the_page_cap_is_read_and_advanced_once_then_the_agent_drives_until_the_dialogue_closes
    client = ScriptedClient.new(objective: objective, skill: [ok('skill' => 'explore', 'params' => {}, 'transcription' => 'Early'),
                                                              ok('skill' => 'advance_dialogue', 'params' => {}, 'transcription' => 'Late'),
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
    assert_equal({ skill: 'advance_dialogue', params: {} }, capped[:choice])
    assert_match(/keep advancing/, capped[:justification])
    advance(p, capped, state(frame: 1300, **OPEN), 1300)
    resumed = decide_with_shot(p, state(frame: 1330, **OPEN))
    assert_equal 'automatic dialogue advance', resumed[:justification]
    assert_equal 2, client.calls.size
    pages(p, 39, from: 1360)
    second = decide_with_shot(p, state(frame: 2600, **OPEN))
    assert_equal 'Late', second[:transcription].first[:text]
    advance(p, second, state(frame: 2601, **OPEN), 2601)
    driven = decide_with_shot(p, state(frame: 2630, **OPEN))
    assert_equal SHOT, client.calls.last[:image]
    assert_equal 'claude', driven[:agent]
    refute_includes client.calls.last[:system], 'stacked vertically in sheets'
    advance(p, driven, state(frame: 2660), 2660)
    decide_with_shot(p, state(frame: 2661))
    again = decide_with_shot(p, state(frame: 2700, **OPEN))
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
    assert_equal 'advance_dialogue', result[:choice][:skill]
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
    assert_equal :boot, wrapper.decision_point_for(state(game_mode: 1)).name
    2.times { |i| wrapper.observe(state, frame: i) }
    assert_equal %w[press wait], wrapper.decision_point_for(state(game_mode: 1)).registry.names
    assert_equal :choose_objective, wrapper.decision_point_for(state).name
    assert_equal :choose_skill, wrapper.decision_point_for(state(dialog_state: 3)).name
    wrapper.after_action(choice: { buttons: [:a], frames: 1 }, outcome: {}, state:, frame: 1)
  end

  LOCKED = { motion_blocked: 2 }.freeze

  def locked_step(policy, frame, **over)
    at = state(frame:, **LOCKED, **over)
    result = decide_with_shot(policy, at)
    advance(policy, result, at, frame + 30)
    result
  end

  def test_a_locked_link_waits_without_calling_the_client_or_logging_attempts
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    calls = client.calls.size
    results = 3.times.map { |i| locked_step(p, 100 + (i * 30)) }
    assert_equal calls, client.calls.size
    results.each do |r|
      assert_equal [{ skill: 'wait', params: { frames: 30, until_free: true } }, 'locked: waiting for Link to be free', 'delegated', 0.0, false, nil, nil],
                   r.values_at(:choice, :justification, :agent, :cost_usd, :fallback, :prompt, :image)
    end
    assert_equal 0, @objectives.attempts_for_prompt.to_s.scan('wait').size
  end

  def test_a_long_lock_is_followed_by_a_short_wait_before_the_model_is_asked
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    calls = client.calls.size
    [100, 130].each { |frame| locked_step(p, frame) }
    free = state(frame: 160)
    p.observe(free, frame: 160)
    settle = decide_with_shot(p, free)
    assert_equal [{ skill: 'wait', params: { frames: 30 } }, 'delegated'], settle.values_at(:choice, :agent)
    assert_equal calls, client.calls.size
    advance(p, settle, state(frame: 190), 190)
    decide_with_shot(p, state(frame: 190))
    assert_equal calls + 1, client.calls.size
  end

  def test_a_short_lock_is_followed_by_a_wait_as_long_as_itself
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    calls = client.calls.size
    at = state(frame: 100, **LOCKED)
    advance(p, decide_with_shot(p, at), at, 106)
    free = state(frame: 106)
    p.observe(free, frame: 106)
    settle = decide_with_shot(p, free)
    assert_equal [{ skill: 'wait', params: { frames: 6 } }, 'delegated'], settle.values_at(:choice, :agent)
    assert_equal calls, client.calls.size
  end

  def test_a_one_frame_release_between_two_locks_does_not_reach_the_model
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    calls = client.calls.size
    first = state(frame: 100, **LOCKED)
    advance(p, decide_with_shot(p, first), first, 115)
    released = state(frame: 115)
    p.observe(released, frame: 115)
    settle = decide_with_shot(p, released)
    assert_equal({ skill: 'wait', params: { frames: 15 } }, settle[:choice])
    advance(p, settle, released, 116)
    again = state(frame: 116, **LOCKED)
    p.observe(again, frame: 116)
    relock = decide_with_shot(p, again)
    assert_equal({ skill: 'wait', params: { frames: 30, until_free: true } }, relock[:choice])
    advance(p, relock, again, 174)
    free = state(frame: 174)
    p.observe(free, frame: 174)
    long = decide_with_shot(p, free)
    assert_equal({ skill: 'wait', params: { frames: 30 } }, long[:choice])
    assert_equal calls, client.calls.size
    advance(p, long, free, 204)
    decide_with_shot(p, state(frame: 204))
    assert_equal calls + 1, client.calls.size
  end

  def test_a_lock_past_the_wait_cap_is_noted_once_and_handed_to_the_model
    client = ScriptedClient.new(objective: objective, skill: [walk, walk])
    p = policy(client)
    decide(p)
    calls = client.calls.size
    locked_step(p, 100, link_frozen: 5)
    capped = locked_step(p, 100 + Koholint::Policies::Delegated::LOCKED_WAIT_LIMIT_FRAMES, link_frozen: 5)
    assert_equal calls + 1, client.calls.size
    assert_equal ['lock_cap'], Array(capped[:notables]).map { |note| note[:kind] }
    again = locked_step(p, 130 + Koholint::Policies::Delegated::LOCKED_WAIT_LIMIT_FRAMES, link_frozen: 5)
    assert_equal calls + 2, client.calls.size
    assert_empty Array(again[:notables]).select { |note| note[:kind] == 'lock_cap' }
  end

  def test_a_scripted_scene_holding_link_is_a_lock
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    calls = client.calls.size
    held = state(frame: 100, link_frozen: 5)
    assert_equal :locked, held.phase
    assert_equal 'locked: waiting for Link to be free', decide_with_shot(p, held)[:justification]
    assert_equal :playing, state(frame: 100, link_frozen: 1).phase
    assert_equal calls, client.calls.size
  end

  def test_a_dialogue_with_no_objective_is_advanced_before_an_objective_is_asked
    client = ScriptedClient.new
    p = policy(client)
    open = state(frame: 100, **OPEN)
    assert_equal :choose_skill, p.decision_point_for(open).name
    assert_equal 'automatic dialogue advance', decide_with_shot(p, open)[:justification]
    assert_empty client.calls
  end

  def test_a_locked_link_with_no_objective_still_waits_with_a_skill
    client = ScriptedClient.new
    p = policy(client)
    point = p.decision_point_for(state(**LOCKED))
    assert_equal :choose_skill, point.name
    assert_empty client.calls
  end

  def test_a_settled_menu_asks_the_agent_with_the_menu_skills_and_no_lock_or_dialogue_handling
    press = ok('skill' => 'press', 'params' => { 'button' => 'b', 'frames' => 3 })
    client = ScriptedClient.new(skill: press)
    p = policy(client)
    menu = state(game_mode: 0x0C, game_submode: 8, dialog_state: 1, motion_blocked: 2)
    p.observe(menu, frame: 100)
    point, result = decide(p, menu)
    assert_equal :choose_skill, point.name
    assert_equal %w[menu_move menu_assign close_menu press wait], point.registry.names
    assert_equal 'claude', result[:agent]
    assert_equal({ skill: 'press', params: { 'button' => 'b', 'frames' => 3 } }, result[:choice])
    assert_includes client.calls.last[:prompt], 'Phase: menu'
    assert_includes client.calls.last[:prompt], 'Screen: inventory (menu)'
    assert_includes client.calls.last[:prompt], 'To leave: START closes it'
  end

  def test_a_menu_still_opening_waits_without_calling_the_agent
    client = ScriptedClient.new
    p = policy(client)
    opening = state(game_mode: 0x0C, game_submode: 1)
    _point, result = decide(p, opening)
    assert_equal({ skill: 'wait', params: { frames: 5 } }, result[:choice])
    assert_equal 'delegated', result[:agent]
    assert_empty client.calls
  end

  def test_the_screen_settling_clock_restarts_after_leaving_the_screen
    client = ScriptedClient.new
    p = policy(client)
    opening = ->(frame) { state(frame:, game_mode: 0x0C, game_submode: 1) }
    p.observe(opening.(100), frame: 100)
    decide(p, opening.(100))
    p.observe(state(frame: 2000), frame: 2000)
    assert_nil p.instance_variable_get(:@screen_since)
    p.observe(opening.(2100), frame: 2100)
    _point, result = decide(p, opening.(2100))
    assert_equal 'delegated', result[:agent]
    assert_empty client.calls
  end

  def test_each_screen_offers_its_own_skills_and_play_offers_no_screen_only_skill
    p = policy(ScriptedClient.new)
    assert_equal %w[close_map press wait], p.decision_point_for(state(game_mode: 7, game_submode: 5)).registry.names
    assert_equal %w[choose_option press wait], p.decision_point_for(state(game_mode: 6, game_submode: 5)).registry.names
    assert_equal %w[choose_option press wait], p.decision_point_for(state(game_mode: 11, game_submode: 7, link_motion_state: 7, game_over_stage: 4)).registry.names
    assert_equal %w[press wait], p.decision_point_for(state(game_mode: 0x0D, game_submode: 1)).registry.names
    play = Koholint::Policies::Delegated::SCREEN_ONLY & p.instance_variable_get(:@skill_point).registry.names
    assert_empty play
    assert_includes p.instance_variable_get(:@skill_point).registry.names, 'open_menu'
  end

  def test_the_locked_cap_hands_the_decision_back_to_the_agent_with_a_note
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    frame = 100
    while frame < 100 + Koholint::Policies::Delegated::LOCKED_WAIT_LIMIT_FRAMES
      assert_equal 'locked: waiting for Link to be free', locked_step(p, frame)[:justification]
      frame += 30
    end
    assert_equal 'obj-1', @objectives.current[:id]
    assert_empty p.instance_variable_get(:@last_results)
    assert_empty @objectives.attempts_for_prompt
    calls = client.calls.size
    result = locked_step(p, frame)
    assert_equal 'claude', result[:agent]
    assert_equal calls + 1, client.calls.size
    assert_includes client.calls.last[:prompt], 'Phase: locked'
    assert_includes client.calls.last[:prompt], "Link has been locked for #{frame - 100} frames (cause unknown)"
  end

  def test_leaving_the_locked_phase_resets_the_cap_and_touches_the_objective
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    p.observe(state(frame: 100, **LOCKED), frame: 100)
    p.observe(state(frame: 1000, **LOCKED), frame: 1000)
    p.observe(state(frame: 1010), frame: 1010)
    assert_equal 1010, @objectives.last_change_frame
    p.observe(state(frame: 1100, **LOCKED), frame: 1100)
    calls = client.calls.size
    assert_equal 'locked: waiting for Link to be free', locked_step(p, 1100)[:justification]
    assert_equal calls, client.calls.size
  end

  def test_a_dialogue_opening_during_the_lock_advances_automatically
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    decide(p)
    locked_step(p, 100)
    calls = client.calls.size
    result = decide_with_shot(p, state(frame: 130, **OPEN))
    assert_equal 'automatic dialogue advance', result[:justification]
    assert_equal calls, client.calls.size
  end

  def test_leads_from_dialogue_sheets_are_validated_sourced_and_shown_with_the_goal
    sheet = ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "Go north.\n\nFind the  key.", 'goal' => 'find the key',
               'leads' => [{ 'quote' => 'find the KEY', 'claim' => 'a key is needed', 'importance' => 'high' },
                           { 'quote' => 'never said', 'claim' => 'x', 'importance' => 'high' }])
    client = ScriptedClient.new(objective: objective, skill: [sheet, walk])
    p = policy(client)
    decide_with_shot(p, state)
    p.after_action(choice: { skill: 'talk_to', params: { 'row' => 2, 'col' => 4 } }, outcome: { stopped_by: 'done', talked: true }, state: state, frame: 100)
    pages(p, 2)
    result = flush(p, 300)
    assert_equal [{ id: 'lead-1', place: [163, 16], source: { row: 2, col: 4 }, quote: 'find the KEY', claim: 'a key is needed', importance: 'high' }], result[:leads]
    assert_equal [1, 'find the key'], result.values_at(:leads_rejected, :goal)
    decide_with_shot(p, state(frame: 400))
    assert_match(/Goal \(yours, long-term\): find the key \(set at frame \d+, 0 objectives ago\)\n/, client.calls.last[:prompt])
    assert_includes client.calls.last[:prompt], '- [lead-1 high] a key is needed — "find the KEY"'
  end

  def test_a_transcribed_text_not_read_before_achieves_new_text
    sheet = ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => "Go no\n\nGo north, then east.")
    client = ScriptedClient.new(objective: ok('title' => 'read', 'predicate' => { 'kind' => 'new_text' }), skill: [sheet, walk])
    p = policy(client)
    decide_with_shot(p, state)
    pages(p, 2)
    result = flush(p, 300)
    assert_equal 'obj-1', @objectives.current[:id]
    p.after_action(choice: result[:choice], outcome: { stopped_by: 'done' }, state: state(frame: 320), frame: 320)
    assert_equal :achieved, @objectives.history.last[:outcome]
    refute @objectives.note_text('go north, then east.')
  end

  def test_a_person_talked_to_is_remembered_with_whether_the_talk_gave_new_text
    sheet = ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'transcription' => 'Hello there.')
    client = ScriptedClient.new(objective: objective, skill: [sheet, walk])
    p = policy(client)
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    person = Koholint::Vision::Grid.new(cells:, static_sprites: [{ 'x' => 72, 'y' => 48, 'pattern' => 'p', 'height' => 16 }],
                                        beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
    shot = ->(at) { p.decide(p.decision_point_for(at), at, { grid: person, dialogue_shot: -> { SHOT }, dialogue_rgb: -> { PAGE } }) }
    shot.call(state)
    p.after_action(choice: { skill: 'talk_to', params: { 'row' => 2, 'col' => 4 } }, outcome: { stopped_by: 'done', talked: true }, state: state, frame: 100)
    2.times { |i| at = state(frame: 100 + (i * 30), **OPEN); advance(p, shot.call(at), at, at.frame + 30) }
    shot.call(state(frame: 300))
    shot.call(state(frame: 310))
    shot.call(state(frame: 320))
    assert_includes client.calls.last[:prompt], '- at (2,4): talked to 1 time (dialogue opened 1); 1 text read, last talk gave new text, worth retrying: yes'
  end

  def test_a_goal_is_reported_only_when_it_changes_and_leads_need_a_transcription
    same = ok('skill' => 'wait', 'params' => { 'frames' => 3 }, 'goal' => 'explore',
              'leads' => [{ 'quote' => 'q', 'claim' => 'c', 'importance' => 'low' }])
    client = ScriptedClient.new(objective: ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' }, 'goal' => 'explore'), skill: same)
    p = policy(client)
    _, first = decide(p)
    assert_equal 'explore', first[:goal]
    _, second = decide(p)
    refute second.key?(:goal)
    assert_equal [[], 1], second.values_at(:leads, :leads_rejected)
  end

  def test_the_goal_line_says_when_it_was_set_and_how_many_objectives_ago
    keep = ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' }, 'goal' => 'explore')
    p = policy(ScriptedClient.new(objective: [keep, keep, keep]))
    client = p.instance_variable_get(:@client)
    decide(p)
    2.times do |n|
      @objectives.abandon(frame: 101 + n, reason: 'test')
      decide(p, state(frame: 200 + n))
    end
    assert_includes client.calls.last[:prompt], 'Goal (yours, long-term): explore (set at frame 100, 2 objectives ago)'
    leads = Koholint::Leads.from_events(Koholint::Trace.read(File.join(@dir, 'trace.jsonl')) + [{ 'type' => 'goal', 'frame' => 300, 'text' => 'new' }])
    assert_equal ['new', 300, 2], [leads.goal, leads.goal_frame, leads.goal_objectives]
  end

  def test_because_is_kept_only_when_it_names_a_known_lead
    known = Koholint::Leads.from_events([{ 'type' => 'lead', 'id' => 'lead-1', 'place' => [1, 2], 'source' => nil, 'quote' => 'q', 'claim' => 'c', 'importance' => 'high' }])
    because = ->(id) { ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' }, 'because' => id) }
    client = ScriptedClient.new(objective: [because.call('lead-1'), because.call('lead-7')])
    @objectives = Koholint::Objectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, leads: known)
    decide(p)
    @objectives.abandon(frame: 101, reason: 'test')
    decide(p)
    started = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['status'] == 'started' }
    assert_equal ['lead-1', nil], started.map { |e| e['because'] }
    assert_includes client.calls.last[:prompt], '- [lead-1 high open: obj-1 "go" abandoned at frame 101] c — "q"'
  end

  def test_a_lead_followed_twice_without_success_is_shown_refuted
    known = Koholint::Leads.from_events([{ 'type' => 'lead', 'id' => 'lead-1', 'place' => [1, 2], 'source' => nil, 'quote' => 'q', 'claim' => 'c', 'importance' => 'high' }])
    client = ScriptedClient.new(objective: [ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' }, 'because' => 'lead-1')] * 3)
    @objectives = Koholint::Objectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, leads: known)
    2.times do |n|
      decide(p, state(frame: 100 + n))
      @objectives.abandon(frame: 150 + n, reason: 'test')
    end
    decide(p, state(frame: 200))
    assert_includes client.calls.last[:prompt], '- [lead-1 high refuted: obj-1 "go" abandoned at frame 150; obj-2 "go" abandoned at frame 151] c — "q"'
  end

  def test_the_game_over_screen_continues_without_a_model_call_and_never_quits
    client = ScriptedClient.new(objective: objective, skill: walk)
    p = policy(client)
    over = state(hp: 0, link_motion_state: 7, game_over_stage: 4)
    p.observe(over, frame: 100)
    _point, result = decide(p, over)
    assert_empty client.calls
    assert_equal({ skill: 'choose_option', params: { option: 0 } }, result[:choice])
    refute Koholint::Modes.for(over).quits?(result[:choice][:params][:option])
    assert_equal [0.0, 'delegated'], result.values_at(:cost_usd, :agent)
    assert_includes result[:notables], { kind: 'death', detail: 'game over: save and continue' }
    p.observe(over, frame: 110)
    refute decide(p, over).last[:notables]&.any? { |note| note[:kind] == 'death' }
  end

  def test_hp_drops_emit_a_damage_notable_and_show_in_the_next_prompt
    client = ScriptedClient.new(objective: objective, default: walk)
    p = policy(client)
    p.observe(state(hp: 16), frame: 100)
    decide(p, state(hp: 16))
    p.observe(state(frame: 200, hp: 12), frame: 200)
    _point, result = decide(p, state(frame: 200, hp: 12))
    assert_includes result[:notables], { kind: 'damage', detail: 'hp 16 -> 12' }
    assert_includes client.calls.last[:prompt], 'Health: 1.5 of 3 hearts, 0.5 lost since your last decision'
    p.observe(state(frame: 300, hp: 12), frame: 300)
    _point, result = decide(p, state(frame: 300, hp: 12))
    assert_nil result[:notables]
    assert_includes client.calls.last[:prompt], "Health: 1.5 of 3 hearts\n"
  end
end
