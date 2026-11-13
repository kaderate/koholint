require_relative 'support/delegated_helpers'

class DelegatedAutopilotTest < Minitest::Test
  include DelegatedHelpers

  def new_place = ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' })
  def explore = ok('skill' => 'explore', 'params' => { 'direction' => 'up' })

  def autopiloted(client, autopilot: Koholint::Autopilot.new, revisit: nil)
    @objectives = Koholint::Objectives.new(trace: trace)
    Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', autopilot:, revisit:)
  end

  def outcome(stop, frame) = { skill: 'explore', params: {}, stopped_by: stop, moved_cells: 2, cells_walked: 2, place_changed: false, room_changed: false,
                               hp_delta: 0, from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 3, col: 4 + frame % 3 },
                               blocked_edges: [], exits: [], offered: [] }

  def tours(policy, count, stop: :budget, start: 100)
    results = []
    count.times do |i|
      frame = start + i * 300
      now = state(frame:, x: 40 + 16 * (i % 5))
      policy.observe(now, frame:)
      point = policy.decision_point_for(now)
      result = policy.decide(point, now, { grid: })
      results << result
      next unless point.name == :choose_skill

      policy.after_action(choice: result[:choice], outcome: outcome(stop, frame), state: state(frame: frame + 290, x: 40 + 16 * (i % 5)), frame: frame + 290)
    end
    results
  end

  def test_benign_explore_stops_are_continued_for_free_and_paid_calls_drop
    on = ScriptedClient.new(objective: new_place, default: explore)
    results = tours(autopiloted(on), 9)
    off = ScriptedClient.new(objective: new_place, default: explore)
    tours(autopiloted(off, autopilot: nil), 9)
    assert_equal 9, off.calls.size
    assert_equal 3, on.calls.size
    free = results.select { |r| r[:autopilot] }
    assert_equal 6, free.size
    assert(free.all? { |r| r[:choice] == { skill: 'explore', params: {} } && r[:cost_usd].zero? && r[:agent] == 'delegated' && r[:prompt].nil? })
    assert_equal 'claude', results[8][:agent]
    assert_equal 8, @objectives.current[:attempts].size
  end

  def test_an_autopilot_explore_still_completes_a_new_place_objective_and_the_model_picks_the_next
    client = ScriptedClient.new(objective: [new_place] * 2, default: explore)
    p = autopiloted(client)
    assert tours(p, 3).last[:autopilot]
    assert_equal 2, client.calls.size
    p.observe(state(frame: 2000, room_id: 7), frame: 2000)
    assert_equal :achieved, @objectives.history.last[:outcome]
    point = p.decision_point_for(state(frame: 2010, room_id: 7))
    assert_equal :choose_objective, point.name
    refute p.decide(point, state(frame: 2010, room_id: 7), { grid: })[:autopilot]
    assert_equal 3, client.calls.size
  end

  def lap(policy, now, stop, ctx: { grid: }, to: { room: 163, map: 16, row: 3, col: 4 })
    policy.observe(now, frame: now.frame)
    result = policy.decide(policy.decision_point_for(now), now, ctx)
    policy.after_action(choice: result[:choice], outcome: outcome(stop, now.frame).merge(to:), state: now, frame: now.frame + 20)
    result
  end

  def test_at_one_heart_of_six_the_autopilot_keeps_going_and_no_shelter_is_offered
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    p.instance_variable_get(:@explore_log).absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :up, outcome: :left, to: [166, 16] }] })
    results = (0..3).map { |i| lap(p, state(frame: 100 + (i * 300), room_id: 1, map_id: 0, hp: 4), :known_place, to: { room: 1, map: 0, row: 3, col: 4 }) }
    assert(results.any? { |r| r[:autopilot] })
    refute_includes client.calls.map { |c| c[:prompt] }.join, 'LOW HEALTH'
  end

  def test_six_fruitless_results_in_one_place_emit_stuck_and_a_reset_hint
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = policy(client)
    results = (0..8).map { |i| lap(p, state(frame: 100 + (i * 50)), i.even? ? :no_frontier : :no_path) }
    stuck = results.flat_map { |r| Array(r[:notables]) }.select { |note| note[:kind] == 'stuck' }
    assert_equal ['6 results in 163-16 without a new cell (1 times here)'], stuck.map { |note| note[:detail] }
    assert_includes client.calls.last[:prompt], 'STUCK: 6 results in a row here'
    refute_includes client.calls[7][:prompt], 'STUCK'
    lap(p, state(frame: 900), :done, to: { room: 163, map: 16, row: 5, col: 5 })
    lap(p, state(frame: 950), :no_path)
    refute_includes client.calls.last[:prompt], 'STUCK'
  end

  def test_a_place_objective_shows_its_known_route_and_aims_a_model_explore_with_no_direction
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [147, 16] }] })
    log.absorb({ from: { room: 147, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [146, 16] }] })
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [146, 16]), default: ok('skill' => 'explore', 'params' => {}))
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', explore_log: log)
    decide(p)
    context = { grid: }
    p.decide(p.decision_point_for(state), state, context)
    assert_includes client.calls.last[:prompt], 'Known route to 146-16 over exits taken before (2 screens; explore with no direction follows it): up to 147-16, left to 146-16'
    assert_equal({ place: [146, 16] }, context[:aim])
    skipped = { skill: 'explore', params: {}, stopped_by: :no_frontier, moved_cells: 0, cells_walked: 0, from: { room: 163, map: 16, row: 3, col: 4 },
                to: { room: 163, map: 16, row: 3, col: 4 }, unreachable: [:up], blocked_edges: [], exits: [], offered: [] }
    p.after_action(choice: { skill: 'explore', params: {} }, outcome: skipped, state:, frame: 200)
    p.decide(p.decision_point_for(state), state, { grid: })
    assert_includes client.calls.last[:prompt], 'Known route to 146-16: none over the exits taken so far (the last explore found no way from Link to the up exit here).'
  end

  def test_coming_back_to_the_same_known_places_emits_a_loop_stuck_and_a_hint_until_a_new_place
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = policy(client)
    notes = [163, 164, 163, 164, 163, 164, 163, 164, 163].each_with_index.flat_map do |room, i|
      now = state(frame: 100 + (i * 300), room_id: room)
      p.observe(now, frame: now.frame)
      Array(p.decide(p.decision_point_for(now), now, { grid: })[:notables])
    end
    assert_equal ['loop: 163-16 entered 4 times in 1800 frames without a new place (163-16, 164-16), 1 times this run'],
                 notes.select { |note| note[:kind] == 'stuck' }.map { |note| note[:detail] }
    now = state(frame: 2800, room_id: 163)
    p.decide(p.decision_point_for(now), now, { grid: })
    assert_includes client.calls.last[:prompt], 'LOOP: 163-16 was entered 4 times in 1800 frames without reaching a new place'
    now = state(frame: 3100, room_id: 165)
    p.observe(now, frame: now.frame)
    p.decide(p.decision_point_for(now), now, { grid: })
    refute_includes client.calls.last[:prompt], 'LOOP'
  end

  def test_a_detected_loop_drops_the_objective_and_explores_toward_the_nearest_untried_place_once
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [146, 16]), default: explore)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', explore_log: log)
    results = [163, 164, 163, 164, 163, 164, 163, 164, 163, 163].each_with_index.map do |room, i|
      now = state(frame: 100 + (i * 300), room_id: room)
      p.observe(now, frame: now.frame)
      context = { grid: }
      [p.decide(p.decision_point_for(now), now, context), context]
    end
    broken, context = results[8]
    assert_equal ['delegated', 'explore', { place: [165, 16] }], [broken[:agent], broken[:choice][:skill], context[:aim]]
    assert_match(/\Aloop in 163-16, 164-16: explore toward 165-16/, broken[:justification])
    assert_equal 'loop', @objectives.history.last[:reason]
    assert_equal 'new_place', @objectives.current[:predicate][:kind]
    assert_equal 'claude', results[9][0][:agent]
  end

  def test_a_loop_with_no_untried_work_anywhere_goes_to_the_least_entered_place_outside_it_on_every_detection
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    log.absorb({ from: { room: 165, map: 16 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [163, 16] }], survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    client = ScriptedClient.new(objective: new_place, default: walk)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', explore_log: log)
    broken = [165, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164].each_with_index.filter_map do |room, i|
      now = state(frame: 100 + (i * 200), room_id: room)
      p.observe(now, frame: now.frame)
      context = { grid: }
      result = p.decide(p.decision_point_for(now), now, context)
      [i, result, context] if result[:agent] == 'delegated'
    end
    assert_equal [9, 16], broken.map(&:first), 'each detection is acted on'
    _, result, context = broken.first
    assert_equal [{ kind: 'reach_place', place: [165, 16] }, { place: [165, 16] }], [result[:choice][:predicate], context[:aim]]
    assert_equal 'loop in 163-16, 164-16: no place has untried work: explore toward 165-16, the reachable place entered least', result[:justification]
    assert_equal [{ kind: 'reach_place', place: [165, 16] }, { kind: 'place', place: [165, 16] }], [@objectives.current[:predicate], @objectives.current[:target]]
  end

  def test_repeated_zero_frame_results_in_one_place_are_answered_by_the_harness
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: nil)
    decide(p)
    instant = outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0)
    3.times do |i|
      result = p.decide(p.decision_point_for(state), state, { grid: })
      assert_equal 'claude', result[:agent]
      p.after_action(choice: result[:choice], outcome: instant, state:, frame: 200 + i)
    end
    calls = client.calls.size
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal [{ skill: 'wait', params: { frames: 120 } }, 'delegated', calls], [result[:choice], result[:agent], client.calls.size]
    assert_equal ['zero-frame: explore no_frontier 3 times in a row in 163-16'], result[:notables].map { |note| note[:detail] }
    p.after_action(choice: result[:choice], outcome: { skill: 'wait', params: { frames: 120 }, frames: 120, stopped_by: 'done' }, state:, frame: 500)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal 'claude', result[:agent]
    p.after_action(choice: result[:choice], outcome: instant, state:, frame: 501)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal 'delegated', result[:agent], 'one more instant repeat waits again'
    p.after_action(choice: result[:choice], outcome: { skill: 'wait', params: { frames: 120 }, frames: 120, stopped_by: 'done' }, state:, frame: 502)
    p.after_action(choice: { skill: 'walk', params: {} }, outcome: instant.merge(frames: 16, stopped_by: 'done'), state:, frame: 520)
    assert_equal 'claude', p.decide(p.decision_point_for(state), state, { grid: })[:agent]
    p.instance_variable_get(:@explore_log).absorb({ from: { room: 163, map: 16 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [147, 16] }] })
    3.times { |i| p.after_action(choice: { skill: 'explore', params: {} }, outcome: instant, state:, frame: 600 + i) }
    context = { grid: }
    result = p.decide(p.decision_point_for(state), state, context)
    assert_equal ['explore', { place: [147, 16] }], [result[:choice][:skill], context[:aim]]
    p.after_action(choice: result[:choice], outcome: instant, state:, frame: 700)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal 'claude', result[:agent]
    p.after_action(choice: result[:choice], outcome: instant, state:, frame: 701)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal({ skill: 'wait', params: { frames: 120 } }, result[:choice], 'a harness explore that came back instantly escalates to the wait')
  end

  def test_untried_objects_continue_and_other_stops_go_to_the_model
    client = ScriptedClient.new(objective: new_place, default: explore)
    results = tours(autopiloted(client), 4, stop: :untried_object)
    assert_equal 2, client.calls.size
    assert_equal 2, results.count { |r| r[:autopilot] }
    client = ScriptedClient.new(objective: new_place, default: explore)
    results = tours(autopiloted(client), 4, stop: :blocked)
    assert_equal 4, client.calls.size
    assert(results.none? { |r| r[:autopilot] })
  end

  def test_autopilot_results_are_marked_in_the_next_prompt
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    tours(p, 3)
    tours(p, 1, stop: :blocked, start: 1000)
    tours(p, 1, start: 2000)
    assert_includes client.calls.last[:prompt], '- (autopilot) explore {}'
    assert(@objectives.attempts_for_prompt.any? { |line| line.include?('-> (autopilot) stopped_by budget') })
  end

  def test_the_harness_picks_the_next_explore_objective_after_a_chain_reaches_a_new_place
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    tours(p, 2)
    arrived = outcome(:new_place, 700).merge(place_changed: true, room_changed: true, to: { room: 7, map: 16, row: 3, col: 4 })
    p.after_action(choice: { skill: 'explore', params: {} }, outcome: arrived, state: state(frame: 990, room_id: 7), frame: 990)
    assert_equal :achieved, @objectives.history.last[:outcome]
    point = p.decision_point_for(state(frame: 1000, room_id: 7))
    assert_equal :choose_objective, point.name
    result = p.decide(point, state(frame: 1000, room_id: 7), { grid: })
    assert result[:autopilot]
    assert_equal 'new_place', result[:choice][:predicate][:kind]
    assert @objectives.current[:autopilot]
    following = p.decide(p.decision_point_for(state(frame: 1010, room_id: 7)), state(frame: 1010, room_id: 7), { grid: })
    assert following[:autopilot]
    assert_equal 2, client.calls.size
    assert_includes Koholint::Agents::Context.build(state: state, grid:, objective: nil, history: @objectives.history + [@objectives.current.merge(outcome: :achieved)],
                                                    attempts: [], manual: '', last_results: []), '(picked by the harness)'
  end

  class OpenGrid
    def passable(*) = :yes
    def static_sprite(*) = nil
  end

  class QuietRevisit < Koholint::Revisit
    def candidate(**) = nil
    def next_action(**) = nil
  end

  def test_a_candidate_id_sets_the_objective_and_its_target_is_followed_without_a_call
    client = ScriptedClient.new(objective: ok('candidate' => 'exit-up', 'plan' => 'leave', 'goal' => 'g'), default: explore)
    p = autopiloted(client)
    result = p.decide(p.decision_point_for(state), state, { grid: OpenGrid.new })
    assert_includes client.calls.first[:prompt], '- exit-up: leave by the up side'
    assert_equal({ kind: 'leave_place', place: [163, 16] }, @objectives.current[:predicate])
    assert_equal({ kind: 'exit', place: [163, 16], direction: 'up' }, @objectives.current[:target])
    assert_equal 'Leave by the up side', result[:choice][:title]
    context = { grid: }
    follow = p.decide(p.decision_point_for(state), state, context)
    assert follow[:autopilot]
    assert_equal({ skill: 'explore', params: { direction: 'up' } }, follow[:choice])
    assert_equal 1, client.calls.size
    bad = ScriptedClient.new(objective: ok('candidate' => 'exit-sideways', 'plan' => 'x', 'goal' => 'g'))
    p = autopiloted(bad)
    refused = p.decide(p.decision_point_for(state), state, { grid: })
    assert refused[:refused]
    assert_match(/unknown candidate exit-sideways/, refused[:justification])
  end

  def test_a_door_or_a_person_candidate_is_followed_with_an_aimed_explore_or_a_talk
    entities = -> { [{ type: 62, kind: 'npc', cell: [2, 3] }] }
    objects = -> { [{ kind: 'door', cell: [0, 5], object: 226 }] }
    client = ScriptedClient.new(objective: [ok('candidate' => 'door-0-5', 'plan' => 'x', 'goal' => 'g'), ok('candidate' => 'person-t62', 'plan' => 'x', 'goal' => 'g')])
    p = autopiloted(client, revisit: QuietRevisit.new(talk_log: Koholint::TalkLog.new))
    p.decide(p.decision_point_for(state), state, { grid:, entities:, objects: })
    assert_includes client.calls.first[:prompt], '- person-t62: talk to person (type 62) at (2,3), never talked to'
    context = { grid:, entities:, objects: }
    assert_equal({ skill: 'explore', params: {} }, p.decide(p.decision_point_for(state), state, context)[:choice])
    assert_equal({ door: [0, 5] }, context[:aim])
    @objectives.abandon(frame: 200, reason: 'test')
    p.decide(p.decision_point_for(state), state, { grid:, entities:, objects: })
    assert_equal 'new_text', @objectives.current[:predicate][:kind]
    talk = p.decide(p.decision_point_for(state), state, { grid:, entities:, objects: })
    assert_equal({ skill: 'talk_to', params: { row: 2, col: 3 } }, talk[:choice])
    assert talk[:autopilot]
    assert_nil p.send(:follow_choice, state(room_id: 9))
  end

  def test_a_place_name_is_noted_once_and_shown_in_the_next_prompt
    client = ScriptedClient.new(objective: ok('title' => 'go', 'predicate' => { 'kind' => 'new_place' }, 'place_name' => " Tarin's\nhouse "), default: explore)
    p = autopiloted(client, autopilot: nil)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal({ place: [163, 16], name: "Tarin's house" }, result[:place_name])
    p.decide(p.decision_point_for(state), state, { grid: })
    assert_includes client.calls.last[:prompt], "Place: room 163, map 16, named by you: Tarin's house"
  end

  def test_a_reach_cell_objective_is_never_autopiloted
    cell = ok('title' => 'go', 'predicate' => { 'kind' => 'reach_cell', 'place' => [163, 16], 'row' => 0, 'col' => 0 })
    client = ScriptedClient.new(objective: cell, default: explore)
    p = autopiloted(client)
    context = { grid: Koholint::Vision::Grid.new(cells: Array.new(8) { Array.new(10) }, static_sprites: {}, beliefs: Koholint::Vision::Beliefs.new,
                                                 capabilities: Koholint::Vision::Capabilities.new) }
    p.decide(p.decision_point_for(state), state, context)
    assert_equal 'reach_cell', @objectives.current[:predicate][:kind]
    2.times do |i|
      result = p.decide(p.decision_point_for(state), state(frame: 200 + i), context)
      refute result[:autopilot]
      p.after_action(choice: result[:choice], outcome: outcome(:budget, 200 + i), state: state(frame: 300 + i), frame: 300 + i)
    end
    assert_equal 3, client.calls.size
  end

  def test_a_due_revisit_comes_before_the_autopilot
    revisit = Class.new(Koholint::Revisit) do
      def candidate(**) = true
      def next_action(**) = { skill: 'talk_to', params: { row: 2, col: 3 }, npc: { type: 5, cell: [2, 3] }, round: 1 }
    end.new(talk_log: Koholint::TalkLog.new)
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, revisit:)
    p.decide(Koholint::DecisionPoint.choose_objective, state, { grid: })
    p.decide(p.decision_point_for(state), state, { grid: })
    p.after_action(choice: { skill: 'explore', params: { direction: 'up' } }, outcome: outcome(:budget, 200), state: state(frame: 200), frame: 200)
    result = p.decide(p.decision_point_for(state(frame: 210)), state(frame: 210), { grid:, entities: -> { [] } })
    assert_equal 'talk_to', result[:choice][:skill]
    refute result[:autopilot]
  end

  def test_a_revisit_waits_while_a_surveyed_place_still_has_untried_work
    revisit = Class.new(Koholint::Revisit) do
      def candidate(danger: false, **) = !danger
      def next_action(danger: false, **) = danger ? nil : { skill: 'talk_to', params: { row: 2, col: 3 }, npc: { type: 5, cell: [2, 3] }, round: 1 }
    end.new(talk_log: Koholint::TalkLog.new)
    p = autopiloted(ScriptedClient.new(objective: new_place, default: explore), revisit:)
    log = p.instance_variable_get(:@explore_log)
    p.decide(Koholint::DecisionPoint.choose_objective, state, { grid:, entities: -> { [] } })
    assert_equal 'talk_to', p.decide(p.decision_point_for(state), state, { grid:, entities: -> { [] } })[:choice][:skill]
    log.absorb({ from: { room: 163, map: 16 }, exits: [], survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [] } })
    refute_equal 'talk_to', p.decide(p.decision_point_for(state), state, { grid:, entities: -> { [] } })[:choice][:skill]
  end

  def test_a_wait_or_guard_next_to_a_hostile_creature_becomes_explore
    near = [{ slot: 2, type: 9, x: 60, y: 60, cell: [3, 3], kind: :enemy, contact: 9 }]
    far = [{ slot: 2, type: 9, x: 150, y: 130, cell: [7, 9], kind: :enemy, contact: 9 }]
    wait = ok('skill' => 'wait', 'params' => { 'frames' => 30 })
    p = policy(ScriptedClient.new(objective: new_place, skill: [wait, wait], default: wait))
    decide = ->(frame, list) { 2.times.map { p.decide(p.decision_point_for(state(frame:)), state(frame:), { grid:, entities: -> { list } }) }.last }
    assert_equal 'wait', decide.(100, far)[:choice][:skill]
    held = decide.(200, near)
    assert_equal 'explore', held[:choice][:skill]
    assert_includes held[:justification], 'replaces the model'
  end
end
