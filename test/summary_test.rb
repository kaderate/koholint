require_relative 'test_helper'
require 'tmpdir'
require 'json'
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

  PLAYING = STATE.merge('game_mode' => 0x0B, 'game_submode' => 7)

  def decide(trace, frame, agent, latency_ms, cost_usd, **extra)
    trace.emit(:decision, frame:, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                          agent:, latency_ms:, cost_usd:, **extra)
  end

  def test_model_calls_exclude_scripted_agents_and_free_delegated_advances
    with_run do |run|
      t = run.trace
      decide(t, 0, 'start_game', 0, 0.0)
      decide(t, 1, 'walk_and_talk', 0, 0.0)
      decide(t, 2, 'delegated', 0, 0.0)
      decide(t, 3, 'delegated', 0, 0.02, prompt_sha: 'a' * 64)
      decide(t, 4, 'claude', 4000, 0.01)
      decide(t, 5, 'claude', 0, 0.0, fallback: true)
      calls = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).select { |e| Koholint::Summary.model_call?(e) }
      assert_equal [3, 4, 5], calls.map { |e| e['frame'] }
    end
  end

  def test_record_derives_the_run_summary_from_manifest_and_trace
    with_run do |run|
      run.manifest.merge!('tag' => 'exp', 'model' => 'sonnet', 'harness_sha' => 'abc')
      run.write_manifest
      t = run.trace
      t.emit(:perception, frame: 0, state: STATE.merge('room_id' => 0, 'map_id' => 0, 'game_mode' => 1), state_hash: 'h')
      t.emit(:perception, frame: 10, state: PLAYING, state_hash: 'h')
      [1000, 3000, 2000, 5000].each_with_index { |ms, n| decide(t, 20 + n, 'claude', ms, 0.25) }
      decide(t, 30, 'start_game', 0, 0.0)
      t.emit(:objective, frame: 40, id: 'obj-1', status: 'started', predicate: {})
      t.emit(:objective, frame: 50, id: 'obj-1', status: 'achieved', predicate: {})
      t.emit(:objective, frame: 50, id: 'obj-1', status: 'achieved', predicate: {})
      t.emit(:objective, frame: 50, id: 'obj-2', status: 'started', predicate: {})
      t.emit(:perception, frame: 1000, state: PLAYING.merge('room_id' => 1, 'milestone' => 'shield'), state_hash: 'h')
      t.emit(:stop, frame: 2000, reason: 'dollars')
      assert_equal({ v: Koholint::Summary::VERSION, run_id: run.id, flow_version: 'f', tag: 'exp', harness_sha: 'abc', prompts_sha: run.manifest['prompts_sha'], model: 'sonnet',
                     frames: 2000, dollars: 1.0, calls: 4, calls_per_1000f: 2.0, usd_per_1000f: 0.5,
                     latency_ms: { median: 3000, p90: 5000 }, highest_milestone: 'shield', places_seen: 2,
                     objectives: { count: 2, achieved: 1 }, stop_reason: 'dollars', symptoms: [], starred: false,
                     cost_by_skill: { 'choose_skill' => { calls: 4, usd: 1.0 } }, decisions_by_agent: { 'claude' => 4, 'start_game' => 1 },
                     usage: { goal_changes: 0, leads: { high: 0, normal: 0, low: 0 }, lead_rejected: 0, objectives_by_kind: { 'unknown' => 2 },
                              because_used: 0, talks: 0, talks_to_known: 0, dialogues: 0 } },
                   Koholint::Summary.record(run.dir))
    end
  end

  def test_write_stores_the_record_and_sees_a_star
    with_run do |run|
      File.write(File.join(run.dir, 'star.json'), '{}')
      Koholint::Summary.write(run.dir)
      summary = JSON.parse(File.read(File.join(run.dir, 'summary.json')))
      assert_equal [true, 0, nil, nil], summary.values_at('starred', 'calls', 'calls_per_1000f', 'stop_reason')
      assert_equal({ 'median' => nil, 'p90' => nil }, summary['latency_ms'])
    end
  end

  def talk(trace, frame, room, row, col)
    trace.emit(:action, frame:, skill: 'talk_to', params: { row:, col: }, result: { from: { room:, map: 16 } })
  end

  def test_record_measures_cost_by_skill_free_decisions_and_feature_usage
    with_run do |run|
      t = run.trace
      t.emit(:decision, frame: 0, decision_point: 'choose_objective', input: {}, options: [], choice: { title: 'x' }, justification: 'j',
                        confidence: 1.0, agent: 'claude', latency_ms: 5, cost_usd: 0.1)
      decide(t, 1, 'claude', 5, 0.2, choice: { skill: 'walk', params: {} })
      decide(t, 2, 'claude', 5, 0.3, choice: { skill: 'walk', params: {} })
      decide(t, 3, 'delegated', 0, 0.0, choice: { skill: 'advance_dialogue', params: {} })
      decide(t, 4, 'start_game', 0, 0.0)
      t.emit(:goal, frame: 5, text: 'a')
      t.emit(:goal, frame: 6, text: 'b')
      t.emit(:goal, frame: 7, text: 'c')
      t.emit(:lead, frame: 8, id: 'lead-1', place: [1, 16], source: nil, quote: 'q', claim: 'c', importance: 'high')
      t.emit(:lead, frame: 8, id: 'lead-2', place: [1, 16], source: nil, quote: 'q', claim: 'c', importance: 'normal')
      t.emit(:notable, frame: 8, kind: 'lead_rejected', detail: '1 leads')
      t.emit(:objective, frame: 9, id: 'obj-1', status: 'started', predicate: { kind: 'dialogue_closed' }, because: 'lead-1')
      t.emit(:objective, frame: 9, id: 'obj-1', status: 'achieved', predicate: { kind: 'dialogue_closed' })
      t.emit(:objective, frame: 9, id: 'obj-2', status: 'started', predicate: { kind: 'dialogue_closed' })
      talk(t, 10, 1, 2, 3)
      talk(t, 11, 1, 2, 3)
      talk(t, 12, 2, 2, 3)
      talk(t, 13, 1, 2, 4)
      t.emit(:dialogue, frame: 14, place: [1, 16], text: 'a', source: 'agent', page: 1)
      t.emit(:dialogue, frame: 14, place: [1, 16], text: 'b', source: 'agent', page: 2)
      t.emit(:dialogue, frame: 15, place: [1, 16], text: 'c', source: 'agent', page: 1)
      record = Koholint::Summary.record(run.dir)
      assert_equal({ 'choose_objective' => { calls: 1, usd: 0.1 }, 'walk' => { calls: 2, usd: 0.5 } }, record[:cost_by_skill])
      assert_equal({ 'claude' => 3, 'delegated' => 1, 'start_game' => 1 }, record[:decisions_by_agent])
      assert_equal({ goal_changes: 2, leads: { high: 1, normal: 1, low: 0 }, lead_rejected: 1, objectives_by_kind: { 'dialogue_closed' => 2 },
                     because_used: 1, talks: 4, talks_to_known: 1, dialogues: 2 }, record[:usage])
    end
  end

  def test_diagnostic_notables_are_not_progress
    %w[grid_overlay_stuck lead_rejected unknown_mode].each { |kind| refute Koholint::Summary.progress?({ 'type' => 'notable', 'kind' => kind }), kind }
    assert Koholint::Summary.progress?({ 'type' => 'notable', 'kind' => 'other' })
  end
end
