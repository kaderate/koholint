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

  DARK = [27, 42, 9].pack('C3')
  LIGHT = [154, 158, 63].pack('C3')
  MID = [73, 107, 34].pack('C3')

  def page(box_band:, text:, scene: MID)
    rows = Array.new(96) do |y|
      band = y / 48
      Array.new(160) do |x|
        next scene unless band == box_band

        lit = text.any? { |tx, ty, width| y % 48 == ty && x.between?(tx, tx + width - 1) }
        lit ? LIGHT : DARK
      end
    end
    rows.map { |row| row.map { |pixel| pixel * 4 }.join * 4 }.join
  end

  def test_text_rows_read_only_the_dialogue_box_band
    shot = Koholint::Vision::DialogueShot
    rows = shot.text_rows(page(box_band: 1, text: [[20, 10, 30], [20, 26, 12]]))
    assert_equal 2, rows.size
    assert_equal shot.text_rows(page(box_band: 1, text: [[20, 10, 30], [20, 26, 12]], scene: LIGHT)), rows
    assert_equal rows, shot.text_rows(page(box_band: 0, text: [[20, 14, 30], [20, 30, 12]]))
    assert_empty shot.text_rows(page(box_band: 2, text: []))
  end

  def test_the_signature_ignores_partly_typed_rows_and_the_capture_phase
    shot = Koholint::Vision::DialogueShot
    typed = ->(width) { shot.text_rows(page(box_band: 1, text: [[20, 10, width]])) }
    second = shot.text_rows(page(box_band: 1, text: [[20, 10, 50], [30, 26, 40]]))
    assert_equal shot.signature([typed.(10), typed.(50), second]), shot.signature([typed.(30), second, []])
    assert_nil shot.signature([[], []])
    assert_nil shot.signature([typed.(50)])
    assert_equal shot.page_hash(page(box_band: 1, text: [[20, 10, 50]])), shot.page_hash(page(box_band: 1, text: [[20, 10, 50]], scene: LIGHT))
  end

  def test_two_capture_phases_of_the_same_conversation_share_a_signature
    skip_without_rom!
    require 'koholint/probes/entity_census'
    census = Koholint::Probes::EntityCensus
    base = EmulatorCache.replayed(File.expand_path('../runs/20261024-095541-18df', __dir__), 3150)
    marin = Koholint::Entities.read(base).find { |entity| entity[:type] == 62 }
    first = census.converse(census.approach(base, marin, :up, [0, 16]))
    shifted = Koholint::Emulator.restore(base.dump)
    7.times { shifted.step([]) }
    second = census.converse(census.approach(shifted, marin, :up, [0, 16]))
    assert_operator first[:pages], :>, 5
    refute_equal first[:page_sequence], second[:page_sequence]
    assert_equal first[:signature], second[:signature]
  end
end
