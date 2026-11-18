require_relative 'test_helper'
require 'tmpdir'
require 'koholint/exits'
require 'koholint/explore_log'

class ExitsTest < Minitest::Test
  CONTEXT = { 'milestone' => 'sword', 'held' => [1, 4] }.freeze

  def trial(visit, to) = { 'run' => "r#{visit}", 'parent' => 'p', 'frame' => visit, 'visit' => visit, 'to' => to }

  def test_an_edge_is_verified_by_two_visits_that_agree_and_contradicted_by_two_destinations
    data = { 'edges' => [], 'benches' => [] }
    edge = Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(73_299, [99, 0]), refutes: { 'to' => [65, 0], 'source' => 'neighbour' })
    assert_equal ['observed', 1, [99, 0]], edge.values_at('status', 'verified_count', 'to')
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(73_299, [99, 0]))
    assert_equal 'observed', edge['status'], 'two keyframes of one visit are one check'
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(93_925, [99, 0]))
    assert_equal ['verified', 2], edge.values_at('status', 'verified_count')
    assert_equal [{ 'to' => [65, 0], 'source' => 'neighbour' }], edge['refutes']
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(99_000, [65, 0]))
    assert_equal ['contradicted', 0], edge.values_at('status', 'verified_count')
    refute edge.key?('to')
  end

  def test_only_verified_edges_of_the_same_context_route_and_join_the_digest
    data = { 'edges' => [], 'benches' => [{ 'place' => [81, 0], 'context' => CONTEXT, 'status' => 'depends_on_context' }] }
    [73_299, 93_925].each { |visit| Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(visit, [99, 0])) }
    Koholint::Exits.record(data, place: [81, 0], way: 'left', context: CONTEXT, trial: trial(73_299, [80, 0]))
    found = Koholint::Exits.for_context(data, CONTEXT)
    assert_equal({ [[81, 0], :up] => [99, 0] }, found[:edges])
    assert_equal [[81, 0]], found[:benches].keys
    assert_equal({ edges: {}, benches: {} }, Koholint::Exits.for_context(data, CONTEXT.merge('held' => [1, 4, 5])), 'another item held is another context')
    assert_equal [{ 'place' => [81, 0], 'way' => 'up', 'context' => CONTEXT, 'to' => [99, 0] }], Koholint::Exits.digest_part(data)
  end

  def test_the_file_refuses_a_verified_edge_below_two_checks
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'exits.json')
      bad = { 'edges' => [{ 'place' => [1, 0], 'way' => 'up', 'context' => CONTEXT, 'trials' => [], 'status' => 'verified', 'verified_count' => 1 }], 'benches' => [] }
      assert_raises(ArgumentError) { Koholint::Exits.write(bad, path) }
      assert_equal({ 'edges' => [], 'benches' => [] }, Koholint::Exits.load(path))
    end
  end

  def test_a_bench_edge_fills_a_way_the_run_never_crossed_and_never_overrides_one_it_did
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 81, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [97, 0] }] })
    log.use_bench({ edges: { [[81, 0], :up] => [99, 0], [[81, 0], :down] => [5, 1], [[97, 0], :up] => [7, 1] }, benches: {} })
    assert_equal({ goal: [99, 0], next: [99, 0], via: :up }, log.route([81, 0], goal: [99, 0]))
    assert_equal [97, 0], log.route([81, 0], goal: [97, 0])[:next], 'the crossing the run made wins'
    assert_equal [7, 1], log.route([97, 0], goal: [7, 1])[:next], 'a bench edge replaces an assumed way back'
    assert log.side_left?([81, 0], :up)
  end
end
