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

  def test_crop_stacks_the_top_and_bottom_bands_upscaled_four_times
    skip_without_rom!
    emulator = EmulatorCache.at(700)
    emulator.step until Koholint::Perception.read(emulator).dialog_open?
    30.times { emulator.step }
    width, height, rows = decode(Koholint::Vision::DialogueShot.crop(emulator))
    assert_equal [640, 384], [width, height]
    full = emulator.frame_rgb
    sources = (0...48).to_a + (80...128).to_a
    sources.each_with_index do |y, i|
      expected = full.byteslice(y * 160 * 3, 160 * 3).unpack('a3' * 160).flat_map { |p| [p] * 4 }.join
      4.times { |k| assert_equal expected, rows[i * 4 + k], "source row #{y}" }
    end
    assert_operator rows.join.bytes.uniq.size, :>, 2
  end

  def test_sheets_tile_up_to_eight_pages_vertically
    page = ("\x20".b * (640 * 384 * 3))
    nine = Koholint::Vision::DialogueShot.sheets(Array.new(9) { page })
    assert_equal [[640, 384 * 8], [640, 384]], nine.map { |png| decode(png).first(2) }
    assert_equal 5, Koholint::Vision::DialogueShot.sheets(Array.new(40) { page }).size
    assert_empty Koholint::Vision::DialogueShot.sheets([])
  end

  def test_sheets_keep_the_page_order
    pages = [1, 2, 3].map { |v| v.chr.b * (640 * 384 * 3) }
    _, _, rows = decode(Koholint::Vision::DialogueShot.sheets(pages).first)
    assert_equal [1, 2, 3], [0, 384, 768].map { |y| rows[y].getbyte(0) }
  end
end
