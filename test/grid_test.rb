require_relative 'test_helper'
require 'koholint/vision/grid'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'

class GridTest < Minitest::Test
  def grid(sprites, beliefs: Koholint::Vision::Beliefs.new)
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: sprites, beliefs:, capabilities: Koholint::Vision::Capabilities.new)
  end

  def test_a_sprite_straddling_two_rows_marks_both
    grid = grid([{ 'x' => 72, 'y' => 56, 'pattern' => 'npc' }])
    assert_equal 'npc', grid.static_sprite(2, 4)
    assert_equal 'npc', grid.static_sprite(3, 4)
    assert_nil grid.static_sprite(4, 4)
    assert_nil grid.static_sprite(2, 5)
  end

  def test_two_side_by_side_halves_mark_their_cells
    grid = grid([{ 'x' => 64, 'y' => 48, 'pattern' => 'l' }, { 'x' => 72, 'y' => 48, 'pattern' => 'r' }])
    assert_equal 'l', grid.static_sprite(2, 3)
    assert_equal 'r', grid.static_sprite(2, 4)
    assert_nil grid.static_sprite(2, 5)
  end

  def test_a_sprite_inside_one_cell_marks_one_cell
    grid = grid([{ 'x' => 72, 'y' => 48, 'pattern' => 'pot' }])
    assert_equal 'pot', grid.static_sprite(2, 4)
    marked = (0...8).to_a.product((0...10).to_a).count { |r, c| grid.static_sprite(r, c) }
    assert_equal 1, marked
  end

  def test_an_explicit_height_limits_the_cover
    grid = grid([{ 'x' => 72, 'y' => 56, 'pattern' => 'small', 'height' => 8 }])
    assert_equal 'small', grid.static_sprite(2, 4)
    assert_nil grid.static_sprite(3, 4)
  end

  def test_a_sprite_partly_off_the_grid_does_not_raise
    grid = grid([{ 'x' => 4, 'y' => 8, 'pattern' => 'edge' }, { 'x' => 166, 'y' => 140, 'pattern' => 'far' }])
    assert_equal 'edge', grid.static_sprite(0, 0)
    assert_equal 'far', grid.static_sprite(7, 9)
  end

  def test_a_covered_cell_is_not_answered_from_the_floor
    beliefs = Koholint::Vision::Beliefs.new
    beliefs.record(appearance: 'floor', action: :walk, direction: :down, result: :yes, method: 't',
                   context: Koholint::Vision::Capabilities.new, frame: 1, source: 't')
    grid = grid([{ 'x' => 72, 'y' => 56, 'pattern' => 'npc' }], beliefs:)
    assert_equal :yes, grid.passable(1, 4, :down)
    refute_equal :yes, grid.passable(2, 4, :down)
    refute_equal :yes, grid.passable(3, 4, :down)
  end
end
