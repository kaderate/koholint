require_relative 'test_helper'
require 'koholint/vision/capabilities'
require 'koholint/vision/beliefs'
require 'koholint/vision/world'

class WorldTest < Minitest::Test
  World = Koholint::Vision::World
  Caps = Koholint::Vision::Capabilities

  def grid_of(name) = Array.new(8) { Array.new(10) { name } }

  def screen(frame, place: [1, 2], name: 'a1', sprites: [])
    { 'v' => 1, 'type' => 'screen', 'frame' => frame, 'place' => place, 'terrain_hash' => "t#{frame}", 'objects_hash' => 'o',
      'grid' => grid_of(name), 'static_sprites' => sprites }
  end

  def affordance(frame, appearance:, result: 'no', direction: nil, context: [])
    { 'v' => 1, 'type' => 'affordance', 'frame' => frame, 'appearance' => appearance, 'action' => 'walk', 'direction' => direction,
      'result' => result, 'method' => 'probe', 'context' => context, 'source' => 'test' }
  end

  def test_at_frame_truncates_places_and_beliefs
    events = [screen(100), affordance(500, appearance: 'a1'), screen(600, place: [3, 4])]
    full = World.from_events(events)
    assert_equal [[1, 2], [3, 4]], full.places.keys
    assert_equal :no, full.beliefs.query(appearance: 'a1', action: :walk, direction: nil, context: Caps.new)
    early = World.from_events(events, at_frame: 400)
    assert_equal [[1, 2]], early.places.keys
    assert_equal :unknown, early.beliefs.query(appearance: 'a1', action: :walk, direction: nil, context: Caps.new)
  end

  def test_two_visits_count_and_keep_latest_grid
    world = World.from_events([screen(10, name: 'a1'), screen(90, name: 'b2', sprites: [{ 'x' => 8, 'y' => 16, 'pattern' => 'p' }])])
    place = world.places.fetch([1, 2])
    assert_equal 2, place[:visits]
    assert_equal 'b2', place[:grid][0][0]
    assert_equal 't90', place[:terrain_hash]
    assert_equal [10, 90], [place[:first_frame], place[:last_frame]]
    assert_equal [{ 'x' => 8, 'y' => 16, 'pattern' => 'p' }], place[:static_sprites]
  end

  def test_grid_for_unknown_place_is_nil
    assert_nil World.from_events([]).grid_for([9, 9], Caps.new)
  end

  def test_stale_propagates_through_grid_for
    world = World.from_events([screen(10), affordance(20, appearance: 'a1', direction: 'up')])
    assert_equal :no, world.grid_for([1, 2], Caps.new).passable(0, 0, :up)
    assert_equal :stale, world.grid_for([1, 2], Caps.new(['swim'])).passable(0, 0, :up)
    assert_equal 'a1', world.grid_for([1, 2], Caps.new).appearance(3, 4)
  end

  def test_sprite_cell_is_unknown_by_default_and_ignores_background
    sprite = { 'x' => 24, 'y' => 48, 'pattern' => 'p9' }
    world = World.from_events([screen(10, sprites: [sprite]), affordance(20, appearance: 'a1', result: 'yes')])
    grid = world.grid_for([1, 2], Caps.new)
    assert_equal 'p9', grid.static_sprite(2, 1)
    assert_nil grid.static_sprite(0, 0)
    assert_equal :yes, grid.passable(0, 0, :up)
    assert_equal :unknown, grid.passable(2, 1, :up)
  end

  def test_sprite_cell_with_no_belief_on_pattern
    sprite = { 'x' => 24, 'y' => 48, 'pattern' => 'p9' }
    world = World.from_events([screen(10, sprites: [sprite]), affordance(20, appearance: 'p9')])
    assert_equal :no, world.grid_for([1, 2], Caps.new).passable(2, 1, :left)
  end

  def test_oam_to_cell_arithmetic
    sprites = [
      { 'x' => 0, 'y' => 8, 'pattern' => 'first' }, { 'x' => 15, 'y' => 23, 'pattern' => 'dup' },
      { 'x' => 16, 'y' => 24, 'pattern' => 'next' }, { 'x' => 80, 'y' => 56, 'pattern' => 'npc' }, { 'x' => 88, 'y' => 56, 'pattern' => 'half' },
      { 'x' => 159, 'y' => 135, 'pattern' => 'last' }, { 'x' => 160, 'y' => 16, 'pattern' => 'off_right' },
      { 'x' => 8, 'y' => 7, 'pattern' => 'off_top' }, { 'x' => 8, 'y' => 136, 'pattern' => 'off_bottom' }
    ]
    grid = World.from_events([screen(1, sprites:)]).grid_for([1, 2], Caps.new)
    assert_equal 'first', grid.static_sprite(0, 0)
    assert_equal 'next', grid.static_sprite(1, 1)
    assert_equal 'npc', grid.static_sprite(3, 5)
    assert_nil grid.static_sprite(2, 4)
    assert_equal 'last', grid.static_sprite(7, 9)
    assert_nil grid.static_sprite(0, 9)
    assert_nil grid.static_sprite(7, 0)
  end

  def test_out_of_range_raises
    grid = World.from_events([screen(1)]).grid_for([1, 2], Caps.new)
    [[-1, 0], [8, 0], [0, 10], [0, -1]].each do |row, col|
      assert_raises(ArgumentError) { grid.passable(row, col, :up) }
      assert_raises(ArgumentError) { grid.appearance(row, col) }
    end
  end
end
