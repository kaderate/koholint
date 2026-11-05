require_relative 'support/delegated_helpers'

class DelegatedLedgerTest < Minitest::Test
  include DelegatedHelpers

  PLACE = [163, 16].freeze

  def free_grid(cells: nil)
    beliefs = Koholint::Vision::Beliefs.new
    %i[up down left right].each do |d|
      beliefs.record(appearance: 'floor', action: :walk, direction: d, result: :yes, method: 'test', context: Koholint::Vision::Capabilities.new, frame: 1, source: 'test')
    end
    cells ||= Array.new(8) { Array.new(10) { 'floor' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs:, capabilities: Koholint::Vision::Capabilities.new)
  end

  def unknown_grid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[1][9] = 'mystery'
    free_grid(cells:)
  end

  def reach_cell(row, col) = ok('title' => 'go', 'predicate' => { 'kind' => 'reach_cell', 'place' => PLACE, 'row' => row, 'col' => col })

  def block(p, direction: 'up', frame: 101, state: self.state)
    place = { room: 163, map: 16, row: 3, col: 4 }
    outcome = { skill: 'walk', params: { direction:, cells: 1 }, frames: 8, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'blocked',
                from: place, to: place, blocked_at: { row: 3, col: 4, direction: direction.to_sym } }
    p.after_action(choice: { skill: 'walk', params: outcome[:params] }, outcome:, state:, frame:)
  end

  def neighbour_line(client, direction) = client.calls.last[:prompt].lines.find { |l| l =~ /\b#{direction}\b/ && l =~ /blocked|free|unknown/ }

  def test_reach_cell_on_a_known_free_reachable_cell_is_rejected_and_unknown_is_accepted
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    result = p.decide(p.decision_point_for(state), state, { grid: free_grid })
    assert result[:fallback]
    assert_match(/already reachable/, result[:justification])
    assert_equal 'wait', result[:choice][:skill]
    assert_nil @objectives.current

    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[3][6] = 'mystery'
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid(cells:) })[:fallback]
    assert @objectives.current
  end

  def test_reach_cell_is_not_judged_without_a_grid
    p = policy(ScriptedClient.new(objective: reach_cell(3, 6)))
    refute p.decide(p.decision_point_for(state), state, {})[:fallback]
  end

  def test_reach_cell_behind_a_doubtful_edge_stays_valid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: { row: 3, col: 4, direction: :right }) }
    cells[2][4] = cells[4][4] = cells[3][3] = 'mystery'
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(3, 5)), registry: Koholint::Skills::Registry.default,
                                          objectives: Koholint::Objectives.new(trace:), ledger:)
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid(cells:) })[:fallback]
  end

  def test_blocked_walks_feed_the_next_context_and_become_doubtful
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk, default: walk)
    p = policy(client)
    context = { grid: free_grid }
    p.decide(p.decision_point_for(state), state, context)
    block(p)
    p.decide(p.decision_point_for(state), state, context)
    assert_includes client.calls.last[:prompt], 'blocked 1 time'
    refute_includes client.calls.last[:prompt], 'blocked 1 times'
    block(p, frame: 102)
    p.decide(p.decision_point_for(state), state, context)
    assert_includes client.calls.last[:prompt], 'blocked 2 times'
    assert_includes neighbour_line(client, 'up'), '!'
  end

  def test_the_policy_hands_its_ledger_to_the_skills_through_the_context
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    context = { grid: free_grid }
    decide_with = ->(c) { p.decide(p.decision_point_for(state), state, c) }
    decide_with.call(context)
    assert_instance_of Koholint::Ledger, context[:ledger]
    2.times { block(p, direction: 'right') }
    run = Koholint::Skills::Registry.default.start('goto', state, { row: 3, col: 5 }, context)
    refute_equal [:right], run.next_input(state)
  end

  def test_unreachable_abandons_the_objective_and_the_next_tour_asks_for_an_objective
    cell = reach_cell(1, 4)
    p = policy(ScriptedClient.new(objective: cell, skill: walk, default: walk))
    context = { grid: free_grid(cells: Array.new(8) { Array.new(10) { 'mystery' } }) }
    p.decide(p.decision_point_for(state), state, context)
    assert @objectives.current
    Koholint::Objectives::UNREACHABLE_PAIRS.times { |i| block(p, frame: 101 + i) }
    assert_nil @objectives.current
    assert_equal 1, @objectives.history.count { |h| h[:outcome] == :abandoned }
    assert_equal 'unreachable', @objectives.history.last[:reason]
    assert_equal :choose_objective, p.decision_point_for(state).name
  end

  def test_a_place_change_clears_the_ledger
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk, default: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    2.times { |i| block(p, frame: 101 + i) }
    assert ledger.doubtful?(PLACE, [3, 4], :up)
    p.observe(state(room_id: 9), frame: 200)
    assert_equal 0, ledger.count(PLACE, [3, 4], :up)
  end

  def test_a_walk_entering_a_cell_undoubts_the_edge
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    2.times { |i| block(p, frame: 101 + i) }
    moved = { skill: 'walk', params: { direction: 'up', cells: 1 }, moved_cells: 1, stopped_by: 'done',
              from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 4 }, blocked_at: nil }
    p.after_action(choice: { skill: 'walk', params: moved[:params] }, outcome: moved, state: state(y: 44), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :up)
  end

  def goto_outcome(crossed:, to:)
    { skill: 'goto', params: { row: to[0], col: to[1] }, moved_cells: crossed.size, stopped_by: 'done', blocked_at: nil, crossed:,
      from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: to[0], col: to[1] } }
  end

  def test_goto_undoubts_only_the_edges_it_crossed
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    [[3, 4, :right], [3, 5, :right], [2, 6, :down]].each { |r, c, d| 2.times { ledger.record(place: PLACE, blocked_at: { row: r, col: c, direction: d }) } }
    outcome = goto_outcome(crossed: [[3, 4, :right], [3, 5, :right]], to: [3, 6])
    p.after_action(choice: { skill: 'goto', params: outcome[:params] }, outcome:, state: state(x: 104), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :right)
    refute ledger.doubtful?(PLACE, [3, 5], :right)
    assert ledger.doubtful?(PLACE, [2, 6], :down)
  end

  def test_talk_to_crossed_edges_are_cleared_like_goto
    p = policy(ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk))
    ledger = p.instance_variable_get(:@ledger)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    [[3, 4, :right], [2, 6, :down]].each { |r, c, d| 2.times { ledger.record(place: PLACE, blocked_at: { row: r, col: c, direction: d }) } }
    outcome = goto_outcome(crossed: [[3, 4, :right]], to: [3, 5]).merge(skill: 'talk_to', stopped_by: 'no_response', talked: false,
                                                                         standing_cell: { row: 3, col: 5 })
    p.after_action(choice: { skill: 'talk_to', params: outcome[:params] }, outcome:, state: state(x: 104), frame: 110)
    refute ledger.doubtful?(PLACE, [3, 4], :right)
    assert ledger.doubtful?(PLACE, [2, 6], :down)
    assert_equal 0, ledger.count(PLACE, [3, 5], :right)
  end

  def test_talk_to_no_path_counts_but_no_response_does_not_and_the_summary_shows_the_talk
    @objectives = NoPathObjectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(1, 9), skill: walk), registry: Koholint::Skills::Registry.default,
                                          objectives: @objectives)
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    params = { row: 2, col: 5 }
    sealed = { skill: 'talk_to', params:, stopped_by: 'no_path', cause: 'no reachable cell next to the target', moved_cells: 0, talked: false }
    p.after_action(choice: { skill: 'talk_to', params: }, outcome: sealed, state:, frame: 140)
    assert_equal [140], @objectives.no_paths
    quiet = { skill: 'talk_to', params:, stopped_by: 'no_response', moved_cells: 1, talked: false, standing_cell: { row: 1, col: 5 } }
    p.after_action(choice: { skill: 'talk_to', params: }, outcome: quiet, state:, frame: 150)
    assert_equal [140], @objectives.no_paths
    attempt = @objectives.attempts_for_prompt.last
    assert_includes attempt, 'talked false'
    assert_includes attempt, 'standing_cell (1,5)'
  end

  def test_talk_to_blocked_or_target_free_is_not_a_talk_attempt
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: walk))
    params = { row: 2, col: 5 }
    %w[blocked no_path target_free].each do |reason|
      p.after_action(choice: { skill: 'talk_to', params: }, outcome: { skill: 'talk_to', params:, stopped_by: reason, moved_cells: 0, talked: false, from: { room: PLACE[0], map: PLACE[1], row: 1, col: 1 } }, state:, frame: 140)
    end
    assert_equal 0, p.instance_variable_get(:@talk_log).attempts(PLACE, [[2, 5]])
  end

  def test_new_place_starts_and_is_achieved_on_a_first_visit
    p = policy(ScriptedClient.new(objective: ok('title' => 'discover', 'predicate' => { 'kind' => 'new_place' }), skill: walk), visited: [PLACE])
    refute decide(p).last[:fallback]
    assert @objectives.current
    p.observe(state(room_id: 9), frame: 200)
    assert_nil @objectives.current
    assert_equal :achieved, @objectives.history.last[:outcome]
  end

  def test_refused_objectives_are_flagged_remembered_three_deep_and_shown_then_cleared
    trivial = reach_cell(3, 6)
    elsewhere = objective(kind: 'leave_place', place: [1, 2])
    good = objective(kind: 'reach_place', place: [1, 2])
    client = ScriptedClient.new(objective: [trivial, elsewhere, trivial, elsewhere, trivial, good], skill: walk)
    p = policy(client)
    results = 5.times.map { p.decide(p.decision_point_for(state), state, { grid: free_grid }) }
    assert(results.all? { |r| r[:refused] && r[:fallback] })
    prompt = client.calls.last[:prompt]
    assert_includes prompt, <<~TEXT.chomp
      Refused objectives:
      - go {"kind":"leave_place","place":[1,2]}: leave_place must name the current place [163, 16], not [1, 2]
      - go {"kind":"reach_cell","place":[163,16],"row":3,"col":6}: reach_cell target is already reachable over cells observed free; choose a goal that needs exploration
      - go {"kind":"leave_place","place":[1,2]}: leave_place must name the current place [163, 16], not [1, 2]
    TEXT
    refute_includes client.calls.first[:prompt], 'Refused objectives'
    refute p.decide(p.decision_point_for(state), state, { grid: free_grid })[:refused]
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    refute_includes client.calls.last[:prompt], 'Refused objectives'
  end

  def test_an_agent_failure_is_not_a_refusal
    p = policy(ScriptedClient.new(objective: failing('down')))
    result = p.decide(p.decision_point_for(state), state, { grid: free_grid })
    assert result[:fallback]
    refute result.key?(:refused)
  end

  def test_a_goto_chosen_on_an_overlay_frame_still_plans
    goto = ok('skill' => 'goto', 'params' => { 'row' => 3, 'col' => 6 })
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: goto))
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    context = { grid: nil }
    result = p.decide(p.decision_point_for(state), state, context)
    assert_same context[:grid], p.instance_variable_get(:@last_grid)
    run = Koholint::Skills::Registry.default.start('goto', state, result[:choice][:params], context)
    refute_empty run.next_input(state)
  end

  def test_no_grid_is_invented_for_a_new_place
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: walk))
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    context = {}
    p.decide(p.decision_point_for(state(room_id: 9)), state(room_id: 9), context)
    assert_nil context[:grid]
  end

  class NoPathObjectives < Koholint::Objectives
    attr_reader :no_paths

    def note_no_path(frame:) = (@no_paths = [*@no_paths, frame]).then { nil }
  end

  def test_no_path_results_are_reported_to_the_objectives_and_summarised_with_their_cause
    @objectives = NoPathObjectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(1, 9), skill: walk), registry: Koholint::Skills::Registry.default,
                                          objectives: @objectives)
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    outcome = { skill: 'goto', params: { row: 1, col: 9 }, stopped_by: 'no_path', cause: 'target is sealed', moved_cells: 0,
                blocked_at: { row: 3, col: 5, direction: :right } }
    p.after_action(choice: { skill: 'goto', params: outcome[:params] }, outcome:, state:, frame: 140)
    assert_equal [140], @objectives.no_paths
    attempt = @objectives.attempts_for_prompt.last
    assert_includes attempt, 'blocked_at (3,5) right'
    assert_includes attempt, 'cause target is sealed'
    walked = { skill: 'walk', params: { direction: 'up', cells: 1 }, stopped_by: 'done', moved_cells: 1 }
    p.after_action(choice: { skill: 'walk', params: walked[:params] }, outcome: walked, state:, frame: 150)
    assert_equal [140], @objectives.no_paths
  end

  def test_explore_results_feed_the_explore_log_the_ledger_and_the_no_path_count
    @objectives = NoPathObjectives.new(trace:)
    log = Koholint::ExploreLog.new
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: reach_cell(1, 9), skill: walk), registry: Koholint::Skills::Registry.default,
                                          objectives: @objectives, explore_log: log)
    context = { grid: unknown_grid }
    p.decide(p.decision_point_for(state), state, context)
    assert_same log, context[:explore_log]
    from = { room: 163, map: 16, row: 3, col: 4 }
    edge = { row: 3, col: 5, direction: :right }
    outcome = { skill: 'explore', params: {}, stopped_by: :no_frontier, moved_cells: 0, from:, to: from, blocked_at: nil, cells_walked: 2,
                place_changed: false, blocked_edges: [edge, edge], exits: [{ row: 7, col: 5, direction: :down, outcome: :left }], offered: [], tried_exits: [] }
    p.after_action(choice: { skill: 'explore', params: {} }, outcome:, state:, frame: 140)
    assert_nil @objectives.no_paths
    assert log.tried?(PLACE, [7, 5], :down)
    assert p.instance_variable_get(:@ledger).doubtful?(PLACE, [3, 5], :right)
    assert_includes @objectives.attempts_for_prompt.last, 'cells walked 2, place_changed false, exits already tried none'
  end

  def test_repeated_explore_no_frontier_or_stalled_does_not_abandon_a_reach_cell_objective
    p = policy(ScriptedClient.new(objective: reach_cell(1, 9), skill: walk))
    p.decide(p.decision_point_for(state), state, { grid: unknown_grid })
    assert @objectives.current
    from = { room: 163, map: 16, row: 3, col: 4 }
    10.times do |i|
      outcome = { skill: 'explore', params: {}, stopped_by: %i[no_frontier stalled][i % 2], moved_cells: 0, from:, to: from, cells_walked: 0, place_changed: false,
                  blocked_edges: [], exits: [], offered: [], tried_exits: [] }
      p.after_action(choice: { skill: 'explore', params: { direction: %w[up down][i % 2] } }, outcome:, state:, frame: 140 + i)
    end
    assert @objectives.current
  end

  def test_a_doubtful_edge_emits_a_grid_contradiction_once_per_crossing
    sink = trace
    @objectives = Koholint::Objectives.new(trace: sink)
    @objectives.define_singleton_method(:trace) { sink }
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk),
                                          registry: Koholint::Skills::Registry.default, objectives: @objectives, ledger: Koholint::Ledger.new)
    p.decide(p.decision_point_for(state), state, { grid: free_grid })
    3.times { |i| block(p, frame: 101 + i) }
    events = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'grid_contradiction' }
    assert_equal 1, events.size
    assert_equal [102, [163, 16], 3, 4, 'up', 'yes', 'blocked x2'], events.first.values_at('frame', 'place', 'row', 'col', 'direction', 'believed', 'observed')
  end

  def test_a_believed_wall_blocking_twice_is_not_a_contradiction
    sink = trace
    @objectives = Koholint::Objectives.new(trace: sink)
    beliefs = Koholint::Vision::Beliefs.new
    capabilities = Koholint::Vision::Capabilities.new
    %w[floor wall].zip(%i[yes no]).each do |appearance, result|
      %i[up down left right].each do |d|
        beliefs.record(appearance:, action: :walk, direction: d, result:, method: 'test', context: capabilities, frame: 1, source: 'test')
      end
    end
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[3][5] = 'wall'
    grid = Koholint::Vision::Grid.new(cells:, static_sprites: {}, beliefs:, capabilities:)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk),
                                          registry: Koholint::Skills::Registry.default, objectives: @objectives, ledger: Koholint::Ledger.new)
    p.decide(p.decision_point_for(state), state, { grid: })
    2.times { |i| block(p, direction: 'right', frame: 101 + i) }
    events = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'grid_contradiction' }
    assert_empty events
  end

  def test_the_system_prompts_state_the_vocabulary
    objective_system = Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.choose_objective)
    skill_system = Koholint::Agents::Prompts.system_for(Koholint::DecisionPoint.choose_skill(Koholint::Skills::Registry.default))
    assert_match(/leave_place means finding a way out/, objective_system)
    assert_match(/new_place .*not yet visited/, objective_system)
    assert_match(/goto walks several cells/, skill_system)
    assert_match(/!.*doubtful.*goto avoids/, skill_system)
  end
end
