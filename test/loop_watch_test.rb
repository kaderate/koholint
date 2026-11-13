require_relative 'test_helper'
require 'koholint/loop_watch'

class LoopWatchTest < Minitest::Test
  def enter(watch, places)
    places.each { |frame, room| watch.observe(place: [room, 0], frame:) }
    watch
  end

  def test_the_4ec5_back_and_forth_between_known_screens_is_a_loop
    watch = enter(Koholint::LoopWatch.new, [[0, 243], [10, 226], [20, 242], [61127, 226], [61436, 242], [61820, 243], [63006, 242], [63118, 243], [63175, 242], [63671, 243]])
    assert_empty watch.notes
    assert_nil watch.hint
    enter(watch, [[63755, 242]])
    assert_equal ['loop: 242-0 entered 4 times in 2319 frames without a new place (226-0, 242-0, 243-0), 1 times this run'], watch.notes.map { |note| note[:detail] }
    assert_equal({ place: [242, 0], places: %w[226-0 242-0 243-0], span: 2319 }, watch.hint)
    enter(watch, [[63966, 226]])
    assert watch.hint
    enter(watch, [[64100, 225]])
    assert_nil watch.hint
  end

  def test_entries_older_than_the_window_and_a_new_place_do_not_count
    watch = enter(Koholint::LoopWatch.new, [[0, 1], [10, 2], [100, 1], [200, 2], [300, 1], [400, 2], [4000, 1], [4100, 2], [4200, 1]])
    assert_empty watch.notes
    enter(watch, [[4200, 3], [4300, 1], [4400, 3], [4500, 1], [4600, 3], [4700, 1]])
    assert_empty watch.notes
    enter(watch, [[4800, 3], [4900, 1]])
    assert_equal 1, watch.notes.size
  end

  def test_it_is_rebuilt_from_play_perceptions_without_repeating_notes
    events = [[0, 1], [10, 2], [20, 1], [30, 2], [40, 1], [50, 2], [60, 1], [70, 2], [80, 1]].map do |frame, room|
      { 'type' => 'perception', 'frame' => frame, 'state' => { 'room_id' => room, 'map_id' => 0, 'game_mode' => 0x0B } }
    end
    events << { 'type' => 'perception', 'frame' => 70, 'state' => { 'room_id' => 9, 'map_id' => 0, 'game_mode' => 2 } }
    watch = Koholint::LoopWatch.from_events(events)
    assert_empty watch.notes
    assert_equal [1, 0], watch.hint[:place]
  end

  def test_a_detection_acted_on_stays_acted_on_after_a_resume
    events = [[0, 1], [10, 2], [20, 1], [30, 2], [40, 1], [50, 2], [60, 1], [70, 2], [80, 1]].map do |frame, room|
      { 'type' => 'perception', 'frame' => frame, 'state' => { 'room_id' => room, 'map_id' => 0, 'game_mode' => 0x0B } }
    end
    assert_equal [1, 0], Koholint::LoopWatch.from_events(events).pending_hint[:place]
    events << { 'type' => 'decision', 'frame' => 80, 'justification' => 'loop in 1-0, 2-0: explore here, the nearest place with untried work' }
    watch = Koholint::LoopWatch.from_events(events)
    assert watch.hint
    assert_nil watch.pending_hint
    enter(watch, [[90, 2], [100, 3], [110, 1], [120, 3], [130, 1], [140, 3], [150, 1], [160, 3], [170, 1]])
    assert_equal [1, 0], watch.pending_hint[:place], 'a new detection is acted on again'
  end
end
