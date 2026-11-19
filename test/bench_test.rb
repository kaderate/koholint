require_relative 'test_helper'
require 'tmpdir'
require 'stringio'
require 'koholint/bench'

class BenchTest < Minitest::Test
  RUN = Struct.new(:id).new('20261118-142325-20ea')
  CONTEXT = { 'milestone' => 'sword', 'held' => [1, 4] }.freeze
  FakeRun = Struct.new(:id, :dir, :manifest)

  def seen(frame, room) = { 'type' => 'perception', 'frame' => frame, 'state' => { 'room_id' => room, 'map_id' => 0, 'game_mode' => 11, 'game_submode' => 7 } }

  def at(room, row, col, hp: 24) = Koholint::GameState.new(frame: 0, room_id: room, map_id: 0, x: (col * 16) + 8, y: (row * 16) + 16, hp:, dialog_state: 0,
                                                            game_mode: 0x0B, game_submode: 7, milestone: :none)

  def trial(direction = :up, door: false)
    Koholint::Bench::ExitTrial.new(registry: Koholint::Skills::Registry.default, place: [81, 0], stands: [[0, 4], [0, 5]], direction:, budget: Koholint::Budget.new, door:)
  end

  def step(trial, state, outcome = { stopped_by: 'done' })
    choice = trial.decide(nil, state, {})[:choice]
    trial.after_action(choice:, outcome:, state: yield) if block_given?
    choice
  end

  def test_an_exit_trial_walks_to_a_border_crosses_lands_and_walks_back
    t = trial
    assert_equal({ skill: 'goto', params: { row: 0, col: 4 } }, step(t, at(81, 3, 4)) { at(81, 3, 4) }, 'a stand goto did not reach is skipped')
    step(t, at(81, 3, 4), { stopped_by: 'blocked' }) { at(81, 3, 4) }
    t.instance_variable_set(:@stands, [[0, 5]])
    assert_equal({ skill: 'goto', params: { row: 0, col: 5 } }, step(t, at(81, 3, 4)) { at(81, 0, 5) })
    assert_equal({ skill: 'walk', params: { direction: 'up', cells: 2 } }, step(t, at(81, 0, 5)) { at(99, 7, 5) })
    assert_equal({ skill: 'walk', params: { direction: 'down', cells: 2 } }, step(t, at(99, 7, 5)) { at(115, 0, 5) })
    step(t, at(115, 0, 5))
    assert_equal [:left, { to: [99, 0], landing: [7, 5] }, { to: [115, 0], landing: [0, 5] }], [t.outcome, t.arrival, t.back]
  end

  def test_a_walk_back_that_stays_in_the_arrival_place_records_no_way_back
    t = trial
    step(t, at(81, 3, 4)) { at(81, 0, 4) }
    step(t, at(81, 0, 4)) { at(99, 7, 4) }
    step(t, at(99, 7, 4)) { at(99, 6, 4) }
    step(t, at(99, 6, 4))
    assert_equal [:left, [99, 0], nil], [t.outcome, t.arrival[:to], t.back]
  end

  def test_damage_a_death_or_a_landing_off_the_opposite_border_discards_the_trial
    hurt = trial
    step(hurt, at(81, 3, 4)) { at(81, 0, 4) }
    step(hurt, at(81, 0, 4, hp: 20))
    assert_equal [:discarded, nil], [hurt.outcome, hurt.arrival]
    fell = trial
    step(fell, at(81, 3, 4)) { at(81, 0, 4) }
    step(fell, at(81, 0, 4)) { at(99, 3, 3) }
    step(fell, at(99, 3, 3))
    assert_equal [:discarded, nil], [fell.outcome, fell.arrival]
    door = trial(door: true)
    step(door, at(81, 3, 4)) { at(81, 4, 3) }
    step(door, at(81, 4, 3)) { at(99, 3, 3) }
    step(door, at(99, 3, 3))
    assert_equal [99, 0], door.arrival[:to], 'a door lands anywhere in the next place'
  end

  def test_each_visit_gives_its_first_keyframe_and_a_keyframe_maps_to_its_visit
    events = [seen(73_299, 81), { 'type' => 'keyframe', 'frame' => 73_800 }, { 'type' => 'keyframe', 'frame' => 75_234 }, seen(75_235, 99),
              { 'type' => 'keyframe', 'frame' => 75_600 }, seen(93_925, 81), { 'type' => 'keyframe', 'frame' => 95_400 }]
    assert_equal [{ frame: 73_800, visit: 73_299 }, { frame: 95_400, visit: 93_925 }], Koholint::Bench.keyframes(events, [81, 0])
    assert_equal [73_299, 73_299], [73_800, 75_234].map { |frame| Koholint::Bench.visit_at(events, [81, 0], frame) }, 'two keyframes of one visit are one visit'
  end

  def test_the_lineage_is_the_oldest_ancestor_found_beside_the_run_or_archived
    Dir.mktmpdir do |dir|
      { 'b' => 'a', 'c' => 'b' }.each { |id, parent| FileUtils.mkdir_p(File.join(dir, id)) && File.write(File.join(dir, id, 'manifest.json'), JSON.generate('parent' => { 'id' => parent })) }
      run = FakeRun.new('d', File.join(dir, 'd'), { 'parent' => { 'id' => 'c' } })
      assert_equal 'a', Koholint::Bench.lineage_root(run, roots: [dir]), 'a parent found nowhere ends the chain with its id'
      assert_equal 'e', Koholint::Bench.lineage_root(FakeRun.new('e', File.join(dir, 'e'), {}), roots: [dir])
    end
  end

  def test_a_trial_records_the_arrival_against_the_neighbour_and_the_way_back_against_the_reverse
    data = { 'edges' => [], 'benches' => [] }
    start = { frame: 73_800, visit: 73_299, lineage: 'boot' }
    trial = { outcome: :left, arrival: { to: [99, 0], landing: [7, 3] }, back: { to: [115, 0], landing: [0, 3] }, run: 'child' }
    Koholint::Bench.record(data, [81, 0], :up, CONTEXT, start, trial, RUN)
    up, back = data['edges']
    assert_equal [[81, 0], 'up', [99, 0], [{ 'to' => [65, 0], 'source' => 'neighbour' }]], up.values_at('place', 'way', 'to', 'refutes')
    assert_equal [[99, 0], 'down', [115, 0], [{ 'to' => [81, 0], 'source' => 'reverse' }]], back.values_at('place', 'way', 'to', 'refutes')
    assert_equal ['boot', 'up'], back['trials'].first.values_at('lineage', 'via')
    Koholint::Bench.record(data, [81, 0], :up, CONTEXT, start, trial.merge(back: nil, run: 'again'), RUN)
    assert_equal [1, 1], data['edges'].map { |edge| edge['trials'].size }, 'a rerun at the same frame adds nothing'
    Koholint::Bench.record(data, [81, 0], :left, CONTEXT, start, { outcome: :unreached, run: 'child2' }, RUN)
    assert_equal 'unreached', data['edges'].last['status']
    Koholint::Bench.record(data, [81, 0], :right, CONTEXT, start, { outcome: :discarded, arrival: { to: [5, 0], landing: [3, 0] }, run: 'child3' }, RUN)
    assert_equal 3, data['edges'].size, 'a discarded trial records nothing'
  end

  def test_a_bench_with_an_unreached_way_is_incomplete_and_only_every_way_reached_depends_on_context
    events = [seen(73_299, 81), seen(70_000, 97),
              { 'type' => 'dialogue', 'frame' => 74_971, 'place' => [81, 0], 'text' => 'Hé hé! Tu vas te perdre' },
              { 'type' => 'dialogue', 'frame' => 74_971, 'place' => [81, 0], 'text' => 'te perdre dans la Forêt.' },
              { 'type' => 'lead', 'frame' => 75_169, 'place' => [81, 0], 'id' => 'lead-22', 'quote' => 'Tu vas te perdre dans' },
              { 'type' => 'dialogue', 'frame' => 75_300, 'place' => [99, 0], 'text' => 'elsewhere' }, seen(75_235, 99)]
    data = { 'edges' => [], 'benches' => [] }
    Koholint::Bench.note_bench(data, events, [81, 0], CONTEXT, { frame: 95_400 }, { 'up' => [99, 0], 'left' => nil }, RUN)
    bench = data['benches'].first
    assert_equal ['incomplete', [], { 'up' => [99, 0], 'left' => 'unreached' }], bench.values_at('status', 'new_places', 'ways')
    assert_equal [{ 'type' => 'dialogue', 'frame' => 74_971, 'text' => 'Hé hé! Tu vas te perdre dans la Forêt.' },
                  { 'type' => 'lead', 'id' => 'lead-22', 'frame' => 75_169, 'quote' => 'Tu vas te perdre dans' }], bench['hypotheses']
    Koholint::Bench.note_bench(data, events, [81, 0], CONTEXT, { frame: 95_400 }, { 'left' => [97, 0], 'up' => nil }, RUN)
    assert_equal ['depends_on_context', { 'up' => [99, 0], 'left' => [97, 0] }], bench.values_at('status', 'ways'), 'a later unreached never erases a reached way'
    Koholint::Bench.note_bench(data, events, [81, 0], CONTEXT, { frame: 95_400 }, { 'right' => [82, 0] }, RUN)
    assert_equal ['leads_on', [[82, 0]], []], bench.values_at('status', 'new_places', 'hypotheses')
  end

  def test_bench_exits_runs_each_way_of_each_keyframe_and_writes_the_file
    Dir.mktmpdir do |dir|
      events = [seen(90, 99), seen(100, 81), { 'type' => 'keyframe', 'frame' => 120 },
                { 'type' => 'puzzle', 'frame' => 130, 'id' => 'unexpected_arrival-81-0-up', 'kind' => 'unexpected_arrival', 'place' => [81, 0], 'way' => 'up',
                  'expected' => { 'to' => [65, 0], 'source' => 'neighbour' }, 'observed' => { 'to' => [99, 0] }, 'frames' => [125] }]
      run_dir = File.join(dir, 'parent')
      FileUtils.mkdir_p(run_dir)
      File.write(File.join(run_dir, 'trace.jsonl'), events.map { |event| JSON.generate(event) }.join("\n"))
      run = FakeRun.new('parent', run_dir, { 'parent' => { 'id' => 'boot' } })
      tried = []
      fake = lambda do |_run, frame, _place, way, _stands, root:|
        tried << [frame, way]
        way == :up ? { outcome: :left, arrival: { to: [99, 0], landing: [7, 3] }, back: nil, run: "t#{tried.size}" } : { outcome: :unreached, run: "t#{tried.size}" }
      end
      path = File.join(dir, 'exits.json')
      out = StringIO.new
      original = Koholint::Bench.method(:trial)
      Koholint::Bench.define_singleton_method(:trial, &fake)
      begin
        Koholint::Bench.exits(run, root: dir, path:, out:)
      ensure
        Koholint::Bench.define_singleton_method(:trial, original)
      end
      assert_equal [[120, :up], [120, :down], [120, :left], [120, :right]], tried
      data = Koholint::Exits.load(path)
      assert_equal [['up', 'observed', 'boot'], ['down', 'unreached', 'boot']], data['edges'].first(2).map { |edge| [edge['way'], edge['status'], edge['trials'].first['lineage']] }
      assert_equal 'incomplete', data['benches'].first['status']
      assert_match(/81-0 :up from 120: left 99-0/, out.string)
    end
  end
end
