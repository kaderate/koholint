require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/vision/grid_builder'
require 'koholint/calibration/walk_probe'
require 'support/emulator_cache'

class GridBuilderProbeTest < Minitest::Test
  Builder = Koholint::Vision::GridBuilder
  Capabilities = Koholint::Vision::Capabilities
  Beliefs = Koholint::Vision::Beliefs
  State = Struct.new(:frame, :room_id, :map_id, :x, :y)
  DIRECTIONS = %i[up down left right].freeze

  class FakeEmulator
    attr_accessor :frame

    def initialize
      @memory = Hash.new(0)
      @memory[0xFF40] = 0x91
      @frame = 0
    end

    def read(addr) = @memory[addr]

    def sprite(index, x:, y:)
      [y, x, 1, 0].each_with_index { |value, i| @memory[0xFE00 + (index * 4) + i] = value }
    end
  end

  class FakeTrace
    attr_reader :events

    def initialize = @events = []
    def emit(type, frame:, **fields) = @events << { type:, frame:, **fields }
    def of(type) = @events.select { |event| event[:type] == type }
  end

  class StubProber
    attr_reader :calls
    attr_accessor :at

    def initialize(&result)
      @calls = []
      @result = result
      @at = { x: 70, y: 52 }
    end

    def run(_emulator, direction:, method:, frames:)
      @calls << { direction:, method:, frames: }
      { moved: false, from: at, to: at, room_changed: false, inconclusive: false, hp_delta: 0,
        frames: frames + 10 }.merge(@result.call(direction))
    end
  end

  class CountingProber
    attr_reader :calls

    def initialize = @calls = []

    def run(emulator, **options)
      @calls << options
      Koholint::Calibration::WalkProbe.run(emulator, **options)
    end
  end

  def test_link_cell_is_the_cell_under_the_center_of_his_sprites
    assert_equal [2, 4], Builder.link_cell(70, 52)
    assert_equal [1, 4], Builder.link_cell(70, 26)
    assert_equal [6, 4], Builder.link_cell(70, 112)
    assert_equal [6, 4], Builder.link_cell(70, 119)
    assert_equal [7, 4], Builder.link_cell(70, 120)
    assert_equal [0, 0], Builder.link_cell(15, 23)
    assert_equal [1, 1], Builder.link_cell(16, 24)
    assert_equal [7, 9], Builder.link_cell(159, 135)
    assert_nil Builder.link_cell(160, 52)
    assert_nil Builder.link_cell(70, 136)
    assert_nil Builder.link_cell(70, 7)
  end

  def fake_observe(builder, emulator, link:, place: [163, 16])
    emulator.frame += 30
    builder.observe(emulator, State.new(emulator.frame, *place, *link))
  end

  def fake_appearance
    Koholint::Vision::ScreenVision.snapshot(FakeEmulator.new, place: [0, 0]).cells[0][0].appearance
  end

  def test_contradiction_when_link_enters_a_cell_believed_blocked
    beliefs = Beliefs.new
    beliefs.record(appearance: fake_appearance, action: :walk, direction: :right, result: :no, method: 'hold', context: Capabilities.new,
                   frame: 1, source: 'test')
    trace = FakeTrace.new
    builder = Builder.new(trace:, beliefs:, prober: nil)
    emulator = FakeEmulator.new
    fake_observe(builder, emulator, link: [70, 52])
    fake_observe(builder, emulator, link: [86, 52])
    assert_equal [{ type: :grid_contradiction, frame: 60, place: [163, 16], row: 2, col: 5, direction: 'right', believed: 'no',
                    observed: 'entered' }], trace.of(:grid_contradiction)
  end

  def test_no_contradiction_for_open_cells_jumps_diagonals_or_place_changes
    beliefs = Beliefs.new
    DIRECTIONS.each do |direction|
      beliefs.record(appearance: fake_appearance, action: :walk, direction:, result: :no, method: 'hold', context: Capabilities.new,
                     frame: 1, source: 'test')
    end
    beliefs.record(appearance: fake_appearance, action: :walk, direction: :down, result: :yes, method: 'hold', context: Capabilities.new,
                   frame: 2, source: 'test')
    trace = FakeTrace.new
    builder = Builder.new(trace:, beliefs:, prober: nil)
    emulator = FakeEmulator.new
    [[70, 52], [70, 68], [102, 68], [118, 84], [118, 84]].each { |link| fake_observe(builder, emulator, link:) }
    fake_observe(builder, emulator, link: [134, 84], place: [164, 16])
    assert_empty trace.of(:grid_contradiction)
  end

  def test_probes_each_unknown_neighbour_once_after_statics_settle
    prober = StubProber.new { |direction| direction == :up ? { moved: true, to: { x: 70, y: 30 } } : {} }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    fake_observe(builder, emulator, link: [70, 52])
    assert_empty prober.calls
    3.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal(DIRECTIONS.map { |direction| { direction:, method: :hold, frames: Builder::PROBE_HOLD_FRAMES } }, prober.calls)
    events = trace.of(:affordance)
    assert_equal %w[up down left right], events.map { |e| e[:direction] }
    assert_equal %w[yes no no no], events.map { |e| e[:result] }
    assert(events.all? do |e|
      e.slice(:appearance, :action, :method, :context, :source, :frame) ==
        { appearance: fake_appearance, action: 'walk', method: 'hold', context: [], source: 'probe', frame: 60 }
    end)
  end

  def test_room_changing_hurting_sideways_or_off_grid_probes_record_nothing
    results = { up: { hp_delta: -4, to: { x: 70, y: 30 } }, down: { room_changed: true, to: { x: 70, y: 80 } },
                left: { to: { x: 70, y: 70 } }, right: { to: { x: 200, y: 52 } } }
    prober = StubProber.new { |direction| results.fetch(direction) }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    grid = 3.times.map { fake_observe(builder, emulator, link: [70, 52]) }.last
    assert_empty trace.of(:affordance)
    assert_equal 4, prober.calls.size
    assert_equal :unknown, grid.passable(1, 4, :up)
  end

  def test_a_discarded_probe_waits_for_links_cell_to_change
    prober = StubProber.new { |direction| direction == :up ? { room_changed: true } : {} }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    4.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal DIRECTIONS, prober.calls.map { |c| c[:direction] }
    assert_equal %w[down left right], trace.of(:affordance).map { |e| e[:direction] }
    fake_observe(builder, emulator, link: [71, 52])
    assert_equal 4, prober.calls.size
    prober.at = { x: 70, y: 68 }
    2.times { fake_observe(builder, emulator, link: [70, 68]) }
    assert_equal DIRECTIONS + %i[up], prober.calls.map { |c| c[:direction] }
  end

  def test_the_probe_is_judged_from_where_it_started_not_from_the_state_argument
    prober = StubProber.new { |direction| direction == :up ? { moved: true, to: { x: 70, y: 52 } } : {} }
    prober.at = { x: 70, y: 68 }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal [%w[up yes], %w[down no], %w[left no], %w[right no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
  end

  def test_a_stop_misaligned_with_the_neighbour_records_nothing_until_aligned
    prober = StubProber.new { |direction| direction == :down ? { to: { x: 78, y: 80 } } : {} }
    prober.at = { x: 78, y: 52 }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    3.times { fake_observe(builder, emulator, link: [78, 52]) }
    assert_equal [%w[down yes], %w[left no], %w[right no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
    assert_equal 4, prober.calls.size
    prober.at = { x: 73, y: 52 }
    fake_observe(builder, emulator, link: [73, 52])
    assert_equal %i[up down], prober.calls.drop(4).map { |c| c[:direction] }
    assert_equal %w[up no], trace.of(:affordance).last.values_at(:direction, :result)
  end

  def test_a_sprite_ahead_of_link_voids_a_stop_but_not_one_beside_or_far
    prober = StubProber.new { |direction| direction == :up ? { to: { x: 70, y: 30 } } : {} }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    emulator.sprite(0, x: 90, y: 52)
    emulator.sprite(1, x: 76, y: 48)
    emulator.sprite(2, x: 150, y: 130)
    2.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal [%w[up yes], %w[down no], %w[left no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
  end

  def test_a_left_or_right_stop_needs_vertical_alignment
    prober = StubProber.new { |direction| direction == :up ? { to: { x: 70, y: 30 } } : {} }
    prober.at = { x: 70, y: 59 }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [70, 59]) }
    assert_equal [%w[up yes], %w[down no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
  end

  def test_an_inconclusive_probe_voids_the_whole_observation
    prober = StubProber.new { |direction| direction == :down ? { inconclusive: true } : { moved: true, to: { x: 70, y: 30 } } }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal %i[up down], prober.calls.map { |c| c[:direction] }
    assert_empty trace.of(:affordance)
  end

  def test_a_link_that_no_direction_moves_is_not_free
    prober = StubProber.new { {} }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal DIRECTIONS, prober.calls.map { |c| c[:direction] }
    assert_empty trace.of(:affordance)
  end

  def test_a_link_not_free_is_reprobed_only_once_he_has_moved
    prober = StubProber.new { {} }
    builder = Builder.new(trace: FakeTrace.new, prober:)
    emulator = FakeEmulator.new
    4.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal 4, prober.calls.size
    fake_observe(builder, emulator, link: [71, 52])
    assert_equal 8, prober.calls.size
  end

  def test_a_known_direction_is_probed_only_to_show_link_is_free
    beliefs = Beliefs.new
    beliefs.record(appearance: fake_appearance, action: :walk, direction: :up, result: :yes, method: 'hold', context: Capabilities.new,
                   frame: 1, source: 'test')
    prober = StubProber.new { |direction| direction == :up ? { moved: true, to: { x: 70, y: 30 } } : {} }
    trace = FakeTrace.new
    builder = Builder.new(trace:, beliefs:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [70, 52]) }
    assert_equal %i[down left right up], prober.calls.map { |c| c[:direction] }
    assert_equal [%w[down no], %w[left no], %w[right no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
  end

  def test_neighbours_off_the_grid_are_not_probed
    corner = { x: 8, y: 20 }
    prober = StubProber.new { |direction| { from: corner, to: direction == :down ? { x: 8, y: 40 } : corner } }
    trace = FakeTrace.new
    builder = Builder.new(trace:, prober:)
    emulator = FakeEmulator.new
    2.times { fake_observe(builder, emulator, link: [8, 20]) }
    assert_equal %i[down right], prober.calls.map { |c| c[:direction] }
    assert_equal [%w[down yes], %w[right no]], trace.of(:affordance).map { |e| e.values_at(:direction, :result) }
  end

  def interactive_probes(capabilities: Capabilities.new, beliefs: Beliefs.new, observations: 2)
    emulator = EmulatorCache.interactive
    trace = FakeTrace.new
    prober = CountingProber.new
    builder = Builder.new(trace:, capabilities:, beliefs:, prober:)
    state = Koholint::Perception.read(emulator)
    grid = observations.times.map { builder.observe(emulator, state) }.last
    [trace, prober, grid, emulator]
  end

  def direct_cell_change(direction)
    copy = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
    before = Koholint::Perception.read(copy)
    120.times { copy.step([direction]) }
    after = Koholint::Perception.read(copy)
    Builder.link_cell(before.x, before.y) != Builder.link_cell(after.x, after.y)
  end

  def test_link_still_in_bed_gets_no_beliefs
    skip_without_rom!
    emulator = Koholint::Emulator.restore(EmulatorCache.at(700).dump)
    30.times { emulator.step }
    trace = FakeTrace.new
    prober = CountingProber.new
    builder = Builder.new(trace:, prober:)
    state = Koholint::Perception.read(emulator)
    2.times { builder.observe(emulator, state) }
    assert_equal 4, prober.calls.size
    assert_empty trace.of(:affordance)
  end

  def test_link_cell_anchoring_keeps_him_out_of_the_walls_that_stop_him
    skip_without_rom!
    expected = { up: [1, 4], down: [6, 4], left: [2, 4], right: [2, 4] }
    expected.each do |direction, cell|
      copy = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
      120.times { copy.step([direction]) }
      state = Koholint::Perception.read(copy)
      assert_equal cell, Builder.link_cell(state.x, state.y), direction.to_s
    end
  end

  def test_probe_beliefs_match_direct_movement_from_the_interactive_start
    skip_without_rom!
    trace, prober, grid, = interactive_probes
    assert_equal 4, prober.calls.size
    events = trace.of(:affordance).to_h { |e| [e[:direction], e] }
    assert_equal %w[down left up], events.keys.sort
    expected = { up: :yes, down: :yes, left: :no, right: :no }
    assert_equal(expected, DIRECTIONS.to_h { |d| [d, direct_cell_change(d) ? :yes : :no] })
    refute events.key?('right')
    assert_equal :unknown, grid.passable(2, 5, :right)
    expected.delete(:right)
    neighbours = { up: [1, 4], down: [3, 4], left: [2, 3] }
    neighbours.each do |direction, (row, col)|
      event = events.fetch(direction.to_s)
      assert_equal expected[direction].to_s, event[:result], direction.to_s
      assert_equal grid.static_sprite(row, col) || grid.appearance(row, col), event[:appearance], direction.to_s
      assert_equal expected[direction], grid.passable(row, col, direction), direction.to_s
    end
  end

  def test_house_objects_sit_on_the_cell_under_their_center
    skip_without_rom!
    grid = interactive_probes[2]
    assert_equal({ [3, 4] => true, [3, 5] => true, [4, 7] => true },
                 (0...8).to_a.product((0...10).to_a).select { |row, col| grid.static_sprite(row, col) }.to_h { |cell| [cell, true] })
    assert_nil grid.static_sprite(4, 8)
    assert_nil grid.static_sprite(*Builder.link_cell(70, 52))
  end

  def test_known_neighbours_are_never_reprobed
    skip_without_rom!
    trace, prober, = interactive_probes(observations: 5)
    assert_equal 4, prober.calls.size
    assert_equal 3, trace.of(:affordance).size
  end

  def test_other_capabilities_reprobe_a_blocked_neighbour
    skip_without_rom!
    beliefs = Beliefs.new
    interactive_probes(beliefs:)
    trace, prober, grid, = interactive_probes(beliefs:, capabilities: Capabilities.new(['swim']))
    assert_equal 4, prober.calls.size
    left = trace.of(:affordance).find { |e| e[:direction] == 'left' }
    assert_equal({ result: 'no', context: ['swim'] }, left.slice(:result, :context))
    assert_equal :no, grid.passable(2, 3, :left)
  end

  def test_probing_leaves_the_real_emulator_untouched
    skip_without_rom!
    hash = EmulatorCache.interactive.state_hash
    *, emulator = interactive_probes
    assert_equal hash, emulator.state_hash
    assert_equal 1630, emulator.frame
  end

  def test_a_resumed_engine_does_not_reprobe_what_the_trace_already_knows
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      counts = 2.times.map do
        Koholint::Engine.new(run:, policy: Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new),
                             budget: Koholint::Budget.new(frames: 400), emulator: EmulatorCache.interactive, grid: true).run
        Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).count { |e| e['type'] == 'affordance' }
      end
      assert_operator counts.first, :>=, 4
      assert_equal counts.first, counts.last
    end
  end

  def play(grid:)
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      emulator = EmulatorCache.interactive
      Koholint::Engine.new(run:, policy: Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new),
                           budget: Koholint::Budget.new(frames: 400), emulator:, grid:).run
      affordances = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).count { |e| e['type'] == 'affordance' }
      [File.binread(File.join(run.dir, 'inputs.log')), emulator.state_hash, affordances]
    end
  end

  def test_engine_run_with_probing_matches_the_run_without
    skip_without_rom!
    with_grid = play(grid: true)
    without = play(grid: false)
    assert_equal without.first(2), with_grid.first(2)
    assert_operator with_grid.last, :>=, 4
    assert_equal 0, without.last
  end
end
