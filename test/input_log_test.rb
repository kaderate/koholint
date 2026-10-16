require_relative 'test_helper'
require 'tmpdir'
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
end
