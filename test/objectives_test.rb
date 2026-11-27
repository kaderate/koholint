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
    assert Koholint::Objectives.valid_predicate?({ kind: 'new_text' })
    assert_equal %w[dialogue_closed leave_place new_place new_text reach_cell reach_place], Koholint::Objectives::PREDICATES.keys.sort
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
    assert_nil @objectives.update(state(frame: 99, x: 90), frame: 99)
    assert_equal :abandoned, @objectives.update(state(frame: 100, x: 40), frame: 100)
    assert_equal 'stall', events.last['reason']
    assert_nil @objectives.current
  end

  # b32c (flow-112) obj-7 at 13322: "reach D12 column 9" walked C11, C12, D11 and D12 for 6364 frames, never closed, and held the autopilot.
  def test_only_a_new_place_a_new_text_or_a_shorter_route_to_its_place_keeps_an_objective
    @objectives.update(state(frame: 0, room: 9), frame: 0)
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1, room: 9), frame: 1, distance: 3)
    assert_nil @objectives.update(state(frame: 80, room: 10), frame: 80, distance: 2), 'a shorter route'
    assert_nil @objectives.update(state(frame: 170, room: 9), frame: 170, distance: 3), 'a known place again'
    assert @objectives.note_text('A text never read before')
    assert_nil @objectives.update(state(frame: 260, room: 11), frame: 260, distance: 3), 'a new text at 170 is progress'
    assert_nil @objectives.update(state(frame: 330, room: 12), frame: 330), 'a place never visited'
    assert_equal :abandoned, @objectives.update(state(frame: 430, room: 9, dialog: 134), frame: 430, distance: 3)
    assert_equal 'stall', events.last['reason']
  end

  def test_open_dialogue_with_animating_counter_stalls
    start({ kind: 'reach_place', place: [7, 8] })
    @objectives.update(state(frame: 1, dialog: 134), frame: 1)
    assert_nil @objectives.update(state(frame: 60, dialog: 137), frame: 60)
    assert_nil @objectives.update(state(frame: 99, dialog: 140), frame: 99)
    assert_equal :abandoned, @objectives.update(state(frame: 100, dialog: 141), frame: 100)
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

  def test_new_text_needs_a_text_not_read_before_in_the_run
    refute @objectives.note_text('   ')
    assert @objectives.note_text('Hello  there')
    assert @objectives.note_text('Hélló there')
    start({ kind: 'new_text' })
    refute @objectives.note_text('hello there')
    refute @objectives.note_text('there')
    refute @objectives.note_text('Hello, there!')
    assert_nil @objectives.update(state(frame: 1), frame: 1)
    assert @objectives.note_text('Go north')
    assert_equal :achieved, @objectives.update(state(frame: 2), frame: 2)
    start({ kind: 'new_text' }, frame: 3)
    assert_nil @objectives.update(state(frame: 4), frame: 4)
  end

  def test_a_chest_objective_ends_when_that_chest_is_seen_open_even_with_a_known_text
    @objectives.note_text('Tu as trouvé quelque chose')
    @objectives.start(frame: 1, title: 'Open the chest', predicate: { kind: 'new_text' }, target: { kind: 'chest', place: [1, 0], cell: [3, 4] })
    refute @objectives.note_text('Tu as trouvé quelque chose')
    assert_nil @objectives.update(state(frame: 2), frame: 2)
    @objectives.note_chest_open(place: [1, 0], cell: [5, 6])
    assert_nil @objectives.update(state(frame: 3), frame: 3), 'another chest'
    @objectives.note_chest_open(place: [1, 0], cell: [3, 4])
    assert_equal :achieved, @objectives.update(state(frame: 4), frame: 4)
  end

  def test_a_thing_to_try_is_reached_only_once_tried_with_an_answer_or_a_touch_after_a_silent_talk
    @objectives.start(frame: 1, title: 'Go examine', predicate: { kind: 'reach_place', place: [7, 8] }, target: { kind: 'person', place: [7, 8], type: 132, cell: [3, 4], try: true })
    assert_nil @objectives.update(state(frame: 2, room: 7, map: 8), frame: 2), 'reaching the place is not enough'
    @objectives.note_try(place: [7, 8], type: 64, skill: 'touch', answered: false)
    assert_nil @objectives.update(state(frame: 3, room: 7, map: 8), frame: 3), 'another thing'
    @objectives.note_try(place: [7, 8], type: 132, skill: 'talk_to', answered: false)
    assert @objectives.talked_to?
    assert_nil @objectives.update(state(frame: 4, room: 7, map: 8), frame: 4), 'a talk that drew nothing'
    @objectives.note_try(place: [7, 8], type: 132, skill: 'touch', answered: false)
    assert_equal :achieved, @objectives.update(state(frame: 5, room: 7, map: 8), frame: 5)
    @objectives.start(frame: 6, title: 'Go examine', predicate: { kind: 'reach_place', place: [7, 8] }, target: { kind: 'person', place: [7, 8], type: 132, cell: [3, 4], try: true })
    refute @objectives.talked_to?
    @objectives.note_try(place: [7, 8], type: 132, skill: 'talk_to', answered: true)
    assert_equal :achieved, @objectives.update(state(frame: 7, room: 7, map: 8), frame: 7), 'an answer is a try'
  end

  def test_a_person_brought_an_item_is_reached_only_once_the_item_is_used_after_the_talk
    @objectives.start(frame: 1, title: 'Bring the Champignon', predicate: { kind: 'reach_place', place: [7, 8] },
                      target: { kind: 'person', place: [7, 8], type: 64, cell: [3, 4], try: true, item: 12, name: 'Champignon' })
    @objectives.note_try(place: [7, 8], type: nil, skill: 'use_item', answered: false, item: 12)
    assert_nil @objectives.update(state(frame: 2, room: 7, map: 8), frame: 2), 'a use before the talk'
    @objectives.note_try(place: [7, 8], type: 64, skill: 'talk_to', answered: true)
    assert @objectives.talked_to?
    assert_nil @objectives.update(state(frame: 2, room: 7, map: 8), frame: 2), 'an answer alone does not bring the item'
    @objectives.note_try(place: [7, 8], type: nil, skill: 'use_item', answered: false, item: 1)
    assert_nil @objectives.update(state(frame: 3, room: 7, map: 8), frame: 3), 'another item'
    @objectives.note_try(place: [7, 8], type: nil, skill: 'use_item', answered: false, item: 12)
    assert_equal :achieved, @objectives.update(state(frame: 3, room: 7, map: 8), frame: 3)
  end

  def test_a_sign_objective_ends_on_that_signs_text_only_even_when_the_text_is_known
    @objectives.note_text('Attention au plancher')
    @objectives.start(frame: 1, title: 'Go read the sign', predicate: { kind: 'new_text' }, target: { kind: 'sign', place: [101, 0], cell: [4, 8], remote: true })
    assert @objectives.note_text('Un villageois parle')
    assert_nil @objectives.update(state(frame: 2), frame: 2), 'another text met on the way'
    @objectives.note_sign_read(place: [101, 0], cell: [4, 7])
    assert_nil @objectives.update(state(frame: 3), frame: 3), 'another sign'
    refute @objectives.note_text('Attention au plancher')
    @objectives.note_sign_read(place: [101, 0], cell: [4, 8])
    assert_equal :achieved, @objectives.update(state(frame: 4), frame: 4)
  end

  def test_read_texts_are_rebuilt_from_dialogue_events_on_resume
    @trace.emit(:dialogue, frame: 5, place: [1, 2], text: 'Pour sauvegard', source: 'agent', page: 1)
    @trace.emit(:dialogue, frame: 5, place: [1, 2], text: 'sauvegarder, appuyez', source: 'agent', page: 2)
    resumed = Koholint::Objectives.resume(trace: @trace, events: Koholint::Trace.read(@path), frame: 6)
    refute resumed.note_text('pour sauvegarder, appuyez')
    assert resumed.note_text('something else')
  end

  def test_visited_seeding_on_resume
    objectives = Koholint::Objectives.new(trace: @trace, visited: [[9, 2]])
    objectives.start(frame: 0, title: 't', predicate: { kind: 'new_place' })
    assert_nil objectives.update(state(room: 9), frame: 1)
    assert_equal :achieved, objectives.update(state(room: 1), frame: 2)
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
