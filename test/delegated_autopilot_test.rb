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
    assert_equal ['no model call yet', 'chain cap'], results.values_at(0, 8).map { |r| r[:autopilot_hold] }
    assert(free.none? { |r| r.key?(:autopilot_hold) })
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

  def test_at_half_a_heart_the_autopilot_keeps_choosing_and_no_shelter_is_offered
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

  # Gate run 1d73: the loop break at 98777 dropped souvenir-162-14-t64 and the harness kept exploring, so the delivery was never offered again.
  def test_a_souvenir_objective_a_loop_break_dropped_is_taken_up_again_once_the_loop_is_cut
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    @objectives = Koholint::Objectives.new(trace: trace)
    target = { kind: 'person', place: [165, 16], type: 64, cell: [4, 4], try: true, item: 12, name: 'champignon' }
    souvenirs = [{ 'place' => [165, 16], 'entity' => 64, 'cell' => [4, 4], 'text' => 'Il me faut le champignon de la forêt.', 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1, 4] }] }]
    talk_log = Koholint::TalkLog.new
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                          memory: Koholint::Policies::Memory.new(explore_log: log, talk_log:), souvenirs:)
    loop_in = lambda do |from|
      @objectives.start(frame: from, title: 'Bring the champignon to person (type 64)', predicate: { kind: 'reach_place', place: [165, 16] }, candidate: 'souvenir-165-16-t64', target:)
      [163, 164, 163, 164, 163, 164, 163, 164, 163].each_with_index do |room, i|
        now = state(frame: from + (i * 300), room_id: room, item_b: 12)
        p.observe(now, frame: now.frame)
        p.decide(p.decision_point_for(now), now, { grid: })
      end
      assert_equal ['souvenir-165-16-t64', 'loop'], @objectives.history.last.values_at(:candidate, :reason)
      @objectives.abandon(frame: from + 2700, reason: 'test')
    end
    choose = lambda do |frame|
      now = state(frame:, room_id: 163, item_b: 12)
      p.observe(now, frame:)
      p.decide(p.decision_point_for(now), now, { grid: })
    end
    loop_in.(100)
    again = choose.(2900)
    assert_equal ['delegated', 'souvenir-165-16-t64', target], [again[:agent], @objectives.current[:candidate], @objectives.current[:target]]
    @objectives.abandon(frame: 3000, reason: 'test')
    choose.(3100)
    refute_equal 'souvenir-165-16-t64', @objectives.current&.dig(:candidate), 'the re-offer is spent once it started'
    @objectives.abandon(frame: 3200, reason: 'test') if @objectives.current
    loop_in.(4000)
    talk_log.give(place: [165, 16], item: 12)
    choose.(6800)
    refute_equal 'souvenir-165-16-t64', @objectives.current&.dig(:candidate), 'the delivery fired: the menu no longer offers it'
  end

  # Gate run 15df: at 8 hp after 82/0, the way to the hut crossed 66/0's enemies; 83/0, where a talk had healed Link at 88340, was a room away.
  def test_at_one_heart_a_way_through_enemies_first_goes_to_heal_where_a_talk_healed_link_then_takes_the_objective_up_again
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    healers = Koholint::Healers.new
    healers.saw(place: [164, 16], health: 8)
    healers.heard([164, 16])
    healers.saw(place: [164, 16], health: 24)
    cards = { [165, 16] => { enemies: [{ type: 27, cell: [4, 5] }] }, [164, 16] => { unknown: [{ type: 132, cell: [3, 5] }] } }
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 100, title: 'Bring the champignon', predicate: { kind: 'reach_place', place: [165, 16] }, candidate: 'souvenir-165-16-t64', target: { kind: 'person', place: [165, 16], type: 64, cell: [4, 4], try: true, item: 12 })
    souvenirs = [{ 'place' => [165, 16], 'entity' => 64, 'cell' => [4, 4], 'text' => 'Il me faut le champignon de la forêt.', 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1, 4] }] }]
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                          memory: Koholint::Policies::Memory.new(explore_log: log, cards:, healers:), souvenirs:)
    full = state(frame: 200, hp: 24, item_b: 12)
    p.observe(full, frame: 200)
    refute_match(/heal/, p.decide(p.decision_point_for(full), full, { grid: })[:justification].to_s, 'not at full health')
    low = state(frame: 300, hp: 8, item_b: 12)
    p.observe(low, frame: 300)
    context = { grid: }
    detour = p.decide(p.decision_point_for(low), low, context)
    assert_match(/heal in 164-16 first/, detour[:justification])
    assert_equal [{ place: [164, 16] }, { kind: 'person', place: [164, 16], type: 132, cell: [3, 5], heal_below: 8 }, 'heal'], [context[:aim], @objectives.current[:target], @objectives.history.last[:reason]]
    @objectives.abandon(frame: 400, reason: 'test')
    healed = state(frame: 500, hp: 24, room_id: 164, item_b: 12)
    p.observe(healed, frame: 500)
    p.decide(p.decision_point_for(healed), healed, { grid: })
    assert_equal 'souvenir-165-16-t64', @objectives.current[:candidate]
  end

  def lineage_with_a_healer_and_an_eight_hp_hit(leads: nil)
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 162, map: 14 }, exits: [{ row: 7, col: 4, direction: :down, outcome: :left, to: [100, 0] }], survey: { sides: { down: [{ row: 7, col: 4 }] }, doors: [] } })
    log.absorb({ from: { room: 100, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [84, 0] }], survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 84, map: 0 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [83, 0] }], survey: { sides: { left: [{ row: 3, col: 0 }] }, doors: [] } })
    healers = Koholint::Healers.new
    healers.saw(place: [83, 0], health: 4)
    healers.heard([83, 0])
    healers.saw(place: [83, 0], health: 24)
    healers.saw(place: [84, 0], health: 20)
    healers.saw(place: [99, 0], health: 16)
    healers.saw(place: [99, 0], health: 8)
    cards = { [83, 0] => { unknown: [{ type: 132, cell: [3, 5] }] } }
    Koholint::Policies::Memory.new(explore_log: log, cards:, healers:, leads:)
  end

  # Run d871: an 8 hp hit measured, 83/0 healed at 96398; at 99915 in 162/14 with 8 hp the model chose the next objective and died later from 8 hp.
  # Here the places on the way hit for at most 4.
  def test_at_or_below_the_largest_measured_hit_the_next_objective_is_to_heal_where_a_talk_healed_link_without_asking_the_model
    @objectives = Koholint::Objectives.new(trace: trace)
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: lineage_with_a_healer_and_an_eight_hp_hit)
    low = state(frame: 99915, room_id: 162, map_id: 14, hp: 8)
    p.observe(low, frame: 99915)
    context = { grid: }
    decision = p.decide(p.decision_point_for(low), low, context)
    assert_match(/8 hp and the largest hit measured is 8 hp: heal in 83-0 first/, decision[:justification])
    assert_equal [[83, 0], { kind: 'person', place: [83, 0], type: 132, cell: [3, 5], heal_below: 8 }], [@objectives.current.dig(:predicate, :place), @objectives.current[:target]]
    assert_empty client.calls
  end

  # Stub gate 9666 (flow-105 at 1d642de): the heal set out from 84/0 at 8 hp, then the low-health hold handed every step to the model, which wandered back east and died.
  def test_the_heal_objective_is_followed_by_the_autopilot_at_low_health
    @objectives = Koholint::Objectives.new(trace: trace)
    client = ScriptedClient.new(objective: new_place, default: explore)
    autopilot = Koholint::Autopilot.new
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', autopilot:,
                                          memory: lineage_with_a_healer_and_an_eight_hp_hit)
    low = state(frame: 99687, room_id: 84, map_id: 0, hp: 8)
    autopilot.model_called(state: state(frame: 99600, room_id: 84, map_id: 0, hp: 16), objective: nil)
    p.observe(low, frame: 99687)
    assert_match(/heal in 83-0 first/, p.decide(p.decision_point_for(low), low, { grid: })[:justification])
    autopilot.acted(skill: 'explore', outcome: { stopped_by: 'damage' })
    later = state(frame: 99725, room_id: 84, map_id: 0, hp: 4)
    p.observe(later, frame: 99725)
    decision = p.decide(p.decision_point_for(later), later, { grid: })
    assert_empty client.calls, decision[:justification]
  end

  # Stub gate 355b (flow-105 at 9bbd554): from 84/0 at 8 hp the only known way to 83/0 went through 66/0's type 27; Link was hemmed there, wandered back and died.
  def test_below_the_measured_hit_no_heal_is_sent_by_a_way_through_enemies
    memory = lineage_with_a_healer_and_an_eight_hp_hit
    memory.cards[[100, 0]] = { enemies: [{ type: 27, cell: [4, 5] }] }
    @objectives = Koholint::Objectives.new(trace: trace)
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory:)
    low = state(frame: 99915, room_id: 162, map_id: 14, hp: 8)
    p.observe(low, frame: 99915)
    refute_match(/heal/, p.decide(p.decision_point_for(low), low, { grid: })[:justification].to_s)
  end

  # Stub gate 7c9c (flow-106 at f03aac0), 68/0 at 101171 with 4 hp: the zero-frame redirect explored toward 84/0, the nearest place with untried work,
  # where hits of 8 were measured; Link was hit there at 101406 and died.
  def test_no_harness_route_enters_a_place_whose_measured_hit_would_take_links_health
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 68, map: 0 }, exits: [{ row: 4, col: 0, direction: :left, outcome: :left, to: [67, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [84, 0] }],
                 survey: { sides: { left: [{ row: 4, col: 0 }], down: [{ row: 7, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 84, map: 0 }, exits: [], survey: { sides: { up: [{ row: 0, col: 5 }], right: [{ row: 3, col: 9 }] }, doors: [] } })
    log.absorb({ from: { room: 67, map: 0 }, exits: [{ row: 4, col: 9, direction: :right, outcome: :left, to: [68, 0] }], survey: { sides: { right: [{ row: 4, col: 9 }] }, doors: [] } })
    healers = Koholint::Healers.new
    [[67, 0], [68, 0]].each { |place| healers.saw(place:, health: 24) }
    healers.saw(place: [84, 0], health: 20)
    healers.saw(place: [84, 0], health: 12)
    healers.saw(place: [68, 0], health: 4)
    assert_equal [84, 0], log.route([68, 0])&.dig(:goal), 'untried work in 84/0'
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                          memory: Koholint::Policies::Memory.new(explore_log: log, healers:))
    low = state(frame: 101171, room_id: 68, map_id: 0, hp: 4)
    p.observe(low, frame: 101171)
    p.decide(p.decision_point_for(low), low, { grid: })
    assert_nil log.route([68, 0]), 'at 4 hp no route enters 84/0'
    refute_equal [84, 0], log.least_visited([68, 0])&.dig(:goal)
    assert_equal [84, 0], log.route([68, 0], goal: [84, 0])&.dig(:goal), 'an objective may still lead there'
    assert_match(/which the harness never walks into: 84-0 \(8 hp\)/, p.send(:route_line, low))
  end

  # Run d871 at 99915: the way out of 162/14 to 83/0 crosses 84/0, which hit for 8 at 98204, so at 8 hp no heal is sent that way.
  def test_no_heal_is_sent_by_a_way_through_a_place_whose_measured_hit_would_take_links_health
    memory = lineage_with_a_healer_and_an_eight_hp_hit
    memory.healers.saw(place: [84, 0], health: 20)
    memory.healers.saw(place: [84, 0], health: 12)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory:)
    low = state(frame: 99915, room_id: 162, map_id: 14, hp: 8)
    p.observe(low, frame: 99915)
    refute_match(/heal/, p.decide(p.decision_point_for(low), low, { grid: })[:justification].to_s)
  end

  # Review of #113 (diamond): the heal picked its place by the safe way but explore routed unbanned, so its first hop could enter the shorter dangerous way.
  def test_the_heal_walk_keeps_to_the_safe_way_it_was_picked_by
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [2, 0] }, { row: 7, col: 5, direction: :down, outcome: :left, to: [3, 0] }] })
    log.absorb({ from: { room: 2, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [83, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [4, 0] }] })
    log.absorb({ from: { room: 4, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [83, 0] }] })
    healers = Koholint::Healers.new
    healers.saw(place: [83, 0], health: 4)
    healers.heard([83, 0])
    healers.saw(place: [83, 0], health: 24)
    [[3, 0], [4, 0]].each { |place| healers.saw(place:, health: 24) }
    healers.saw(place: [2, 0], health: 16)
    healers.saw(place: [2, 0], health: 8)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                          memory: Koholint::Policies::Memory.new(explore_log: log, healers:))
    low = state(frame: 100, room_id: 1, map_id: 0, hp: 8)
    p.observe(low, frame: 100)
    context = { grid: }
    assert_match(/heal in 83-0 first/, p.decide(p.decision_point_for(low), low, context)[:justification])
    assert_equal [3, 0], log.route([1, 0], goal: context.dig(:aim, :place), ban: context[:ban])[:next]
  end

  # Stub fork 5b45 (0e98 @101300, flow-107): the heal set out at 8 hp in 66/0; at 4 hp the autopilot kept walking it through 66/0 toward 82/0,
  # both measured at 4 hp hits, and Link died at 102771.
  def test_an_objective_way_through_a_place_whose_measured_hit_would_take_links_health_is_left_to_the_model
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 66, map: 0 }, exits: [{ row: 7, col: 5, direction: :down, outcome: :left, to: [82, 0] }], survey: { sides: { down: [{ row: 7, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 82, map: 0 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [83, 0] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    healers = Koholint::Healers.new
    healers.saw(place: [83, 0], health: 4)
    healers.heard([83, 0])
    healers.saw(place: [83, 0], health: 24)
    healers.saw(place: [82, 0], health: 24)
    healers.saw(place: [82, 0], health: 20)
    healers.saw(place: [66, 0], health: 12)
    healers.saw(place: [66, 0], health: 8)
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 102310, title: 'Heal in 83-0, where a talk healed Link before', predicate: { kind: 'reach_place', place: [83, 0] },
                      target: { kind: 'place', place: [83, 0], heal_below: 8 })
    client = ScriptedClient.new(default: explore)
    autopilot = Koholint::Autopilot.new
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', autopilot:,
                                          memory: Koholint::Policies::Memory.new(explore_log: log, healers:))
    autopilot.model_called(state: state(frame: 102300, room_id: 66, map_id: 0, hp: 8), objective: @objectives.current)
    walking = state(frame: 102320, room_id: 66, map_id: 0, hp: 8)
    p.observe(walking, frame: 102320)
    context = { grid: }
    assert_equal 'delegated', p.decide(p.decision_point_for(walking), walking, context)[:agent], 'at 8 hp the way hits for less'
    assert context[:fragile], 'at the lineage hit'
    p.after_action(choice: { skill: 'explore', params: {} }, outcome: { stopped_by: 'no_frontier', held_back: true, from: { room: 66, map: 0, row: 3, col: 8 } }, state: walking, frame: 102374)
    assert_equal [nil, 'unreachable'], [@objectives.current, @objectives.history.last[:reason]]
    @objectives.start(frame: 102380, title: 'Heal in 83-0, where a talk healed Link before', predicate: { kind: 'reach_place', place: [83, 0] },
                      target: { kind: 'place', place: [83, 0], heal_below: 8 })
    autopilot.acted(skill: 'explore', outcome: { stopped_by: 'damage' })
    hurt = state(frame: 102390, room_id: 66, map_id: 0, hp: 4)
    p.observe(hurt, frame: 102390)
    assert_equal 'claude', p.decide(p.decision_point_for(hurt), hurt, { grid: })[:agent]
    assert_match(/which the harness never walks into: .*82-0 \(4 hp\)/, client.calls.last[:prompt])
  end

  # Run 0e98, 84/0 at 4 hp from 101616: the objective was to talk to type 185, not a way through enemies, and Link stayed at 4 hp until the stop.
  def test_below_the_measured_hit_any_objective_gives_way_to_the_heal_at_the_skill_choice
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 101600, title: 'Try type 185', predicate: { kind: 'new_text' }, target: { kind: 'person', place: [84, 0], type: 185, cell: [2, 2] })
    client = ScriptedClient.new(default: explore)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: lineage_with_a_healer_and_an_eight_hp_hit)
    full = state(frame: 101500, room_id: 84, map_id: 0, hp: 12)
    p.observe(full, frame: 101500)
    refute_match(/heal/, p.decide(p.decision_point_for(full), full, { grid: })[:justification].to_s, 'above the measured hit')
    low = state(frame: 101616, room_id: 84, map_id: 0, hp: 4)
    p.observe(low, frame: 101616)
    decision = p.decide(p.decision_point_for(low), low, { grid: })
    assert_match(/heal in 83-0 first/, decision[:justification])
    assert_equal 'heal', @objectives.history.last[:reason]
  end

  # Run 0e98, lead-27 at 100422: the model's claim named the person beyond the quoted text, so a lead set aside for a heal goes back to the menu.
  def test_a_lead_set_aside_by_a_heal_is_never_taken_up_again_by_the_harness_alone
    leads = Koholint::Leads.from_events([{ 'type' => 'lead', 'id' => 'lead-27', 'place' => [162, 14], 'where' => '84-0', 'quote' => "Tu m'apportes le Champignon",
                                           'claim' => 'The witch wants the mushroom', 'importance' => 'high' }])
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 100422, title: 'Go to 84-0', predicate: { kind: 'reach_place', place: [84, 0] }, candidate: 'lead-27', target: { kind: 'lead', place: [84, 0], lead: 'lead-27' })
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: lineage_with_a_healer_and_an_eight_hp_hit(leads:))
    low = state(frame: 100500, room_id: 100, map_id: 0, hp: 8)
    p.observe(low, frame: 100500)
    assert_match(/heal in 83-0 first/, p.decide(p.decision_point_for(low), low, { grid: })[:justification])
    @objectives.abandon(frame: 100600, reason: 'test')
    healed = state(frame: 100700, room_id: 83, map_id: 0, hp: 24)
    p.observe(healed, frame: 100700)
    p.decide(p.decision_point_for(healed), healed, { grid: })
    refute_equal 'lead-27', @objectives.current&.dig(:candidate)
    assert(client.calls.any? { |call| call[:system].include?('choose the next objective') })
  end

  def heal_lineage_with_a_souvenir(reoffers: {})
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 3, col: 0, direction: :left, outcome: :left, to: [164, 16] }, { row: 0, col: 5, direction: :up, outcome: :left, to: [165, 16] }],
                 survey: { sides: { left: [{ row: 3, col: 0 }], up: [{ row: 0, col: 5 }] }, doors: [] } })
    log.absorb({ from: { room: 164, map: 16 }, exits: [{ row: 3, col: 9, direction: :right, outcome: :left, to: [163, 16] }], survey: { sides: { right: [{ row: 3, col: 9 }] }, doors: [] } })
    healers = Koholint::Healers.new
    healers.saw(place: [164, 16], health: 20)
    healers.heard([164, 16])
    healers.saw(place: [164, 16], health: 24)
    healers.saw(place: [164, 16], health: 20)
    cards = { [165, 16] => { enemies: [{ type: 27, cell: [4, 5] }] }, [164, 16] => { unknown: [{ type: 132, cell: [3, 5] }] } }
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 100, title: 'Bring the champignon', predicate: { kind: 'reach_place', place: [165, 16] }, candidate: 'souvenir-165-16-t64', target: { kind: 'person', place: [165, 16], type: 64, cell: [4, 4], try: true, item: 12 })
    souvenirs = [{ 'place' => [165, 16], 'entity' => 64, 'cell' => [4, 4], 'text' => 'Il me faut le champignon de la forêt.', 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1, 4] }] }]
    Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: new_place, default: explore), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                      memory: Koholint::Policies::Memory.new(explore_log: log, cards:, healers:, reoffers:), souvenirs:)
  end

  # Paid fork g7-2 (4e10, flow-108): the loop break had already given the delivery back twice when the heal at 101033 set it aside; after the heal
  # at 101838 nothing gave it back, and at 102174 the model saw it 9th in its options and explored elsewhere to the end.
  def test_the_objective_a_heal_set_aside_comes_back_when_the_heal_is_over_outside_the_re_offer_cap
    p = heal_lineage_with_a_souvenir(reoffers: { 'souvenir-165-16-t64' => 2 })
    low = state(frame: 101033, hp: 8, item_b: 12)
    p.observe(low, frame: 101033)
    assert_match(/heal in 164-16 first/, p.decide(p.decision_point_for(low), low, { grid: })[:justification])
    @objectives.abandon(frame: 101838, reason: 'test')
    healed = state(frame: 102174, hp: 24, room_id: 164, item_b: 12)
    p.observe(healed, frame: 102174)
    decision = p.decide(p.decision_point_for(healed), healed, { grid: })
    assert_equal ['souvenir-165-16-t64', 'the heal is over: souvenir-165-16-t64, set aside for it, is taken up again'], [@objectives.current&.dig(:candidate), decision[:justification]]
  end

  # Paid fork g7-2 (4e10, flow-108): at 98830 in 82/0 with 8 hp the loop break replaced the heal started at 98678, and Link wandered at one heart
  # until 101033; a heal holds against a loop until hp rises, and once it is over the objective it set aside comes back before the loop break.
  def test_a_loop_break_never_replaces_a_heal_before_hp_rises_and_the_set_aside_objective_comes_back_before_it
    p = heal_lineage_with_a_souvenir
    low = state(frame: 98678, hp: 8, item_b: 12)
    p.observe(low, frame: 98678)
    assert_match(/heal in 164-16 first/, p.decide(p.decision_point_for(low), low, { grid: })[:justification])
    [164, 163, 164, 163, 164, 163, 164, 163, 164].each_with_index do |room, i|
      now = state(frame: 98700 + (i * 300), room_id: room, hp: 8, item_b: 12)
      p.observe(now, frame: now.frame)
      refute_match(/loop in/, p.decide(p.decision_point_for(now), now, { grid: })[:justification].to_s)
    end
    assert @objectives.current[:heal]
    @objectives.abandon(frame: 101800, reason: 'test')
    healed = state(frame: 101838, hp: 24, room_id: 164, item_b: 12)
    p.observe(healed, frame: 101838)
    assert_match(/\Athe heal is over: souvenir-165-16-t64/, p.decide(p.decision_point_for(healed), healed, { grid: })[:justification])
    assert_equal 'souvenir-165-16-t64', @objectives.current[:candidate]
  end

  # Review of #115 (KOHO-146): a lead the guard sets aside goes back to the menu, never to a harness-alone take, as with a heal.
  def test_a_lead_the_guard_sets_aside_is_never_taken_up_again_by_the_harness_alone
    leads = Koholint::Leads.from_events([{ 'type' => 'lead', 'id' => 'lead-27', 'place' => [162, 14], 'where' => '164-16', 'quote' => "Tu m'apportes le Champignon",
                                           'claim' => 'The witch wants the mushroom', 'importance' => 'high' }])
    @objectives = Koholint::Objectives.new(trace: trace)
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(leads:))
    p.instance_variable_set(:@entities_reader, -> { [{ slot: 2, type: 27, kind: 'enemy', x: 84, y: 60, contact: 11, cell: [3, 5] }] })
    decide(p)
    @objectives.abandon(frame: 200, reason: 'test') if @objectives.current
    @objectives.start(frame: 250, title: 'Go to 164-16', predicate: { kind: 'reach_place', place: [164, 16] }, candidate: 'lead-27', target: { kind: 'lead', place: [164, 16], lead: 'lead-27' })
    [300, 800, 1300].each do |frame|
      here = state(frame:, hp: 24)
      p.instance_variable_set(:@retreated, nil)
      result = p.decide(p.decision_point_for(here), here, { grid: })
      p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: here, frame:)
      result = p.decide(p.decision_point_for(here), here, { grid: })
      p.after_action(choice: result[:choice], outcome: outcome(:known_place, 0).merge(frames: 40, moved_cells: 2, cells_walked: 2), state: here, frame: frame + 1)
    end
    assert_equal ['lead-27', 'guarded'], @objectives.history.last.values_at(:candidate, :reason)
    @objectives.abandon(frame: 1400, reason: 'test')
    later = state(frame: 1500, room_id: 165, hp: 24)
    p.observe(later, frame: 1500)
    refute_match(/lead-27/, p.decide(p.decision_point_for(later), later, { grid: })[:justification].to_s)
    refute_equal 'lead-27', @objectives.current&.dig(:candidate)
  end

  # Review of #115 (KOHO-146): a delivery the menu no longer offers is not taken up again when the heal is over.
  def test_the_objective_a_heal_set_aside_is_not_taken_up_again_once_the_menu_no_longer_offers_it
    p = heal_lineage_with_a_souvenir
    low = state(frame: 98678, hp: 8, item_b: 12)
    p.observe(low, frame: 98678)
    assert_match(/heal in 164-16 first/, p.decide(p.decision_point_for(low), low, { grid: })[:justification])
    @objectives.abandon(frame: 101800, reason: 'test')
    healed = state(frame: 101838, hp: 24, room_id: 164)
    p.observe(healed, frame: 101838)
    refute_match(/heal is over/, p.decide(p.decision_point_for(healed), healed, { grid: })[:justification].to_s)
    refute_equal 'souvenir-165-16-t64', @objectives.current&.dig(:candidate)
  end

  def c5_attack(stop, target, at: [7, 5]) = { skill: 'attack', params: { row: target[:cell][0], col: target[:cell][1] }, stopped_by: stop, target:, moved_cells: 0, hp_delta: 0,
                                                from: { room: 66, map: 0, row: at[0], col: at[1] }, to: { room: 66, map: 0, row: at[0], col: at[1] } }

  def blob(slot, x, y) = { slot:, type: 28, kind: 'unknown', moves: true, x:, y:, cell: [(y - 8) / 16, x / 16] }

  # Paid fork g7-2 (4e10, flow-108), C5 (66/0) at 97280: from (6,5), one hit on the type 27 at (5,4) ended target_gone; its slot became a type 28 beside a
  # second one where it stood, and the autopilot explored on into them. What appears in the struck slot or on its cell is fought as an enemy until struck once.
  def test_what_appears_where_an_enemy_was_just_hit_is_fought_as_an_enemy_until_struck
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    blobs = [blob(2, 72, 90), blob(14, 76, 92)]
    p.instance_variable_set(:@entities_reader, -> { blobs })
    decide(p, state(frame: 97200, room_id: 66, map_id: 0, x: 84, y: 104))
    hit = c5_attack(:target_gone, { slot: 2, type: 27, cell: [5, 4] }, at: [6, 5])
    p.after_action(choice: { skill: 'attack', params: hit[:params] }, outcome: hit, state: state(frame: 97280, room_id: 66, map_id: 0, x: 84, y: 104), frame: 97280)
    now = state(frame: 97289, room_id: 66, map_id: 0, x: 84, y: 104)
    p.observe(now, frame: 97289)
    result = p.decide(p.decision_point_for(now), now, { grid: })
    assert_equal [{ skill: 'attack', params: { row: 5, col: 4 } }, 'delegated'], [result[:choice], result[:agent]]
    assert_match(/fight type 28 at \(5,4\), not identified, taken for an enemy/, result[:justification])
    struck = c5_attack(:blocked, { slot: 2, type: 28, cell: [5, 4] }, at: [6, 5])
    p.after_action(choice: { skill: 'attack', params: struck[:params] }, outcome: struck, state: now, frame: 97300)
    blobs.replace([blob(2, 72, 90), blob(14, 76, 106)])
    later = state(frame: 97310, room_id: 66, map_id: 0, x: 84, y: 104)
    p.observe(later, frame: 97310)
    assert_match(/fight type 28 at \(6,4\)/, p.decide(p.decision_point_for(later), later, { grid: })[:justification], 'the second one is still taken for an enemy, the struck one no more')
    blobs.replace([{ slot: 14, type: 46, kind: 'creature', moves: false, x: 76, y: 106, cell: [6, 4] }])
    reused = state(frame: 97330, room_id: 66, map_id: 0, x: 84, y: 104)
    p.observe(reused, frame: 97330)
    refute_match(/fight type 46/, p.decide(p.decision_point_for(reused), reused, { grid: })[:justification].to_s, 'gate 150d at 98029: the slot came back as a still type 46')
  end

  # Review of #116 (KOHO-147): gate 71fb struck type 5 (uncatalogued) and type 46 (catalogued as still) beside a struck type 27; a person could be there too.
  def test_an_uncatalogued_or_still_thing_where_an_enemy_was_just_hit_is_not_fought
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    p.instance_variable_set(:@entities_reader, -> { [{ slot: 2, type: 5, kind: 'unknown', x: 72, y: 90, cell: [5, 4] }, { slot: 13, type: 46, kind: 'creature', moves: false, x: 76, y: 92, cell: [5, 4] }] })
    decide(p, state(frame: 97200, room_id: 66, map_id: 0, x: 84, y: 104))
    hit = c5_attack(:target_gone, { slot: 2, type: 27, cell: [5, 4] }, at: [6, 5])
    p.after_action(choice: { skill: 'attack', params: hit[:params] }, outcome: hit, state: state(frame: 97280, room_id: 66, map_id: 0, x: 84, y: 104), frame: 97280)
    now = state(frame: 97289, room_id: 66, map_id: 0, x: 84, y: 104)
    p.observe(now, frame: 97289)
    refute_match(/fight type/, p.decide(p.decision_point_for(now), now, { grid: })[:justification].to_s)
  end

  def test_a_heal_objective_in_a_place_with_several_people_closes_when_hp_rises_not_on_arrival
    @objectives = Koholint::Objectives.new(trace: trace)
    @objectives.start(frame: 100, title: 'Heal in 164-16, where a talk healed Link before', predicate: { kind: 'reach_place', place: [164, 16] }, target: { kind: 'place', place: [164, 16], heal_below: 8 })
    arrived = state(frame: 200, room_id: 164, hp: 8)
    assert_nil @objectives.update(arrived, frame: 200), 'arriving heals nothing'
    healed = state(frame: 300, room_id: 164, hp: 24)
    assert_equal :achieved, @objectives.update(healed, frame: 300)
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

  # Run f741, 172/10 at 4 hp: every route out crossed a type 155's contact zone, and explore and a 120-frame wait alternated 94 times.
  def test_at_one_heart_after_three_waits_that_changed_nothing_explore_leaves_by_the_side_link_came_in
    answers = lambda do |hp|
      client = ScriptedClient.new(objective: new_place, default: explore)
      p = autopiloted(client, autopilot: nil)
      low = state(hp:)
      decide(p)
      instant = outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0)
      (1..4).map do |n|
        result = p.decide(p.decision_point_for(low), low, { grid: })
        p.after_action(choice: result[:choice], outcome: instant, state: low, frame: 200 + (n * 300))
        context = { grid: }
        result = p.decide(p.decision_point_for(low), low, context)
        p.after_action(choice: result[:choice], outcome: { skill: 'wait', params: { frames: 120 }, frames: 120, stopped_by: 'done' }, state: low, frame: 300 + (n * 300))
        [result[:choice][:skill], context[:retreat]]
      end
    end
    assert_equal [['wait', nil]] * 3 + [['explore', true]], answers.(8)
    assert_equal [['wait', nil]] * 4, answers.(24), 'above one heart the waits go on'
  end

  # Run 5442, 66/0 at 24 hp: two 120-frame waits beside the type 27s took Link from 24 to 8 hp.
  def test_at_full_health_with_a_hostile_in_touch_explore_leaves_by_the_side_link_came_in_without_waiting
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: nil)
    p.instance_variable_set(:@entities_reader, -> { [{ slot: 2, type: 27, kind: 'enemy', x: 84, y: 60, contact: 11, cell: [3, 5] }] })
    full = state(hp: 24)
    decide(p)
    result = p.decide(p.decision_point_for(full), full, { grid: })
    p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: full, frame: 300)
    context = { grid: }
    result = p.decide(p.decision_point_for(full), full, context)
    assert_equal ['explore', true], [result[:choice][:skill], context[:retreat]]
    p.observe(full, frame: 301)
    refute_nil p.instance_variable_get(:@retreated), 'full health is no heal: the way back is not sent again from that cell'
  end

  # Gate run 15df: sent back from 66/0 to 65/0 about every 440 frames, Link came back each time and was sent back again.
  def test_a_third_retreat_by_the_same_side_within_the_window_marks_the_place_guarded_and_sets_the_objective_aside
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: nil)
    p.instance_variable_set(:@entities_reader, -> { [{ slot: 2, type: 27, kind: 'enemy', x: 84, y: 60, contact: 11, cell: [3, 5] }] })
    decide(p)
    events = []
    answers = [300, 800, 1300].map do |frame|
      here = state(frame:, hp: 24)
      p.instance_variable_set(:@retreated, nil)
      result = p.decide(p.decision_point_for(here), here, { grid: })
      p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: here, frame:)
      context = { grid: }
      result = p.decide(p.decision_point_for(here), here, context)
      events << { 'type' => 'decision', 'frame' => frame, 'input' => { 'room_id' => here.room_id, 'map_id' => here.map_id }, 'justification' => result[:justification] }
      p.after_action(choice: result[:choice], outcome: outcome(:known_place, 0).merge(frames: 40, moved_cells: 2, cells_walked: 2), state: here, frame: frame + 1)
      [context[:retreat], result[:justification].to_s[/guarded/]]
    end
    assert_equal [[true, nil], [true, nil], [nil, 'guarded']], answers
    assert_equal 'guarded', @objectives.history.last[:reason]
    assert_equal p.instance_variable_get(:@retreats), Koholint::Policies::Memory.from_events(events).retreats, 'a resume reads the retreats back'
  end

  def test_a_resume_reads_back_the_heal_detours_and_the_re_offers
    events = [{ 'type' => 'objective', 'frame' => 10, 'id' => 'obj-1', 'status' => 'started', 'target' => { 'kind' => 'place', 'place' => [83, 0], 'heal_below' => 8 } },
              { 'type' => 'decision', 'frame' => 20, 'input' => {}, 'justification' => 'the loop is cut: souvenir-162-14-t64, set aside, is taken up again (1/2)' }]
    memory = Koholint::Policies::Memory.from_events(events)
    assert_equal [1, { 'souvenir-162-14-t64' => 1 }], [memory.healers.detours, memory.reoffers]
  end

  # Run 5e81, 172/10 at 4 hp: the type 155 walked up to Link during the first 120-frame wait and killed him.
  def test_at_one_heart_with_a_hostile_in_touch_explore_leaves_by_the_side_link_came_in_without_waiting
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client, autopilot: nil)
    hostile = { slot: 3, type: 155, kind: 'enemy', x: 68, y: 84, contact: 11, cell: [4, 4] }
    p.instance_variable_set(:@entities_reader, -> { [hostile] })
    low = state(hp: 8)
    decide(p)
    result = p.decide(p.decision_point_for(low), low, { grid: })
    p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: low, frame: 300)
    context = { grid: }
    result = p.decide(p.decision_point_for(low), low, context)
    assert_equal ['explore', true], [result[:choice][:skill], context[:retreat]]
    assert_match(/hostile in touch/, result[:justification])
    p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: low, frame: 301)
    result = p.decide(p.decision_point_for(low), low, { grid: })
    p.after_action(choice: result[:choice], outcome: outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0), state: low, frame: 302)
    context = { grid: }
    result = p.decide(p.decision_point_for(low), low, context)
    assert_equal ['wait', nil], [result[:choice][:skill], context[:retreat]], 'a way back that is out of reach too is not sent again from that cell'
    p.observe(state(hp: 24), frame: 400)
    assert_nil p.instance_variable_get(:@retreated), 'a heal lifts it'
    p.instance_variable_set(:@retreated, { spot: [low.place, low.cell], hp: 8 })
    p.observe(state(hp: 8, room_id: 9), frame: 410)
    assert_nil p.instance_variable_get(:@retreated), 'another place lifts it'
    p.instance_variable_set(:@retreated, { spot: [low.place, low.cell], hp: 24 })
    p.observe(state(hp: 20), frame: 420)
    refute_nil p.instance_variable_get(:@retreated), 'damage does not lift it'
    p.observe(state(hp: 24), frame: 430)
    assert_nil p.instance_variable_get(:@retreated), 'a heal back to the health it was sent at lifts it'
  end

  # Review of #111: with the only way out leading into a place whose measured hit would take Link's health, the zero-frame cap waited 120 frames instead of asking.
  def test_with_only_dangerous_ways_left_the_zero_frame_cap_hands_the_choice_to_the_model_with_the_danger_listed
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 163, map: 16 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [147, 16] }] })
    healers = Koholint::Healers.new
    healers.saw(place: [147, 16], health: 24)
    healers.saw(place: [147, 16], health: 0)
    client = ScriptedClient.new(objective: new_place, default: explore)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', memory: Koholint::Policies::Memory.new(explore_log: log, healers:))
    decide(p)
    instant = outcome(:no_frontier, 0).merge(frames: 1, moved_cells: 0, cells_walked: 0)
    3.times { |i| p.after_action(choice: { skill: 'explore', params: {} }, outcome: instant, state:, frame: 600 + i) }
    calls = client.calls.size
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal ['claude', calls + 1], [result[:agent], client.calls.size]
    assert_match(/which the harness never walks into: 147-16 \(24 hp\)/, client.calls.last[:prompt])
    p.after_action(choice: result[:choice], outcome: instant, state:, frame: 700)
    result = p.decide(p.decision_point_for(state), state, { grid: })
    assert_equal [{ skill: 'wait', params: { frames: 120 } }, 'delegated'], [result[:choice], result[:agent]], 'once per spot, then the bounded wait'
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

  # Runs d871, 0e98 and 2c93 (g6): 84/0 had hit Link for 8 hp (d871 98187); the harness then tried types 185 and 203 there with talk_to and took 8 hp
  # each time (d871 102332, 0e98 101616, 2c93 101833 and 102369). The entity census (b8b7 @100867, cleared control) measures 185 hostile, 203 not.
  def test_the_harness_never_tries_a_type_that_hurt_link
    tried = lambda do |hurt|
      client = ScriptedClient.new(objective: new_place, default: explore)
      p = autopiloted(client)
      ctx = { grid:, entities: -> { [{ kind: :unknown, type: 185, cell: [2, 2], slot: 3, x: 40, y: 48 }] } }
      p.prepare(ctx)
      p.note_card({ place: [163, 16], unknown: [{ type: 185, cell: [2, 2] }] })
      p.observe(state(frame: 50, hp: 24), frame: 50)
      hit = outcome(:damage, 0).merge(hp_delta: hurt ? -8 : 0)
      p.after_action(choice: { skill: 'explore', params: {} }, outcome: hit, state: state(frame: 60, x: 44, y: 52, hp: hurt ? 16 : 24), frame: 60)
      tours(p, 2)
      p.decide(p.decision_point_for(state(frame: 800)), state(frame: 800), ctx)[:choice][:skill]
    end
    assert_equal 'talk_to', tried.(false), 'control: a type that never hurt Link is tried'
    refute_equal 'talk_to', tried.(true)
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

  def test_a_thing_to_try_is_talked_to_then_touched_through_the_touch_decision_point_even_at_low_health
    client = ScriptedClient.new(objective: new_place, default: explore)
    pilot = Koholint::Autopilot.new
    p = autopiloted(client, autopilot: pilot)
    here = [state.room_id, state.map_id]
    ctx = { grid:, entities: -> { [{ kind: :unknown, type: 132, cell: [2, 2], slot: 3, x: 40, y: 48 }] } }
    p.prepare(ctx)
    tours(p, 2)
    @objectives.start(frame: 700, title: 'Go examine', predicate: { kind: 'reach_place', place: here }, target: { kind: 'person', place: here, type: 132, cell: [2, 2], try: true })
    pilot.adopt(@objectives.current)
    low = state(frame: 800, hp: 8)
    result = p.decide(p.decision_point_for(low), low, ctx)
    assert_equal [true, { skill: 'talk_to', params: { row: 2, col: 2 } }], result.values_at(:autopilot, :choice)
    p.after_action(choice: result[:choice], outcome: { skill: 'talk_to', params: { row: 2, col: 2 }, stopped_by: 'no_path', talked: false, target_type: 132,
                                                       from: { room: here[0], map: here[1], row: 3, col: 4 }, to: { room: here[0], map: here[1], row: 3, col: 4 } },
                   state: state(frame: 900, hp: 8), frame: 900)
    refute @objectives.talked_to?, 'a talk that never reached the thing'
    p.after_action(choice: result[:choice], outcome: { skill: 'talk_to', params: { row: 2, col: 2 }, stopped_by: 'no_response', talked: false, target_type: 132,
                                                       from: { room: here[0], map: here[1], row: 3, col: 4 }, to: { room: here[0], map: here[1], row: 2, col: 3 } },
                   state: state(frame: 950, hp: 8), frame: 950)
    low = state(frame: 1000, hp: 8)
    result = p.decide(p.decision_point_for(low), low, ctx)
    touch = { skill: 'touch', params: { row: 2, col: 2, type: 132 } }
    assert_equal [true, touch], result.values_at(:autopilot, :choice)
    assert_equal touch, result[:decision_point].validate(result[:choice])
    p.after_action(choice: touch, outcome: { skill: 'touch', params: touch[:params], stopped_by: 'no_contact', target_type: 132,
                                             from: { room: here[0], map: here[1], row: 2, col: 3 }, to: { room: here[0], map: here[1], row: 2, col: 3 } },
                   state: state(frame: 1100, hp: 8), frame: 1100)
    assert @objectives.current, 'a touch that never reached the thing'
  end

  def test_below_full_health_a_visible_heart_is_taken_with_a_safe_touch_and_the_chain_goes_on
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = autopiloted(client)
    beliefs = Koholint::Vision::Beliefs.new
    beliefs.record(appearance: 'floor', action: :walk, direction: :up, result: :yes, method: 't', context: Koholint::Vision::Capabilities.new, frame: 1, source: 't')
    seen = Koholint::Vision::Grid.new(cells: Array.new(8) { Array.new(10) { 'floor' } }, static_sprites: [{ 'x' => 40, 'y' => 48, 'pattern' => 'heart' }], beliefs:,
                                      capabilities: Koholint::Vision::Capabilities.new)
    heart = { slot: 3, kind: :creature, type: 45, x: 40, y: 48, cell: [2, 2], heals: 8 }
    tours(p, 2)
    ctx = { grid: seen, entities: -> { [heart] } }
    calls = client.calls.size
    result = p.decide(p.decision_point_for(state(frame: 800, hp: 16)), state(frame: 800, hp: 16), ctx)
    touch = { skill: 'touch', params: { row: 2, col: 2, type: 45, safe: true, slot: 3 } }
    assert_equal ['delegated', true, touch], result.values_at(:agent, :autopilot, :choice)
    assert_equal touch, result[:decision_point].validate(result[:choice])
    p.after_action(choice: result[:choice], outcome: { skill: 'touch', params: touch[:params], stopped_by: 'done', hp_delta: 8,
                                                       from: { room: 163, map: 16, row: 3, col: 4 }, to: { room: 163, map: 16, row: 2, col: 3 } },
                   state: state(frame: 830, hp: 24), frame: 830)
    after = p.decide(p.decision_point_for(state(frame: 840)), state(frame: 840), { grid: seen, entities: -> { [] } })
    assert_equal [{ skill: 'explore', params: {} }, true], after.values_at(:choice, :autopilot)
    assert_equal calls, client.calls.size
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

  def test_a_souvenir_candidate_here_is_taken_by_the_harness_and_followed_with_a_talk
    entities = -> { [{ type: 64, kind: 'npc', cell: [2, 3] }] }
    souvenirs = [{ 'place' => [163, 16], 'entity' => 64, 'cell' => [2, 3], 'text' => 'Pour ma poudre, il me faut le Champignon de la forêt.',
                   'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1, 4] }] }]
    client = ScriptedClient.new(objective: objective)
    @objectives = Koholint::Objectives.new(trace:)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', autopilot: Koholint::Autopilot.new,
                                          revisit: QuietRevisit.new(talk_log: Koholint::TalkLog.new), souvenirs:)
    p.decide(p.decision_point_for(state), state, { grid:, entities: })
    @objectives.abandon(frame: 100, reason: 'test')
    holding = state(item_a: 1, item_b: 4, inventory: [12, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    picked = p.decide(p.decision_point_for(holding), holding, { grid:, entities: })
    assert picked[:autopilot], picked[:justification]
    assert_equal 1, client.calls.size, 'the harness takes it before asking the model'
    assert_equal({ kind: 'person', place: [163, 16], type: 64, cell: [2, 3], try: true, item: 12, name: 'champignon' }, @objectives.current[:target])
    talk = p.decide(p.decision_point_for(holding), holding, { grid:, entities: })
    assert_equal({ skill: 'talk_to', params: { row: 2, col: 3 } }, talk[:choice])
  end

  def test_a_picked_examine_candidate_starts_its_objective_and_is_followed_with_a_talk
    sprite = Koholint::Vision::Grid.new(cells: Array.new(8) { Array.new(10) { 'floor' } }, static_sprites: [{ 'x' => 72, 'y' => 48, 'pattern' => 'p', 'height' => 16 }],
                                        beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
    client = ScriptedClient.new(objective: ok('candidate' => 'examine-2-4', 'plan' => 'x', 'goal' => 'g'))
    p = autopiloted(client, revisit: QuietRevisit.new(talk_log: Koholint::TalkLog.new))
    picked = p.decide(p.decision_point_for(state), state, { grid: sprite })
    refute picked[:fallback], picked[:justification]
    assert_includes client.calls.first[:prompt], '- examine-2-4: examine the unidentified object at (2,4)'
    assert_equal({ kind: 'examine', place: [163, 16], cell: [2, 4] }, @objectives.current[:target])
    started = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).find { |e| e['type'] == 'objective' && e['status'] == 'started' }
    assert_equal({ 'kind' => 'examine', 'place' => [163, 16], 'cell' => [2, 4] }, started&.dig('target'))
    talk = p.decide(p.decision_point_for(state), state, { grid: sprite })
    assert_equal({ skill: 'talk_to', params: { row: 2, col: 4 } }, talk[:choice])
    assert talk[:autopilot]
  end

  def test_a_thing_to_try_is_walked_to_talked_to_then_touched
    here = [state.room_id, state.map_id]
    entities = [{ type: 132, kind: 'unknown', cell: [3, 4] }]
    p = autopiloted(ScriptedClient.new(objective: []))
    p.instance_variable_set(:@entities_reader, -> { entities })
    @objectives.start(frame: 10, title: 'Go examine', predicate: { kind: 'reach_place', place: here }, target: { kind: 'person', place: here, type: 132, cell: [3, 4], try: true })
    assert_equal({ choice: { skill: 'explore', params: {} }, aim: { place: here } }, p.send(:follow_choice, state(room_id: 9)))
    assert_equal({ choice: { skill: 'talk_to', params: { row: 3, col: 4 } } }, p.send(:follow_choice, state))
    @objectives.note_try(place: here, type: 132, skill: 'talk_to', answered: false)
    assert_equal({ choice: { skill: 'touch', params: { row: 3, col: 4, type: 132 } } }, p.send(:follow_choice, state))
  end

  def test_a_person_whose_text_named_a_held_item_becomes_the_objective_talked_to_holding_it_then_given_it
    here = [state.room_id, state.map_id]
    entities = [{ type: 64, kind: 'person', cell: [3, 4] }]
    p = autopiloted(ScriptedClient.new(objective: []))
    p.instance_variable_set(:@entities_reader, -> { entities })
    p.instance_variable_set(:@item_names, { 12 => %w[Champignon] })
    talk_log = p.instance_variable_get(:@talk_log)
    talk_log.remember(place: here, cell: [3, 4], text: 'Il me faut le Champignon de la forêt.', stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0), entity: 64)
    holding = state(inventory: [12] + Array.new(9, 0))
    assert_nil p.send(:item_objective, p.decision_point_for(state), state), 'not while Link does not hold it'
    picked = p.send(:item_objective, p.decision_point_for(holding), holding)
    assert picked[:autopilot]
    assert_equal({ kind: 'person', place: here, type: 64, cell: [3, 4], try: true, item: 12, name: 'Champignon', seen: [1, true] }, @objectives.current[:target])
    assert_equal({ choice: { skill: 'talk_to', params: { row: 3, col: 4 } } }, p.send(:follow_choice, holding))
    @objectives.note_try(place: here, type: 64, skill: 'talk_to', answered: true)
    assert_equal({ choice: { skill: 'use_item', params: { item: Koholint::Items.name(12) } } }, p.send(:follow_choice, holding))
  end

  # Paid forks 5a6d, c187 and f760: the model left by the nearest side every time the hut's souvenir was offered.
  def test_a_reachable_souvenir_naming_a_held_item_by_its_pickup_text_becomes_the_objective_once
    here = [state.room_id, state.map_id]
    souvenir = ->(text) { { 'place' => here, 'entity' => 64, 'cell' => [3, 4], 'text' => text, 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1, 4] }] } }
    build = lambda do |souvenirs, item_names: {}|
      @objectives = Koholint::Objectives.new(trace: trace)
      Koholint::Policies::Delegated.new(client: ScriptedClient.new(objective: []), registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '',
                                        autopilot: Koholint::Autopilot.new, souvenirs:, memory: Koholint::Policies::Memory.new(item_names:))
    end
    take = ->(p, now) { p.send(:souvenir_objective, p.decision_point_for(now), now, { grid: }) }
    p = build.([souvenir.('Pour ma poudre, il me faut le Champignon de la forêt.')])
    holding = state(inventory: [12] + Array.new(9, 0))
    assert_nil take.(p, state), 'not while Link does not hold it'
    picked = take.(p, holding)
    assert picked[:autopilot]
    assert_equal ['souvenir-163-16-t64', { kind: 'person', place: here, type: 64, cell: [3, 4], try: true, item: 12, name: 'champignon' }], @objectives.current.values_at(:candidate, :target)
    @objectives.abandon(frame: 200, reason: 'stall')
    assert_nil take.(p, holding), 'taken once; a drop is the re-offer rules\' to take up'
    started = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'objective' }
    assert_equal ['souvenir-163-16-t64'], Koholint::Policies::Memory.souvenirs_taken(started), 'a resumed run keeps it taken'
    named = build.([souvenir.('Rapporte-moi le boomerang, petit.')], item_names: { 13 => %w[boomerang] })
    assert_nil take.(named, state(inventory: [13] + Array.new(9, 0))), 'a name not read from a pickup text stays a model choice'
  end

  def test_an_item_objective_whose_try_drew_no_text_is_not_picked_again_until_a_new_text_from_that_person
    here = [state.room_id, state.map_id]
    p = autopiloted(ScriptedClient.new(objective: []))
    p.instance_variable_set(:@entities_reader, -> { [{ type: 64, kind: 'person', cell: [3, 4] }] })
    p.instance_variable_set(:@item_names, { 12 => %w[Champignon] })
    talk_log = p.instance_variable_get(:@talk_log)
    before = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0)
    talk_log.remember(place: here, cell: [3, 4], text: 'Il me faut le Champignon de la forêt.', stamp: before, entity: 64)
    holding = state(inventory: [12] + Array.new(9, 0))
    assert p.send(:item_objective, p.decision_point_for(holding), holding)
    @objectives.note_try(place: here, type: 64, skill: 'talk_to', answered: false)
    @objectives.note_try(place: here, type: nil, skill: 'use_item', answered: false, item: 12)
    assert_equal :achieved, @objectives.update(holding, frame: 50)
    assert_nil p.send(:item_objective, p.decision_point_for(holding), holding), 'a silent try is not repeated'
    talk_log.remember(place: here, cell: [3, 4], text: 'Ah, il est si loin.', stamp: before, entity: 64)
    assert p.send(:item_objective, p.decision_point_for(holding), holding), 'a new text from them reopens it'
    started = Koholint::Trace.read(File.join(@dir, 'trace.jsonl')).select { |e| e['type'] == 'objective' && e['status'] == 'started' }
    assert_equal({ [12, here, 64] => [2, true] }, Koholint::Policies::Memory.item_tries(started), 'a resumed run keeps the tries')
  end

  # Run f089, 172/10: examine-68-0-t53, with no known route, was picked five times and stalled each time.
  def test_a_candidate_no_known_route_reaches_is_not_offered_again_after_it_stalled_until_a_route_appears
    p = autopiloted(ScriptedClient.new(objective: []))
    p.instance_variable_get(:@cards)[[9, 0]] = { people: [{ type: 70, cell: [1, 1] }], held: [] }
    holding = state(inventory: [12] + Array.new(9, 0))
    offered = -> { p.send(:build_candidates, holding, { grid: }).map { |c| c[:id] } }
    assert_includes offered.(), 'person-9-0-t70'
    @objectives.start(frame: 100, title: 'Go talk', predicate: { kind: 'reach_place', place: [9, 0] }, candidate: 'person-9-0-t70',
                      target: { kind: 'person', place: [9, 0], type: 70, cell: [1, 1] })
    @objectives.update(holding, frame: 101)
    assert_equal :abandoned, @objectives.update(holding, frame: 2000)
    refute_includes offered.(), 'person-9-0-t70'
    p.instance_variable_get(:@explore_log).absorb({ from: { room: 163, map: 16 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [9, 0] }] })
    assert_includes offered.(), 'person-9-0-t70', 'a route to it reopens it'
    events = Koholint::Trace.read(File.join(@dir, 'trace.jsonl'))
    assert_equal ['person-9-0-t70'], Koholint::Policies::Memory.stalled(events), 'a resumed run keeps it'
  end

  # Run 626d, 80/0: item 12 is held at 91617 but its pickup sheet is transcribed only at 91633, once it closed.
  def test_a_gained_item_is_named_by_the_pickup_text_transcribed_after_it_is_held
    here = [state.room_id, state.map_id]
    p = autopiloted(ScriptedClient.new(objective: []))
    p.instance_variable_set(:@last_read, { text: 'Bonjour, petit!', place: here, frame: 80 })
    p.observe(state(frame: 90), frame: 90)
    p.observe(state(frame: 100, inventory: [12] + Array.new(9, 0)), frame: 100)
    assert_nil p.instance_variable_get(:@item_names)[12]
    p.instance_variable_set(:@last_read, { text: 'Tu as trouvé le Champignon! Un arôme subtil.', place: here, frame: 116 })
    p.observe(state(frame: 120, inventory: [12] + Array.new(9, 0)), frame: 120)
    assert_equal %w[Champignon], p.instance_variable_get(:@item_names)[12]
  end

  # Run 20261125-175039-96c6, 83/0: the thing spoke as Link walked up to it, so talk_to stopped on that dialogue without a talk of its own.
  def test_a_dialogue_that_stops_the_talk_to_a_thing_to_try_is_its_answer
    here = [state.room_id, state.map_id]
    p = autopiloted(ScriptedClient.new(objective: []))
    @objectives.start(frame: 10, title: 'Go examine', predicate: { kind: 'reach_place', place: here }, target: { kind: 'person', place: here, type: 132, cell: [3, 4], try: true })
    outcome = { skill: 'talk_to', params: { row: 3, col: 4 }, stopped_by: :dialogue, dialog_after: true, talked: false, target_type: 132, moved_cells: 2,
                from: { room: here[0], map: here[1], row: 5, col: 4 }, to: { room: here[0], map: here[1], row: 4, col: 4 } }
    p.after_action(choice: { skill: 'talk_to', params: { row: 3, col: 4 } }, outcome:, state:, frame: 20)
    @objectives.update(state, frame: 21)
    assert_nil @objectives.current
    assert_equal :achieved, @objectives.history.last[:outcome]
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

  def e6(slot, type, x, y) = { slot:, type:, kind: :unknown, moves: nil, x:, y:, cell: [(y - 8) / 16, x / 16] }

  def e6_hurt(client, autopilot: nil)
    @objectives = Koholint::Objectives.new(trace: trace)
    p = Koholint::Policies::Delegated.new(client:, registry: Koholint::Skills::Registry.default, objectives: @objectives, manual: '', autopilot:)
    things = [e6(1, 185, 102, 67), e6(2, 203, 72, 64)]
    p.instance_variable_set(:@entities_reader, -> { things })
    start = state(frame: 98300, room_id: 84, map_id: 0, x: 101, y: 58)
    p.observe(start, frame: 98300)
    decide(p, start)
    hit = outcome(:damage, 0).merge(hp_delta: -8, from: { room: 84, map: 0, row: 3, col: 6 }, to: { room: 84, map: 0, row: 3, col: 6 })
    p.after_action(choice: { skill: 'explore', params: {} }, outcome: hit, state: state(frame: 98402, room_id: 84, map_id: 0, x: 101, y: 58, hp: 16), frame: 98402)
    p
  end

  # Paid fork g8-3 (f78e, flow-110), E6 (84/0): autopilot explore lost 8 hp at 98402 with type 185 at (3,6) 1 px right and 9 px below Link (restored),
  # type 203 at (3,4) 29 px away; at 98418 the model struck the uncatalogued 185 (-8), and at 98506, at 8 hp, its explore up walked into (3,6) and Link died.
  def test_the_thing_nearest_link_when_hp_drops_is_listed_as_hurting_him_and_never_attacked_at_its_hit
    attack = ok('skill' => 'attack', 'params' => { 'row' => 3, 'col' => 6 })
    client = ScriptedClient.new(objective: new_place, default: attack)
    p = e6_hurt(client)
    now = state(frame: 98418, room_id: 84, map_id: 0, x: 100, y: 39, hp: 16)
    p.observe(now, frame: 98418)
    result = p.decide(p.decision_point_for(now), now, { grid: })
    assert_equal [{ kind: 'hurt', detail: { type: 185, hit: 8, place: [84, 0], cell: [3, 6] } }], Array(result[:notables]).select { |note| note[:kind] == 'hurt' }
    assert_match(/type 203 at \(3,4\) \(not identified\), type 185 at \(3,6\) \(hurt Link for 8\)/, client.calls.last[:prompt])
    assert_equal 'attack', result[:choice][:skill], 'above its hit the model may still strike it'
    low = state(frame: 98506, room_id: 84, map_id: 0, x: 101, y: 38, hp: 8)
    p.observe(low, frame: 98506)
    refused = p.decide(p.decision_point_for(low), low, { grid: })
    assert_equal ['wait', 'type 185 hurt Link for 8 and Link has 8 hp: no attack on it at 8 hp or less'], [refused[:choice][:skill], refused[:justification]]
    assert_includes Koholint::Entities.danger_cells(p.send(:entities_now)), [3, 6], 'routes keep out of its reach'
  end

  # Paid fork g7-1 (b8b7, flow-108): the autopilot walked up to talk to type 203 in E6 (84/0) at 100867 and Link lost 8 hp.
  def test_a_type_that_hurt_link_is_never_a_talk_target
    client = ScriptedClient.new(objective: new_place, default: explore)
    p = e6_hurt(client)
    @objectives.abandon(frame: 98420, reason: 'test')
    menu = state(frame: 98430, room_id: 84, map_id: 0, x: 100, y: 39, hp: 16)
    p.observe(menu, frame: 98430)
    p.decide(p.decision_point_for(menu), menu, { grid: })
    labels = p.offered_candidates.map { |candidate| candidate[:label] }.join("\n")
    refute_match(/type 185/, labels)
    assert_match(/type 203/, labels, 'a thing that never hurt Link is still offered')
  end

  def test_the_hurt_hypotheses_come_back_from_the_lineage_trace
    events = [{ 'type' => 'notable', 'frame' => 98418, 'kind' => 'hurt', 'detail' => { 'type' => 185, 'hit' => 8, 'place' => [84, 0], 'cell' => [3, 6] } },
              { 'type' => 'notable', 'frame' => 101772, 'kind' => 'hurt', 'detail' => { 'type' => 185, 'hit' => 4, 'place' => [84, 0], 'cell' => [3, 6] } }]
    fact = Koholint::Policies::Memory.from_events(events).hurts.facts[185]
    assert_equal({ hit: 8, confidence: 'hypothesis', verified_count: 1 }, fact.slice(:hit, :confidence, :verified_count))
    assert_match(/nearest Link in the census window/, fact[:source])
  end

  def test_a_hurts_fact_in_the_catalogue_makes_its_type_an_enemy_from_the_first_look
    thing = { slot: 1, type: 185, kind: :unknown, moves: true, hurts: 8, x: 102, y: 67, cell: [3, 6] }
    person = { slot: 2, type: 62, kind: :npc, hurts: 8, x: 40, y: 60, cell: [3, 2] }
    assert_equal [[:enemy, 8], [:npc, nil]], Koholint::Hurts.new.overlay([thing, person]).map { |entity| entity.values_at(:kind, :hurt) }
    assert_equal 8, Koholint::Entities.catalogue.dig(185, :hurts)
  end

  def blamed(things, spared: [], at: [101, 58])
    link = state(room_id: 84, map_id: 0, x: at[0], y: at[1])
    Koholint::Hurts.in_contact(link, Koholint::Hurts.new.overlay(things), spared:)&.dig(:type)
  end

  def thing(type, x, y, kind: :unknown, **more) = { slot: type % 16, type:, kind:, x:, y:, cell: [(y - 8) / 16, x / 16], **more }

  # Review of #117 (KOHO-149): a catalogued enemy (type 9) hit Link with the D6 healer (type 132, uncatalogued) nearer in the window.
  def test_no_blame_with_a_catalogued_enemy_in_the_window
    assert_nil blamed([thing(132, 102, 60), thing(9, 106, 70, kind: :enemy)])
    assert_equal 132, blamed([thing(132, 102, 60)]), 'control: alone in the window it takes the blame'
  end

  def test_a_person_or_a_type_link_talked_with_is_never_blamed
    assert_nil blamed([thing(64, 102, 60)], spared: [64]), 'the witch of 162/14 after a talk'
    assert_nil blamed([thing(62, 102, 60, kind: :npc), thing(132, 106, 70)])
    log = Koholint::TalkLog.new
    log.record(place: [162, 14], row: 4, col: 4, talked: true, entity: 64)
    log.record(place: [162, 14], row: 3, col: 5, talked: false, entity: 59)
    assert_equal [64], log.talked_types
  end

  # Stub gate 35b7 (flow-111 at b6e1e863): 185 hit Link at 99052, and the next hit at 99160 blamed type 125 beside it.
  def test_a_type_that_already_hurt_takes_its_next_hit_and_shields_its_neighbours
    hurting = thing(185, 102, 64, hurts: 8)
    assert_equal 185, blamed([hurting, thing(125, 96, 70)])
    assert_nil blamed([thing(203, 101, 60), hurting]), 'a nearer thing beside a type that already hurt is not blamed'
    assert_nil blamed([thing(185, 135, 125, hurts: 8), thing(125, 115, 125)], at: [120, 116]), 'gate d388 99160: 185 15 px away, 125 measured harmless'
  end
end
