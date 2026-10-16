require_relative 'test_helper'
require 'koholint/emulator'
require_relative 'support/emulator_cache'

class EmulatorTest < Minitest::Test
  SCRIPT = ([[:start]] * 10) + ([[]] * 590)

  def run_script(emulator, inputs)
    inputs.each { |buttons| emulator.step(buttons) }
    emulator
  end

  def test_two_boots_with_same_inputs_have_equal_state_hash
    skip_without_rom!
    a = run_script(Koholint::Emulator.boot, SCRIPT)
    b = run_script(Koholint::Emulator.boot, SCRIPT)
    assert_equal 600, a.frame
    assert_equal a.state_hash, b.state_hash
  end

  def test_restore_then_step_matches_continuous
    skip_without_rom!
    live = run_script(Koholint::Emulator.boot, SCRIPT)
    first = run_script(Koholint::Emulator.boot, SCRIPT.first(300))
    resumed = run_script(Koholint::Emulator.restore(first.dump), SCRIPT.last(300))
    assert_equal live.state_hash, resumed.state_hash
    assert_equal 600, resumed.frame
  end

  def test_boot_ignores_a_sav_file_next_to_the_rom
    skip_without_rom!
    assert_equal ['FF'], Koholint::Emulator.boot.cartridge_ram.bytes.uniq.map { |b| format('%02X', b) }
  end

  def test_frame_png_is_deterministic_and_does_not_touch_state
    skip_without_rom!
    a = EmulatorCache.at(60)
    b = EmulatorCache.at(60)
    before = a.state_hash
    assert_equal 160 * 144 * 3, a.frame_rgb.bytesize
    assert a.frame_png.start_with?("\x89PNG\r\n\x1a\n".b)
    assert_equal before, a.state_hash
    assert_equal a.frame_png, b.frame_png
  end
end
