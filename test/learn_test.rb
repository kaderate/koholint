require_relative 'test_helper'
require 'koholint/learn'
require 'tmpdir'
require 'stringio'
require 'fileutils'

class LearnTest < Minitest::Test
  L = Koholint::Learn

  def grid(fill: 4, at: {})
    rows = Array.new(8) { Array.new(10, fill) }
    at.each { |(row, col), id| rows[row][col] = id }
    rows
  end

  def perception(frame, room, x, y) = { 'type' => 'perception', 'frame' => frame, 'state' => { 'game_mode' => 0x0B, 'room_id' => room, 'map_id' => 0, 'x' => x, 'y' => y } }

  def gain = { item: 1, name: 'sword', frame: 100 }

  def sightings
    { [224, 0] => { frame: 120, arrival: [4, 4], grid: grid(at: { [6, 5] => 92, [6, 7] => 92, [0, 0] => 37 }) },
      [209, 0] => { frame: 300, arrival: [2, 2], grid: grid(at: { [5, 6] => 92, [7, 9] => 212 }) },
      [193, 0] => { frame: 400, arrival: [3, 3], grid: grid(at: { [2, 2] => 37, [3, 3] => 50, [1, 1] => 92 }) } }
  end

  def stood = { [224, 0] => Set[[4, 4]], [193, 0] => Set[[3, 3]] }

  def trial(outcome, place) = { 'outcome' => outcome, 'place' => place }

  def test_triggers_and_first_frames_after_the_gain
    held = ->(event, a) { event.tap { |e| e['state'].merge!('item_a' => a, 'item_b' => 4, 'inventory' => [0] * 10) } }
    events = [held.(perception(50, 224, 72, 66), 0), held.(perception(120, 224, 72, 66), 1), perception(130, 224, 88, 66), perception(300, 209, 40, 40)]
    assert_equal [{ item: 1, name: 'sword', frame: 120, gained: 120 }, { item: 4, name: 'shield', frame: 120, gained: 50 }], L.triggers(events, since: 100),
                 'a fork also learns from the items held at its first frame, keeping the frame they were first held'
    assert_equal [{ item: 4, name: 'shield', frame: 50, gained: 50 }, { item: 1, name: 'sword', frame: 120, gained: 120 }], L.triggers(events)
    inherited = L.hypothesis(gain: { item: 1, name: 'sword', frame: 75_334, gained: 64_774 }, object: 92, run: '20261113-213856-0b19')
    assert_equal({ 'run' => '20261113-213856-0b19', 'frame' => 64_774, 'item' => 1, 'held_from' => 75_334 }, inherited['trigger'])
    assert_includes inherited['source'], 'first held at frame 64774 of the lineage and held from the fork frame 75334 of run 20261113-213856-0b19'
    assert_equal({ 'run' => 'r', 'frame' => 100, 'item' => 1 }, L.hypothesis(gain:, object: 92, run: 'r')['trigger'])
    firsts = L.first_frames(events, 120)
    assert_equal({ frame: 120, arrival: Koholint::GameState.cell_at(72, 66) }, firsts[[224, 0]])
    assert_equal 300, firsts[[209, 0]][:frame]
  end

  def test_candidates_are_uncatalogued_never_stood_on_and_widest_first
    found = L.candidates(gain:, sightings:, stood:, known: [])
    assert_equal [92, 37], found.map { |c| c[:object] }
    assert_equal [[224, 0], [209, 0], [193, 0]], found.first[:places].map { |p| p[:place] }
    assert_equal [[6, 5], [6, 7]], found.first[:places].first[:cells]
    place = found.first[:places].first
    stand, direction = L.stands([6, 5], place).first
    dr, dc = Koholint::Skills::Composite::DELTAS[direction]
    assert_equal 92, place[:grid].dig(stand[0] + dr, stand[1] + dc)
    assert_equal [37], L.candidates(gain:, sightings:, stood:, known: [], object: 37).map { |c| c[:object] }
    assert_equal [92], L.candidates(gain:, sightings:, stood:, known: [], limit: 1).map { |c| c[:object] }
  end

  def test_a_cell_entered_only_after_a_capability_cleared_it_is_not_stood_on
    x, y = Koholint::Geometry.center_of(1, 7)
    use = ->(skill, before, after) { { 'type' => 'action', 'skill' => skill, 'result' => { 'from' => { 'room' => 225, 'map' => 0 }, 'capability' => { 'id' => 'sword-on-object-92' },
                                                                                          'target' => { 'row' => 1, 'col' => 7 }, 'object_before' => before, 'object_after' => after } } }
    from = { [225, 0] => 0 }
    assert_equal Set[[1, 7]], L.stood([use.('sword_on_object_92', 92, 92), perception(10, 225, x, y)], from:)[[225, 0]]
    assert_empty L.stood([use.('sword_on_object_92', 92, 4), perception(10, 225, x, y)], from:)[[225, 0]]
  end

  def test_a_clear_by_a_moving_skill_counts_in_its_own_place_only
    x, y = Koholint::Geometry.center_of(1, 6)
    explore = { 'type' => 'action', 'skill' => 'explore', 'result' => { 'from' => { 'room' => 225, 'map' => 0 }, 'clears' => [
      { 'capability' => { 'id' => 'sword-on-object-92' }, 'target' => { 'row' => 1, 'col' => 6 }, 'object_before' => 92, 'object_after' => 4 }] } }
    stood = L.stood([explore, perception(10, 225, x, y), perception(20, 224, x, y)], from: { [225, 0] => 0, [224, 0] => 0 })
    assert_empty stood[[225, 0]]
    assert_equal Set[[1, 6]], stood[[224, 0]]
  end

  def test_stands_count_from_each_sighting_frame_on_including_the_arrival_cell_at_that_frame
    arrival = Koholint::Geometry.center_of(4, 4)
    early = Koholint::Geometry.center_of(6, 5)
    stood = L.stood_since([perception(119, 224, *early), perception(120, 224, *arrival), perception(299, 209, *early)], sightings)
    assert_equal Set[[4, 4]], stood[[224, 0]]
    assert_empty stood[[209, 0]]
  end

  def test_a_stand_before_the_sighting_of_its_place_is_not_evidence
    x, y = Koholint::Geometry.center_of(3, 8)
    events = [perception(25_509, 160, x, y), perception(80_743, 160, 40, 40)]
    refute_includes L.stood(events, from: { [160, 0] => 80_743 })[[160, 0]], [3, 8], 'fef5 stood on 160/0 (3,8) long before the sighting where it holds 0x5C'
    assert_includes L.stood(events + [perception(80_800, 160, x, y)], from: { [160, 0] => 80_743 })[[160, 0]], [3, 8]
  end

  def test_objects_that_stopped_link_come_before_widespread_ones
    events = [{ 'type' => 'action', 'skill' => 'walk', 'result' => { 'from' => { 'room' => 224, 'map' => 0 }, 'blocked_at' => { 'row' => 1, 'col' => 0, 'direction' => 'up' } } },
              { 'type' => 'action', 'skill' => 'explore', 'result' => { 'from' => { 'room' => 193, 'map' => 0 }, 'walls' => [{ 'row' => 2, 'col' => 2 }],
                                                                     'blocked_edges' => [{ 'row' => 2, 'col' => 3, 'direction' => 'left' }, { 'row' => 0, 'col' => 0, 'direction' => 'up' }] } },
              { 'type' => 'action', 'skill' => 'explore', 'result' => { 'from' => { 'room' => 209, 'map' => 0 }, 'clears' => [
                { 'target' => { 'row' => 5, 'col' => 6 }, 'steps' => [{ 'skill' => 'goto', 'stopped_by' => 'done' }, { 'skill' => 'step', 'stopped_by' => 'blocked' }] },
                { 'target' => { 'row' => 7, 'col' => 9 }, 'steps' => [{ 'skill' => 'goto', 'stopped_by' => 'blocked' }] }] } }]
    blocked = L.blocks(events)
    assert_equal({ [224, 0] => Set[[0, 0]], [193, 0] => Set[[2, 2]], [209, 0] => Set[[5, 6]] }, blocked)
    found = L.candidates(gain:, sightings:, stood:, known: [], blocked:)
    assert_equal [[37, 2], [92, 1]], found.map { |c| [c[:object], c[:blocks]] }
  end

  def test_an_inconclusive_pair_is_retried_on_new_place_cell_and_stand_triples_only
    entry = ->(trials) { Koholint::Capabilities.transition(L.hypothesis(gain:, object: 92, run: 'r'), 'inconclusive', 'test', evidence: trials) }
    places = L.candidates(gain:, sightings:, stood:, known: []).first[:places]
    all = L.triples(places).map { |sighting, cell, stand| { 'outcome' => 'failure', 'place' => sighting[:place], 'cell' => cell, 'stand' => stand } }
    partial = entry.(all.first(2))
    assert_equal [92, 37], L.candidates(gain:, sightings:, stood:, known: [partial]).map { |c| c[:object] }
    assert_equal partial, L.known([partial], 1, 92)
    assert_equal [37], L.candidates(gain:, sightings:, stood:, known: [entry.(all)]).map { |c| c[:object] }
    calls = []
    original = L.method(:trial)
    L.define_singleton_method(:trial) do |_run, _entry, sighting, cell, stand, _direction, root:, walls:|
      calls << [sighting[:place], cell, stand]
      { 'outcome' => 'failure', 'place' => sighting[:place], 'cell' => cell, 'stand' => stand }
    end
    fresh = L.try(nil, partial, places, root: nil, out: StringIO.new)
    refute_empty fresh
    assert_empty calls & all.first(2).map { |trial| trial.values_at('place', 'cell', 'stand') }, 'a triple already in the evidence is not tried again'
    assert_equal calls.uniq, calls
  ensure
    L.define_singleton_method(:trial, original) if original
  end

  def test_the_lineage_is_the_tree_of_runs_under_the_same_root
    Dir.mktmpdir do |root|
      { 'a' => nil, 'b' => 'a', 'c' => 'b', 'd' => nil, 'e' => 'd' }.each do |id, parent|
        FileUtils.mkdir_p(File.join(root, id))
        File.write(File.join(root, id, 'manifest.json'), JSON.generate({ 'parent' => parent && { 'id' => parent, 'frame' => 1 } }.compact))
      end
      run = Struct.new(:dir, :id).new(File.join(root, 'b'), 'b')
      assert_equal %w[a b c], L.lineage(run).map { |dir| File.basename(dir) }
    end
  end

  def test_a_pair_already_in_the_file_is_never_retried
    rejected = Koholint::Capabilities.transition(L.hypothesis(gain:, object: 92, run: '20261112-103604-0c64'), 'rejected', 'test')
    assert_equal [37], L.candidates(gain:, sightings:, stood:, known: [rejected]).map { |c| c[:object] }
    assert_equal [92, 37], L.candidates(gain: gain.merge(item: 2), sightings:, stood:, known: [rejected]).map { |c| c[:object] }
  end

  def test_standing_sides_skip_the_border_and_the_same_object_nearest_first
    sighting = sightings[[224, 0]]
    sides = L.stands([6, 5], sighting)
    assert_includes [[[5, 5], :down], [[6, 4], :right]], sides.first
    assert_equal 4, sides.size
    sighting = sighting.merge(grid: grid(at: { [6, 5] => 92, [6, 6] => 92 }))
    refute_includes L.stands([6, 5], sighting).map(&:first), [6, 6]
    assert_equal [[6, 0], [7, 1]].sort, L.stands([7, 0], sightings[[224, 0]].merge(grid: grid(at: { [7, 0] => 92 }))).map(&:first).sort
  end

  def test_judge
    assert_equal 'validated', L.judge([trial('success', [224, 0]), trial('failure', [224, 0]), trial('success', [209, 0])])
    assert_equal 'inconclusive', L.judge([trial('success', [224, 0]), trial('success', [224, 0])])
    assert_equal 'rejected', L.judge([trial('failure', [224, 0]), trial('not_solid', [224, 0]), trial('failure', [209, 0]), trial('failure', [209, 0])])
    assert_equal 'inconclusive', L.judge([trial('failure', [224, 0])] * 4)
    assert_equal 'inconclusive', L.judge([trial('unreached', [224, 0]), trial('unreached', [209, 0])] * 3)
  end

  Policy = Struct.new(:outcome, :before, :after)

  def test_outcome_needs_blocked_before_effect_and_an_id_change
    entry = L.hypothesis(gain:, object: 92, run: '20261112-103604-0c64')
    steps = ->(*stops) { stops.map { |stop| { stopped_by: stop } } }
    good = { steps: steps.(:done, :blocked, :done, :done, :done), effect: true, frames: 150 }
    assert_equal 'success', L.outcome(Policy.new(good, 92, 4), entry)['outcome']
    assert_equal 'failure', L.outcome(Policy.new(good, 92, 92), entry)['outcome']
    assert_equal 'failure', L.outcome(Policy.new(good.merge(effect: false), 92, 4), entry)['outcome']
    assert_equal 'not_solid', L.outcome(Policy.new({ steps: steps.(:done, :done), effect: false }, 92, 92), entry)['outcome']
    assert_equal 'unreached', L.outcome(Policy.new({ steps: steps.(:no_path), effect: false }, 92, 92), entry)['outcome']
    assert_equal 'unreached', L.outcome(Policy.new(nil, nil, nil), entry)['outcome']
    stopped = { steps: [{ stopped_by: :blocked, blocked_at: { row: 5, col: 8, direction: :up }, avoided: [{ row: 6, col: 8, direction: :right }] }], effect: false }
    assert_equal [[5, 8, 'up'], [6, 8, 'right']], L.outcome(Policy.new(stopped, 92, 92), entry)['blocked_edges']
    refute L.outcome(Policy.new(good, 92, 4), entry).key?('blocked_edges')
  end

  # Open except column 5, which only row 0 crosses.
  class Walk
    def static_sprite(_row, _col) = nil
    def passable(row, col, _direction) = col == 5 && row.positive? ? :no : :yes
  end

  def test_a_stand_the_planner_cannot_reach_past_known_walls_is_skipped_without_a_trial
    sighting = { place: [224, 0], frame: 120, arrival: [4, 2], grid: grid(at: { [4, 8] => 92 }), walk: Walk.new, cells: [[4, 8]] }
    wall = ->(run) { { 'place' => [224, 0], 'run' => run, 'blocked_edges' => [[0, 5, 'right']] } }
    assert L.reachable?(sighting, [4, 7], L.walls([{ 'evidence' => [wall.('a'), wall.('a')] }])), 'one run is not enough'
    walls = L.walls([{ 'evidence' => [wall.('a'), wall.('b')] }])
    assert_equal [[0, 5, 'right']], L.confirmed(walls, [224, 0])
    refute L.reachable?(sighting, [4, 7], walls)
    assert L.reachable?(sighting, [4, 3], walls)
    out = StringIO.new
    entry = L.hypothesis(gain:, object: 92, run: '20261112-103604-0c64')
    assert_empty L.try(nil, entry, [sighting], root: nil, out:, walls:)
    assert_equal 4, out.string.scan('skipped, no path').size
  end

  def test_the_trial_policy_reads_the_cell_around_one_action_and_stops
    cells = grid(at: { [6, 5] => 92 })
    budget = Koholint::Budget.new
    registry = Koholint::Skills::Registry.default
    policy = L::Trial.new(registry:, choice: { skill: 'wait', params: { frames: 1 } }, target: [6, 5], budget:)
    assert_equal :choose_skill, policy.decision_point_for(nil).name
    answer = policy.decide(nil, nil, { room_objects: -> { cells } })
    assert_equal({ skill: 'wait', params: { frames: 1 } }, answer[:choice])
    assert_equal 'learner', answer[:agent]
    cells[6][5] = 4
    policy.after_action(choice: answer[:choice], outcome: { stopped_by: :done }, state: nil, frame: 1)
    assert_equal [92, 4], [policy.before, policy.after]
    assert_equal :trial_done, budget.exhausted
  end

  class OpenGrid
    def static_sprite(_row, _col) = nil
    def passable(_row, _col, _direction) = :yes
  end

  def test_a_trial_goto_plans_around_its_confirmed_walls_and_keeps_an_existing_ledger
    registry = Koholint::Skills::Registry.default
    start = Koholint::GameState.new(frame: 0, room_id: 224, map_id: 0, x: 88, y: 80, hp: 24, dialog_state: 0, game_mode: 0x0B, game_submode: 7, milestone: :none)
    first = lambda do |walls, ledger = nil|
      context = { room_objects: -> { grid }, grid: OpenGrid.new, ledger: }.compact
      L::Trial.new(registry:, choice: { skill: 'goto', params: { row: 4, col: 8 } }, target: [4, 8], budget: Koholint::Budget.new, place: [224, 0], walls:).prepare(context)
      [registry.start('goto', start, { row: 4, col: 8 }, context).next_input(start), context[:ledger]]
    end
    assert_equal [:right], first.([]).first
    refute_equal [:right], first.([[4, 5, 'right']]).first
    existing = Koholint::Ledger.new
    existing.record(place: [224, 0], blocked_at: { row: 1, col: 1, direction: :up })
    _, ledger = first.([[4, 5, 'right']], existing)
    assert_same existing, ledger
    assert ledger.doubtful?([224, 0], [4, 5], :right)
    assert_equal 1, ledger.count([224, 0], [1, 1], :up)
  end
end
