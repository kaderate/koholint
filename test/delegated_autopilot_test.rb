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

  class ChainDone
    def objective_hold(**) = nil
    def adopt(_objective) = nil
    def next_choice(**) = nil
    def model_called(**) = nil
    def acted(**) = nil
  end

  def test_the_harness_keeps_exploring_after_an_arrival_unless_a_person_here_was_never_talked_to
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: ChainDone.new)
    people = []
    ctx = { grid:, entities: -> { people } }
    p.prepare(ctx)
    auto = p.decide(p.decision_point_for(state), state, ctx)
    assert_equal ['delegated', 'new_place'], [auto[:agent], auto[:choice][:predicate][:kind]]
    @objectives.abandon(frame: 120, reason: 'test')
    people << { kind: :npc, type: 49, cell: [5, 5] }
    asked = p.decide(p.decision_point_for(state(frame: 130)), state(frame: 130), ctx)
    assert_equal 'claude', asked[:agent], 'fef5 242/0: the type 49 at (5,5) was never offered'
    assert_includes client.calls.last[:prompt], 'person-t49'
    @objectives.abandon(frame: 140, reason: 'test')
    p.instance_variable_get(:@talk_log).record(place: [163, 16], row: 5, col: 5, talked: false, entity: 49)
    tried = p.decide(p.decision_point_for(state(frame: 150)), state(frame: 150), ctx)
    assert_equal 'delegated', tried[:agent], 'a person tried once without a talk no longer holds the harness'
  end

  def test_a_person_already_talked_to_does_not_hold_the_harness_after_an_arrival
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: ChainDone.new)
    talk_log = p.instance_variable_get(:@talk_log)
    talk_log.record(place: [163, 16], row: 5, col: 5, talked: true, entity: 49)
    ctx = { grid:, entities: -> { [{ kind: :npc, type: 49, cell: [5, 5] }] } }
    p.prepare(ctx)
    assert_equal 'delegated', p.decide(p.decision_point_for(state), state, ctx)[:agent]
  end

  def lap(policy, now, stop, ctx: { grid: }, to: { room: 163, map: 16, row: 3, col: 4 })
    policy.observe(now, frame: now.frame)
    result = policy.decide(policy.decision_point_for(now), now, ctx)
    policy.after_action(choice: result[:choice], outcome: outcome(stop, now.frame).merge(to:), state: now, frame: now.frame + 20)
    result
  end

  def test_at_half_a_heart_every_decision_goes_to_the_model_and_no_shelter_is_offered
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    p.instance_variable_get(:@explore_log).absorb({ from: { room: 1, map: 0 }, exits: [{ row: 7, col: 5, direction: :up, outcome: :left, to: [166, 16] }] })
    results = (0..3).map { |i| lap(p, state(frame: 100 + (i * 300), room_id: 1, map_id: 0, hp: 4), :known_place, to: { room: 1, map: 0, row: 3, col: 4 }) }
    assert(results.none? { |r| r[:autopilot] })
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
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log: log))
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

  # 81/0 in the 21b0 lineage: its top led to 99/0 every time, never to 65/0 above it.
  def test_a_crossing_that_lands_away_from_the_neighbour_screen_is_traced_once_and_shown_as_a_fact
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = policy(client)
    crossing = { skill: 'explore', params: {}, stopped_by: :new_place, from: { room: 81, map: 0, row: 1, col: 3 }, to: { room: 99, map: 0, row: 0, col: 3 },
                 exits: [{ row: 0, col: 3, direction: :up, outcome: :left, to: [99, 0] }], blocked_edges: [], offered: [] }
    p.after_action(choice: { skill: 'explore', params: {} }, outcome: crossing, state: state(frame: 75199, room_id: 99, map_id: 0), frame: 75199)
    landed = state(frame: 75210, room_id: 99, map_id: 0, x: 56, y: 124)
    puzzles = p.decide(p.decision_point_for(landed), landed, { grid: })[:puzzles]
    assert_equal [{ id: 'unexpected_arrival-81-0-up', kind: 'unexpected_arrival', place: [81, 0], way: :up, expected: { to: [65, 0], source: 'neighbour' },
                    observed: { to: [99, 0], landing: [7, 3] }, frames: [75199] }], puzzles
    assert_nil p.decide(p.decision_point_for(landed), landed, { grid: })[:puzzles], 'traced once'
    back = state(frame: 75400, room_id: 81, map_id: 0)
    p.decide(p.decision_point_for(back), back, { grid: })
    assert_includes client.calls.last[:prompt], 'PUZZLE (observed, not explained): leaving 81-0 by the up side led to 99-0 (landing row 7, col 3), not to 65-0, ' \
                                                'the screen next to it on the map, 1 time since frame 75199.'
    again = state(frame: 75600, room_id: 81, map_id: 0)
    p.decide(p.decision_point_for(again), again, { grid: })
    refute_includes client.calls.last[:prompt], 'PUZZLE', 'stated once per visit'
  end

  def puzzled_policy(client, explore_log)
    leads = Koholint::Leads.new
    leads.name_place([144, 0], 'Forêt Enchantée')
    leads.restore({ 'id' => 'lead-20', 'place' => [128, 0], 'quote' => 'Vas-y avec la Clé cachée dans la Forêt.', 'claim' => 'a key', 'importance' => 'high' })
    leads.note_read('Hé hé! Tu vas te perdre dans la Forêt.', place: [81, 0])
    @objectives = Koholint::Objectives.new(trace: trace)
    Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log:, leads:))
  end

  def puzzle_crossings
    [{ 'type' => 'action', 'frame' => 10, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 97, 'map' => 0 }, 'exits' => [{ 'row' => 0, 'col' => 6, 'direction' => 'up', 'outcome' => 'left', 'to' => [81, 0] }] } },
     { 'type' => 'action', 'frame' => 20, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 81, 'map' => 0 }, 'exits' => [{ 'row' => 0, 'col' => 3, 'direction' => 'up', 'outcome' => 'left', 'to' => [99, 0] }] } },
     { 'type' => 'action', 'frame' => 30, 'skill' => 'explore', 'result' => { 'from' => { 'room' => 98, 'map' => 0 }, 'exits' => [{ 'row' => 3, 'col' => 0, 'direction' => 'left', 'outcome' => 'left', 'to' => [97, 0] }] } }]
  end

  def test_the_puzzle_objective_is_offered_once_per_run_and_context_even_on_resume
    leave = ->(room) { ok('title' => 'leave', 'predicate' => { 'kind' => 'leave_place', 'place' => [room, 0] }) }
    client = ScriptedClient.new(objective: [leave.(97), leave.(98)], default: explore)
    log = Koholint::ExploreLog.from_events(puzzle_crossings)
    p = puzzled_policy(client, log)
    here = state(room_id: 97, map_id: 0)
    first = p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert_includes client.calls.last[:prompt], 'puzzle-81-0'
    assert_includes client.calls.last[:prompt], 'TEXT READ IN 81-0 (beside the candidate puzzle-81-0): « Hé hé! Tu vas te perdre dans la Forêt. »'
    assert_equal [[81, 0]], first[:puzzles_offered]
    there = state(room_id: 98, map_id: 0, frame: 200)
    p.observe(there, frame: there.frame)
    second = p.decide(p.decision_point_for(there), there, { grid: OpenGrid.new })
    assert_includes client.calls.last[:system], 'choose the next objective', 'a second objective decision with no bench change'
    refute_includes client.calls.last[:prompt], 'puzzle-81-0'
    assert_nil second[:puzzles_offered]
    decision = { 'type' => 'decision', 'frame' => 40, 'input' => JSON.parse(JSON.generate(here.to_h)), 'puzzles_offered' => [[81, 0]] }
    resumed = ScriptedClient.new(objective: leave.(97), default: explore)
    p = puzzled_policy(resumed, Koholint::ExploreLog.from_events(puzzle_crossings + [decision]))
    p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    refute_includes resumed.calls.last[:prompt], 'puzzle-81-0', 'the offer survives a resume'
    held = ScriptedClient.new(objective: leave.(97), default: explore)
    p = puzzled_policy(held, Koholint::ExploreLog.from_events(puzzle_crossings + [decision]))
    sword = state(room_id: 97, map_id: 0, item_a: 1)
    p.decide(p.decision_point_for(sword), sword, { grid: OpenGrid.new })
    assert_includes held.calls.last[:prompt], 'puzzle-81-0', 'a new item is a new context'
  end

  def test_a_place_with_an_open_puzzle_quotes_every_text_read_there_in_full
    client = ScriptedClient.new(objective: new_place, default: explore)
    log = Koholint::ExploreLog.from_events(puzzle_crossings)
    p = puzzled_policy(client, log)
    p.instance_variable_get(:@leads).note_read("J'suis un raton-laveur espiègle.\n\nEt j'aime pas du tout c'qu'est poudreux...", place: [81, 0])
    here = state(room_id: 81, map_id: 0)
    p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert_includes client.calls.last[:prompt], "TEXT READ HERE (quoted in full while a puzzle here is open): « J'suis un raton-laveur espiègle. Et j'aime pas du tout c'qu'est poudreux... »"
    assert_includes client.calls.last[:prompt], '« Hé hé! Tu vas te perdre dans la Forêt. »'
    p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert_includes client.calls.last[:system], 'skill'
    refute_includes client.calls.last[:prompt], 'TEXT READ HERE', 'a skill decision later in the same visit repeats nothing'
    away = state(room_id: 97, map_id: 0, frame: 300)
    p.observe(away, frame: away.frame)
    p.decide(p.decision_point_for(away), away, { grid: OpenGrid.new })
    refute_includes client.calls.last[:prompt], 'TEXT READ HERE', 'a place without a puzzle quotes nothing'
    log.use_bench({ edges: {}, status: {}, benches: { [81, 0] => { 'status' => 'depends_on_context', 'ways' => {}, 'new_places' => [] } } })
    assert_empty p.send(:puzzle_texts, [81, 0], objective: true), 'nor one a conclusive bench measured'
  end

  def test_the_quoted_texts_keep_the_newest_within_a_character_budget_and_say_where_one_was_cut
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = puzzled_policy(client, Koholint::ExploreLog.from_events(puzzle_crossings))
    leads = p.instance_variable_get(:@leads)
    %w[A B C].each { |letter| leads.note_read("#{letter} #{'mot ' * 300}fin.", place: [81, 0]) }
    lines = p.send(:puzzle_texts, [81, 0], objective: true)
    assert_equal ['« C', '« B'], lines.map { |line| line[/« ./] }, 'newest first, and the oldest no longer fits'
    assert lines.last.end_with?('... (cut) »')
    refute lines.first.include?('(cut)')
    assert_operator lines.sum { |line| line.size - Koholint::Policies::Delegated::TEXT_PREFIX.size - 4 }, :<=, Koholint::Policies::Delegated::TEXTS_BUDGET + 20
  end

  def entered(p, room, frame, **over)
    now = state(room_id: room, map_id: 0, frame:, **over)
    p.observe(now, frame:)
    now
  end

  def test_entering_a_puzzle_place_asks_the_model_once_per_context_and_set_of_texts_read_there
    client = ScriptedClient.new(objective: ok('title' => 'follow what was said here', 'predicate' => { 'kind' => 'new_place' }), default: explore)
    log = Koholint::ExploreLog.from_events(puzzle_crossings)
    p = puzzled_policy(client, log)
    p.instance_variable_set(:@autopilot, Koholint::Autopilot.new)
    @objectives.start(frame: 90, **Koholint::Policies::Delegated::AUTO_OBJECTIVE, autopilot: true)
    here = entered(p, 81, 100)
    assert_equal ['abandoned', 'puzzle'], @objectives.history.last.values_at(:outcome, :reason).map(&:to_s)
    point = p.decision_point_for(here)
    assert_equal :choose_objective, point.name
    result = p.decide(point, here, { grid: OpenGrid.new })
    assert_includes client.calls.last[:system], 'choose the next objective', 'the model chooses, not the harness explore objective'
    assert_includes client.calls.last[:prompt], 'TEXT READ HERE (quoted in full while a puzzle here is open): « Hé hé! Tu vas te perdre dans la Forêt. »'
    assert_equal [[81, 0], 'follow what was said here'], [result[:puzzle_entry][:place], @objectives.current[:title]]
    restart = lambda do |frame|
      @objectives.abandon(frame:, reason: 'test')
      @objectives.start(frame:, **Koholint::Policies::Delegated::AUTO_OBJECTIVE, autopilot: true)
    end
    entered(p, 97, 110)
    restart.(120)
    entered(p, 81, 130)
    assert @objectives.current[:autopilot], 'a second entry with no new text asks nothing'
    p.instance_variable_get(:@leads).note_read('Un texte nouveau lu ici.', place: [81, 0])
    entered(p, 97, 140)
    restart.(145)
    entered(p, 81, 150)
    assert_equal 'puzzle', @objectives.history.last[:reason], 'a new text read there asks again'
    entered(p, 97, 170)
    restart.(175)
    entered(p, 81, 180, item_a: 1)
    assert_equal 'puzzle', @objectives.history.last[:reason], 'and so does a new context'
    decision = { 'type' => 'decision', 'frame' => 100, 'input' => JSON.parse(JSON.generate(here.to_h)), 'puzzle_entry' => JSON.parse(JSON.generate(result[:puzzle_entry])) }
    resumed = Koholint::ExploreLog.from_events(puzzle_crossings + [decision])
    refute resumed.enter_puzzle([81, 0], Koholint::Exits.context(here), result[:puzzle_entry][:texts]), 'a resume keeps the entry'
  end

  def test_one_ask_clears_the_entry_whatever_comes_back_and_leaving_clears_it_too
    client = ScriptedClient.new(objective: ok('title' => 'x', 'predicate' => { 'kind' => 'leave_place', 'place' => [5, 5] }), default: explore)
    p = puzzled_policy(client, Koholint::ExploreLog.from_events(puzzle_crossings))
    p.instance_variable_set(:@autopilot, Koholint::Autopilot.new)
    here = entered(p, 81, 100)
    refute_nil p.instance_variable_get(:@puzzle_ask)
    refused = p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert refused[:refused]
    assert_nil p.instance_variable_get(:@puzzle_ask), 'a refusal ends the ask'
    other = puzzled_policy(ScriptedClient.new(default: explore), Koholint::ExploreLog.from_events(puzzle_crossings))
    entered(other, 81, 100)
    refute_nil other.instance_variable_get(:@puzzle_ask)
    entered(other, 97, 110)
    assert_nil other.instance_variable_get(:@puzzle_ask), 'leaving the place drops the ask'
  end

  def test_an_entry_under_a_model_objective_is_kept_for_later
    p = puzzled_policy(ScriptedClient.new(default: explore), Koholint::ExploreLog.from_events(puzzle_crossings))
    @objectives.start(frame: 90, title: 'mine', predicate: { kind: 'new_place' })
    entered(p, 81, 100)
    assert_equal ['mine', nil], [@objectives.current[:title], p.instance_variable_get(:@puzzle_ask)]
    @objectives.abandon(frame: 110, reason: 'test')
    entered(p, 97, 120)
    entered(p, 81, 130)
    refute_nil p.instance_variable_get(:@puzzle_ask), 'the entry was never asked, so it asks now'
  end

  def test_a_pending_puzzle_ask_holds_back_the_loop_break_until_the_model_answered
    client = ScriptedClient.new(objective: [new_place, new_place], default: explore)
    log = Koholint::ExploreLog.from_events(puzzle_crossings)
    p = puzzled_policy(client, log)
    leads = p.instance_variable_get(:@leads)
    leads.instance_variable_get(:@read_at).delete([81, 0])
    ([81, 97] * 6).each_with_index { |room, i| entered(p, room, 100 + (i * 100)) }
    refute_nil p.instance_variable_get(:@loop_watch).pending_hint
    leads.note_read('Un texte lu ici.', place: [81, 0])
    here = entered(p, 81, 1000)
    first = p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert_equal 'claude', first[:agent], 'the model is asked, the loop break waits'
    @objectives.abandon(frame: 1010, reason: 'test')
    second = p.decide(p.decision_point_for(here), here, { grid: OpenGrid.new })
    assert_match(/\Aloop in/, second[:justification].to_s)
  end

  def test_a_model_objective_holds_through_a_loop_for_a_bounded_number_of_frames
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [146, 16]), default: explore)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log: log))
    results = [163, 164, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164, 163, 164].each_with_index.map do |room, i|
      now = state(frame: 100 + (i * 150), room_id: room)
      p.observe(now, frame: now.frame)
      p.decide(p.decision_point_for(now), now, { grid: })
    end
    held = results.first(12).count { |result| result[:justification].to_s.start_with?('loop in') }
    assert_equal 0, held, 'no loop break while the model objective is younger than MODEL_HOLD_FRAMES'
    assert results.last(2).any? { |result| result[:justification].to_s.start_with?('loop in') }, 'and the break comes once the hold ran out'
  end

  def test_the_exit_bench_applies_only_in_the_context_it_measured
    sword = { 'milestone' => 'none', 'held' => [] }
    exits = { 'edges' => [], 'benches' => [{ 'place' => [81, 0], 'context' => sword, 'ways' => { 'up' => [99, 0] }, 'new_places' => [], 'status' => 'depends_on_context' }] }
    log = Koholint::ExploreLog.new
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives,
                                          manual: '', exits:, memory: Koholint::Policies::Memory.new(explore_log: log))
    now = state(room_id: 81, map_id: 0)
    p.decide(p.decision_point_for(now), now, { grid: })
    assert_equal 'depends_on_context', log.bench_of([81, 0])['status']
    held = state(room_id: 81, map_id: 0, item_a: 1)
    p.decide(p.decision_point_for(held), held, { grid: })
    assert_nil log.bench_of([81, 0]), 'an item gained since the bench is another context'
  end

  def test_a_detected_loop_drops_the_objective_and_explores_toward_the_nearest_untried_place_once
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [146, 16]), default: explore)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log: log))
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
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log: log))
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
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal 'claude', result[:agent]
    p.after_action(choice: result[:choice], outcome: instant, state:, frame: 200)
    calls = client.calls.size
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal [{ skill: 'wait', params: { frames: 120 } }, 'delegated', calls], [result[:choice], result[:agent], client.calls.size], 'an explore with no frontier at once is not asked again'
    assert_equal ['zero-frame: explore no_frontier 1 times in a row in 163-16'], result[:notables].map { |note| note[:detail] }
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

  def test_other_zero_frame_results_are_answered_after_three
    client = ScriptedClient.new(objective: new_place, default: walk)
    p = autopiloted(client, autopilot: nil)
    decide(p)
    blocked = outcome(:blocked, 0).merge(frames: 1, moved_cells: 0)
    3.times do |i|
      result = p.decide(p.decision_point_for(state), state, { grid: })
      assert_equal 'claude', result[:agent]
      p.after_action(choice: result[:choice], outcome: blocked, state:, frame: 200 + i)
    end
    assert_equal 'delegated', p.decide(p.decision_point_for(state), state, { grid: })[:agent]
  end

  def test_the_harness_tries_a_never_tried_unknown_entity_once_before_exploring_on
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    ctx = { grid:, entities: -> { [{ kind: :unknown, type: 79, cell: [2, 2], slot: 3, x: 40, y: 48 }] } }
    p.prepare(ctx)
    p.note_card({ place: [163, 16], unknown: [{ type: 79, cell: [2, 2] }] })
    tours(p, 2)
    result = p.decide(p.decision_point_for(state(frame: 800)), state(frame: 800), ctx)
    assert_equal ['delegated', { skill: 'talk_to', params: { row: 2, col: 2 } }], result.values_at(:agent, :choice)
    p.after_action(choice: result[:choice], outcome: { skill: 'talk_to', params: { row: 2, col: 2 }, stopped_by: 'no_response', talked: false, target_type: 79,
                                                       from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 3 } },
                   state: state(frame: 900), frame: 900)
    result = p.decide(p.decision_point_for(state(frame: 1000)), state(frame: 1000), ctx)
    assert_equal ['delegated', { skill: 'touch', params: { row: 2, col: 2, type: 79 } }], result.values_at(:agent, :choice)
    p.after_action(choice: result[:choice], outcome: { skill: 'touch', params: { row: 2, col: 2, type: 79 }, stopped_by: 'done', picked_up: false,
                                                       from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 2 } },
                   state: state(frame: 1100), frame: 1100)
    result = p.decide(p.decision_point_for(state(frame: 1200)), state(frame: 1200), ctx)
    assert_equal ['delegated', { skill: 'explore', params: {} }], result.values_at(:agent, :choice)
    assert_equal 2, client.calls.size
  end

  def test_a_still_entity_whose_try_gave_nothing_is_touched_through_a_point_the_model_never_sees
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    ctx = { grid:, entities: -> { [{ kind: :unknown, type: 79, cell: [2, 2], slot: 3, x: 40, y: 48 }] } }
    p.prepare(ctx)
    p.note_card({ place: [163, 16], unknown: [{ type: 79, cell: [2, 2] }] })
    tours(p, 2)
    refute_includes p.decision_point_for(state(frame: 800)).registry.names, 'touch'
    result = p.decide(p.decision_point_for(state(frame: 800)), state(frame: 800), ctx)
    p.after_action(choice: result[:choice], outcome: { skill: 'talk_to', params: { row: 2, col: 2 }, stopped_by: 'frame_cap', talked: false, target_type: 79,
                                                       from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 3 } },
                   state: state(frame: 900), frame: 900)
    result = p.decide(p.decision_point_for(state(frame: 1000)), state(frame: 1000), ctx)
    assert_equal ['delegated', true, { skill: 'touch', params: { row: 2, col: 2, type: 79 } }], result.values_at(:agent, :autopilot, :choice)
    assert_equal({ skill: 'touch', params: { row: 2, col: 2, type: 79 } }, result[:decision_point].validate(result[:choice]))
    assert_equal 2, client.calls.size
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

  def test_a_sign_of_another_place_is_walked_to_and_read_before_its_objective_ends
    p = autopiloted(ScriptedClient.new(objective: []))
    here = [state.room_id, state.map_id]
    @objectives.start(frame: 10, title: 'Go read the sign', predicate: { kind: 'new_text' }, target: { kind: 'sign', place: here, cell: [4, 8], remote: true })
    assert_equal({ choice: { skill: 'explore', params: {} }, aim: { place: here } }, p.send(:follow_choice, state(room_id: 9)))
    assert_equal({ choice: { skill: 'talk_to', params: { row: 4, col: 8 } } }, p.send(:follow_choice, state))
    @objectives.abandon(frame: 20, reason: 'test')
    @objectives.start(frame: 20, title: 'Read the sign', predicate: { kind: 'new_text' }, target: { kind: 'sign', place: here, cell: [4, 8] })
    assert_nil p.send(:follow_choice, state(room_id: 9)), 'a sign of the place Link left is not routed back to'
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

  # 66/0: each strike on the pieces of a split enemy cost a call; after a kill the harness strikes the next one in reach.
  def test_after_the_model_s_attack_kills_the_harness_strikes_the_next_enemy_in_reach_for_free
    attack = ok('skill' => 'attack', 'params' => { 'row' => 3, 'col' => 5 })
    client = ScriptedClient.new(objective: new_place, skill: attack, default: explore)
    p = autopiloted(client)
    foes = [{ slot: 4, type: 9, x: 56, y: 76, cell: [4, 3], kind: :enemy, contact: 9 }]
    ctx = { grid:, entities: -> { foes } }
    first = p.decide(p.decision_point_for(state), state, ctx)
    first = p.decide(p.decision_point_for(state), state, ctx) unless first[:choice][:skill] == 'attack'
    killed = { skill: 'attack', params: { row: 3, col: 5 }, stopped_by: :done, killed: true, moved_cells: 0, hp_delta: 0, target: { slot: 2, type: 9, cell: [3, 5] },
               from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 3, col: 4 } }
    p.after_action(choice: first[:choice], outcome: killed, state: state(frame: 160), frame: 160)
    calls = client.calls.size
    chained = p.decide(p.decision_point_for(state(frame: 160)), state(frame: 160), ctx)
    assert_equal [{ skill: 'attack', params: { row: 4, col: 3 } }, 'delegated', true], chained.values_at(:choice, :agent, :autopilot)
    assert_equal calls, client.calls.size
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

  def test_a_place_card_noted_on_arrival_keeps_its_uncatalogued_things_with_the_items_held_now
    seen = { [172, 10] => { people: [], unknown: [{ type: 155, cell: [3, 3] }], held: [1, 4] } }
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new, registry: Koholint::Skills::Registry.default, objectives: Koholint::Objectives.new(trace:), manual: '',
                                          memory: Koholint::Policies::Memory.new(cards: seen))
    p.observe(state(item_a: 1, item_b: 4, inventory: [12]), frame: 100)
    p.note_card({ place: [172, 10], unknown: [{ type: 155, cell: [3, 4], moves: nil }] })
    assert_equal({ people: [], unknown: [{ type: 155, cell: [3, 4] }], held: [1, 4, 12] }, p.instance_variable_get(:@cards)[[172, 10]])
    p.note_card({ place: [172, 10], unknown: [{ type: 155, cell: [3, 4], moves: nil }] })
    assert_equal [{ type: 155, cell: [3, 4], still: true }], p.instance_variable_get(:@cards)[[172, 10]][:unknown], 'the second look in the same cell'
  end
end
