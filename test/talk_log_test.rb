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
end
