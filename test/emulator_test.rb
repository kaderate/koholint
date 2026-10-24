require_relative 'test_helper'
require 'tmpdir'
require 'zlib'
require 'koholint/emulator'
require 'koholint/perception'
require 'koholint/boot_script'
require_relative 'support/emulator_cache'

class EmulatorTest < Minitest::Test
  SCRIPT = ([[:start]] * 10) + ([[]] * 590)

  def run_script(emulator, inputs)
    inputs.each { |buttons| emulator.step(buttons) }
    emulator
  end

  def test_dump_survives_a_pending_interrupt_enable_and_restores_it
    skip_without_rom!
    original = run_script(Koholint::Emulator.boot, [[]] * 120)
    cpu = original.instance_variable_get(:@driver).motherboard.cpu
    cpu.instance_exec { @pending_operations << -> { @ime = true } }
    copy = Koholint::Emulator.restore(original.dump)
    assert_equal 1, cpu.instance_variable_get(:@pending_operations).size
    assert_equal 1, copy.instance_variable_get(:@driver).motherboard.cpu.instance_variable_get(:@pending_operations).size
    run_script(original, [[]] * 5)
    run_script(copy, [[]] * 5)
    assert_equal original.state_hash, copy.state_hash
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
    while emulator.frame < frames
      macro = Koholint::BootScript.macro_for(Koholint::Perception.read(emulator))
      [macro[:frames], frames - emulator.frame].min.times { emulator.step(macro[:buttons]) }
    end
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
      rgb = emulator.frame_rgb
      assert(rgb.bytes.each_slice(3).any? { |r, _g, b| r != b })
      assert_equal rows.join, rgb
    end
  end
end
