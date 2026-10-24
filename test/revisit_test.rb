require_relative 'test_helper'
require 'koholint/game_state'
require 'koholint/revisit'
require 'koholint/talk_log'

class RevisitTest < Minitest::Test
  PLACE = [163, 16].freeze
  STAMP = ['shield', 1].freeze

  def setup
    @log = Koholint::TalkLog.new
    @revisit = Koholint::Revisit.new(talk_log: @log)
  end

  def state(frame: 100, **over)
    Koholint::GameState.new(frame:, room_id: 163, map_id: 16, x: 88, y: 64, direction: 3, hp: 24, max_hp: 24, milestone: :shield, game_mode: 0x0B,
                            game_submode: 7, dialog_state: 0, **over)
  end

  def npc(type, cell, slot: type, kind: :npc, verified: true, moves: false) = { slot:, type:, x: (cell[1] * 16) + 8, y: (cell[0] * 16) + 16, cell:, kind:, verified:, moves: }

  def people = [npc(62, [3, 5], slot: 0), npc(63, [4, 7], slot: 1)]

  def act(frame: 100, entities: people, stamp: STAMP, **opts) = @revisit.next_action(state: state(frame:), entities:, stamp:, **opts)

  def say(type, text, conversation: nil, stamp: STAMP)
    @log.remember(place: PLACE, cell: [4, 7], text:, stamp:, entity: type, conversation:)
    @revisit.read
  end

  def test_talks_to_the_nearest_never_talked_npc_first
    action = act
    assert_equal({ skill: 'talk_to', params: { row: 3, col: 5 } }, action.slice(:skill, :params))
    assert_equal 1, action[:round]
    assert_equal({ place: PLACE, type: 62, cell: [3, 5] }, action[:npc])
  end

  def test_repeats_the_same_npc_until_two_identical_conversations_then_moves_on
    act
    say(62, 'Hello there.', conversation: 'a' * 16)
    assert_equal 62, act[:npc][:type]
    say(62, 'Hello there.', conversation: 'a' * 16)
    next_one = act
    assert_equal 63, next_one[:npc][:type]
    notes = @revisit.notes
    assert_equal %w[new exhausted], notes.map { |note| note[:detail][:outcome] }
    assert_equal [1, 2], notes.map { |note| note[:detail][:round] }
    assert(notes.all? { |note| note[:kind] == 'revisit' })
  end

  def test_a_new_stamp_reopens_an_exhausted_npc
    act(entities: [people.first])
    2.times do
      say(62, 'Hello there.')
      act(entities: [people.first])
    end
    assert_nil act(entities: [people.first])
    assert_equal 62, act(entities: [people.first], stamp: ['shield', 2])[:npc][:type]
  end

  def test_round_cap_per_npc_and_stamp
    rounds = (1..Koholint::Revisit::ROUND_CAP).map do |i|
      action = act(entities: [people.first], frame: 100 + i)
      say(62, "Text number #{%w[one two three four five six seven][i - 1]}.")
      action[:round]
    end
    assert_equal (1..6).to_a, rounds
    assert_nil act(entities: [people.first], frame: 200)
  end

  def test_two_failed_talks_make_the_npc_unreachable_for_the_stamp
    act(entities: [people.last])
    @revisit.talked({ talked: false, stopped_by: 'no_path' })
    act(entities: [people.last])
    @revisit.talked({ talked: false, stopped_by: 'target_free' })
    assert_nil act(entities: [people.last])
    assert_equal %w[no_dialogue unreachable], @revisit.notes.map { |note| note[:detail][:outcome] }
    assert_nil act(entities: [people.last], stamp: ['shield', 3])
    @revisit.next_action(state: state(room_id: 162), entities: [], stamp: STAMP)
    refute_nil act(entities: [people.last], stamp: ['shield', 3])
  end

  def test_the_cycle_stops_at_its_frame_cap_for_the_place_and_stamp
    act(frame: 100)
    say(62, 'One.')
    assert act(frame: 100 + Koholint::Revisit::CYCLE_FRAMES - 1)
    say(62, 'Two.')
    assert_nil act(frame: 100 + Koholint::Revisit::CYCLE_FRAMES)
    assert_equal 'cycle_frame_cap', @revisit.notes.last[:detail][:outcome]
    assert_nil act(frame: 5000)
  end

  def test_only_npcs_on_screen_in_free_play_and_never_when_the_budget_is_low
    assert_nil act(entities: [npc(45, [6, 1], kind: :unknown), npc(110, [2, 2], kind: :enemy)])
    assert_nil act(entities: [npc(117, [5, 7], verified: false)])
    assert_nil act(entities: [{ slot: 3, type: 63, x: 250, y: 20, cell: nil, kind: :npc }])
    assert_nil @revisit.next_action(state: state(dialog_state: 3), entities: people, stamp: STAMP)
    assert_nil @revisit.next_action(state: state(game_mode: 0x0C, game_submode: 8), entities: people, stamp: STAMP)
    assert_nil act(budget_low: true)
    assert act
  end

  def test_a_round_without_any_text_is_closed_at_the_next_action
    act
    act
    assert_equal ['no_text'], @revisit.notes.map { |note| note[:detail][:outcome] }
  end

  def test_candidate_does_not_count_a_round
    assert_equal 62, @revisit.candidate(state: state, entities: people, stamp: STAMP)[:type]
    assert_equal 1, act[:round]
  end

  def test_a_visit_serves_at_most_three_stamps
    [1, 2, 3].each { |places| assert act(entities: [people.first], stamp: ['shield', places]) }
    assert_nil act(entities: [people.first], stamp: ['shield', 4])
    @revisit.next_action(state: state(room_id: 162), entities: [], stamp: STAMP)
    assert act(entities: [people.first], stamp: ['shield', 4])
  end

  def test_the_candidate_applies_the_frame_cap_like_next_action
    act(frame: 100)
    say(62, 'One.')
    assert_nil @revisit.candidate(state: state(frame: 100 + Koholint::Revisit::CYCLE_FRAMES), entities: people, stamp: STAMP)
    assert_nil act(frame: 100 + Koholint::Revisit::CYCLE_FRAMES)
    assert_equal ['new', 'cycle_frame_cap'], @revisit.notes.map { |note| note[:detail][:outcome] }
  end

  def test_two_people_of_one_type_are_each_tried_once_per_stamp
    twins = [npc(115, [5, 2], slot: 6), npc(115, [2, 8], slot: 7)]
    first = act(entities: twins)
    say(115, 'Same words.')
    second = act(entities: twins)
    say(115, 'Same words.')
    assert_equal [[2, 8], [5, 2]], [first, second].map { |a| a[:params].values_at(:row, :col) }
    assert_nil act(entities: twins)
    assert_nil act(entities: [twins.first])
  end

  def test_danger_gates_the_revisit
    near = npc(110, [3, 5], slot: 9, kind: :unknown, moves: true)
    assert_nil act(entities: people + [near])
    assert_nil act(entities: people + [near.merge(kind: :enemy, moves: false)])
    assert_nil act(entities: people + [near.merge(moves: nil)])
    refute_nil @revisit.candidate(state: state, entities: people + [near.merge(moves: false)], stamp: STAMP)
    refute_nil @revisit.candidate(state: state, entities: people + [near.merge(x: 150, y: 130)], stamp: STAMP)
    assert_nil @revisit.next_action(state: state(hp: 15), entities: people, stamp: STAMP)
    assert_nil act(danger: true)
    assert act
  end
end
