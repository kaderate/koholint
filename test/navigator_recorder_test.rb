# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/validation/checkpoint_support"

# Navigator has no dedicated test file yet; this covers only the regression guarantee the
# recorder: keyword addition must hold, not a general Navigator test suite.
class NavigatorRecorderTest < Minitest::Test
  include Koholint::CheckpointSupport

  # recorder: nil (every pre-existing call site) must behave exactly like the pre-recorder code:
  # same #move! result and same resulting position, from the same starting checkpoint.
  def test_recorder_nil_default_does_not_change_move_behavior
    dump = boot_fresh.dump

    without_recorder = Motherboard.load(dump)
    result_without = Koholint::Navigator.move!(without_recorder, :down)
    pos_without = Koholint::Navigator.position(without_recorder.mmu)

    with_recorder = Motherboard.load(dump)
    result_with = Koholint::Navigator.move!(with_recorder, :down, recorder: nil)
    pos_with = Koholint::Navigator.position(with_recorder.mmu)

    assert_equal result_without, result_with
    assert_equal pos_without, pos_with
  end
end
