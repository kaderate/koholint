require_relative 'test_helper'
require 'koholint/readiness'
require 'support/emulator_cache'

class ReadinessTest < Minitest::Test
  RUN = File.join(Koholint::Config::ROOT, 'runs', '20261024-184627-b97e')

  def play(frame, **fields) = Koholint::GameState.new(frame:, game_mode: 11, game_submode: 7, hp: 24, x: 80, y: 60, **fields)

  def test_free_play_is_ready_after_the_stable_frames
    readiness = Koholint::Readiness.new
    assert_equal 'settling', readiness.reason(play(10))
    assert readiness.ready?(play(11))
  end

  def test_each_signal_blocks_with_its_reason
    { { room_transition: 4 } => 'transition', { link_airborne: 1 } => 'airborne', { link_z: 12 } => 'airborne',
      { link_knockback: 9 } => 'knockback', { link_motion_state: 3 } => 'forced', { game_submode: 2 } => 'loading' }.each do |fields, reason|
      readiness = Koholint::Readiness.new
      readiness.observe(play(1))
      assert_equal reason, readiness.reason(play(2, **fields)), fields.inspect
    end
  end

  def test_a_signal_restarts_the_stable_count_and_a_gap_does_too
    readiness = Koholint::Readiness.new
    [play(1), play(2)].each { |state| readiness.observe(state) }
    assert readiness.ready?(play(3))
    readiness.observe(play(4, room_transition: 5))
    assert_equal 'settling', readiness.reason(play(5))
    assert readiness.ready?(play(6))
    assert_equal 'settling', readiness.reason(play(9))
  end

  def test_screens_outside_play_and_loading_are_not_gated
    readiness = Koholint::Readiness.new
    [{ dialog_state: 1 }, { motion_blocked: 2 }, { game_mode: 12, game_submode: 8 }, { game_mode: 2, game_submode: 7 },
     { link_motion_state: 7 }].each { |fields| assert_nil readiness.reason(play(1, **fields)), fields.inspect }
  end

  def test_an_old_trace_state_without_the_new_fields_is_ready
    state = Koholint::GameState.new(game_mode: 11, game_submode: 7, hp: 24, x: 80, y: 60)
    assert Koholint::Readiness.signals_ready?(state)
  end

  def test_a_recorded_screen_scroll_is_not_ready_until_two_frames_after_its_signal_clears
    skip_without_rom!
    skip 'run bundle not available' unless File.file?(File.join(RUN, 'inputs.log'))
    emulator = Koholint::Emulator.restore(EmulatorCache.replayed(RUN, 6100).dump)
    frames = Koholint::InputLog.new(File.join(RUN, 'inputs.log')).each_frame.drop(6100).first(30)
    readiness = Koholint::Readiness.new
    reasons = frames.map do |buttons|
      emulator.step(buttons)
      readiness.reason(Koholint::Perception.read(emulator))
    end
    assert_equal ['transition'] * 21, reasons.first(21)
    assert_equal 'settling', reasons[21]
    assert_nil reasons[22]
  end

  def test_a_recorded_ledge_jump_is_airborne_until_landing
    skip_without_rom!
    skip 'run bundle not available' unless File.file?(File.join(RUN, 'inputs.log'))
    emulator = Koholint::Emulator.restore(EmulatorCache.replayed(RUN, 20095).dump)
    frames = Koholint::InputLog.new(File.join(RUN, 'inputs.log')).each_frame.drop(20095).first(30)
    readiness = Koholint::Readiness.new
    reasons = frames.map do |buttons|
      emulator.step(buttons)
      readiness.reason(Koholint::Perception.read(emulator))
    end
    assert_equal %w[forced airborne], reasons.first(2)
    assert_equal 'airborne', reasons[10]
    first_ready = reasons.index(nil)
    assert_equal 20_124, 20_096 + first_ready
  end
end
