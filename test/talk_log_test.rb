require_relative 'test_helper'
require 'koholint/talk_log'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'

class TalkLogTest < Minitest::Test
  PLACE = [163, 16].freeze

  def grid(sprites)
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: sprites, beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
  end

  def sprite(row, col, height: 16) = { 'x' => col * 16 + 8, 'y' => row * 16 + 16, 'pattern' => "s#{row}#{col}", 'height' => height }

  def test_objects_are_connected_components_ordered_by_cell
    sprites = [sprite(4, 7), sprite(2, 4, height: 32), sprite(2, 5, height: 32)]
    assert_equal [[[2, 4], [2, 5], [3, 4], [3, 5]], [[4, 7]]], Koholint::TalkLog.objects(grid(sprites))
    assert_equal [], Koholint::TalkLog.objects(grid([]))
  end

  def test_diagonal_cells_are_separate_objects
    assert_equal [[[1, 1]], [[2, 2]]], Koholint::TalkLog.objects(grid([sprite(1, 1), sprite(2, 2)]))
  end

  def test_counts_map_a_cell_to_its_object
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 3, col: 5, talked: true)
    log.record(place: PLACE, row: 2, col: 4, talked: false)
    log.record(place: PLACE, row: 2, col: 4, talked: true)
    g = grid([sprite(2, 4, height: 32), sprite(2, 5, height: 32), sprite(4, 7)])
    assert_equal ['- at (2,4)-(3,5): talked to 3 times (dialogue opened 2)', '- at (4,7): never tried'], log.lines(g, PLACE)
    assert_equal ['- at (2,4)-(3,5): never tried', '- at (4,7): never tried'], log.lines(g, [1, 2])
  end

  def test_singular_time
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 7, talked: true)
    assert_equal ['- at (4,7): talked to 1 time (dialogue opened 1)'], log.lines(grid([sprite(4, 7)]), PLACE)
  end

  def test_from_events_rebuilds_talk_to_counts_only
    spot = { 'room' => 163, 'map' => 16, 'row' => 3, 'col' => 4 }
    talk = ->(talked, skill = 'talk_to') { { 'type' => 'action', 'skill' => skill, 'params' => { 'row' => 4, 'col' => 7 }, 'result' => { 'from' => spot, 'talked' => talked, 'stopped_by' => talked ? 'done' : 'no_response' } } }
    log = Koholint::TalkLog.from_events([talk.call(true), talk.call(false), talk.call(true, 'goto'), { 'type' => 'decision' }])
    assert_equal 2, log.attempts(PLACE, [[4, 7]])
    assert_equal 1, log.talked(PLACE, [[4, 7]])
  end

  def test_failed_sides_are_recorded_and_a_success_clears_them
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 7, talked: false, standing: [[[5, 7], true]])
    log.record(place: PLACE, row: 4, col: 7, talked: false, standing: [[[5, 7], true], [[3, 7], true]])
    assert_equal [[5, 7], [3, 7]], log.failed_sides(PLACE, [4, 7])
    assert_equal [], log.failed_sides([1, 2], [4, 7])
    assert_equal ['- at (4,7): talked to 2 times (dialogue opened 0); no response from (5,7), (3,7)'], log.lines(grid([sprite(4, 7)]), PLACE)
    log.record(place: PLACE, row: 4, col: 7, talked: true, standing: [[[5, 7], false]])
    assert_equal [[3, 7]], log.failed_sides(PLACE, [4, 7])
  end

  def test_from_events_rebuilds_the_failed_sides
    spot = { 'room' => 163, 'map' => 16, 'row' => 3, 'col' => 4 }
    event = ->(result) { { 'type' => 'action', 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 7 }, 'result' => { 'from' => spot }.merge(result) } }
    tried = [{ 'row' => 5, 'col' => 7, 'outcome' => 'no_response' }, { 'row' => 3, 'col' => 7, 'outcome' => 'done' }]
    log = Koholint::TalkLog.from_events([event.call('stopped_by' => 'done', 'talked' => true, 'standing_cells_tried' => tried),
                                         event.call('stopped_by' => 'no_response', 'talked' => false, 'standing_cell' => { 'row' => 4, 'col' => 6 })])
    assert_equal [[5, 7], [4, 6]], log.failed_sides(PLACE, [4, 7])
  end

  def test_only_a_reached_talk_is_an_attempt
    assert Koholint::TalkLog.attempt?({ talked: true })
    assert Koholint::TalkLog.attempt?({ stopped_by: :no_response })
    assert Koholint::TalkLog.attempt?({ 'stopped_by' => 'done' })
    %i[blocked no_path target_free frame_cap].each { |reason| refute Koholint::TalkLog.attempt?({ stopped_by: reason, talked: false }), reason.to_s }
    log = Koholint::TalkLog.from_events([{ 'type' => 'action', 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 7 },
                                           'result' => { 'from' => { 'room' => 163, 'map' => 16, 'row' => 3, 'col' => 4 }, 'talked' => false, 'stopped_by' => 'target_free' } }])
    assert_equal 0, log.attempts(PLACE, [[4, 7]])
  end

  def test_adjacent_people_are_split_into_one_footprint_each
    two = [sprite(2, 4), sprite(2, 5), sprite(2, 6), sprite(2, 7)]
    assert_equal [[[2, 4], [2, 5]], [[2, 6], [2, 7]]], Koholint::TalkLog.objects(grid(two))
    square = [sprite(2, 4, height: 32), sprite(2, 5, height: 32)]
    assert_equal [[[2, 4], [2, 5], [3, 4], [3, 5]]], Koholint::TalkLog.objects(grid(square))
    row = (0..4).map { |c| sprite(1, c) }
    assert_equal [2, 2, 1], Koholint::TalkLog.objects(grid(row)).map(&:size)
  end

  def test_a_stale_cell_goes_to_the_nearest_object_within_one_cell_else_is_dropped
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 8, talked: true)
    log.record(place: PLACE, row: 7, col: 0, talked: true)
    assert_equal ['- at (4,7): talked to 1 time (dialogue opened 1)'], log.lines(grid([sprite(4, 7)]), PLACE)
  end

  def test_the_list_is_bounded_with_tried_objects_first
    sprites = [0, 2, 4, 6].flat_map { |r| [0, 2, 4, 6, 8].map { |c| sprite(r, c) } }
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 6, col: 2, talked: false)
    lines = log.lines(grid(sprites), PLACE, limit: 12)
    assert_equal 13, lines.size
    assert_includes lines, '- at (6,2): talked to 1 time (dialogue opened 0)'
    assert_equal '... 8 more objects', lines.last
  end
  def talk(log, text, stamp = ['none', 1, 0]) = log.remember(place: PLACE, cell: [4, 7], text:, stamp:)

  def memory_line(log, stamp = ['none', 1, 0]) = log.lines(grid([sprite(4, 7)]), PLACE, stamp:).first.split('; ', 2).last

  def test_people_are_exhausted_when_two_talks_repeat_under_an_unchanged_world
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 7, talked: true)
    talk(log, 'Hello.')
    assert_equal '1 text read, last talk gave new text, worth retrying: yes', memory_line(log)
    talk(log, 'Go north.')
    talk(log, 'hello .')
    assert_equal '3 texts read, last talk gave nothing new (1 talk in a row with nothing new)', memory_line(log)
    talk(log, 'Hello.')
    assert_equal '4 texts read, last talk gave nothing new (2 talks in a row with nothing new), exhausted', memory_line(log)
    assert_equal '4 texts read, last talk gave nothing new (2 talks in a row with nothing new), worth retrying: yes (something changed since the last talk)',
                 memory_line(log, ['none', 2, 0])
    talk(log, 'Hello.', ['none', 2, 0])
    assert_equal '5 texts read, last talk gave nothing new (3 talks in a row with nothing new)', memory_line(log, ['none', 2, 0])
  end

  def test_the_memory_is_rebuilt_from_dialogue_events_and_the_last_talk_target
    perception = { 'type' => 'perception', 'state' => { 'room_id' => 163, 'map_id' => 16, 'game_mode' => 0x0B, 'game_submode' => 7, 'milestone' => 'none' } }
    talked = { 'type' => 'action', 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 7 },
               'result' => { 'talked' => true, 'stopped_by' => 'done', 'from' => { 'room' => 163, 'map' => 16 } } }
    said = ->(text) { { 'type' => 'dialogue', 'frame' => 9, 'place' => PLACE, 'text' => text } }
    events = [perception, talked, said.call('Hi'), perception, talked, said.call('Hi'), { 'type' => 'action', 'skill' => 'walk', 'params' => {}, 'result' => {} },
              said.call('A sign')]
    log = Koholint::TalkLog.from_events(events)
    assert_equal ['- at (4,7): talked to 2 times (dialogue opened 2); 2 texts read, last talk gave nothing new (1 talk in a row with nothing new), exhausted'],
                 log.lines(grid([sprite(4, 7)]), PLACE, stamp: ['none', 1, 0])
  end
  def test_punctuation_or_a_re_read_contained_in_an_earlier_text_is_not_new
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 7, talked: true)
    talk(log, 'Go north. Then, east!')
    talk(log, 'go north')
    assert_equal '2 texts read, last talk gave nothing new (1 talk in a row with nothing new), exhausted', memory_line(log)
    talk(log, 'Go north... then east')
    assert_equal '3 texts read, last talk gave nothing new (2 talks in a row with nothing new)', memory_line(log)
  end

  def entity(type, cell, kind: :npc, slot: 0) = { slot:, type:, x: (cell[1] * 16) + 8, y: (cell[0] * 16) + 16, cell:, kind: }

  def test_an_npc_is_known_by_its_entity_type_wherever_it_stands
    log = Koholint::TalkLog.new
    log.record(place: PLACE, row: 4, col: 7, talked: true, entity: 63)
    log.remember(place: PLACE, cell: [4, 7], text: 'Hello.', stamp: ['none', 1, 0], entity: 63)
    log.record(place: PLACE, row: 2, col: 2, talked: true, entity: 63)
    log.remember(place: PLACE, cell: [2, 2], text: 'Hello.', stamp: ['none', 1, 0], entity: 63)
    lines = log.lines(grid([sprite(5, 1)]), PLACE, stamp: ['none', 1, 0], entities: [entity(63, [5, 1])])
    assert_equal ['- at (5,1): entity type 63 (npc): talked to 2 times (dialogue opened 2); 2 texts read, last talk gave nothing new (1 talk in a row with nothing new), exhausted'],
                 lines
    assert_equal :exhausted, log.status(place: PLACE, entity: 63, stamp: ['none', 1, 0])
    assert_equal :changed, log.status(place: PLACE, entity: 63, stamp: ['shield', 1, 0])
    assert_equal :never, log.status(place: PLACE, entity: 62, stamp: ['none', 1, 0])
  end

  def test_entities_come_first_and_sprites_without_an_entity_stay_as_fallback
    log = Koholint::TalkLog.new
    g = grid([sprite(2, 4, height: 32), sprite(2, 5, height: 32), sprite(6, 8)])
    lines = log.lines(g, PLACE, entities: [entity(62, [3, 5]), entity(45, [6, 1], kind: :unknown, slot: 2), entity(117, [0, 0], slot: 3).merge(verified: false)])
    assert_equal ['- at (0,0): entity type 117 (npc, unverified): never tried', '- at (3,5): entity type 62 (npc): never tried',
                  '- at (6,1): entity type 45 (kind unknown): never tried', '- at (6,8): never tried'], lines
  end

  def test_identical_conversation_signatures_exhaust_even_when_transcriptions_differ
    log = Koholint::TalkLog.new
    log.remember(place: PLACE, cell: [4, 7], text: 'Hello traveller.', stamp: ['none', 1, 0], entity: 63, conversation: 'c' * 16)
    log.remember(place: PLACE, cell: [4, 7], text: 'Helo travler!', stamp: ['none', 1, 0], entity: 63, conversation: 'c' * 16)
    assert_equal :exhausted, log.status(place: PLACE, entity: 63, stamp: ['none', 1, 0])
    assert_equal :exhausted, log.last_status(place: PLACE, entity: 63)
  end

  def test_pages_and_speaker_are_rebuilt_from_dialogue_events
    perception = { 'type' => 'perception', 'state' => { 'room_id' => 163, 'map_id' => 16, 'game_mode' => 0x0B, 'game_submode' => 7, 'milestone' => 'none' } }
    talked = { 'type' => 'action', 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 7 },
               'result' => { 'talked' => true, 'stopped_by' => 'done', 'from' => { 'room' => 163, 'map' => 16 }, 'entity' => { 'type' => 63, 'slot' => 1 } } }
    said = lambda do |text, page, cached = nil|
      { 'type' => 'dialogue', 'frame' => 9, 'place' => PLACE, 'text' => text, 'page' => page, 'conversation' => 'ab' * 8, 'speaker' => 'Tarkin', 'cached' => cached }.compact
    end
    log = Koholint::TalkLog.from_events([perception, talked, said.call('Hi there,', 1), said.call('friend.', 2), perception, talked, said.call('Hi there,', 1, true)])
    assert_equal ['Hi there,', 'friend.'], log.pages_for('ab' * 8)
    assert_equal 'Tarkin', log.speaker_for('ab' * 8)
    assert_equal 'Tarkin', log.name_of(PLACE, 63)
    assert_equal 2, log.attempts(PLACE, [[:entity, 63]])
    assert_equal ['Tarkin (4,7)'], log.people(PLACE, [entity(63, [4, 7])])
    assert_equal :exhausted, log.status(place: PLACE, entity: 63, stamp: ['none', 1, 0])
  end
end
