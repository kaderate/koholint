require_relative 'test_helper'
require 'koholint/game_state'

class GameStateTest < Minitest::Test
  def state(**fields) = Koholint::GameState.new(milestone: :none, **fields)

  def test_controllable_needs_hp_and_a_position
    assert state(hp: 24, x: 80).controllable?
    refute state(hp: 0, x: 80).controllable?
    refute state(hp: 24, x: 0).controllable?
  end

  def test_missing_readings_are_not_controllable
    refute state(frame: 0).controllable?
  end

  def test_dialog_open_when_dialog_state_is_non_zero
    assert state(dialog_state: 1).dialog_open?
    refute state(dialog_state: 0).dialog_open?
    refute state(frame: 0).dialog_open?
  end

  def test_loading_is_play_mode_before_the_settled_submode
    assert state(game_mode: 0x0B, game_submode: 3).loading?
    refute state(game_mode: 0x0B, game_submode: 7).loading?
    refute state(game_mode: 0x01, game_submode: 3).loading?
  end

  def test_phase
    assert_equal :boot, state(game_mode: 0x01, game_submode: 7).phase
    assert_equal :boot, state(frame: 0).phase
    assert_equal :loading, state(game_mode: 0x0B, game_submode: 3, dialog_state: 1).phase
    assert_equal :dialogue, state(game_mode: 0x0B, game_submode: 7, dialog_state: 1).phase
    assert_equal :playing, state(game_mode: 0x0B, game_submode: 7, dialog_state: 0).phase
  end

  def test_cell_is_the_grid_cell_under_link_or_nil_outside
    assert_equal [0, 0], state(x: 0, y: 8).cell
    assert_equal [3, 4], state(x: 68, y: 60).cell
    assert_equal [7, 9], state(x: 159, y: 135).cell
    assert_nil state(x: 160, y: 60).cell
    assert_nil state(x: 68, y: 7).cell
    assert_nil state(x: 68, y: 136).cell
    assert_nil state(frame: 0).cell
  end
end
