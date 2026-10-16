require_relative 'test_helper'
require 'tmpdir'
require 'zlib'
require 'koholint/input_log'

class InputLogTest < Minitest::Test
  BUTTONS = %i[up down left right a b start select].freeze

  def with_path
    Dir.mktmpdir { |dir| yield File.join(dir, 'inputs.log') }
  end

  def test_round_trip_preserves_every_frame
    rng = Random.new(7)
    frames = Array.new(5000) { BUTTONS.select { rng.rand < 0.2 } }
    with_path do |path|
      log = Koholint::InputLog.new(path)
      frames.each { |buttons| log.append(buttons) }
      log.flush
      loaded = Koholint::InputLog.load(path)
      assert_equal 5000, loaded.frames
      seen = []
      loaded.each_frame { |buttons| seen << buttons }
      assert_equal frames.map { |b| b.sort_by { |x| BUTTONS.index(x) } }, seen
    end
  end

  def test_rle_makes_idle_runs_small
    with_path do |path|
      log = Koholint::InputLog.new(path)
      100_000.times { log.append([]) }
      log.flush
      assert_operator File.size(path), :<, 1024
    end
  end

  def test_rejects_unknown_format_version
    with_path do |path|
      File.binwrite(path, "\x63garbage")
      assert_raises(Koholint::Error) { Koholint::InputLog.load(path) }
    end
  end

  def test_new_on_existing_file_appends
    with_path do |path|
      first = Koholint::InputLog.new(path)
      3.times { first.append([:a]) }
      first.flush
      second = Koholint::InputLog.new(path)
      2.times { second.append([]) }
      second.flush
      assert_equal 5, Koholint::InputLog.load(path).frames
    end
  end

  def test_flush_then_read_without_closing
    with_path do |path|
      log = Koholint::InputLog.new(path)
      4.times { log.append([:a]) }
      log.flush
      assert_equal 4, Koholint::InputLog.load(path).frames
      2.times { log.append([:a]) }
      log.flush
      assert_equal 6, Koholint::InputLog.load(path).frames
      assert_equal 1 + 2 * 5, File.size(path)
    end
  end

  def test_partial_trailing_entry_is_ignored
    with_path do |path|
      log = Koholint::InputLog.new(path)
      3.times { log.append([:b]) }
      log.flush
      File.binwrite(path, "\x01\x02\x03", mode: 'ab')
      assert_equal 3, Koholint::InputLog.load(path).frames
      entries, offset = Koholint::InputLog.read_from(path, 1)
      assert_equal [[1 << BUTTONS.index(:b), 3]], entries
      assert_equal 6, offset
      resumed = Koholint::InputLog.new(path)
      resumed.append([:b])
      resumed.flush
      assert_equal 4, Koholint::InputLog.load(path).frames
    end
  end

  def test_read_from_returns_only_new_entries
    with_path do |path|
      log = Koholint::InputLog.new(path)
      2.times { log.append([:a]) }
      log.flush
      _, offset = Koholint::InputLog.read_from(path, 1)
      3.times { log.append([]) }
      log.append([:a])
      log.flush
      entries, next_offset = Koholint::InputLog.read_from(path, offset)
      assert_equal [[0, 3], [1 << BUTTONS.index(:a), 1]], entries
      assert_equal File.size(path), next_offset
      assert_equal [[], next_offset], Koholint::InputLog.read_from(path, next_offset)
    end
  end

  def test_version_1_files_still_load
    with_path do |path|
      packed = [[1 << BUTTONS.index(:a), 7], [0, 2]].map { |m, c| [m, c].pack('CV') }.join
      File.binwrite(path, [1].pack('C') + Zlib::Deflate.deflate(packed))
      log = Koholint::InputLog.load(path)
      assert_equal 9, log.frames
      log.append([])
      log.flush
      assert_equal 2, File.binread(path).getbyte(0)
      assert_equal 10, Koholint::InputLog.load(path).frames
    end
  end
end
