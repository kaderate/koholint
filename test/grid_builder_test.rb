require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/vision/grid'
require 'koholint/vision/grid_builder'
require 'support/emulator_cache'

class GridBuilderTest < Minitest::Test
  LCDC = 0xFF40
  OAM = 0xFE00
  DIALOG = 0xC19F
  State = Struct.new(:frame, :room_id, :map_id, :x, :y)

  class FakeEmulator
    attr_accessor :frame

    def initialize
      @memory = Hash.new(0)
      @memory[LCDC] = 0x91
      @frame = 0
    end

    def read(addr) = @memory[addr]
    def write(addr, value) = @memory[addr] = value

    def sprite(index, x:, y:, tile: 1)
      [y, x, tile, 0].each_with_index { |value, i| write(OAM + (index * 4) + i, value) }
    end
  end

  class FakeTrace
    attr_reader :events

    def initialize = @events = []
    def emit(type, frame:, **fields) = @events << { type:, frame:, **fields }
    def of(type) = @events.select { |event| event[:type] == type }
  end

  def setup
    @trace = FakeTrace.new
    @builder = Koholint::Vision::GridBuilder.new(trace: @trace)
    @emulator = FakeEmulator.new
  end

  def observe(place: [163, 16], link: [200, 200])
    @emulator.frame += 30
    @builder.observe(@emulator, State.new(@emulator.frame, *place, *link))
  end

  def test_overlay_emits_nothing_and_returns_nil
    @emulator.write(DIALOG, 1)
    assert_nil observe
    assert_empty @trace.events
  end

  def test_first_observation_emits_screen_with_no_static_sprites
    grid = observe
    assert_instance_of Koholint::Vision::Grid, grid
    screen = @trace.of(:screen).fetch(0)
    assert_equal [163, 16], screen[:place]
    assert_equal [], screen[:static_sprites]
    assert_equal [8, 10], [screen[:grid].size, screen[:grid][0].size]
    assert_equal 30, screen[:frame]
    assert_empty @trace.of(:screen_changed)
  end

  def test_same_screen_again_emits_nothing_new
    observe
    observe
    assert_equal 1, @trace.of(:screen).size
  end

  def test_sprite_seen_twice_becomes_static_and_triggers_a_screen
    @emulator.sprite(0, x: 40, y: 56)
    observe
    assert_equal [], @trace.of(:screen).last[:static_sprites]
    observe
    assert_equal 2, @trace.of(:screen).size
    sprites = @trace.of(:screen).last[:static_sprites]
    assert_equal [{ x: 40, y: 56 }], sprites.map { |s| s.slice(:x, :y) }
    assert_match(/\A\h{8}\z/, sprites.first[:pattern])
  end

  def test_a_moving_sprite_never_becomes_static
    4.times do |i|
      @emulator.sprite(0, x: 40 + i, y: 56)
      observe
    end
    assert_equal 1, @trace.of(:screen).size
  end

  def test_overlay_forgets_sprite_tracking
    @emulator.sprite(0, x: 40, y: 56)
    observe
    @emulator.write(DIALOG, 1)
    observe
    @emulator.write(DIALOG, 0)
    observe
    assert_equal 1, @trace.of(:screen).size
  end

  def test_sprites_on_link_never_become_static
    @emulator.sprite(0, x: 70, y: 52)
    @emulator.sprite(1, x: 78, y: 53)
    3.times { observe(link: [70, 52]) }
    assert_equal 1, @trace.of(:screen).size
    assert_equal [], @trace.of(:screen).last[:static_sprites]
  end

  def test_a_sprite_next_to_link_can_be_static
    @emulator.sprite(0, x: 80, y: 56)
    3.times { observe(link: [70, 52]) }
    assert_equal [{ x: 80, y: 56 }], @trace.of(:screen).last[:static_sprites].map { |s| s.slice(:x, :y) }
  end

  def test_place_change_emits_a_screen_without_a_diff
    observe
    observe(place: [164, 16])
    assert_equal [[163, 16], [164, 16]], @trace.of(:screen).map { |s| s[:place] }
    assert_empty @trace.of(:screen_changed)
  end

  def test_terrain_change_emits_screen_then_screen_changed
    observe
    @emulator.write(0x9800, 7)
    @emulator.write(0x8000 + (7 * 16), 0xFF)
    observe
    assert_equal 2, @trace.of(:screen).size
    changed = @trace.of(:screen_changed).fetch(0)
    assert_equal [163, 16], changed[:place]
    assert_equal [[0, 0]], changed[:cells].map { |c| c.values_at(:row, :col) }
    assert_operator @trace.events.index(@trace.of(:screen).last), :<, @trace.events.index(changed)
  end

  def test_returns_a_grid_of_the_latest_snapshot
    @emulator.sprite(0, x: 40, y: 56)
    observe
    grid = observe
    assert_equal @trace.of(:screen).last[:static_sprites].first[:pattern], grid.static_sprite(2, 2)
    assert_equal @trace.of(:screen).last[:grid][0][0], grid.appearance(0, 0)
  end

  def with_run
    Dir.mktmpdir { |dir| yield Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {}) }
  end

  def policy_class
    Class.new(Koholint::Policies::WalkAndTalk) do
      attr_reader :contexts

      def decide(point, state, context)
        (@contexts ||= []) << context
        super
      end
    end
  end

  def play(grid:, frames: 400)
    with_run do |run|
      policy = policy_class.new
      engine = Koholint::Engine.new(run:, policy: Koholint::Policies::StartGame.new(policy), budget: Koholint::Budget.new(frames:),
                                    emulator: EmulatorCache.interactive, grid:)
      engine.run
      yield run, policy, engine.instance_variable_get(:@emulator)
    end
  end

  def test_engine_run_with_grid_matches_the_run_without
    skip_without_rom!
    results = [false, true].map do |grid|
      play(grid:) { |run, _policy, emulator| [File.binread(File.join(run.dir, 'inputs.log')), emulator.state_hash] }
    end
    assert_equal results[0], results[1]
  end

  def test_engine_run_emits_screens_and_feeds_the_policy
    skip_without_rom!
    play(grid: true, frames: 900) do |run, policy, _emulator|
      events = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl'))
      screens = events.select { |e| e['type'] == 'screen' }
      refute_empty screens
      assert(screens.all? { |s| s['place'] == [163, 16] })
      assert(screens.all? { |s| s['grid'].size == 8 && s['grid'][0].size == 10 })
      assert(policy.contexts.all? { |c| c[:grid].nil? || c[:grid].is_a?(Koholint::Vision::Grid) })
      assert(policy.contexts.any? { |c| c[:grid].is_a?(Koholint::Vision::Grid) })
    end
  end

  def test_engine_without_grid_passes_an_empty_context
    skip_without_rom!
    play(grid: false, frames: 120) { |_run, policy, _emulator| assert(policy.contexts.all?(&:empty?)) }
  end

  def test_link_standing_still_never_has_static_sprites_but_objects_do
    skip_without_rom!
    emulator = EmulatorCache.interactive
    trace = FakeTrace.new
    builder = Koholint::Vision::GridBuilder.new(trace:)
    state = nil
    6.times do
      30.times { emulator.step }
      state = Koholint::Perception.read(emulator)
      builder.observe(emulator, state)
    end
    statics = trace.of(:screen).last[:static_sprites]
    refute_empty statics
    assert(statics.none? { |s| Koholint::Vision::GridBuilder.link_sprite?(s, state) })
    assert(Koholint::Vision::ScreenVision.snapshot(emulator, place: [163, 16]).sprites.count { |s| Koholint::Vision::GridBuilder.link_sprite?(s, state) } >= 2)
  end

  def test_replay_verifies_a_grid_run_from_boot
    skip_without_rom!
    with_run do |run|
      Koholint::Engine.new(run:, policy: Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new),
                           budget: Koholint::Budget.new(frames: 700), grid: true).run
      assert_empty Koholint::Replay.verify(run, every: 200).reject(&:last)
    end
  end
end
