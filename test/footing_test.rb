require_relative 'test_helper'
require 'koholint/footing'
require 'koholint/game_state'
require 'koholint/skills/registry'

class FootingTest < Minitest::Test
  CRUMBLING = 223
  HOLE = 174

  def state(x:, y:, timer: 0, frame: 0, game_mode: 0x0B)
    Koholint::GameState.new(frame:, room_id: 189, map_id: 10, x:, y:, hp: 12, max_hp: 24, dialog_state: 0, game_mode:, game_submode: 7,
                            milestone: :none, crumble_timer: timer)
  end

  def objects = Array.new(8) { |row| Array.new(10) { row == 1 ? CRUMBLING : 0 } }

  class Grid
    def initialize(holes = [], dead_ends = []) = (@holes = holes; @dead_ends = dead_ends)
    def passable(row, col, direction) = @dead_ends.include?([row, col, direction]) ? :no : :yes
    def hole?(row, col) = @holes.include?([row, col])
  end

  def footing(rows = objects)
    Koholint::Footing.new.tap { |footing| footing.observe(state(x: 68, y: 26), rows) }
  end

  def wait_with(footing, grid, at)
    Koholint::Skills::Registry.default.start('wait', at, { frames: 60 }, { footing:, grid: }).tap { |wait| wait.next_input(at) }
  end

  def test_the_foot_point_is_four_pixels_below_link
    assert_equal [[0, 4]], Koholint::Footing.feet(68, 19)
    assert_equal [[1, 4]], Koholint::Footing.feet(68, 20)
    assert_equal [[1, 2]], Koholint::Footing.feet(47, 28)
    assert_equal [[1, 3]], Koholint::Footing.feet(48, 28)
  end

  def test_the_frames_left_come_from_the_game_timer_on_floor_that_gives_way
    assert_equal [{ cell: [1, 4], left: 15 }], footing.under(state(x: 68, y: 26, timer: 25))
    assert_empty footing.under(state(x: 68, y: 19, timer: 25)), 'a wall row never gives way'
    other = state(x: 68, y: 26, timer: 25).to_h.merge(room_id: 172)
    assert_empty footing.under(Koholint::GameState.new(**other)), 'the objects read belong to another place'
  end

  def test_every_skill_steps_off_onto_another_floor_cell_the_shortest_way_just_in_time
    assert_equal [], wait_with(footing, Grid.new, state(x: 68, y: 26, timer: 26)).next_input(state(x: 68, y: 26, timer: 26))
    assert_equal [:left], wait_with(footing, Grid.new, state(x: 68, y: 26, timer: 27)).next_input(state(x: 68, y: 26, timer: 27))
    walled = Grid.new([[0, 4], [1, 3], [2, 4]])
    assert_equal [], wait_with(footing, walled, state(x: 68, y: 26, timer: 19)).next_input(state(x: 68, y: 26, timer: 19))
    assert_equal [:right], wait_with(footing, walled, state(x: 68, y: 26, timer: 20)).next_input(state(x: 68, y: 26, timer: 20)),
                 'a cell that gives way too is a cell where the count starts over'
    boxed = Grid.new([[0, 4], [2, 4], [1, 3], [1, 5]])
    assert_equal [], wait_with(footing, boxed, state(x: 68, y: 26, timer: 39)).next_input(state(x: 68, y: 26, timer: 39))
  end

  def test_floor_link_cannot_walk_on_from_is_still_floor_to_step_onto
    grid = Grid.new([[0, 4], [2, 4], [1, 3]], [[1, 5, :right]])
    assert_equal [:right], wait_with(footing, grid, state(x: 68, y: 26, timer: 20)).next_input(state(x: 68, y: 26, timer: 20))
  end

  def test_a_hole_that_opened_since_the_skill_planned_is_no_floor_to_step_onto
    live = footing(objects.tap { |rows| rows[1][3] = HOLE })
    assert_equal [:up], wait_with(live, Grid.new, state(x: 68, y: 26, timer: 26)).next_input(state(x: 68, y: 26, timer: 26))
  end

  def test_a_step_off_that_leaves_link_in_place_tries_another_way
    wait = wait_with(footing, Grid.new, state(x: 68, y: 26, timer: 27))
    assert_equal [:left], wait.next_input(state(x: 68, y: 26, timer: 27))
    assert_equal [:left], wait.next_input(state(x: 68, y: 26, timer: 28))
    assert_equal [:up], wait.next_input(state(x: 68, y: 26, timer: 29))
  end

  def test_a_skill_keeps_its_first_frame_and_menus_keep_their_directions
    urgent = state(x: 68, y: 26, timer: 27)
    walk = Koholint::Skills::Registry.default.start('walk', urgent, { direction: 'right', cells: 1 }, { footing:, grid: Grid.new })
    assert_equal [:right], walk.next_input(urgent), 'the first frame is the skill own'
    assert_equal [:left], walk.next_input(urgent)
    live = footing(objects.tap { |rows| rows[1][5] = HOLE })
    menu = state(x: 78, y: 26, timer: 39, game_mode: 12)
    cursor = Koholint::Skills::Registry.default.start('walk', menu, { direction: 'right', cells: 1 }, { footing: live, grid: Grid.new })
    2.times { assert_equal [:right], cursor.next_input(menu), 'a direction in a menu moves no Link' }
  end

  def test_a_step_into_a_hole_that_opened_after_the_skill_planned_ends_the_skill
    live = footing(objects.tap { |rows| rows[1][5] = HOLE })
    walk = ->(x) { Koholint::Skills::Registry.default.start('walk', state(x:, y: 26), { direction: 'right', cells: 1 }, { footing: live, grid: Grid.new }) }
    assert_equal [:right], walk.(72).next_input(state(x: 72, y: 26))
    near = walk.(78)
    assert_nil near.next_input(state(x: 78, y: 26))
    assert_equal :hole, near.result[:stopped_by]
  end
end
