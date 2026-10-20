require_relative 'test_helper'
require 'koholint/vision/screen_vision'
require 'koholint/vision/screen_diff'
require 'koholint/addresses'
require 'koholint/emulator'
require 'koholint/perception'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'support/emulator_cache'

class ScreenDiffTest < Minitest::Test
  LCDC = 0xFF40
  WY = 0xFF4A
  WX = 0xFF4B
  SCX = 0xFF43
  ADDRESSES = Koholint::Addresses.load

  class FakeReader
    def initialize = @memory = Hash.new(0)
    def read(addr) = @memory[addr]
    def write(addr, value) = @memory[addr] = value
  end

  def reader(lcdc: 0x91, **registers)
    FakeReader.new.tap do |fake|
      fake.write(LCDC, lcdc)
      registers.each { |name, value| fake.write(self.class.const_get(name.upcase), value) }
    end
  end

  def put_tile(fake, number, seed) = 16.times { |i| fake.write(0x8000 + (number * 16) + i, (seed * 16 + i) & 0xFF) }

  def put_cell(fake, row, col, number)
    [[0, 0], [0, 1], [1, 0], [1, 1]].each { |dr, dc| fake.write(0x9800 + ((row * 2 + dr) * 32) + (col * 2) + dc, number) }
  end

  def snapshot(fake, place: [163, 16]) = Koholint::Vision::ScreenVision.snapshot(fake, place:)

  def between(a, b) = Koholint::Vision::ScreenDiff.between(a, b)

  def test_one_changed_cell_is_reported_with_both_appearances
    before = reader
    after = reader
    put_tile(after, 3, 7)
    put_cell(after, 2, 5, 3)
    a = snapshot(before)
    b = snapshot(after)
    assert_equal [{ row: 2, col: 5, from: a.cells[2][5].appearance, to: b.cells[2][5].appearance }], between(a, b)
  end

  def test_changes_are_listed_in_row_major_order
    before = reader
    after = reader
    put_tile(after, 3, 7)
    [[4, 1], [0, 9], [4, 0]].each { |row, col| put_cell(after, row, col, 3) }
    assert_equal [[0, 9], [4, 0], [4, 1]], between(snapshot(before), snapshot(after)).map { |c| c.values_at(:row, :col) }
  end

  def test_identical_screens_give_no_change
    assert_equal [], between(snapshot(reader), snapshot(reader))
  end

  def test_window_over_the_playfield_is_an_overlay_and_not_comparable
    covered = snapshot(reader(lcdc: 0xB1, wy: 40, wx: 7))
    assert covered.overlay
    assert_nil between(snapshot(reader), covered)
    assert_nil between(covered, snapshot(reader))
  end

  def test_window_limited_to_the_hud_is_not_an_overlay
    refute snapshot(reader(lcdc: 0xF1, wy: 128, wx: 7)).overlay
    refute snapshot(reader(lcdc: 0xB1, wy: 40, wx: 167)).overlay
  end

  def test_lcd_off_and_background_off_are_overlays
    assert snapshot(reader(lcdc: 0x11)).overlay
    assert snapshot(reader(lcdc: 0x90)).overlay
  end

  def test_screen_still_loading_is_an_overlay
    loading = reader
    loading.write(ADDRESSES.fetch(:game_mode), 0x0B)
    loading.write(ADDRESSES.fetch(:game_submode), 3)
    assert snapshot(loading).overlay
    loading.write(ADDRESSES.fetch(:game_submode), 7)
    refute snapshot(loading).overlay
  end

  def test_open_dialogue_is_an_overlay
    talking = reader
    talking.write(ADDRESSES.fetch(:dialog_state), 0x81)
    assert snapshot(talking).overlay
  end

  def test_overlay_is_a_boolean
    assert_same true, snapshot(reader(scx: 3)).overlay
    assert_same true, snapshot(reader.tap { |fake| fake.write(ADDRESSES.fetch(:dialog_state), 2) }).overlay
    assert_same false, snapshot(reader).overlay
  end

  def test_other_places_or_scrolls_are_not_comparable
    assert_nil between(snapshot(reader), snapshot(reader, place: [164, 16]))
    assert_nil between(snapshot(reader), snapshot(reader.tap { |fake| fake.write(0xFF43, 8) }))
  end

  SAMPLE_EVERY = 10
  WALK_FRAMES = 900

  def walk_and_sample
    emulator = EmulatorCache.playable
    policy = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new)
    start = emulator.frame
    samples = []
    while emulator.frame < start + WALK_FRAMES
      state = Koholint::Perception.read(emulator)
      choice = policy.decide(policy.decision_point_for(state), state, {})[:choice]
      choice[:frames].times do
        if ((emulator.frame - start) % SAMPLE_EVERY).zero?
          now = Koholint::Perception.read(emulator)
          samples << Koholint::Vision::ScreenVision.snapshot(emulator, place: [now.room_id, now.map_id])
        end
        emulator.step(choice[:buttons])
      end
    end
    samples
  end

  def grid(snap) = snap.cells.map { |row| row.map(&:appearance) }

  def test_walking_around_the_house_shows_no_phantom_change
    skip_without_rom!
    samples = walk_and_sample
    overlay_frames = samples.select(&:overlay).map(&:frame)
    assert_includes overlay_frames, samples.first.frame, 'the first controllable frame is still loading'
    settled = samples.reject(&:overlay)
    refute_empty settled
    settled.each_cons(2) do |a, b|
      next unless a.place == b.place && a.scroll == b.scroll

      assert_equal [], between(a, b), "phantom change between frames #{a.frame} and #{b.frame}"
    end
    reference = settled.first
    redrawn = samples.select { |s| s.frame > reference.frame && s.place == reference.place && grid(s) != grid(reference) }
    refute_empty redrawn, "no dialogue was drawn (overlay frames: #{overlay_frames})"
    assert redrawn.all?(&:overlay), "screen redrawn without overlay at #{redrawn.reject(&:overlay).map(&:frame)}"
  end
end
