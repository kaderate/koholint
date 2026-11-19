require_relative 'test_helper'
require 'tmpdir'
require 'koholint/exits'
require 'koholint/explore_log'
require 'koholint/run'

class ExitsTest < Minitest::Test
  CONTEXT = { 'milestone' => 'sword', 'held' => [1, 4] }.freeze

  def trial(frame, to, lineage: 'boot-a', parent: 'p') = { 'run' => "r#{frame}", 'parent' => parent, 'lineage' => lineage, 'frame' => frame, 'visit' => frame, 'to' => to }

  def test_an_edge_is_verified_by_two_lineages_that_agree_and_contradicted_by_two_destinations
    data = { 'edges' => [], 'benches' => [] }
    edge = Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(73_800, [99, 0]), refutes: { 'to' => [65, 0], 'source' => 'neighbour' })
    assert_equal ['observed', 1, [99, 0]], edge.values_at('status', 'verified_count', 'to')
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(95_400, [99, 0], parent: 'q'))
    assert_equal ['observed', 1], edge.values_at('status', 'verified_count'), 'two visits of one lineage are one check'
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(73_800, [99, 0]).merge('run' => 'rerun'))
    assert_equal 2, edge['trials'].size, 'a rerun at the same parent and frame adds nothing'
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(40_000, [99, 0], lineage: 'boot-b'))
    assert_equal ['verified', 2], edge.values_at('status', 'verified_count')
    assert_equal [{ 'to' => [65, 0], 'source' => 'neighbour' }], edge['refutes']
    Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(99_000, [65, 0], lineage: 'boot-c'))
    assert_equal ['contradicted', 0], edge.values_at('status', 'verified_count')
    refute edge.key?('to')
  end

  def test_measured_edges_of_the_same_context_route_with_their_status_and_benches_join_the_digest
    data = { 'edges' => [], 'benches' => [] }
    %w[boot-a boot-b].each_with_index { |lineage, n| Koholint::Exits.record(data, place: [81, 0], way: 'up', context: CONTEXT, trial: trial(n, [99, 0], lineage:)) }
    Koholint::Exits.record(data, place: [81, 0], way: 'down', context: CONTEXT, trial: trial(5, [97, 0]))
    Koholint::Exits.record(data, place: [81, 0], way: 'left', context: CONTEXT, trial: trial(6, nil))
    found = Koholint::Exits.for_context(data, CONTEXT)
    assert_equal({ [[81, 0], :up] => [99, 0], [[81, 0], :down] => [97, 0] }, found[:edges])
    assert_equal({ [[81, 0], :up] => 'verified', [[81, 0], :down] => 'observed' }, found[:status])
    assert_equal({ edges: {}, status: {}, benches: {} }, Koholint::Exits.for_context(data, CONTEXT.merge('held' => [1, 4, 5])), 'another item held is another context')
    before = Koholint::Exits.digest(data)
    data['benches'] << { 'place' => [81, 0], 'context' => CONTEXT, 'ways' => { 'left' => 'unreached' }, 'new_places' => [], 'status' => 'incomplete' }
    refute_equal before, Koholint::Exits.digest(data), 'a bench steers play, so it changes the digest'
    assert_equal Koholint::Exits.digest({ 'edges' => [], 'benches' => [] }), Koholint::Exits.digest({ 'edges' => [data['edges'].last], 'benches' => [] }), 'an unreached edge routes nothing'
  end

  def with_run(**options)
    Dir.mktmpdir do |dir|
      rom = File.join(dir, 'game.gbc')
      File.binwrite(rom, 'fake rom bytes')
      yield Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom, **options), rom
    end
  end

  def test_runs_record_the_exits_digest_apart_from_capabilities_and_resume_only_with_it
    with_run(exits: 'abc', capabilities: false) do |run, rom|
      run.check_exits!('abc')
      error = assert_raises(Koholint::Run::ExitsMismatch) { run.check_exits!('def') }
      assert_includes error.message, 'recorded with exits abc, current is def'
      assert_equal Koholint::Exits.digest, run.fork(at_frame: 0, flow_version: 'f1', rom_path: rom).manifest['exits'], 'a capabilities-off arm keeps the exits'
      off = run.fork(at_frame: 0, flow_version: 'f1', rom_path: rom, exits: false)
      assert_equal [false, false], [off.manifest['exits'], off.exits?]
      off.check_exits!('def')
      assert_equal false, off.fork(at_frame: 0, flow_version: 'f1', rom_path: rom).manifest['exits']
      run.manifest.delete('exits')
      run.check_exits!('def')
      refute run.exits?, 'a run recorded before the key resumes without exits'
    end
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
    log.use_bench({ edges: { [[81, 0], :up] => [99, 0], [[81, 0], :down] => [5, 1], [[97, 0], :up] => [7, 1] }, status: {}, benches: {} })
    assert_equal({ goal: [99, 0], next: [99, 0], via: :up }, log.route([81, 0], goal: [99, 0]))
    assert_equal [97, 0], log.route([81, 0], goal: [97, 0])[:next], 'the crossing the run made wins'
    assert_equal [7, 1], log.route([97, 0], goal: [7, 1])[:next], 'a bench edge replaces an assumed way back'
    assert log.side_left?([81, 0], :up)
  end

  def test_a_door_way_is_keyed_like_the_explore_log_keys_the_door_it_walked_through
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 10, map: 0 }, exits: [{ row: 4, col: 3, direction: :up, outcome: :left, to: [200, 16], kind: :door }] })
    assert log.door_edge?([10, 0], [3, 3])
    benched = Koholint::ExploreLog.new
    data = { 'edges' => [], 'benches' => [] }
    %w[boot-a boot-b].each_with_index { |lineage, n| Koholint::Exits.record(data, place: [10, 0], way: [3, 3], context: CONTEXT, trial: trial(n, [200, 16], lineage:)) }
    benched.use_bench(Koholint::Exits.for_context(JSON.parse(JSON.generate(data)), CONTEXT))
    assert benched.door_edge?([10, 0], [3, 3]), 'the bench stores the door cell, as explore keys its door exits'
  end
end
