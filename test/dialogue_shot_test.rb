require_relative 'test_helper'
require 'zlib'
require 'support/emulator_cache'
require 'koholint/vision/dialogue_shot'

class DialogueShotTest < Minitest::Test
  def decode(png)
    pos = 8
    width = height = nil
    data = +''.b
    while pos < png.bytesize
      length, type = png.byteslice(pos, 8).unpack('Na4')
      body = png.byteslice(pos + 8, length)
      width, height = body.unpack('NN') if type == 'IHDR'
      data << body if type == 'IDAT'
      pos += 12 + length
    end
    raw = Zlib::Inflate.inflate(data)
    stride = width * 3 + 1
    [width, height, (0...height).map { |row| raw.byteslice(row * stride + 1, width * 3) }]
  end

  def test_crop_is_the_dialogue_band_upscaled_four_times
    skip_without_rom!
    emulator = EmulatorCache.at(700)
    emulator.step until Koholint::Perception.read(emulator).dialog_open?
    30.times { emulator.step }
    width, height, rows = decode(Koholint::Vision::DialogueShot.crop(emulator))
    assert_equal [640, 192], [width, height]
    full = emulator.frame_rgb
    source = (80...128).map { |y| full.byteslice(y * 160 * 3, 160 * 3).unpack('a3' * 160) }
    assert_equal source.first.flat_map { |p| [p] * 4 }.join, rows[0]
    assert_equal rows[0], rows[3]
    assert_equal source[1].flat_map { |p| [p] * 4 }.join, rows[4]
    assert_operator rows.join.bytes.uniq.size, :>, 2
  end
end
