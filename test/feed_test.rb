require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/trace'
require 'koholint/viewer/feed'

class FeedTest < Minitest::Test
  Follower = Struct.new(:frame, :journal_frames, :lag, :sync)
  STATE = { 'hp' => 16, 'max_hp' => 24, 'milestone' => 'none' }.freeze
  FOLLOWER = Follower.new(90, 100, 10, :in_sync)

  def with_dir(manifest: { 'flow_version' => 'f', 'status' => 'running', 'budget' => { 'frames' => 9 } })
    Dir.mktmpdir('run-x') do |dir|
      File.write(File.join(dir, 'manifest.json'), JSON.generate(manifest)) if manifest
      yield dir, Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    end
  end

  def decision(trace, frame)
    trace.emit(:decision, frame:, point: 'move', input: {}, options: [], choice: { 'to' => frame }, justification: 'j',
                          confidence: 0.5, agent: 'a', latency_ms: 1, cost_usd: 0.1)
  end

  def test_document_has_status_replay_and_events
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 1, state: STATE, state_hash: 'h')
      decision(trace, 2)
      trace.emit(:action, frame: 3, skill: 'walk', params: { 'dir' => 'up' }, result: {})
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal %i[status replay events], doc.keys
      assert_equal File.basename(dir), doc[:status][:run_id]
      assert_equal({ flow_version: 'f', manifest_status: 'running', budget: { 'frames' => 9 }, health: 'unknown',
                     hearts: 2.0, max_hearts: 3.0, objective: nil, last_notable: nil, highest_milestone: 'none',
                     frames: 3, cost_usd: 0.1, run_id: File.basename(dir) }, doc[:status])
      assert_equal({ frame: 90, journal_frames: 100, lag: 10, sync: :in_sync }, doc[:replay])
      assert_equal [{ frame: 2, type: 'decision', agent: 'a', choice: { 'to' => 2 }, confidence: 0.5 },
                    { frame: 3, type: 'action', skill: 'walk', params: { 'dir' => 'up' } }], doc[:events]
    end
  end

  def test_events_are_capped_to_the_latest_in_order
    with_dir do |dir, trace|
      5.times { |i| decision(trace, i) }
      assert_equal [2, 3, 4], Koholint::Viewer::Feed.for(dir, FOLLOWER, limit: 3)[:events].map { |e| e[:frame] }
    end
  end

  def test_empty_trace
    with_dir do |dir, _|
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_empty doc[:events]
      assert_equal 'unknown', doc[:status][:health]
    end
  end

  def test_health_is_unknown_without_any_notable_or_objective_event_even_after_many_frames
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 9000, state: STATE, state_hash: 'h')
      assert_equal 'unknown', Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:health]
    end
  end

  def test_health_keeps_summary_semantics_once_progress_events_exist
    with_dir do |dir, trace|
      trace.emit(:notable, frame: 10, kind: 'k', detail: 'd')
      trace.emit(:perception, frame: 20, state: STATE, state_hash: 'h')
      assert_equal 'progressing', Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:health]
      trace.emit(:perception, frame: 9000, state: STATE, state_hash: 'h')
      assert_equal 'stalled', Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:health]
    end
  end

  def test_stopped_and_dead_are_kept
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 1, state: { 'hp' => 0, 'max_hp' => 24, 'milestone' => 'none' }, state_hash: 'h')
      assert_equal 'dead', Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:health]
      trace.emit(:stop, frame: 2, reason: 'r')
      assert_equal 'stopped', Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:health]
    end
  end

  def count_trace_reads
    reads = 0
    original = Koholint::Trace.method(:read)
    Koholint::Trace.define_singleton_method(:read) { |path| reads += 1; original.call(path) }
    yield
    reads
  ensure
    Koholint::Trace.define_singleton_method(:read, original)
  end

  def test_trace_is_read_once_per_call_and_not_reparsed_when_unchanged
    with_dir do |dir, trace|
      decision(trace, 1)
      reads = count_trace_reads { 3.times { Koholint::Viewer::Feed.for(dir, FOLLOWER) } }
      assert_equal 1, reads
      decision(trace, 2)
      reads = count_trace_reads { Koholint::Viewer::Feed.for(dir, FOLLOWER) }
      assert_equal 1, reads
      assert_equal [1, 2], Koholint::Viewer::Feed.for(dir, FOLLOWER)[:events].map { |e| e[:frame] }
    end
  end

  def test_manifest_without_optional_keys
    with_dir(manifest: {}) do |dir, _|
      status = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status]
      assert_nil status[:flow_version]
      assert_nil status[:budget]
    end
  end

  def test_missing_manifest_or_dir_is_an_error
    with_dir(manifest: nil) { |dir, _| assert_raises(Koholint::Error) { Koholint::Viewer::Feed.for(dir, FOLLOWER) } }
    assert_raises(Koholint::Error) { Koholint::Viewer::Feed.for('/nonexistent/run', FOLLOWER) }
  end

  def test_garbled_manifest_is_an_error
    with_dir(manifest: nil) do |dir, _|
      File.write(File.join(dir, 'manifest.json'), '{oops')
      assert_raises(Koholint::Error) { Koholint::Viewer::Feed.for(dir, FOLLOWER) }
    end
  end

  def test_non_object_manifest_is_a_one_line_error
    ['[]', 'null', '"x"', '5'].each do |content|
      with_dir(manifest: nil) do |dir, _|
        File.write(File.join(dir, 'manifest.json'), content)
        error = assert_raises(Koholint::Error) { Koholint::Viewer::Feed.for(dir, FOLLOWER) }
        refute_includes error.message, "\n"
      end
    end
  end
end
