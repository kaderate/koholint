require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'stringio'
require 'koholint/cli'
require 'koholint/place_shots'

class PlaceShotsTest < Minitest::Test
  PLAYING = { room_id: 3, map_id: 1, game_mode: 0x0B, game_submode: 7, hp: 24, x: 80, y: 80 }.freeze
  Fake = Struct.new(:frame) do
    def frame_png = "\x89PNG\r\n\x1a\nfake".b
  end

  def state(**fields) = Koholint::GameState.new(**PLAYING, **fields)

  def shot_at(shots, emulator, frame, **fields)
    emulator.frame = frame
    shots.capture(emulator, state(frame:, **fields))
  end

  def test_writes_one_png_per_place_once_the_screen_settled
    Dir.mktmpdir do |dir|
      shots = Koholint::PlaceShots.new(dir)
      emulator = Fake.new(0)
      shot_at(shots, emulator, 100)
      shot_at(shots, emulator, 119)
      assert_empty Koholint::PlaceShots.names(dir)
      shot_at(shots, emulator, 120)
      assert_equal ['3-1.png'], Koholint::PlaceShots.names(dir)
      File.write(File.join(dir, 'screens', '3-1.png'), 'kept')
      shot_at(shots, emulator, 400)
      assert_equal 'kept', File.read(File.join(dir, 'screens', '3-1.png'))
      shot_at(shots, emulator, 500, room_id: 4)
      shot_at(shots, emulator, 520, room_id: 4)
      assert_equal %w[3-1.png 4-1.png], Koholint::PlaceShots.names(dir).sort
    end
  end

  def test_skips_loading_dialogue_and_menu_phases
    Dir.mktmpdir do |dir|
      shots = Koholint::PlaceShots.new(dir)
      emulator = Fake.new(0)
      [{ game_submode: 3 }, { dialog_state: 1 }, { game_mode: 0x04 }].each do |fields|
        shot_at(shots, emulator, 0, **fields)
        shot_at(shots, emulator, 500, **fields)
      end
      assert_empty Koholint::PlaceShots.names(dir)
    end
  end

  def test_the_settle_delay_counts_from_the_first_playable_frame_of_the_place
    Dir.mktmpdir do |dir|
      shots = Koholint::PlaceShots.new(dir)
      emulator = Fake.new(0)
      shot_at(shots, emulator, 10, game_submode: 3)
      shot_at(shots, emulator, 50)
      shot_at(shots, emulator, 60)
      assert_empty Koholint::PlaceShots.names(dir)
      shot_at(shots, emulator, 70)
      assert_equal ['3-1.png'], Koholint::PlaceShots.names(dir)
    end
  end

  def test_a_resumed_run_does_not_rewrite_existing_screens
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'screens'))
      File.write(File.join(dir, 'screens', '3-1.png'), 'old')
      shots = Koholint::PlaceShots.new(dir)
      emulator = Fake.new(0)
      shot_at(shots, emulator, 0)
      shot_at(shots, emulator, 100)
      assert_equal 'old', File.read(File.join(dir, 'screens', '3-1.png'))
      assert_equal({ [3, 1] => true }, Koholint::PlaceShots.places(dir))
    end
  end

  def test_a_failed_write_warns_and_never_raises
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'screens'), 'not a directory')
      shots = Koholint::PlaceShots.new(dir)
      emulator = Fake.new(0)
      shot_at(shots, emulator, 0)
      _out, err = capture_io { shot_at(shots, emulator, 100) }
      assert_match(/screenshot 3-1.png not written/, err)
    end
  end

  def test_backfill_writes_the_missing_screens_and_is_idempotent
    skip_without_rom!
    Dir.mktmpdir do |root|
      run = Koholint::Run.create(root:, flow_version: Koholint::FLOW_VERSION, budget: {})
      30.times { run.inputs.append([]) }
      run.inputs.flush
      playing = PLAYING.transform_keys(&:to_s)
      [0, 25].each { |frame| run.trace.emit(:perception, frame:, state: playing.merge('frame' => frame), state_hash: 'h') }
      out = StringIO.new
      assert_equal 1, Koholint::PlaceShots.backfill(run.dir, out:)
      png = File.binread(File.join(run.dir, 'screens', '3-1.png'))
      assert_equal "\x89PNG\r\n\x1a\n".b, png[0, 8]
      assert_equal 0, Koholint::PlaceShots.backfill(run.dir, out:)
      assert_equal png, File.binread(File.join(run.dir, 'screens', '3-1.png'))
    end
  end
end
