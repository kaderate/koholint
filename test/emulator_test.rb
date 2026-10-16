require_relative 'test_helper'
require 'zlib'
require 'koholint/emulator'
require 'koholint/boot_script'
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

  def boot_to(frames)
    emulator = Koholint::Emulator.boot
    frames.times { |f| emulator.step(Koholint::BootScript.input_at(f)) }
    emulator
  end

  def test_frame_png_is_deterministic_and_does_not_touch_state
    skip_without_rom!
    a = boot_to(60)
    before = a.state_hash
    assert_equal 160 * 144 * 3, a.frame_rgb.bytesize
    assert a.frame_png.start_with?("\x89PNG\r\n\x1a\n".b)
    assert_equal before, a.state_hash
    assert_equal a.frame_png, boot_to(60).frame_png
  end

  def test_frame_rgb_matches_the_driver_png_channel_order
    skip_without_rom!
    emulator = EmulatorCache.at(300)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'ref.png')
      emulator.framebuffer_png(path)
      png = File.binread(path)
      idat = +''.b
      pos = 8
      while pos < png.bytesize
        length, type = png.unpack('Na4', offset: pos)
        idat << png.byteslice(pos + 8, length) if type == 'IDAT'
        pos += 12 + length
      end
      raw = Zlib::Inflate.inflate(idat)
      stride = 160 * 3
      rows = (0...144).map { |row| raw.byteslice((row * (stride + 1)) + 1, stride) }
      assert_operator emulator.frame_rgb.bytes.uniq.size, :>, 2
      assert_equal rows.join, emulator.frame_rgb
    end
  end
end
