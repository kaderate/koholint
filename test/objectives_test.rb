require_relative 'test_helper'
require 'tmpdir'
require 'koholint/trace'
require 'koholint/game_state'
require 'koholint/objectives'

class ObjectivesTest < Minitest::Test
  PLAY = { game_mode: 0x0B, game_submode: 7 }.freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'trace.jsonl')
    @trace = Koholint::Trace.new(@path)
    @objectives = Koholint::Objectives.new(trace: @trace, stall_frames: 100, loop_window: 3)
  end

  def teardown = FileUtils.remove_entry(@dir)

  def state(frame: 0, room: 1, map: 2, x: 40, y: 40, hp: 24, dialog: 0, **extra)
    Koholint::GameState.new(frame:, room_id: room, map_id: map, x:, y:, hp:, dialog_state: dialog,
                            milestone: :none, **PLAY, **extra)
  end

  def events = Koholint::Trace.read(@path).select { |e| e['type'] == 'objective' }

  def start(predicate, frame: 0) = @objectives.start(frame:, title: 't', predicate:)

  def test_predicate_validation
    assert Koholint::Objectives.valid_predicate?({ kind: 'leave_place', place: [1, 2] })
    assert Koholint::Objectives.valid_predicate?({ 'kind' => 'reach_cell', 'place' => [1, 2], 'row' => 1, 'col' => 2 })
    assert Koholint::Objectives.valid_predicate?({ kind: 'dialogue_closed' })
    refute Koholint::Objectives.valid_predicate?({ kind: 'reach_cell', place: [1, 2] })
    assert Koholint::Objectives.valid_predicate?({ kind: 'new_place' })
    refute Koholint::Objectives.valid_predicate?({ kind: 'new_place', place: [1, 2] })
    refute Koholint::Objectives.valid_predicate?({ kind: 'nope' })
    refute Koholint::Objectives.valid_predicate?('x')
    assert_equal %w[dialogue_closed leave_place new_place reach_cell reach_place], Koholint::Objectives::PREDICATES.keys.sort
  end

  def test_malformed_predicates_are_rejected
    valid = Koholint::Objectives.method(:valid_predicate?)
    [{ kind: 'leave_place', place: 'x' }, { kind: 'leave_place', place: [1] }, { kind: 'leave_place', place: [1, 2, 3] },
     { kind: 'leave_place', place: [1, '2'] }, { kind: 'leave_place', place: [1.5, 2] },
     { kind: 'reach_place', place: { a: 1 } }, { kind: 'reach_cell', place: [1, 2], row: 8, col: 2 },
     { kind: 'reach_cell', place: [1, 2], row: 1, col: 10 }, { kind: 'reach_cell', place: [1, 2], row: -1, col: 0 },
     { kind: 'reach_cell', place: [1, 2], row: '1', col: 2 }, { kind: 'dialogue_closed', place: [1, 2] },
     { kind: 'leave_place', place: [1, 2], extra: 1 }, { 'kind' => 'leave_place', 'place' => 'x' }].each do |predicate|
      refute valid.call(predicate), predicate.inspect
    end
    assert valid.call({ 'kind' => 'reach_cell', 'place' => [1, 2], 'row' => 7, 'col' => 9 })
  end

  def test_start_emits_and_sets_current
    id = start({ kind: 'dialogue_closed' })
    assert_equal id, @objectives.current[:id]
    assert_equal [{ 'id' => id, 'status' => 'started' }], events.map { |e| e.slice('id', 'status') }
  end

  def test_leave_place_achieved_on_another_place
    start({ kind: 'leave_place', place: [1, 2] })
    assert_nil @objectives.update(state(frame: 1), frame: 1)
    assert_equal :achieved, @objectives.update(state(frame: 2, room: 5), frame: 2)
    assert_nil @objectives.current
  end

  def test_loading_never_satisfies_leave_place
    start({ kind: 'leave_place', place: [1, 2] })
    assert_nil @objectives.update(state(room: 5, game_submode: 3), frame: 1)
    assert @objectives.current
  end

  def test_reach_place
    start({ kind: 'reach_place', place: [7, 8] })
    assert_nil @objectives.update(state(frame: 1), frame: 1)
    assert_equal :achieved, @objectives.update(state(frame: 2, room: 7, map: 8), frame: 2)
  end

  def test_reach_cell
    start({ kind: 'reach_cell', place: [1, 2], row: 2, col: 3 })
    assert_nil @objectives.update(state(frame: 1, x: 40, y: 40), frame: 1)
    assert_equal :achieved, @objectives.update(state(frame: 2, x: 48, y: 40), frame: 2)
  end

  def test_dialogue_closed_needs_open_then_closed
    start({ kind: 'dialogue_closed' })
    assert_nil @objectives.update(state(frame: 1), frame: 1)
    assert_nil @objectives.update(state(frame: 2, dialog: 1), frame: 2)
    assert_equal :achieved, @objectives.update(state(frame: 3), frame: 3)
  end

  def test_terminal_event_exactly_once
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1, room: 7, map: 8), frame: 1)
    assert_nil @objectives.update(state(frame: 2, room: 7, map: 8), frame: 2)
    assert_equal %w[started achieved], events.map { |e| e['status'] }
    assert_equal [:achieved], @objectives.history.map { |h| h[:outcome] }
  end

  def test_stall_abandons
    start({ kind: 'reach_place', place: [7, 8] })
    assert_nil @objectives.update(state(frame: 10), frame: 10)
    assert_nil @objectives.update(state(frame: 109), frame: 109)
    assert_equal :abandoned, @objectives.update(state(frame: 110), frame: 110)
    assert_equal 'stall', events.last['reason']
    assert_nil @objectives.current
  end

  def test_open_dialogue_with_animating_counter_stalls
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1, dialog: 134), frame: 1)
    assert_nil @objectives.update(state(frame: 60, dialog: 137), frame: 60)
    assert_nil @objectives.update(state(frame: 100, dialog: 140), frame: 100)
    assert_equal :abandoned, @objectives.update(state(frame: 101, dialog: 141), frame: 101)
    assert_equal 'stall', events.last['reason']
  end

  def test_open_dialogue_with_animating_counter_loops
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1, dialog: 134), frame: 1)
    2.times { @objectives.record_attempt(skill: 'wait', params: {}, result_summary: 'ok') }
    assert_nil @objectives.update(state(frame: 2, dialog: 135), frame: 2)
    @objectives.record_attempt(skill: 'wait', params: {}, result_summary: 'ok')
    assert_equal :abandoned, @objectives.update(state(frame: 3, dialog: 137), frame: 3)
    assert_equal 'loop', events.last['reason']
  end

  def test_dialogue_opening_counts_as_a_change
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1), frame: 1)
    assert_nil @objectives.update(state(frame: 90, dialog: 134), frame: 90)
    assert_nil @objectives.update(state(frame: 150, dialog: 140), frame: 150)
  end

  def test_change_resets_stall
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 10), frame: 10)
    assert_nil @objectives.update(state(frame: 100, x: 48), frame: 100)
    assert_nil @objectives.update(state(frame: 199, x: 48), frame: 199)
  end

  def test_loop_abandons_after_window
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1), frame: 1)
    2.times { @objectives.record_attempt(skill: 'walk', params: { dir: 'up' }, result_summary: 'blocked') }
    assert_nil @objectives.update(state(frame: 2), frame: 2)
    @objectives.record_attempt(skill: 'walk', params: { dir: 'up' }, result_summary: 'blocked')
    assert_equal :abandoned, @objectives.update(state(frame: 3), frame: 3)
    assert_equal 'loop', events.last['reason']
  end

  def test_different_params_or_state_change_do_not_loop
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1), frame: 1)
    2.times { @objectives.record_attempt(skill: 'walk', params: { dir: 'up' }, result_summary: 'r') }
    @objectives.record_attempt(skill: 'walk', params: { dir: 'down' }, result_summary: 'r')
    assert_nil @objectives.update(state(frame: 2), frame: 2)
    @objectives.record_attempt(skill: 'walk', params: { dir: 'down' }, result_summary: 'r')
    @objectives.update(state(frame: 3, x: 48), frame: 3)
    @objectives.record_attempt(skill: 'walk', params: { dir: 'down' }, result_summary: 'r')
    assert_nil @objectives.update(state(frame: 4, x: 48), frame: 4)
  end

  def test_death_fails
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1), frame: 1)
    assert_equal :failed, @objectives.update(state(frame: 2, hp: 0), frame: 2)
    assert_equal 'failed', events.last['status']
  end

  def test_zero_hp_without_prior_life_is_not_death
    start({ kind: 'reach_place', place: [7, 8] })
    assert_nil @objectives.update(state(frame: 1, hp: 0), frame: 1)
  end

  def test_abandon
    start({ kind: 'dialogue_closed' })
    assert_equal :abandoned, @objectives.abandon(frame: 5, reason: 'agent')
    assert_nil @objectives.current
    assert_equal 'agent', events.last['reason']
    assert_equal [{ outcome: :abandoned, reason: 'agent' }], @objectives.history.map { |h| h.slice(:outcome, :reason) }
  end

  def test_attempts_bounded_and_prompted
    start({ kind: 'dialogue_closed' })
    12.times { |i| @objectives.record_attempt(skill: 's', params: { n: i }, result_summary: "r#{i}") }
    assert_equal 10, @objectives.current[:attempts].size
    lines = @objectives.attempts_for_prompt
    assert_equal 10, lines.size
    assert_includes lines.last, 'r11'
  end

  def test_update_without_current_is_nil
    assert_nil @objectives.update(state, frame: 1)
  end

  def blocked(row: 3, col: 4, direction: 'up') = { row:, col:, direction: }

  def test_new_place_not_achieved_in_starting_place
    start({ kind: 'new_place' })
    assert_nil @objectives.update(state(frame: 1), frame: 1)
    assert_nil @objectives.update(state(frame: 2, x: 50), frame: 2)
    assert_equal [[1, 2]], @objectives.visited
  end

  def test_new_place_achieved_in_another_place_and_never_by_loading
    start({ kind: 'new_place' })
    @objectives.update(state, frame: 1)
    assert_nil @objectives.update(state(room: 9, game_submode: 5), frame: 2)
    assert_equal [[1, 2]], @objectives.visited
    assert_equal :achieved, @objectives.update(state(room: 9), frame: 3)
    assert_equal ['started', 'achieved'], events.map { |e| e['status'] }
  end

  def test_new_place_not_achieved_when_returning_to_visited_place
    start({ kind: 'new_place' })
    @objectives.update(state, frame: 1)
    @objectives.update(state(room: 9), frame: 2)
    start({ kind: 'new_place' }, frame: 3)
    assert_nil @objectives.update(state(room: 1), frame: 4)
    assert_equal :achieved, @objectives.update(state(room: 5), frame: 5)
  end

  def test_visited_seeding_on_resume
    objectives = Koholint::Objectives.new(trace: @trace, visited: [[9, 2]])
    objectives.start(frame: 0, title: 't', predicate: { kind: 'new_place' })
    assert_nil objectives.update(state(room: 9), frame: 1)
    assert_equal :achieved, objectives.update(state(room: 1), frame: 2)
  end

  def test_six_same_pair_blocks_abandon_reach_cell
    target = { kind: 'reach_cell', place: [1, 2], row: 0, col: 0 }
    start(target)
    5.times { assert_nil @objectives.note_blocked(blocked_at: blocked, target:) }
    assert_equal :abandoned, @objectives.note_blocked(blocked_at: blocked, target:)
    done = events.last
    assert_equal ['abandoned', 'unreachable'], [done['status'], done['reason']]
    assert_equal 2, events.size
  end

  def test_mixed_blocks_total_eight_abandons_any_kind
    target = { kind: 'leave_place', place: [1, 2] }
    start(target)
    7.times { |i| assert_nil @objectives.note_blocked(blocked_at: blocked(col: i), target:) }
    assert_equal :abandoned, @objectives.note_blocked(blocked_at: blocked(col: 8), target:)
    assert_equal 'unreachable', events.last['reason']
    assert_nil @objectives.note_blocked(blocked_at: blocked, target:)
    assert_equal 2, events.size
  end

  def test_mixed_blocks_on_reach_cell_do_not_trip_pairs
    target = { kind: 'reach_cell', place: [1, 2], row: 0, col: 0 }
    start(target)
    7.times { |i| assert_nil @objectives.note_blocked(blocked_at: blocked(col: i % 2), target:) }
  end

  def test_same_pair_only_counts_for_reach_cell
    target = { kind: 'leave_place', place: [1, 2] }
    start(target)
    7.times { assert_nil @objectives.note_blocked(blocked_at: blocked, target:) }
  end

  def test_block_counters_reset_on_new_objective
    target = { kind: 'reach_cell', place: [1, 2], row: 0, col: 0 }
    start(target)
    5.times { @objectives.note_blocked(blocked_at: blocked, target:) }
    start(target, frame: 1)
    5.times { assert_nil @objectives.note_blocked(blocked_at: blocked, target:) }
  end

  def test_unreachable_event_carries_the_passed_frame
    target = { kind: 'leave_place', place: [1, 2] }
    start(target)
    7.times { @objectives.note_blocked(blocked_at: blocked, target:, frame: 50) }
    @objectives.note_blocked(blocked_at: blocked, target:, frame: 77)
    assert_equal 77, events.last['frame']
  end

  def test_note_blocked_accepts_string_keys_and_directions
    target = { 'kind' => 'reach_cell', 'place' => [1, 2], 'row' => 0, 'col' => 0 }
    start(target)
    3.times { @objectives.note_blocked(blocked_at: { 'row' => 3, 'col' => 4, 'direction' => 'up' }, target:) }
    2.times { @objectives.note_blocked(blocked_at: { row: 3, col: 4, direction: :up }, target:) }
    assert_equal :abandoned, @objectives.note_blocked(blocked_at: { 'row' => 3, 'col' => 4, 'direction' => :up }, target:)
    assert_equal 'unreachable', events.last['reason']
  end

  def test_reach_cell_abandons_at_eight_mixed_blocks
    target = { kind: 'reach_cell', place: [1, 2], row: 0, col: 0 }
    start(target)
    7.times { |i| assert_nil @objectives.note_blocked(blocked_at: blocked(col: i), target:) }
    assert_equal :abandoned, @objectives.note_blocked(blocked_at: blocked(col: 7), target:)
  end

  def test_visits_are_recorded_without_an_active_objective
    start({ kind: 'new_place' })
    @objectives.update(state, frame: 1)
    @objectives.abandon(frame: 2, reason: 'x')
    @objectives.update(state(room: 9), frame: 3)
    start({ kind: 'new_place' }, frame: 4)
    assert_nil @objectives.update(state(room: 9), frame: 5)
    assert_equal :achieved, @objectives.update(state(room: 5), frame: 6)
  end

  def test_no_path_abandons_as_unreachable_at_the_third
    start({ kind: 'reach_place', place: [7, 8] })
    assert_nil @objectives.note_no_path(frame: 1)
    assert_nil @objectives.note_no_path(frame: 2)
    assert_equal :abandoned, @objectives.note_no_path(frame: 3)
    assert_equal 'unreachable', events.last['reason']
    assert_nil @objectives.note_no_path(frame: 4)
    assert_equal 1, events.count { |e| e['status'] == 'abandoned' }
  end

  def test_no_path_counter_resets_with_a_new_objective
    start({ kind: 'reach_place', place: [7, 8] })
    2.times { @objectives.note_no_path(frame: 1) }
    @objectives.abandon(frame: 2, reason: 'x')
    start({ kind: 'reach_place', place: [7, 8] })
    2.times { assert_nil @objectives.note_no_path(frame: 3) }
  end

  def test_repeated_talking_loops_despite_the_dialogue_opening_and_closing
    start({ kind: 'reach_place', place: [7, 8] })
    outcome = nil
    12.times do |i|
      @objectives.update(state(frame: i * 2), frame: i * 2)
      @objectives.record_attempt(skill: 'goto', params: { row: 1, col: 1 }, result_summary: 'ok')
      outcome ||= @objectives.update(state(frame: (i * 2) + 1, dialog: 134 + i), frame: (i * 2) + 1)
    end
    assert_equal :abandoned, outcome
    assert_equal 'loop', events.last['reason']
  end

  def test_boot_states_are_not_visited
    @objectives.update(state(room: 1, map: 2), frame: 1)
    @objectives.update(Koholint::GameState.new(game_mode: 0, game_submode: 0, room_id: 9, map_id: 9, x: 0, y: 0, hp: 0, dialog_state: 0, milestone: :none), frame: 2)
    refute_includes @objectives.visited, [9, 9]
  end

  def test_trace_reader
    assert_same @trace, @objectives.trace
  end
end
