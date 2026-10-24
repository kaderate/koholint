require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/trace'
require 'koholint/viewer/feed'

class InsightsTest < Minitest::Test
  Follower = Struct.new(:frame, :journal_frames, :lag, :sync)
  Insights = Koholint::Viewer::Insights
  PLAY = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'none', 'game_mode' => 0x0B, 'game_submode' => 7, 'x' => 80, 'y' => 72 }.freeze

  def with_dir
    Dir.mktmpdir('run-i') do |dir|
      File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'f', 'status' => 'running'))
      yield dir, Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    end
  end

  def seen(trace, frame, room, map = 0) = trace.emit(:perception, frame:, state: PLAY.merge('room_id' => room, 'map_id' => map), state_hash: 'h')

  def walk(trace, frame, from, to, at)
    trace.emit(:action, frame:, skill: 'explore', params: {}, result: { 'from' => { 'room' => from, 'map' => 0, 'x' => 80, 'y' => 72 },
                                                                       'to' => { 'room' => to, 'map' => 0, 'x' => at[0], 'y' => at[1] },
                                                                       'stopped_by' => 'new_place' })
  end

  def screen(trace, frame, place, name = 'a1')
    trace.emit(:screen, frame:, place:, terrain_hash: 't', objects_hash: 'o', grid: Array.new(8) { Array.new(10, name) }, static_sprites: [])
  end

  def test_the_map_has_one_node_per_place_in_visit_order_with_links_and_coverage
    with_dir do |dir, trace|
      seen(trace, 10, 5)
      screen(trace, 10, [5, 0])
      trace.emit(:affordance, frame: 11, appearance: 'a1', action: 'walk', direction: 'up', result: 'yes', method: 'hold', context: [], source: 'probe')
      walk(trace, 20, 5, 6, [4, 80])
      seen(trace, 21, 6)
      walk(trace, 30, 6, 5, [155, 80])
      seen(trace, 31, 5)
      walk(trace, 40, 5, 7, [80, 131])
      trace.emit(:lead, frame: 41, id: 'lead-1', place: [7, 0], source: nil, quote: 'q', claim: 'go <b>north</b>', importance: 'high')
      map = Koholint::Viewer::Feed.insight(:map, dir, Follower.new(100, 100, 0, :in_sync))
      assert_equal [[5, 0], [6, 0], [7, 0]], map[:places].map { |n| n[:place] }
      assert_equal [1, 2, 3], map[:places].map { |n| n[:order] }
      assert_equal [7, 0], map[:current]
      assert_equal [false, false, true], map[:places].map { |n| n[:current] }
      assert_equal [[0, 0], [1, 0], [2, 0]], map[:places].map { |n| [n[:x], n[:y]] }
      assert_equal [[5, 0], [6, 0], [7, 0]], map[:places].map { |n| n[:cell] }
      assert_equal %w[world world world], map[:places].map { |n| n[:kind] }
      assert_equal [100, nil, nil], map[:places].map { |n| n[:coverage] }
      assert_equal 'yes', map[:places].first[:cells][0][0]
      assert_equal [{ a: [5, 0], b: [6, 0], count: 2, first_frame: 20 }, { a: [5, 0], b: [7, 0], count: 1, first_frame: 40 }], map[:links]
      assert_equal [{ id: 'lead-1', importance: 'high', claim: 'go <b>north</b>' }], map[:places].last[:leads]
    end
  end

  def test_the_map_flags_the_places_that_have_a_screenshot_and_refreshes_when_one_appears
    with_dir do |dir, trace|
      seen(trace, 10, 5)
      walk(trace, 20, 5, 6, [4, 80])
      seen(trace, 21, 6)
      follower = Follower.new(100, 100, 0, :in_sync)
      assert_equal [false, false], Koholint::Viewer::Feed.insight(:map, dir, follower)[:places].map { |n| n[:screenshot] }
      FileUtils.mkdir_p(File.join(dir, 'screens'))
      File.binwrite(File.join(dir, 'screens', '6-0.png'), 'png')
      assert_equal [false, true], Koholint::Viewer::Feed.insight(:map, dir, follower)[:places].map { |n| n[:screenshot] }
    end
  end

  def test_the_map_follows_the_shown_frame
    with_dir do |dir, trace|
      seen(trace, 10, 5)
      walk(trace, 20, 5, 6, [4, 80])
      early = Koholint::Viewer::Feed.insight(:map, dir, Follower.new(15, 100, 0, :in_sync))
      assert_equal [[5, 0]], early[:places].map { |n| n[:place] }
      late = Koholint::Viewer::Feed.insight(:map, dir, Follower.new(25, 100, 0, :in_sync))
      assert_equal [[5, 0], [6, 0]], late[:places].map { |n| n[:place] }
      assert_same late, Koholint::Viewer::Feed.insight(:map, dir, Follower.new(99, 100, 0, :in_sync))
    end
  end

  def test_world_places_sit_on_the_room_grid_and_interiors_hang_under_their_door
    house = [163, 16]
    other = [167, 16]
    order = [house, [162, 0], [163, 0], [179, 0], [146, 0], other, [9, 99]]
    moves = [{ from: house, to: [162, 0] }, { from: [162, 0], to: [163, 0] }, { from: [163, 0], to: [179, 0] }, { from: [179, 0], to: [163, 0] },
             { from: [162, 0], to: [146, 0] }, { from: [146, 0], to: other }, { from: other, to: [146, 0] }, { from: [146, 0], to: [9, 99] }]
    placed = Insights.layout(order, moves)
    spots = placed[:spots]
    assert_equal [0, 1], spots[[162, 0]]
    assert_equal [1, 1], spots[[163, 0]]
    assert_equal [1, 2], spots[[179, 0]]
    assert_equal [0, 0], spots[[146, 0]]
    assert_equal 4, placed[:lane]
    assert_equal [[0, 4], [0, 5], [0, 6]], [spots[house], spots[other], spots[[9, 99]]]
    assert_equal({ house => [162, 0], other => [146, 0], [9, 99] => [146, 0] }, placed[:parents])
    assert_equal %w[interior world other], [house, [162, 0], [9, 99]].map { |p| Koholint::PlaceKinds.kind(p) }
    assert_equal({ spots: {}, parents: {}, lane: nil, width: 0 }, Insights.layout([], []))
  end

  def test_people_and_dialogues_carry_the_npc_state
    with_dir do |dir, trace|
      seen(trace, 1, 5)
      talk = ->(frame, text) do
        trace.emit(:action, frame:, skill: 'talk_to', params: { 'row' => 2, 'col' => 3 },
                            result: { 'talked' => true, 'stopped_by' => 'done', 'from' => { 'room' => 5, 'map' => 0, 'x' => 80, 'y' => 72 } })
        trace.emit(:dialogue, frame:, place: [5, 0], text:, source: 'agent', page: 1)
      end
      talk.call(10, 'Hello there.')
      talk.call(20, 'Hello there.')
      talk.call(30, 'Hello there.')
      dialogues = Koholint::Viewer::Feed.for(dir, Follower.new(100, 100, 0, :in_sync))[:dialogues]
      assert_equal [{ talk: 3, new_text: false, state: 'exhausted' }, { talk: 2, new_text: false, state: nil }, { talk: 1, new_text: true, state: nil }],
                   dialogues.map { |d| d[:npc] }
      person = Koholint::Viewer::Feed.insight(:map, dir, Follower.new(100, 100, 0, :in_sync))[:places].first[:people]
      assert_equal [{ row: 2, col: 3, attempts: 3, texts: 3, state: 'exhausted', last_frame: 30 }], person
      seen(trace, 40, 6)
      assert_equal 'worth retrying: something changed since', Koholint::Viewer::Feed.for(dir, Follower.new(100, 100, 0, :in_sync))[:dialogues].first[:npc][:state]
    end
  end

  def test_timeline_markers_cover_the_run_and_carry_their_kind
    with_dir do |dir, trace|
      seen(trace, 1, 5)
      trace.emit(:objective, frame: 2, id: 'obj-1', status: 'started', title: 'Leave', predicate: { kind: 'new_place' })
      trace.emit(:decision, frame: 3, decision_point: 'act', input: {}, options: [], choice: { 'skill' => 'explore', 'params' => {} },
                            justification: 'look <b>around</b>', confidence: 1, agent: 'claude', latency_ms: 5, cost_usd: 0.02)
      walk(trace, 4, 5, 6, [4, 80])
      trace.emit(:notable, frame: 5, kind: 'unknown_mode', detail: 'game_mode=9')
      trace.emit(:stop, frame: 6, reason: 'unknown_mode_stuck')
      timeline = Koholint::Viewer::Feed.insight(:timeline, dir, Follower.new(1, 50, 0, :in_sync))
      assert_equal 50, timeline[:frames]
      assert_equal %w[objective call place explore notable stop], timeline[:markers].map { |m| m[:kind] }
      call = timeline[:markers].find { |m| m[:kind] == 'call' }
      assert_equal ['explore', 'explore $0.0200: look <b>around</b>', 1], call.values_at(:skill, :label, :count)
      assert_equal 'objective started: Leave', timeline[:markers].first[:label]
    end
  end

  def test_timeline_markers_are_clustered_past_the_limit
    trace = (1..2000).map { |i| { 'type' => 'lead', 'frame' => i * 10, 'importance' => 'low', 'claim' => 'x' * 400 } }
    timeline = Insights.timeline(trace, frames: 20_000)
    assert_operator timeline[:markers].size, :<=, Insights::MARKERS
    assert_equal 2000, timeline[:markers].sum { |m| m[:count] }
    assert_equal 2000, timeline[:total]
    assert(timeline[:markers].all? { |m| m[:label].length <= Insights::LABEL })
    assert_equal timeline[:markers].map { |m| m[:frame] }.sort, timeline[:markers].map { |m| m[:frame] }
  end

  def test_cost_series_is_cumulative_by_model_call_and_bounded
    decision = ->(frame, agent, cost, skill) { { 'type' => 'decision', 'frame' => frame, 'agent' => agent, 'cost_usd' => cost, 'prompt_sha' => 'x', 'choice' => { 'skill' => skill } } }
    trace = [decision.call(10, 'claude', 0.5, 'walk'), decision.call(20, 'start_game', 0, nil), decision.call(30, 'claude', 0.25, 'talk_to')]
    cost = Insights.cost(trace)
    assert_equal [[0, 0.0], [10, 0.5], [30, 0.75]], cost[:series]
    assert_equal({ 'talk_to' => { calls: 1, usd: 0.25 }, 'walk' => { calls: 1, usd: 0.5 } }, cost[:by_skill])
    assert_equal({ paid: 2, free: 1 }, cost[:decisions])
    many = (1..1000).map { |i| decision.call(i, 'claude', 0.001, 'walk') }
    series = Insights.cost(many)[:series]
    assert_equal Insights::SERIES, series.size
    assert_equal [1000, 1.0], series.last
    stats = Insights.stats(trace)
    assert_equal %i[goal_changes leads lead_rejected objectives_by_kind because_used talks talks_to_known dialogues not_ready_frames not_ready_waits], stats[:usage].keys
  end

  def test_mode_and_alerts_come_from_the_shown_trace
    trace = [{ 'type' => 'perception', 'frame' => 1, 'state' => PLAY }]
    assert_equal({ phase: 'playing', name: 'play', frame: 1 }, Insights.mode(trace).slice(:phase, :name, :frame))
    assert_equal({ phase: 'unknown', name: nil }, Insights.mode([]))
    assert_equal 'unknown', Insights.mode([{ 'type' => 'perception', 'frame' => 1, 'state' => { 'game_mode' => [] } }])[:phase]
    trace += [{ 'type' => 'notable', 'frame' => 2, 'kind' => 'unknown_mode', 'detail' => 'game_mode=9' },
              { 'type' => 'notable', 'frame' => 3, 'kind' => 'lead_rejected', 'detail' => 'x' },
              { 'type' => 'stop', 'frame' => 4, 'reason' => 'stuck_boot' }]
    assert_equal [{ kind: 'unknown_mode', frame: 2, detail: 'game_mode=9' }, { kind: 'stuck_boot', frame: 4, detail: 'run stopped: stuck_boot' }], Insights.alerts(trace)
  end
end
