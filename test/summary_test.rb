require_relative 'test_helper'
require 'tmpdir'
require 'koholint/summary'
require 'koholint/run'

class SummaryTest < Minitest::Test
  STATE = { 'hp' => 16, 'max_hp' => 24, 'milestone' => 'none', 'room_id' => 163, 'map_id' => 16 }.freeze

  def with_run
    Dir.mktmpdir do |dir|
      rom = File.join(dir, 'game.gbc')
      File.binwrite(rom, 'rom')
      yield Koholint::Run.create(root: dir, flow_version: 'f', budget: {}, rom_path: rom)
    end
  end

  def test_summary_is_derived_from_trace_only
    with_run do |run|
      t = run.trace
      t.emit(:perception, frame: 0, state: STATE, state_hash: 'h')
      t.emit(:decision, frame: 0, decision_point: 'move', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                        agent: 'a', latency_ms: 5, cost_usd: 0.25)
      t.emit(:decision, frame: 30, decision_point: 'move', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                        agent: 'a', latency_ms: 5, cost_usd: 0.5)
      t.emit(:objective, frame: 40, id: 'find-sword', status: 'started', predicate: 'item sword')
      t.emit(:notable, frame: 50, kind: 'new_room', detail: '163/16')
      t.emit(:perception, frame: 60, state: STATE, state_hash: 'h2')
      assert_equal({ health: 'progressing', hearts: 2.0, max_hearts: 3.0, objective: 'find-sword',
                     last_notable: { 'kind' => 'new_room', 'detail' => '163/16' }, highest_milestone: 'none',
                     frames: 60, cost_usd: 0.75 }, Koholint::Summary.for(run))
    end
  end

  def test_highest_milestone_keeps_the_best_perceived
    with_run do |run|
      run.trace.emit(:perception, frame: 0, state: STATE, state_hash: 'h')
      run.trace.emit(:perception, frame: 5, state: STATE.merge('milestone' => 'shield'), state_hash: 'h')
      run.trace.emit(:perception, frame: 9, state: STATE, state_hash: 'h')
      assert_equal 'shield', Koholint::Summary.for(run)[:highest_milestone]
    end
  end

  def test_health_is_stopped_after_a_stop_event
    with_run do |run|
      run.trace.emit(:stop, frame: 10, reason: 'frames')
      assert_equal 'stopped', Koholint::Summary.for(run)[:health]
    end
  end

  def test_health_is_dead_at_zero_hp
    with_run do |run|
      run.trace.emit(:perception, frame: 5, state: STATE.merge('hp' => 0), state_hash: 'h')
      assert_equal 'dead', Koholint::Summary.for(run)[:health]
    end
  end

  def test_health_is_stalled_without_notable_events_for_a_long_time
    with_run do |run|
      run.trace.emit(:perception, frame: 0, state: STATE, state_hash: 'h')
      run.trace.emit(:perception, frame: Koholint::Summary::STALL_FRAMES, state: STATE, state_hash: 'h')
      assert_equal 'stalled', Koholint::Summary.for(run)[:health]
    end
  end

  def test_a_diagnostic_notable_is_not_progress_and_not_last_notable
    with_run do |run|
      run.trace.emit(:perception, frame: 0, state: STATE, state_hash: 'h')
      run.trace.emit(:notable, frame: 10, kind: 'grid_overlay_stuck', detail: [1, 2])
      run.trace.emit(:perception, frame: 4000, state: STATE, state_hash: 'h')
      summary = Koholint::Summary.for(run)
      assert_equal 'stalled', summary[:health]
      assert_nil summary[:last_notable]
    end
  end

  def test_a_real_notable_after_a_diagnostic_is_progress
    with_run do |run|
      run.trace.emit(:perception, frame: 0, state: STATE, state_hash: 'h')
      run.trace.emit(:notable, frame: 3900, kind: 'new_room', detail: 'x')
      run.trace.emit(:notable, frame: 3950, kind: 'grid_overlay_stuck', detail: [1, 2])
      run.trace.emit(:perception, frame: 4000, state: STATE, state_hash: 'h')
      summary = Koholint::Summary.for(run)
      assert_equal 'progressing', summary[:health]
      assert_equal 'new_room', summary[:last_notable]['kind']
    end
  end

  def test_empty_trace_summary
    with_run do |run|
      assert_equal 'progressing', Koholint::Summary.for(run)[:health]
      assert_equal 0, Koholint::Summary.for(run)[:frames]
    end
  end
end
