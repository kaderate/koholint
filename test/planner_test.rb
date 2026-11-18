require_relative 'test_helper'
require 'koholint/navigation/planner'
require 'koholint/ledger'
require 'koholint/triggers'

class PlannerTest < Minitest::Test
  Planner = Koholint::Navigation::Planner
  PLACE = [1, 0].freeze

  class FakeGrid
    def initialize(walls: [], unknown: [], sprites: [])
      @walls = walls
      @unknown = unknown
      @sprites = sprites
    end

    def static_sprite(row, col) = (@sprites.include?([row, col]) ? 'sprite' : nil)

    def passable(row, col, _direction)
      return :no if @walls.include?([row, col])

      @unknown.include?([row, col]) ? :unknown : :yes
    end
  end

  def planner(ledger: Koholint::Ledger.new, **cells) = Planner.new(grid: FakeGrid.new(**cells), ledger:, place: PLACE)

  def test_straight_path_includes_both_ends
    assert_equal [[2, 1], [2, 2], [2, 3]], planner.path(from: [2, 1], to: [2, 3])
    assert_equal [[2, 1]], planner.path(from: [2, 1], to: [2, 1])
  end

  def test_detours_around_a_blocked_cell_with_fewest_turns
    path = planner(walls: [[2, 2]]).path(from: [2, 1], to: [2, 3])
    refute_includes path, [2, 2]
    assert_equal 4, path.size - 1
    turns = path.each_cons(2).map { |a, b| Planner.direction_between(a, b) }.each_cons(2).count { |a, b| a != b }
    assert_equal 2, turns
  end

  def test_forbidden_edges_are_blocked
    triggers = Koholint::Triggers.new
    triggers.record(place: PLACE, cell: [2, 1], skill: 'walk', input: :right)
    path = Planner.new(grid: FakeGrid.new, ledger: Koholint::Ledger.new, place: PLACE, triggers:).path(from: [2, 1], to: [2, 3])
    refute_equal [2, 2], path[1]
    assert_equal [2, 3], path.last
    assert_equal [[2, 1], [2, 2], [2, 3]], planner.path(from: [2, 1], to: [2, 3])
  end

  def test_prefers_fewer_turns_among_shortest_paths
    path = planner.path(from: [0, 0], to: [2, 2])
    directions = path.each_cons(2).map { |a, b| Planner.direction_between(a, b) }
    assert_equal 1, directions.each_cons(2).count { |a, b| a != b }
  end

  def test_unknown_cells_are_walkable_only_when_exploring
    wall_line = (0..7).map { |row| [row, 2] }
    assert_equal 2, planner(unknown: [[2, 2]], walls: wall_line - [[2, 2]]).path(from: [2, 1], to: [2, 3]).size - 1
    assert_nil planner(unknown: [[2, 2]], walls: wall_line - [[2, 2]]).path(from: [2, 1], to: [2, 3], mode: :free_only)
  end

  def test_a_doubtful_edge_is_avoided
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: { row: 2, col: 1, direction: :right }) }
    path = planner(ledger:).path(from: [2, 1], to: [2, 3])
    refute_equal [[2, 1], [2, 2], [2, 3]], path
    assert_equal 4, path.size - 1
  end

  def test_a_single_blocked_report_is_not_doubt
    ledger = Koholint::Ledger.new
    ledger.record(place: PLACE, blocked_at: { row: 2, col: 1, direction: :right })
    assert_equal 2, planner(ledger:).path(from: [2, 1], to: [2, 3]).size - 1
  end

  def test_a_static_sprite_cell_is_never_walkable
    path = planner(sprites: [[2, 2]]).path(from: [2, 1], to: [2, 3])
    refute_includes path, [2, 2]
    assert_nil planner(sprites: [[2, 3]]).path(from: [2, 1], to: [2, 3])
  end

  def test_nil_when_no_path_or_out_of_range
    wall_line = (0..7).map { |row| [row, 2] }
    assert_nil planner(walls: wall_line).path(from: [2, 1], to: [2, 3])
    assert_nil planner.path(from: [2, 1], to: [8, 3])
  end

  def doubtful_ledger(cell, direction)
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: { row: cell[0], col: cell[1], direction: }) }
    ledger
  end

  def test_doubt_toward_an_unknown_cell_is_still_walkable
    ledger = doubtful_ledger([2, 1], :right)
    wall_line = (0..7).map { |row| [row, 2] } - [[2, 2]]
    assert planner(ledger:, unknown: [[2, 2]], walls: wall_line).path(from: [2, 1], to: [2, 3])
  end

  def test_doubt_toward_a_believed_free_cell_is_refused
    ledger = doubtful_ledger([2, 1], :right)
    wall_line = (0..7).map { |row| [row, 2] } - [[2, 2]]
    assert_nil planner(ledger:, walls: wall_line).path(from: [2, 1], to: [2, 3])
  end

  def test_why_not_names_forbidden_trigger_edges
    triggers = Koholint::Triggers.new
    triggers.record(place: PLACE, cell: [2, 1], skill: 'walk', input: :right)
    wall_line = (0..7).map { |row| [row, 2] } - [[2, 2]]
    sealed = Planner.new(grid: FakeGrid.new(walls: wall_line), ledger: Koholint::Ledger.new, place: PLACE, triggers:)
    assert_nil sealed.path(from: [2, 1], to: [2, 3])
    assert_equal 'no route: edges where the game opens a dialogue by itself: (2,1) right; walk or step there explicitly if passing is the goal',
                 sealed.why_not(from: [2, 1], to: [2, 3])
    both = Planner.new(grid: FakeGrid.new(walls: wall_line), ledger: doubtful_ledger([2, 1], :right), place: PLACE, triggers:)
    assert_match(/\Ano route: doubtful edges \(2,1\) right; edges where the game opens a dialogue by itself: \(2,1\) right; walk or step/, both.why_not(from: [2, 1], to: [2, 3]))
  end

  def test_why_not_causes
    wall_line = (0..7).map { |row| [row, 2] } - [[2, 2]]
    assert_equal 'target believed blocked', planner(walls: [[2, 3]]).why_not(from: [2, 1], to: [2, 3])
    assert_equal 'target covered by an object', planner(sprites: [[2, 3]]).why_not(from: [2, 1], to: [2, 3])
    assert_equal 'target is current cell', planner.why_not(from: [2, 1], to: [2, 1])
    assert_equal 'no route over known cells', planner(walls: (0..7).map { |row| [row, 2] }).why_not(from: [2, 1], to: [2, 3])
    assert_equal 'no route: doubtful edges (2,1) right',
                 planner(ledger: doubtful_ledger([2, 1], :right), walls: wall_line).why_not(from: [2, 1], to: [2, 3])
  end

  def test_routes_around_danger_zones_and_falls_back_when_none_is_free
    zone = [[2, 2]]
    path = Planner.new(grid: FakeGrid.new, ledger: Koholint::Ledger.new, place: PLACE, danger: -> { zone }).path(from: [2, 1], to: [2, 3])
    refute_includes path, [2, 2]
    boxed = [[1, 2], [2, 2], [3, 2]]
    walled = Planner.new(grid: FakeGrid.new(walls: [[0, 2], [4, 2], [5, 2], [6, 2], [7, 2]]), ledger: Koholint::Ledger.new, place: PLACE, danger: -> { boxed })
    assert_includes walled.path(from: [2, 1], to: [2, 3]), [2, 2]
  end

  class HoledGrid < FakeGrid
    def initialize(margin:, **cells)
      super(**cells)
      @margin = margin
    end

    def hole_margin = @margin
  end

  def holed(margin, walls) = Planner.new(grid: HoledGrid.new(margin:, walls:), ledger: Koholint::Ledger.new, place: PLACE)

  def test_cells_beside_a_hole_are_routed_around_when_another_way_exists
    path = holed([[1, 2], [2, 2], [3, 2]], [[4, 3]]).path(from: [2, 1], to: [2, 3])
    refute_includes path, [2, 2]
    refute_includes path, [1, 2]
  end

  def test_a_one_wide_passage_beside_a_hole_is_a_last_resort_route_and_the_hole_stays_blocked
    hole = [3, 2]
    walls = [hole, [0, 2], [1, 2], [4, 2], [5, 2], [6, 2], [7, 2]]
    assert_equal [[2, 1], [2, 2], [2, 3]], holed([[2, 2], [3, 1], [3, 3], [4, 2]], walls).path(from: [2, 1], to: [2, 3])
    assert_nil holed([[2, 2]], walls).path(from: [3, 1], to: hole)
  end

  def test_a_route_that_must_cross_the_margin_is_refused_without_its_last_tier
    walls = [[3, 2], [0, 2], [1, 2], [4, 2], [5, 2], [6, 2], [7, 2]]
    planner = holed([[2, 2], [3, 1], [3, 3], [4, 2]], walls)
    assert_nil planner.path(from: [2, 1], to: [2, 3], cross_margin: false)
    assert planner.path(from: [2, 1], to: [2, 3])
    assert_equal [[2, 1], [1, 1], [0, 1]], planner.path(from: [2, 1], to: [0, 1], cross_margin: false)
  end

  def test_the_pushable_fallback_keeps_the_margin_when_it_may_not_be_crossed
    walls = [[0, 2], [1, 2], [3, 2], [4, 2], [6, 2], [7, 2]]
    grid = HoledGrid.new(margin: [[2, 2]], walls:, sprites: [[5, 2]])
    planner = Planner.new(grid:, ledger: Koholint::Ledger.new, place: PLACE, pushable: -> { [[5, 2]] })
    assert_includes planner.path(from: [2, 1], to: [2, 3]), [2, 2]
    path = planner.path(from: [2, 1], to: [2, 3], cross_margin: false)
    assert_includes path, [5, 2]
    refute_includes path, [2, 2]
  end

  def test_an_exit_cell_beside_a_hole_is_reached_without_crossing_the_margin_on_the_way
    margin = [[4, 3], [5, 2], [5, 4], [6, 3], [0, 5]]
    path = holed(margin, [[5, 3]]).path(from: [0, 3], to: [0, 5])
    assert_equal [0, 5], path.last
    assert_equal [[0, 3], [0, 4], [0, 5]], path
    route = holed(margin, [[5, 3]]).path(from: [3, 1], to: [5, 4])
    assert_equal [5, 4], route.last
    assert_empty route[0..-2] & margin
  end

  def guarded(danger, contact, walls: [], enemies: [])
    away = ->(cell, target) { enemies.none? { |enemy| ((enemy[0] - cell[0]) * (target[0] - cell[0])) + ((enemy[1] - cell[1]) * (target[1] - cell[1])) > 0 } }
    Planner.new(grid: FakeGrid.new(walls:), ledger: Koholint::Ledger.new, place: PLACE, danger: -> { danger }, contact: -> { contact }, away:)
  end

  def box(rows, cols) = rows.to_a.product(cols.to_a)

  def test_contact_zones_are_never_crossed_but_the_ring_around_them_is_a_last_resort
    walls = [[0, 2], [4, 2], [5, 2], [6, 2], [7, 2]]
    assert_nil guarded([[1, 2], [2, 2], [3, 2]], [[1, 2], [2, 2], [3, 2]], walls:).path(from: [2, 1], to: [2, 3])
    assert_equal [[2, 1], [2, 2], [2, 3]], guarded([[1, 2], [2, 2], [3, 2]], [[1, 2], [3, 2]], walls:).path(from: [2, 1], to: [2, 3])
    refute_includes guarded([[1, 2], [2, 2], [3, 2]], [[1, 2], [2, 2], [3, 2]]).path(from: [2, 1], to: [2, 3]), [2, 2]
  end

  def test_link_inside_a_zone_walks_out_without_heading_toward_an_enemy
    zone = box(2..6, 6..9)
    path = guarded(zone, zone, enemies: [[4, 8]]).path(from: [4, 7], to: [4, 2])
    assert_equal [[4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2]], path
    assert_nil guarded(zone, zone, enemies: [[4, 8]]).path(from: [4, 6], to: [4, 9])
  end

  def test_many_overlapping_enemies_leave_only_the_gap_between_their_contact_zones
    enemies = [[0, 5], [4, 5], [7, 5]]
    planner = guarded(box(0..7, 4..6), box(0..7, 4..6) - box(2..2, 4..6), enemies:)
    path = planner.path(from: [2, 1], to: [2, 8])
    assert_equal [2, 8], path.last
    assert_empty path & (box(0..7, 4..6) - box(2..2, 4..6))
    sealed = guarded(box(0..7, 4..6), box(0..7, 4..6), enemies:)
    assert_nil sealed.path(from: [2, 1], to: [2, 8])
    assert_match(/no route outside the enemy contact zones at one heart or less: .*\(2,5\)/, sealed.why_not(from: [2, 1], to: [2, 8]))
  end

  def test_a_goal_inside_a_zone_is_still_reached
    assert_equal [[2, 0], [2, 1], [2, 2]], guarded([[2, 2]], [[2, 2]], enemies: [[2, 3]]).path(from: [2, 0], to: [2, 2])
  end

  def test_a_cell_held_by_a_sprite_is_a_last_resort_route_when_it_is_pushable
    sprite = FakeGrid.new(walls: [[0, 2], [1, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2]], sprites: [[2, 2]])
    assert_nil Planner.new(grid: sprite, ledger: Koholint::Ledger.new, place: PLACE).path(from: [2, 1], to: [2, 3])
    path = Planner.new(grid: sprite, ledger: Koholint::Ledger.new, place: PLACE, pushable: -> { [[2, 2]] }).path(from: [2, 1], to: [2, 3])
    assert_equal [[2, 1], [2, 2], [2, 3]], path
  end
end
