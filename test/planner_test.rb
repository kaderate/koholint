require_relative 'test_helper'
require 'koholint/navigation/planner'
require 'koholint/ledger'

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
end
