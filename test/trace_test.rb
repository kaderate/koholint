require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/trace'

class TraceTest < Minitest::Test
  def with_path
    Dir.mktmpdir { |dir| yield File.join(dir, 'trace.jsonl') }
  end

  def test_emit_rejects_unknown_type
    with_path do |path|
      assert_raises(Koholint::Trace::InvalidEvent) { Koholint::Trace.new(path).emit(:bogus, frame: 0) }
    end
  end

  def test_emit_rejects_missing_required_field
    with_path do |path|
      error = assert_raises(Koholint::Trace::InvalidEvent) { Koholint::Trace.new(path).emit(:stop, frame: 3) }
      assert_match(/reason/, error.message)
    end
  end

  def test_emit_writes_versioned_line_and_returns_it
    with_path do |path|
      event = Koholint::Trace.new(path).emit(:stop, frame: 3, reason: 'frames')
      assert_equal({ 'v' => 1, 'type' => 'stop', 'frame' => 3, 'reason' => 'frames' }, event)
      assert_equal [event], Koholint::Trace.read(path)
    end
  end

  def test_read_ignores_truncated_last_line
    with_path do |path|
      Koholint::Trace.new(path).emit(:stop, frame: 1, reason: 'x')
      File.open(path, 'a') { |f| f.write('{"v":1,"type":"stop","fra') }
      assert_equal 1, Koholint::Trace.read(path).size
    end
  end

  def test_lines_are_append_only
    with_path do |path|
      Koholint::Trace.new(path).emit(:stop, frame: 1, reason: 'a')
      Koholint::Trace.new(path).emit(:stop, frame: 2, reason: 'b')
      assert_equal [1, 2], Koholint::Trace.read(path).map { |e| e['frame'] }
    end
  end

  def test_emit_after_truncated_line_starts_a_fresh_line
    with_path do |path|
      File.write(path, '{"v":1,"type":"stop","fra')
      Koholint::Trace.new(path).emit(:stop, frame: 9, reason: 'x')
      assert_equal [9], Koholint::Trace.read(path).map { |e| e['frame'] }
    end
  end
end
