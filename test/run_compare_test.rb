require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/run_compare'

class RunCompareTest < Minitest::Test
  PLAYING = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'none', 'room_id' => 3, 'map_id' => 1, 'game_mode' => 0x0B, 'game_submode' => 7 }.freeze

  def perception(frame, **state) = { 'type' => 'perception', 'frame' => frame, 'state' => PLAYING.merge(state.transform_keys(&:to_s)) }

  def make_run(root, id, events, summary)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'trace.jsonl'), events.map { |e| "#{JSON.generate(e)}\n" }.join)
    File.write(File.join(dir, 'summary.json'), JSON.generate(summary))
    dir
  end

  def test_timeline_keeps_the_first_frame_of_each_place_and_milestone
    events = [perception(0, game_mode: 0), perception(10), perception(20, room_id: 4), perception(30, milestone: 'shield'),
              perception(40), perception(50, room_id: 4, milestone: 'shield'), { 'type' => 'decision', 'frame' => 60 }]
    timeline = Koholint::RunCompare.timeline(events)
    assert_equal({ [3, 1] => 10, [4, 1] => 20 }, timeline[:places])
    assert_equal({ 'shield' => 30 }, timeline[:milestones])
  end

  def test_timeline_ignores_malformed_perceptions
    timeline = Koholint::RunCompare.timeline([{ 'type' => 'perception', 'frame' => 1, 'state' => 'x' }, { 'type' => 'perception', 'frame' => 2 }])
    assert_equal({ places: {}, milestones: {} }, timeline)
  end

  def test_compare_lists_differences_and_merges_timelines
    Dir.mktmpdir do |root|
      a = make_run(root, 'a', [perception(5), perception(9, milestone: 'shield')], { 'frames' => 100, 'dollars' => 0.5, 'tag' => 'x' })
      b = make_run(root, 'b', [perception(2, room_id: 7), perception(8)], { 'frames' => 100, 'dollars' => 0.7, 'tag' => 'x' })
      result = Koholint::RunCompare.compare(a, b)
      assert_equal 'a', result[:a][:run_id]
      assert_equal 0.7, result[:b][:summary]['dollars']
      assert_equal %w[dollars], result[:differences]
      assert_equal [{ place: [7, 1], a: nil, b: 2 }, { place: [3, 1], a: 5, b: 8 }], result[:places]
      assert_equal [{ milestone: 'shield', a: 9, b: nil }], result[:milestones]
    end
  end

  def test_compare_reads_an_archived_trace_and_tolerates_a_missing_summary
    Dir.mktmpdir do |root|
      a = make_run(root, 'a', [perception(5)], {})
      Koholint::Trace.compress(File.join(a, 'trace.jsonl'))
      File.delete(File.join(a, 'trace.jsonl'))
      File.delete(File.join(a, 'summary.json'))
      result = Koholint::RunCompare.compare(a, a)
      assert_empty result[:differences]
      assert_equal [{ place: [3, 1], a: 5, b: 5 }], result[:places]
    end
  end
end
