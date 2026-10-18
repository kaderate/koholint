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

  VISION_FIELDS = {
    screen: { place: [1, 2], terrain_hash: 'h', objects_hash: 'o', grid: [], static_sprites: [] },
    screen_changed: { place: [1, 2], cells: [] },
    affordance: { appearance: 'a1', action: 'walk', direction: nil, result: 'no', method: 'probe', context: [], source: 'x' },
    grid_contradiction: { place: [1, 2], row: 0, col: 0, direction: 'up', believed: 'yes', observed: 'no' }
  }.freeze

  def test_vision_events_reject_each_missing_field
    with_path do |path|
      VISION_FIELDS.each do |type, fields|
        fields.each_key do |key|
          error = assert_raises(Koholint::Trace::InvalidEvent) { Koholint::Trace.new(path).emit(type, frame: 1, **fields.except(key)) }
          assert_match(/#{key}/, error.message)
        end
      end
    end
  end

  def test_vision_events_accept_complete_fields_with_nil_direction
    with_path do |path|
      VISION_FIELDS.each { |type, fields| assert_equal type.to_s, Koholint::Trace.new(path).emit(type, frame: 1, **fields)['type'] }
      assert_nil Koholint::Trace.new(path).emit(:affordance, frame: 2, **VISION_FIELDS[:affordance])['direction']
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
