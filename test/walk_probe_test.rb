require 'test_helper'
require 'support/emulator_cache'
require 'koholint/calibration/walk_probe'

class WalkProbeTest < Minitest::Test
  DIRECTIONS = %i[up down left right].freeze

  def setup
    skip_without_rom!
    @emulator = EmulatorCache.interactive
  end

  def probe(direction, method: :tap, frames: nil)
    Koholint::Calibration::WalkProbe.run(@emulator, direction:, method:, frames:)
  end

  def test_rejects_unknown_direction_and_method
    assert_raises(ArgumentError) { Koholint::Calibration::WalkProbe.run(Object.new, direction: :north, method: :tap) }
    assert_raises(ArgumentError) { Koholint::Calibration::WalkProbe.run(Object.new, direction: :up, method: :run) }
  end

  def test_cutscene_state_is_inconclusive_for_every_direction
    cutscene = EmulatorCache.playable
    DIRECTIONS.each do |direction|
      result = Koholint::Calibration::WalkProbe.run(cutscene, direction:, method: :tap)
      assert result[:inconclusive], direction.to_s
      refute result[:moved], direction.to_s
    end
  end

  def test_free_link_is_never_inconclusive
    DIRECTIONS.each { |direction| %i[tap hold].each { |method| refute probe(direction, method:)[:inconclusive] } }
  end

  def test_probe_leaves_the_emulator_untouched
    hash = @emulator.state_hash
    frame = @emulator.frame
    DIRECTIONS.each do |direction|
      %i[tap hold].each { |method| probe(direction, method:) }
      assert_equal hash, @emulator.state_hash
      assert_equal frame, @emulator.frame
    end
  end

  def test_starting_position_has_both_open_and_blocked_directions
    results = DIRECTIONS.to_h { |direction| [direction, probe(direction)] }
    assert results.values.any? { |r| r[:moved] }, results.inspect
    assert results.values.any? { |r| !r[:moved] }, results.inspect
  end

  def test_hold_agrees_with_tap_on_blocked_directions
    blocked = DIRECTIONS.reject { |direction| probe(direction)[:moved] }
    refute_empty blocked
    blocked.each do |direction|
      refute probe(direction, method: :hold)[:moved], direction.to_s
    end
  end

  def test_results_are_deterministic
    DIRECTIONS.each { |direction| assert_equal probe(direction), probe(direction) }
  end

  def test_result_shape
    result = probe(:up)
    assert_equal %i[frames from hp_delta inconclusive moved room_changed to], result.keys.sort
    assert_equal 30, result[:frames]
    assert_equal 130, probe(:up, method: :hold)[:frames]
  end
end
