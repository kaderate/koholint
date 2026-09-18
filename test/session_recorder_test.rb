# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/session_recorder"
require_relative "../lib/navigator"

class SessionRecorderTest < Minitest::Test
  # Mimics PPU::Framebuffer: a single mutable @pixels array reused across ticks, exposing it via
  # #pixels_frame like the real one does -- lets the copy-vs-reference test mutate the underlying
  # buffer between snapshots without touching gemboy.
  FakeFramebuffer = Struct.new(:pixels) do
    def pixels_frame = pixels.dup
  end

  FakePpu = Struct.new(:framebuffer)
  FakeMotherboard = Struct.new(:ppu)

  SpyRecorder = Struct.new(:snapshot_count) do
    def initialize
      super(0)
    end

    def snapshot!
      self.snapshot_count += 1
    end
  end

  def full_frame(color) = Array.new(PPU::WINDOW_WIDTH * PPU::WINDOW_HEIGHT, color)

  def build_motherboard(pixels)
    FakeMotherboard.new(FakePpu.new(FakeFramebuffer.new(pixels)))
  end

  def test_snapshot_and_save_produce_a_real_gif_file_at_the_expected_path
    Dir.mktmpdir do |dir|
      motherboard = build_motherboard(full_frame(0xFFFFFFFF))
      recorder = Koholint::SessionRecorder.new(motherboard, label: "smoke_test", out_dir: dir)

      recorder.snapshot!
      recorder.snapshot!
      path = recorder.save!

      expected = File.join(dir, "#{Time.now.strftime('%Y-%m-%d')}_smoke_test.gif")
      assert_equal expected, path
      assert File.exist?(path)
      assert_equal "GIF89a".b, File.binread(path, 6)
    end
  end

  def test_captured_frames_are_independent_copies_not_aliased_to_a_mutated_buffer
    framebuffer = FakeFramebuffer.new([1, 2, 3, 4])
    motherboard = FakeMotherboard.new(FakePpu.new(framebuffer))
    recorder = Koholint::SessionRecorder.new(motherboard, label: "copy_test")

    recorder.snapshot!
    framebuffer.pixels[0] = 999 # mutate the shared buffer, like the PPU reusing it tick to tick
    recorder.snapshot!

    frames = recorder.instance_variable_get(:@frames)
    assert_equal [1, 2, 3, 4], frames[0], "earlier snapshot must not be affected by a later buffer mutation"
    assert_equal [999, 2, 3, 4], frames[1]
  end

  def test_save_with_zero_snapshots_is_a_safe_no_op
    Dir.mktmpdir do |dir|
      motherboard = build_motherboard(full_frame(0xFFFFFFFF))
      recorder = Koholint::SessionRecorder.new(motherboard, label: "empty_test", out_dir: dir)

      assert_nil recorder.save!
      assert_empty Dir.glob(File.join(dir, "*"))
    end
  end

  def test_save_disambiguates_a_same_day_same_label_filename_collision
    Dir.mktmpdir do |dir|
      motherboard = build_motherboard(full_frame(0xFFFFFFFF))

      first = Koholint::SessionRecorder.new(motherboard, label: "dup_test", out_dir: dir)
      first.snapshot!
      first_path = first.save!

      second = Koholint::SessionRecorder.new(motherboard, label: "dup_test", out_dir: dir)
      second.snapshot!
      second_path = second.save!

      refute_equal first_path, second_path
      assert File.exist?(first_path)
      assert File.exist?(second_path)
    end
  end

  def test_navigator_move_calls_snapshot_once_per_tap_when_recorder_given
    stub_navigator_run_cycles do
      mmu = FakeMmuStub.new(FakeKeysStub.new)
      motherboard = FakeNavigatorMotherboard.new(mmu)
      spy = SpyRecorder.new

      Koholint::Navigator.move!(motherboard, :down, recorder: spy)

      assert_equal Koholint::Navigator::MAX_TAPS, spy.snapshot_count
    end
  end

  def test_navigator_avoid_hostiles_and_push_calls_snapshot_once_per_step_when_recorder_given
    stub_navigator_run_cycles do
      mmu = FakeMmuStub.new(FakeKeysStub.new)
      motherboard = FakeNavigatorMotherboard.new(mmu)
      spy = SpyRecorder.new

      results = Koholint::Navigator.avoid_hostiles_and_push!(motherboard, :down, max_steps: 3, min_hp: 0, recorder: spy)

      assert_equal results.size, spy.snapshot_count
    end
  end

  # Navigator.run_cycles ultimately drives gemboy's real cpu/ppu/apu; stubbed out to a no-op so
  # these spy tests exercise only Navigator's own control flow and snapshot! call sites, with a
  # fixed, never-moving position (see FakeMmuStub) so #move!/#avoid_hostiles_and_push! run their
  # full internal loop deterministically instead of committing early.
  def stub_navigator_run_cycles
    original = Koholint::Navigator.method(:run_cycles)
    Koholint::Navigator.define_singleton_method(:run_cycles) { |*| 0 }
    yield
  ensure
    Koholint::Navigator.define_singleton_method(:run_cycles, original)
  end

  # Minimal stand-ins for Navigator's motherboard/mmu/keys contract.
  FakeKeysStub = Struct.new(:pressed) do
    def initialize
      super([])
    end

    def press(key) = pressed << key
    def clear = pressed.clear
    def method_missing(_name, *) = nil
    def respond_to_missing?(*) = true
  end

  FakeMmuStub = Struct.new(:joypad_keys) do
    def read(_addr) = 100 # HP address reads a healthy, constant value; position stays fixed
    def debug_read(_addr) = 0 # every OAM slot reads as unused, so no hazard ever biases direction
    def joypad = Struct.new(:key_state).new(joypad_keys)
  end

  FakeNavigatorMotherboard = Struct.new(:mmu) do
    def cpu = nil
    def ppu = nil
    def apu = nil
  end
end
