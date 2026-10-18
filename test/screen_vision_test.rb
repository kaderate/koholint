require_relative 'test_helper'
require 'koholint/vision/screen_snapshot'
require 'koholint/vision/screen_vision'
require 'support/emulator_cache'

class ScreenVisionTest < Minitest::Test
  LCDC = 0xFF40
  SCY = 0xFF42
  SCX = 0xFF43
  OAM = 0xFE00

  class FakeReader
    attr_reader :frame

    def initialize(frame: 7)
      @memory = Hash.new(0)
      @frame = frame
    end

    def read(addr) = @memory[addr]
    def write(addr, value) = @memory[addr] = value

    def tile_bytes(addr, bytes) = bytes.each_with_index { |byte, i| write(addr + i, byte) }
  end

  def reader(lcdc: 0x91, scx: 0, scy: 0)
    FakeReader.new.tap do |fake|
      fake.write(LCDC, lcdc)
      fake.write(SCX, scx)
      fake.write(SCY, scy)
    end
  end

  def pattern(seed) = Array.new(16) { |i| (seed * 16 + i) & 0xFF }

  def put_tile(fake, number, seed, lcdc: 0x91)
    base = lcdc.anybits?(0x10) ? 0x8000 + (number * 16) : 0x9000 + ((number < 128 ? number : number - 256) * 16)
    fake.tile_bytes(base, pattern(seed))
  end

  def put_map(fake, row, col, number, lcdc: 0x91)
    base = lcdc.anybits?(0x08) ? 0x9C00 : 0x9800
    fake.write(base + (row % 32) * 32 + (col % 32), number)
  end

  def put_block(fake, cell_row, cell_col, numbers, map_row: 0, map_col: 0, lcdc: 0x91)
    numbers.each_with_index do |number, i|
      put_map(fake, map_row + (cell_row * 2) + (i / 2), map_col + (cell_col * 2) + (i % 2), number, lcdc:)
    end
  end

  def snapshot(fake) = Koholint::Vision::ScreenVision.snapshot(fake, place: [163, 16])

  def test_grid_is_eight_rows_by_ten_columns
    cells = snapshot(reader).cells
    assert_equal 8, cells.size
    assert(cells.all? { |row| row.size == 10 })
    assert_equal 8, cells[0][0].appearance.size
    assert_equal [0, 0, 0, 0], cells[0][0].tiles
  end

  def test_snapshot_carries_frame_place_and_scroll
    snap = snapshot(reader(scx: 8, scy: 16))
    assert_equal 7, snap.frame
    assert_equal [163, 16], snap.place
    assert_equal [8, 16], snap.scroll
  end

  def test_appearance_follows_pixels_not_tile_numbers
    fake = reader
    put_tile(fake, 5, 1)
    put_tile(fake, 6, 1)
    put_tile(fake, 7, 2)
    put_block(fake, 0, 0, [5, 5, 5, 5])
    put_block(fake, 0, 1, [6, 6, 6, 6])
    put_block(fake, 0, 2, [7, 7, 7, 7])
    row = snapshot(fake).cells[0]
    assert_equal row[0].appearance, row[1].appearance
    refute_equal row[0].tiles, row[1].tiles
    refute_equal row[0].appearance, row[2].appearance
  end

  def test_appearance_depends_on_tile_position_within_the_cell
    fake = reader
    put_tile(fake, 1, 1)
    put_tile(fake, 2, 2)
    put_block(fake, 0, 0, [1, 2, 1, 2])
    put_block(fake, 0, 1, [2, 1, 2, 1])
    row = snapshot(fake).cells[0]
    refute_equal row[0].appearance, row[1].appearance
  end

  def test_scrolled_screen_matches_the_equivalent_unscrolled_content
    plain = reader
    scrolled = reader(scx: 96, scy: 128)
    [[1, 1], [3, 7], [7, 9]].each_with_index do |(row, col), i|
      [plain, scrolled].each { |fake| put_tile(fake, 10 + i, 20 + i) }
      put_block(plain, row, col, [10 + i] * 4)
      put_block(scrolled, row, col, [10 + i] * 4, map_row: 16, map_col: 12)
    end
    a = snapshot(plain)
    b = snapshot(scrolled)
    assert_equal a.cells.map { |r| r.map(&:appearance) }, b.cells.map { |r| r.map(&:appearance) }
    assert_equal a.terrain_hash, b.terrain_hash
    refute_equal a.cells[1][1].appearance, a.cells[0][0].appearance
  end

  def test_tilemap_wraps_at_32_tiles
    fake = reader(scx: 30 * 8, scy: 28 * 8)
    put_tile(fake, 3, 9)
    put_block(fake, 0, 0, [3, 3, 3, 3], map_row: 28, map_col: 30)
    put_block(fake, 2, 2, [3, 3, 3, 3], map_row: 28, map_col: 30)
    cells = snapshot(fake).cells
    assert_equal [3, 3, 3, 3], cells[0][0].tiles
    assert_equal [3, 3, 3, 3], cells[2][2].tiles
    assert_equal [0, 0, 0, 0], cells[1][1].tiles
  end

  def test_tilemap_base_follows_lcdc_bit_3
    fake = reader(lcdc: 0x99)
    put_tile(fake, 4, 4, lcdc: 0x99)
    put_block(fake, 0, 0, [4, 4, 4, 4], lcdc: 0x99)
    assert_equal [4, 4, 4, 4], snapshot(fake).cells[0][0].tiles
  end

  def test_tile_data_addressing_follows_lcdc_bit_4
    [0x91, 0x81].each do |lcdc|
      fake = reader(lcdc:)
      put_tile(fake, 2, 5, lcdc:)
      put_tile(fake, 200, 6, lcdc:)
      put_block(fake, 0, 0, [2, 2, 2, 2], lcdc:)
      put_block(fake, 0, 1, [200, 200, 200, 200], lcdc:)
      row = snapshot(fake).cells[0]
      expected_low = Digest::SHA256.hexdigest((pattern(5) * 4).pack('C*'))[0, 8]
      expected_high = Digest::SHA256.hexdigest((pattern(6) * 4).pack('C*'))[0, 8]
      assert_equal [expected_low, expected_high], row.first(2).map(&:appearance), "lcdc=#{lcdc.to_s(16)}"
    end
  end

  def test_numbers_above_127_land_at_0x8800_in_signed_mode
    unsigned = reader(lcdc: 0x91)
    signed = reader(lcdc: 0x81)
    put_tile(unsigned, 130, 1, lcdc: 0x91)
    put_tile(signed, 130, 1, lcdc: 0x81)
    put_block(unsigned, 0, 0, [130] * 4, lcdc: 0x91)
    put_block(signed, 0, 0, [130] * 4, lcdc: 0x81)
    assert_equal snapshot(unsigned).cells[0][0].appearance, snapshot(signed).cells[0][0].appearance
  end

  def test_sub_tile_scroll_marks_overlay
    refute snapshot(reader(scx: 16, scy: 8)).overlay
    assert snapshot(reader(scx: 3)).overlay
    assert snapshot(reader(scy: 5)).overlay
  end

  def test_sprites_are_read_from_oam_with_their_pattern
    fake = reader
    put_tile(fake, 9, 3)
    [0x50, 0x40, 9, 0x20].each_with_index { |byte, i| fake.write(OAM + i, byte) }
    sprite = snapshot(fake).sprites.first
    assert_equal({ x: 0x40, y: 0x50, tile: 9, attr: 0x20, pattern: Digest::SHA256.hexdigest(pattern(3).pack('C*'))[0, 8] }, sprite)
  end

  def test_offscreen_sprites_are_skipped
    assert_empty snapshot(reader).sprites
  end

  def test_terrain_hash_ignores_sprites_and_objects_hash_ignores_cells
    base = reader
    put_tile(base, 9, 3)
    with_sprite = reader
    put_tile(with_sprite, 9, 3)
    [0x50, 0x40, 9, 0].each_with_index { |byte, i| with_sprite.write(OAM + i, byte) }
    other_cells = reader
    put_tile(other_cells, 9, 3)
    put_tile(other_cells, 1, 8)
    put_block(other_cells, 2, 2, [1] * 4)
    [0x50, 0x40, 9, 0].each_with_index { |byte, i| other_cells.write(OAM + i, byte) }
    a = snapshot(base)
    b = snapshot(with_sprite)
    c = snapshot(other_cells)
    assert_equal a.terrain_hash, b.terrain_hash
    refute_equal a.objects_hash, b.objects_hash
    assert_equal b.objects_hash, c.objects_hash
    refute_equal b.terrain_hash, c.terrain_hash
  end

  def test_terrain_hash_includes_the_overlay_flag
    refute_equal snapshot(reader).terrain_hash, snapshot(reader(scx: 4)).terrain_hash
  end

  def test_objects_hash_is_independent_of_oam_order
    a = reader
    b = reader
    sprites = [[0x20, 0x30, 1, 0], [0x40, 0x50, 2, 0]]
    sprites.each_with_index { |s, i| s.each_with_index { |byte, j| a.write(OAM + (i * 4) + j, byte) } }
    sprites.reverse.each_with_index { |s, i| s.each_with_index { |byte, j| b.write(OAM + (i * 4) + j, byte) } }
    assert_equal snapshot(a).objects_hash, snapshot(b).objects_hash
  end

  def test_starting_house_snapshot_on_the_real_screen
    skip_without_rom!
    emulator = EmulatorCache.playable
    first = Koholint::Vision::ScreenVision.snapshot(emulator, place: [163, 16])
    second = Koholint::Vision::ScreenVision.snapshot(emulator, place: [163, 16])
    assert_equal 8, first.cells.size
    assert(first.cells.all? { |row| row.size == 10 })
    assert_equal [163, 16], first.place
    distinct = first.cells.flatten.map(&:appearance).uniq.size
    assert_operator distinct, :<=, 40
    assert_equal first, second
    assert_equal first.terrain_hash, second.terrain_hash
    refute first.overlay
  end
end
