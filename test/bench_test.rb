require_relative 'test_helper'
require 'koholint/bench'

class BenchTest < Minitest::Test
  RUN = Struct.new(:id).new('20261118-142325-20ea')
  CONTEXT = { 'milestone' => 'sword', 'held' => [1, 4] }.freeze

  def seen(frame, room) = { 'type' => 'perception', 'frame' => frame, 'state' => { 'room_id' => room, 'map_id' => 0, 'game_mode' => 11, 'game_submode' => 7 } }

  def test_each_visit_gives_its_first_keyframe_since_the_last_one_can_catch_link_leaving
    events = [seen(73_299, 81), { 'type' => 'keyframe', 'frame' => 73_800 }, { 'type' => 'keyframe', 'frame' => 75_234 }, seen(75_235, 99),
              { 'type' => 'keyframe', 'frame' => 75_600 }, seen(93_925, 81), { 'type' => 'keyframe', 'frame' => 95_400 }]
    assert_equal [{ frame: 73_800, visit: 73_299 }, { frame: 95_400, visit: 93_925 }], Koholint::Bench.keyframes(events, [81, 0])
  end

  def test_a_trial_records_the_arrival_against_the_neighbour_and_the_way_back_against_the_reverse
    data = { 'edges' => [], 'benches' => [] }
    trial = { outcome: :left, arrival: { to: [99, 0], landing: [7, 3] }, back: { to: [115, 0], landing: [0, 3] }, run: 'child' }
    Koholint::Bench.record(data, [81, 0], :up, CONTEXT, { frame: 73_800, visit: 73_299 }, trial, RUN)
    up, back = data['edges']
    assert_equal [[81, 0], 'up', [99, 0], [{ 'to' => [65, 0], 'source' => 'neighbour' }]], up.values_at('place', 'way', 'to', 'refutes')
    assert_equal [[99, 0], 'down', [115, 0], [{ 'to' => [81, 0], 'source' => 'reverse' }]], back.values_at('place', 'way', 'to', 'refutes')
    Koholint::Bench.record(data, [81, 0], :left, CONTEXT, { frame: 73_800, visit: 73_299 }, { outcome: :unreached, run: 'child2' }, RUN)
    assert_equal 'unreached', data['edges'].last['status']
  end

  def test_a_bench_with_no_new_place_depends_on_context_and_keeps_the_texts_read_there
    events = [seen(73_299, 81), seen(70_000, 97),
              { 'type' => 'dialogue', 'frame' => 74_971, 'place' => [81, 0], 'text' => 'Hé hé! Tu vas te perdre' },
              { 'type' => 'dialogue', 'frame' => 74_971, 'place' => [81, 0], 'text' => 'te perdre dans la Forêt.' },
              { 'type' => 'lead', 'frame' => 75_169, 'place' => [81, 0], 'id' => 'lead-22', 'quote' => 'Tu vas te perdre dans' },
              { 'type' => 'dialogue', 'frame' => 75_300, 'place' => [99, 0], 'text' => 'elsewhere' }, seen(75_235, 99)]
    data = { 'edges' => [], 'benches' => [] }
    Koholint::Bench.note_bench(data, events, [81, 0], CONTEXT, { frame: 95_400 }, { 'up' => [99, 0], 'left' => nil }, RUN)
    bench = data['benches'].first
    assert_equal ['depends_on_context', [], { 'up' => [99, 0], 'left' => 'unreached' }], bench.values_at('status', 'new_places', 'ways')
    assert_equal [{ 'type' => 'dialogue', 'frame' => 74_971, 'text' => 'Hé hé! Tu vas te perdre dans la Forêt.' },
                  { 'type' => 'lead', 'id' => 'lead-22', 'frame' => 75_169, 'quote' => 'Tu vas te perdre dans' }], bench['hypotheses']
    Koholint::Bench.note_bench(data, events, [81, 0], CONTEXT, { frame: 95_400 }, { 'right' => [82, 0] }, RUN)
    assert_equal ['leads_on', [[82, 0]], []], bench.values_at('status', 'new_places', 'hypotheses')
  end
end
