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

  def test_dialogue_event_requires_its_fields_and_an_agent_source
    path = File.join(Dir.mktmpdir, 'trace.jsonl')
    trace = Koholint::Trace.new(path)
    event = trace.emit(:dialogue, frame: 1, place: [1, 2], text: 'Hi', source: 'agent', page: 0)
    assert_equal 'Hi', event['text']
    assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:dialogue, frame: 1, place: [1, 2], text: 'Hi', source: 'agent') }
    assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:dialogue, frame: 1, place: [1, 2], text: 'Hi', source: 'ocr', page: 0) }
  end

  def test_decision_plan_is_optional_and_validated
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      base = { decision_point: 'p', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0, agent: 'claude', latency_ms: 0, cost_usd: 0.0 }
      trace.emit(:decision, frame: 1, **base, plan: 'talk to him')
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:decision, frame: 2, **base, plan: 7) }
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:decision, frame: 2, **base, plan: "a\nb") }
      assert_equal 'talk to him', Koholint::Trace.read(File.join(dir, 'trace.jsonl')).last['plan']
    end
  end

  def test_decision_prompt_fields_are_optional_but_validated
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      base = { decision_point: 'p', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0, agent: 'claude', latency_ms: 0, cost_usd: 0.0 }
      trace.emit(:decision, frame: 1, **base)
      trace.emit(:decision, frame: 2, **base, prompt_sha: 'a' * 64, image: false)
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:decision, frame: 3, **base, prompt_sha: 'xyz') }
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:decision, frame: 3, **base, image: 'yes') }
    end
  end

  def test_read_falls_back_to_the_gzipped_trace
    with_path do |path|
      Koholint::Trace.new(path).emit(:stop, frame: 3, reason: 'frames')
      Koholint::Trace.compress(path)
      File.delete(path)
      assert_equal "#{path}.gz", Koholint::Trace.located(path)
      assert_equal [{ 'v' => 1, 'type' => 'stop', 'frame' => 3, 'reason' => 'frames' }], Koholint::Trace.read(path)
      Koholint::Trace.decompress(path)
      refute File.exist?("#{path}.gz")
      assert_equal 3, Koholint::Trace.read(path).first['frame']
    end
  end

  def test_compress_is_deterministic
    with_path do |path|
      Koholint::Trace.new(path).emit(:stop, frame: 3, reason: 'frames')
      Koholint::Trace.compress(path)
      first = File.binread("#{path}.gz")
      Koholint::Trace.compress(path)
      assert_equal first, File.binread("#{path}.gz")
    end
  end

  def test_a_truncated_gzipped_trace_reads_what_it_can_and_refuses_to_decompress
    with_path do |path|
      trace = Koholint::Trace.new(path)
      400.times { |n| trace.emit(:stop, frame: n, reason: "r#{n}" * 20) }
      Koholint::Trace.compress(path)
      File.delete(path)
      gz = "#{path}.gz"
      File.binwrite(gz, File.binread(gz)[0, File.size(gz) / 2])
      events = Koholint::Trace.read(path)
      assert_operator events.size, :<, 400
      assert_equal (0...events.size).to_a, events.map { |e| e['frame'] }
      refute Koholint::Trace.intact?(path)
      assert_raises(Koholint::Error) { Koholint::Trace.decompress(path) }
      assert File.file?(gz)
      refute File.exist?(path)
      File.binwrite(gz, 'garbage')
      assert_equal [], Koholint::Trace.read(path)
    end
  end
end
