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
    refute Koholint::Objectives.valid_predicate?({ kind: 'nope' })
    refute Koholint::Objectives.valid_predicate?('x')
    assert_equal %w[dialogue_closed leave_place reach_cell reach_place], Koholint::Objectives::PREDICATES.keys.sort
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
end
