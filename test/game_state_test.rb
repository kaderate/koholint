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
end
