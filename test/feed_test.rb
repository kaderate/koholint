require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
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
    trace.emit(:decision, frame:, decision_point: 'move', input: {}, options: [], choice: { 'to' => frame }, justification: 'j',
                          confidence: 0.5, agent: 'a', latency_ms: 1, cost_usd: 0.1)
  end

  def test_document_has_status_replay_and_events
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 1, state: STATE, state_hash: 'h')
      decision(trace, 2)
      trace.emit(:action, frame: 3, skill: 'walk', params: { 'dir' => 'up' }, result: {})
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal %i[status replay events grid activity server_now latency budget], doc.keys
      assert_equal File.basename(dir), doc[:status][:run_id]
      assert_equal({ flow_version: 'f', manifest_status: 'running', budget: { 'frames' => 9 }, health: 'unknown',
                     hearts: 2.0, max_hearts: 3.0, objective: nil, last_notable: nil, highest_milestone: 'none',
                     frames: 3, cost_usd: 0.1, calls: 1, objective_title: nil, objective_predicate: nil, objective_attempts: nil, goal: nil, leads: [], run_id: File.basename(dir) }, doc[:status])
      assert_equal({ frame: 90, journal_frames: 100, lag: 10, sync: :in_sync }, doc[:replay])
      assert_equal [{ frame: 2, type: 'decision', decision_point: 'move', agent: 'a', choice: { 'to' => 2 }, confidence: 0.5,
                      justification: 'j' },
                    { frame: 3, type: 'action', skill: 'walk', params: { 'dir' => 'up' }, result: {} }], doc[:events]
    end
  end

  def test_upto_shows_the_run_as_it_was_at_the_follower_frame
    with_dir do |dir, trace|
      decision(trace, 2)
      decision(trace, 50)
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER, upto: 10)
      assert_equal [2], doc[:events].map { |e| e[:frame] }
      assert_equal [1, 0.1], doc[:budget].values_at(:calls, :spent)
      assert_equal 2, Koholint::Viewer::Feed.for(dir, FOLLOWER)[:events].size
    end
  end

  def test_goal_and_leads_follow_the_shown_frame_and_skip_low_leads
    with_dir do |dir, trace|
      lead = ->(frame, id, importance) { trace.emit(:lead, frame:, id:, place: [1, 2], source: nil, quote: 'q', claim: "c #{id}", importance:) }
      trace.emit(:goal, frame: 5, text: 'first')
      lead.call(5, 'lead-1', 'high')
      lead.call(6, 'lead-2', 'low')
      lead.call(7, 'lead-3', 'normal')
      trace.emit(:goal, frame: 20, text: 'second')
      lead.call(20, 'lead-4', 'high')
      early = Koholint::Viewer::Feed.for(dir, FOLLOWER, upto: 10)[:status]
      assert_equal 'first', early[:goal]
      assert_equal [{ id: 'lead-3', importance: 'normal', claim: 'c lead-3' }, { id: 'lead-1', importance: 'high', claim: 'c lead-1' }], early[:leads]
      late = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status]
      assert_equal ['second', %w[lead-4 lead-3 lead-1]], [late[:goal], late[:leads].map { |l| l[:id] }]
    end
  end

  def test_objective_calls_and_dollars_come_from_the_trace
    with_dir do |dir, trace|
      trace.emit(:decision, frame: 1, decision_point: 'boot', input: {}, options: [], choice: {}, justification: 'boot script', confidence: 1.0,
                            agent: 'start_game', latency_ms: 0, cost_usd: 0.0)
      trace.emit(:objective, frame: 2, id: 'o1', status: 'started', predicate: { kind: 'leave_place' }, title: 'Go out')
      trace.emit(:decision, frame: 3, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                            agent: 'claude', latency_ms: 5, cost_usd: 0.25, fallback: true)
      trace.emit(:decision, frame: 4, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                            agent: 'claude', latency_ms: 5, cost_usd: 0.5)
      File.open(File.join(dir, 'trace.jsonl'), 'a') do |file|
        file.puts(JSON.generate(v: 1, type: 'dialogue', frame: 5, place: [1, 2], text: 'Hi', source: 'agent', page: 0))
      end
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal ['o1', 'Go out', 2, 0.75], doc[:status].values_at(:objective, :objective_title, :calls, :cost_usd)
      assert_equal [true, nil], doc[:events].select { |e| e[:agent] == 'claude' }.map { |e| e[:fallback] }
      assert_equal({ frame: 2, type: 'objective', id: 'o1', status: 'started', predicate: { 'kind' => 'leave_place' }, title: 'Go out' },
                   doc[:events].find { |e| e[:type] == 'objective' })
      assert_equal({ frame: 5, type: 'dialogue', place: [1, 2], text: 'Hi', source: 'agent', page: 0 },
                   doc[:events].find { |e| e[:type] == 'dialogue' })
      trace.emit(:objective, frame: 6, id: 'o1', status: 'achieved', predicate: {})
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:objective]
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:objective_title]
    end
  end

  def test_objective_title_falls_back_to_the_id
    with_dir do |dir, trace|
      trace.emit(:objective, frame: 2, id: 'o9', status: 'started', predicate: {})
      assert_equal %w[o9 o9], Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status].values_at(:objective, :objective_title)
    end
  end

  def test_deterministic_agents_are_not_counted_as_calls
    with_dir do |dir, trace|
      %w[start_game walk_and_talk claude other].each_with_index do |agent, i|
        trace.emit(:decision, frame: i, decision_point: 'move', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                              agent:, latency_ms: 0, cost_usd: 0.0)
      end
      assert_equal 2, Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:calls]
    end
  end

  def test_locked_waits_are_not_counted_as_calls_nor_as_attempts
    with_dir do |dir, trace|
      trace.emit(:decision, frame: 1, decision_point: 'choose_skill', input: {}, options: [], choice: { skill: 'wait', params: { frames: 30 } },
                            justification: 'locked: waiting for Link to be free', confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0)
      assert_equal 0, Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:calls]
    end
  end

  def test_free_delegated_decisions_are_not_counted_as_calls
    with_dir do |dir, trace|
      emit = ->(frame, **extra) { trace.emit(:decision, frame:, decision_point: 'move', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0, agent: 'delegated', latency_ms: 0, **extra) }
      emit.call(1, cost_usd: 0.0)
      emit.call(2, cost_usd: 0.0)
      emit.call(3, cost_usd: 0.05)
      emit.call(4, cost_usd: 0.0, prompt_sha: 'a' * 64, image: false)
      assert_equal 2, Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status][:calls]
    end
  end

  def test_events_are_capped_to_the_latest_in_order
    with_dir do |dir, trace|
      5.times { |i| decision(trace, i) }
      assert_equal [2, 3, 4], Koholint::Viewer::Feed.for(dir, FOLLOWER, limit: 3)[:events].map { |e| e[:frame] }
    end

    def test_the_feed_keeps_the_last_300_events_by_default
      Dir.mktmpdir do |dir|
        trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
        350.times { |frame| trace.emit(:decision, frame:, decision_point: 'move', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0, agent: 'x', latency_ms: 0, cost_usd: 0.0, fallback: false) }
        frames = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:events].map { |e| e[:frame] }
        assert_equal 300, frames.size
        assert_equal [50, 349], [frames.first, frames.last]
      end
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

  def test_a_diagnostic_notable_keeps_health_unknown
    with_dir do |dir, trace|
      trace.emit(:notable, frame: 10, kind: 'grid_overlay_stuck', detail: [1, 2])
      trace.emit(:perception, frame: 4000, state: STATE, state_hash: 'h')
      status = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status]
      assert_equal 'unknown', status[:health]
      assert_nil status[:last_notable]
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

  def screen_event(trace, frame, place: [163, 16], name: 'a1')
    trace.emit(:screen, frame:, place:, terrain_hash: "t#{frame}", objects_hash: 'o', grid: Array.new(8) { Array.new(10) { name } },
                        static_sprites: [])
  end

  def affordance_event(trace, frame, appearance, direction, result)
    trace.emit(:affordance, frame:, appearance:, action: 'walk', direction:, result:, method: 'probe', context: [], source: 'test')
  end

  def test_grid_is_nil_before_any_screen_event
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 1, state: STATE, state_hash: 'h')
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid]
    end
  end

  def test_grid_is_nil_when_the_only_screen_is_after_the_follower
    with_dir do |dir, trace|
      screen_event(trace, 95)
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid]
    end
  end

  def test_grid_cells_follow_the_four_direction_beliefs
    with_dir do |dir, trace|
      screen_event(trace, 10, name: 'a1')
      { 'up' => 'yes', 'down' => 'yes' }.each { |d, r| affordance_event(trace, 20, 'a1', d, r) }
      grid = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid]
      assert_equal [163, 16], grid[:place]
      assert_equal 10, grid[:frame]
      assert_equal(['yes'] * 10, grid[:cells][3])
      assert_equal 'a1', grid[:appearances][0][0]
      assert_equal [8, 10], [grid[:cells].size, grid[:cells][0].size]
    end
  end

  def test_cell_states
    with_dir do |dir, trace|
      names = %w[y n m s u]
      trace.emit(:screen, frame: 10, place: [1, 1], terrain_hash: 't', objects_hash: 'o',
                          grid: Array.new(8) { Array.new(10) { |c| names[c % 5] } }, static_sprites: [])
      affordance_event(trace, 11, 'y', 'up', 'yes')
      affordance_event(trace, 11, 'n', 'down', 'no')
      affordance_event(trace, 11, 'm', 'up', 'yes')
      affordance_event(trace, 11, 'm', 'left', 'no')
      trace.emit(:affordance, frame: 12, appearance: 's', action: 'walk', direction: 'up', result: 'no', method: 'probe',
                              context: ['swim'], source: 'test')
      row = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid][:cells][0]
      assert_equal %w[yes no mixed stale unknown], row.first(5)
    end
  end

  def test_link_cell_comes_from_the_latest_perception_at_the_follower_frame
    with_dir do |dir, trace|
      screen_event(trace, 10)
      trace.emit(:perception, frame: 20, state: STATE.merge('x' => 40, 'y' => 40), state_hash: 'h')
      trace.emit(:perception, frame: 80, state: STATE.merge('x' => 100, 'y' => 72), state_hash: 'h')
      trace.emit(:perception, frame: 95, state: STATE.merge('x' => 0, 'y' => 8), state_hash: 'h')
      assert_equal({ row: 4, col: 6 }, Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid][:link])
      early = Koholint::Viewer::Feed.for(dir, Follower.new(30, 100, 0, :in_sync))[:grid][:link]
      assert_equal({ row: 2, col: 2 }, early)
    end
  end

  def test_link_is_nil_off_grid_or_without_perception
    with_dir do |dir, trace|
      screen_event(trace, 10)
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid][:link]
      trace.emit(:perception, frame: 20, state: STATE.merge('x' => 200, 'y' => 8), state_hash: 'h')
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid][:link]
    end
  end

  def test_an_earlier_follower_frame_gets_the_older_grid
    with_dir do |dir, trace|
      screen_event(trace, 10, place: [1, 1], name: 'old')
      screen_event(trace, 80, place: [2, 2], name: 'new')
      assert_equal [2, 2], Koholint::Viewer::Feed.for(dir, FOLLOWER)[:grid][:place]
      older = Koholint::Viewer::Feed.for(dir, Follower.new(50, 100, 0, :in_sync))[:grid]
      assert_equal [[1, 1], 10, 'old'], [older[:place], older[:frame], older[:appearances][0][0]]
      assert_nil Koholint::Viewer::Feed.for(dir, Follower.new(5, 100, 0, :in_sync))[:grid]
    end
  end

  def count_world_events
    counts = []
    world = Koholint::Vision::World
    original = world.method(:new)
    world.define_singleton_method(:new) { |events, *rest| original.call(events, *rest).tap { counts << events.size } }
    yield
    counts
  ensure
    world.singleton_class.send(:remove_method, :new)
  end

  def test_the_grid_work_does_not_scale_with_unrelated_events
    with_dir do |dir, trace|
      screen_event(trace, 10)
      affordance_event(trace, 20, 'a1', 'up', 'yes')
      screen_event(trace, 30)
      File.open(File.join(dir, 'trace.jsonl'), 'a') do |file|
        10_000.times { |i| file.puts(JSON.generate(v: 1, type: 'action', frame: 40 + (i % 40), skill: 'press', params: {}, result: {})) }
      end
      counts = count_world_events { Koholint::Viewer::Feed.for(dir, FOLLOWER) }
      assert_equal [3], counts
    end
  end

  def test_caches_stay_bounded_across_many_run_dirs
    dirs = Array.new(Koholint::Viewer::Feed::MAX_RUNS + 3) do
      Dir.mktmpdir('run-x').tap do |dir|
        File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'f'))
        screen_event(Koholint::Trace.new(File.join(dir, 'trace.jsonl')), 10)
        Koholint::Viewer::Feed.for(dir, FOLLOWER)
      end
    end
    assert_operator Koholint::Viewer::Feed::CACHE.size, :<=, Koholint::Viewer::Feed::MAX_RUNS
    assert_operator Koholint::Viewer::Feed::GRID_CACHE.size, :<=, Koholint::Viewer::Feed::MAX_RUNS
    assert_equal [163, 16], Koholint::Viewer::Feed.for(dirs.last, FOLLOWER)[:grid][:place]
  ensure
    dirs&.each { |dir| FileUtils.remove_entry(dir) }
  end

  def test_malformed_events_never_take_the_grid_down
    good = { 'type' => 'screen', 'frame' => 10, 'place' => [163, 16], 'grid' => Array.new(8) { Array.new(10) { 'a1' } }, 'static_sprites' => [] }
    bad = [{ 'type' => 'screen', 'place' => [1, 1], 'grid' => [] }, { 'type' => 'screen', 'frame' => '5', 'place' => [1, 1], 'grid' => [] },
           { 'type' => 'screen', 'frame' => 20, 'place' => nil, 'grid' => nil }, { 'type' => 'perception', 'state' => { 'x' => 40, 'y' => 40 } },
           { 'type' => 'perception', 'frame' => 'x', 'state' => {} }, { 'type' => 'perception', 'frame' => 30, 'state' => 'bad' },
           { 'type' => 'affordance', 'frame' => nil, 'appearance' => 'a1' },
           { 'type' => 'affordance', 'frame' => 5, 'appearance' => 'a1', 'action' => 'walk', 'direction' => 'north', 'result' => 'yes' },
           { 'type' => 'affordance', 'frame' => 'z', 'action' => 'walk', 'result' => 'yes' }]
    bad += [{ 'type' => 'affordance', 'frame' => 6, 'appearance' => 'a1', 'action' => 'walk', 'result' => 'yes', 'context' => 'swim' },
            good.merge('frame' => 11, 'grid' => Array.new(8) { Array.new(9) { 'a1' } }),
            good.merge('frame' => 12, 'grid' => Array.new(8) { 'row' }),
            good.merge('frame' => 13, 'static_sprites' => 'x'),
            good.merge('frame' => 14, 'static_sprites' => [{ 'x' => 'a', 'y' => 1 }]),
            good.merge('frame' => 15, 'static_sprites' => [5])]
    grid = Koholint::Viewer::Feed.grid('/nonexistent-malformed', [good, *bad], 90)
    assert_equal [[163, 16], 10], [grid[:place], grid[:frame]]
    assert_nil grid[:link]
  end

  def test_a_screen_without_a_place_gives_no_grid
    screen = { 'type' => 'screen', 'frame' => 10, 'place' => nil, 'grid' => [], 'static_sprites' => [] }
    assert_nil Koholint::Viewer::Feed.grid('/nonexistent-no-place', [screen], 90)
  end

  def test_activity_is_parsed_and_tolerates_a_missing_or_garbled_file
    with_dir do |dir, trace|
      trace.emit(:perception, frame: 1, state: STATE, state_hash: 'h')
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:activity]
      File.write(File.join(dir, 'activity.json'), '{"kind":"deciding","labe')
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:activity]
      File.write(File.join(dir, 'activity.json'), '[1]')
      assert_nil Koholint::Viewer::Feed.for(dir, FOLLOWER)[:activity]
      File.write(File.join(dir, 'activity.json'), JSON.generate(kind: 'deciding', label: 'x', started_at: 1.5))
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal 'deciding', doc[:activity]['kind']
      assert_kind_of Float, doc[:server_now]
    end
  end

  def test_latency_and_budget_come_from_model_decisions
    manifest = { 'flow_version' => 'f', 'status' => 'running', 'budget' => { 'dollars' => 2.0 } }
    with_dir(manifest:) do |dir, trace|
      [1000, 2000, 3000, 4000, 10_000].each_with_index do |ms, i|
        trace.emit(:decision, frame: i + 1, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                              agent: 'claude', latency_ms: ms, cost_usd: 0.1)
      end
      trace.emit(:decision, frame: 9, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'auto', confidence: 1.0,
                            agent: 'delegated', latency_ms: 0, cost_usd: 0.0)
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal({ last_ms: 10_000, median_ms: 3000, p90_ms: 10_000, count: 5 }, doc[:latency])
      assert_equal 2.0, doc[:budget][:cap]
      assert_in_delta 0.5, doc[:budget][:spent]
      assert_equal 5, doc[:budget][:calls]
    end
  end

  def test_latency_is_empty_and_budget_has_no_cap_without_data
    with_dir do |dir, _trace|
      doc = Koholint::Viewer::Feed.for(dir, FOLLOWER)
      assert_equal({ last_ms: nil, median_ms: nil, p90_ms: nil, count: 0 }, doc[:latency])
      assert_nil doc[:budget][:cap]
    end
  end

  def test_objective_attempts_count_manual_skill_calls_over_the_whole_trace
    with_dir do |dir, trace|
      trace.emit(:objective, frame: 1, id: 'o1', status: 'started', predicate: { kind: 'leave_place' }, title: 'Go out')
      400.times do |i|
        auto = i.even?
        trace.emit(:decision, frame: 2 + i * 2, decision_point: 'choose_skill', input: {}, options: [], choice: {},
                              justification: auto ? 'automatic dialogue advance' : 'j', confidence: 1.0, agent: auto ? 'delegated' : 'claude', latency_ms: 0, cost_usd: 0.0)
        trace.emit(:action, frame: 3 + i * 2, skill: 'walk', params: {}, result: {})
      end
      status = Koholint::Viewer::Feed.for(dir, FOLLOWER)[:status]
      assert_equal 200, status[:objective_attempts]
      assert_equal({ 'kind' => 'leave_place' }, status[:objective_predicate])
    end
  end

  def test_an_archived_run_is_read_from_the_gzipped_trace
    with_dir do |dir, trace|
      decision(trace, 2)
      path = File.join(dir, 'trace.jsonl')
      Koholint::Trace.compress(path)
      File.delete(path)
      assert_equal [2], Koholint::Viewer::Feed.for(dir, FOLLOWER)[:events].map { |e| e[:frame] }
    end
  end
end
