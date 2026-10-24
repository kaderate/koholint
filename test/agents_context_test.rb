require_relative 'test_helper'
require 'koholint/game_state'
require 'koholint/vision/grid'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/agents/context'
require 'koholint/ledger'
require 'koholint/talk_log'
require 'koholint/triggers'

class AgentsContextTest < Minitest::Test
  Context = Koholint::Agents::Context

  def state(**over)
    Koholint::GameState.new(frame: 100, room_id: 163, map_id: 16, x: 68, y: 60, direction: :up, hp: 24, max_hp: 24,
                            milestone: :none, game_mode: 0x0B, game_submode: 7, dialog_state: 0, **over)
  end

  def record(beliefs, appearance, direction, result)
    beliefs.record(appearance:, action: :walk, direction:, result:, method: 'test', context: Koholint::Vision::Capabilities.new, frame: 1, source: 'test')
  end

  def grid
    beliefs = Koholint::Vision::Beliefs.new
    %i[up down left right].each do |d|
      record(beliefs, 'floor', d, :yes)
      record(beliefs, 'wall', d, :no)
    end
    record(beliefs, 'ledge', :down, :yes)
    record(beliefs, 'ledge', :up, :no)
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    cells[0][0] = 'wall'
    cells[0][1] = 'ledge'
    cells[0][2] = 'mystery'
    cells[0][3] = 'old'
    beliefs.record(appearance: 'old', action: :walk, direction: :up, result: :yes, method: 't', context: Koholint::Vision::Capabilities.new(['x']), frame: 2, source: 't')
    cells[3][5] = 'wall'
    cells[7][9] = 'wall'
    Koholint::Vision::Grid.new(cells:, static_sprites: [{ 'x' => 40, 'y' => 32, 'pattern' => 'pot' }], beliefs:,
                               capabilities: Koholint::Vision::Capabilities.new).freeze
  end

  def result(**over)
    { skill: 'walk', params: { direction: 'up', cells: 2 }, frames: 40, moved_cells: 1, room_changed: false, hp_delta: 0,
      dialog_before: false, dialog_after: false, stopped_by: 'blocked', **over }
  end

  def build(**over)
    Context.build(state: state, grid: grid, objective: nil, history: [], attempts: [], manual: 'Use A to talk.',
                  last_results: [], **over)
  end

  def test_without_triggers_and_talk_log_the_output_is_unchanged
    base = build
    assert_equal base, build(triggers: Koholint::Triggers.new, talk_log: nil)
    refute_includes build(triggers: Koholint::Triggers.new, talk_log: nil), 'opened by itself'
    refute_includes base, 'Things on screen'
  end

  def test_a_known_trigger_input_replaces_the_generic_line
    triggers = Koholint::Triggers.new
    link = grid && state.cell
    triggers.record(place: [163, 16], cell: link, skill: 'walk', direction: 'right', input: 'down')
    text = build(triggers:)
    assert_includes text, 'Pressing down while Link was on this cell opened a dialogue by itself 1 time (the game triggers it; other inputs did not; goto and talk_to routes avoid it, an explicit walk, step or press is not filtered).'
    triggers.record(place: [163, 16], cell: link, skill: 'walk', input: 'down')
    assert_includes build(triggers:), 'by itself 2 times'
    refute_includes text, 'A dialogue opened by itself'
  end

  def test_the_locked_phase_note_appears_only_with_locked_frames
    refute_includes build, 'cause unknown'
    assert_includes build(locked_frames: 930), 'Link has been locked for 930 frames (cause unknown)'
  end

  def test_the_movement_lock_line_appears_only_when_locked
    refute_includes build, 'Link has not moved'
    assert_includes build(locked: 3), "Link has not moved in the last 3 attempts in different directions and no dialogue is open: movement may be locked by an animation or an event; waiting a few seconds is usually enough before trying again."
  end

  def test_the_trigger_line_needs_two_openings_on_the_current_cell
    triggers = Koholint::Triggers.new
    link = state.cell
    triggers.record(place: [163, 16], cell: link, skill: 'walk', direction: 'up')
    refute_includes build(triggers:), 'opened by itself'
    triggers.record(place: [163, 16], cell: link, skill: 'goto')
    text = build(triggers:)
    assert_includes text, "Health: 3 of 3 hearts\nA dialogue opened by itself 2 times while Link was on this cell (the game triggers it; repeating the same action here does not change that).\n\nGrid"
    other = Koholint::Triggers.new
    2.times { other.record(place: [163, 16], cell: [0, 0], skill: 'walk') }
    refute_includes build(triggers: other), 'opened by itself'
  end

  def test_the_things_section_lists_static_objects_with_their_counts
    log = Koholint::TalkLog.new
    assert_includes build(talk_log: log), "Things on screen you can interact with:\n- at (1,2): never tried\n\nGoal: none set yet"
    log.record(place: [163, 16], row: 1, col: 2, talked: true)
    assert_includes build(talk_log: log), '- at (1,2): talked to 1 time (dialogue opened 1)'
  end

  def test_the_things_section_lists_the_sides_without_response
    log = Koholint::TalkLog.new
    log.record(place: [163, 16], row: 1, col: 2, talked: false, standing: [[[2, 2], true], [[0, 2], true]])
    assert_includes build(talk_log: log), '- at (1,2): talked to 1 time (dialogue opened 0); no response from (2,2), (0,2)'
  end

  def test_the_things_section_is_bounded
    sprites = [0, 2, 4, 6].flat_map { |r| [0, 2, 4, 6, 8].map { |c| { 'x' => c * 16 + 8, 'y' => r * 16 + 16, 'pattern' => "s#{r}#{c}" } } }
    big = Koholint::Vision::Grid.new(cells: Array.new(8) { Array.new(10) { 'floor' } }, static_sprites: sprites, beliefs: Koholint::Vision::Beliefs.new,
                                     capabilities: Koholint::Vision::Capabilities.new)
    text = Context.build(state:, grid: big, objective: nil, history: [], attempts: [], manual: '', last_results: [], talk_log: Koholint::TalkLog.new)
    assert_equal 12, text.scan(/^- at \(/).size
    assert_includes text, '... 8 more objects'
  end

  def test_step_result_shows_pixels
    text = build(last_results: [result(skill: 'step', params: { direction: 'up', pixels: 5 }, moved_px: 5, stopped_by: 'done')])
    assert_includes text, 'step {"direction":"up","pixels":5}: stopped_by done, 40 frames, moved 5 px, room_changed'
  end

  def test_goto_results_show_the_path_the_block_and_the_cause
    goto = result(skill: 'goto', params: { row: 1, col: 9 }, stopped_by: 'no_path', cause: 'target is sealed', moved_cells: 0, path_length: 6,
                  steps_done: 2, aligned: false, blocked_at: { row: 3, col: 5, direction: :right })
    text = build(last_results: [goto])
    assert_includes text, 'goto {"row":1,"col":9}: stopped_by no_path (cause: target is sealed), 40 frames, moved 0 cells, room_changed false, ' \
                          'hp_delta 0, dialogue open before false, after false, path 6, steps 2, aligned false, blocked at (3,5) right'
    assert_includes text, "- right: cell (3,5) '#', belief no, last walk: blocked\n"
  end

  def test_talk_to_results_show_the_path_and_what_happened
    talk = result(skill: 'talk_to', params: { row: 2, col: 5 }, stopped_by: 'no_response', moved_cells: 2, path_length: 2, steps_done: 2, aligned: true,
                  talked: false, standing_cell: { row: 1, col: 5 }, facing: :down)
    assert_includes build(last_results: [talk]), 'talk_to {"row":2,"col":5}: stopped_by no_response, 40 frames, moved 2 cells, room_changed false, ' \
                                                 'hp_delta 0, dialogue open before false, after false, path 2, steps 2, aligned true, ' \
                                                 'talked false, standing cell (1,5), facing down'
  end

  def test_a_later_walk_overrides_a_goto_block_for_that_direction
    goto = result(skill: 'goto', params: { row: 1, col: 9 }, stopped_by: 'blocked', path_length: 6, steps_done: 2, aligned: true,
                  blocked_at: { 'row' => 3, 'col' => 5, 'direction' => 'right' })
    walk = result(params: { direction: 'right', cells: 1 }, moved_cells: 1, stopped_by: 'done')
    assert_includes build(last_results: [goto, walk]), 'last walk: done after 1 cell'
  end

  def test_refused_objectives_are_listed
    refusals = [{ title: 'go', predicate: { kind: 'leave_place', place: [1, 2] }, reason: 'wrong place' }]
    text = build(refusals:)
    assert_includes text, "Refused objectives:\n- go {\"kind\":\"leave_place\",\"place\":[1,2]}: wrong place"
    refute_includes build, 'Refused objectives'
  end

  def test_plan_is_shown_after_the_objective_and_before_the_attempts
    objective = { id: 'obj-2', title: 'Leave the room', predicate: { kind: 'new_place' } }
    text = build(objective:, attempts: ['walk -> blocked'], plan: 'talk to the NPC first')
    line = 'Your plan from your last call (written by you; follow it unless the situation changed): talk to the NPC first'
    assert_includes text, "Predicate: {\"kind\":\"new_place\"}\n#{line}\nAttempts on this objective:"
    refute_includes build(objective:, attempts: ['walk -> blocked']), 'Your plan'
    assert_includes build(plan: 'x'), "Current objective: none\nYour plan from your last call"
  end

  def test_snapshot
    objective = { id: 'obj-2', title: 'Leave the room', predicate: { kind: 'leave_place', place: [163, 16] } }
    text = build(objective:, attempts: ['walk {"direction":"up","cells":2} -> blocked'],
                 history: [{ id: 'obj-1', title: 'Close the dialogue', outcome: :achieved, reason: nil }],
                 last_results: [result])
    expected = <<~TEXT.chomp
      Phase: playing
      Place: room 163, map 16
      Link: row 3, col 4 (pixel x=68, y=60), facing up
      Link offset from cell centre (positive = right of / below the centre): dx=-4, dy=-4
      Health: 3 of 3 hearts

      Grid (rows 0-7 top to bottom, cols 0-9 left to right):
          0 1 2 3 4 5 6 7 8 9
       0  # ~ ? ! . . . . . .
       1  . . o . . . . . . .
       2  . . . . . . . . . .
       3  . . . . @ # . . . .
       4  . . . . . . . . . .
       5  . . . . . . . . . .
       6  . . . . . . . . . .
       7  . . . . . . . . . #
      Legend: . passable, # blocked, ? unknown, ! stale or doubtful, ~ one-way, o static object, @ Link
      Unknown cells are not walls.

      Neighbours of Link:
      - up: cell (2,4) '.', belief yes, last walk: blocked after 1 cell
      - right: cell (3,5) '#', belief no, last walk: none
      - down: cell (4,4) '.', belief yes, last walk: none
      - left: cell (3,3) '.', belief yes, last walk: none

      Goal: none set yet — set one in goal when you have a reason (a lead, an observation).
      Current objective: Leave the room
      Predicate: {"kind":"leave_place","place":[163,16]}
      Attempts on this objective:
      - walk {"direction":"up","cells":2} -> blocked

      Finished objectives:
      - obj-1 achieved: Close the dialogue

      Last skill results:
      - walk {"direction":"up","cells":2}: stopped_by blocked, 40 frames, moved 1 cell, room_changed false, hp_delta 0, dialogue open before false, after false

      Game manual:
      Use A to talk.
    TEXT
    assert_equal expected, text
  end

  def test_doubtful_neighbour_is_drawn_and_counted
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: [163, 16], blocked_at: { row: 3, col: 4, direction: :down }) }
    ledger.record(place: [163, 16], blocked_at: { row: 3, col: 4, direction: :left })
    text = build(ledger:)
    assert_includes text, " 4  . . . . ! . . . . ."
    assert_includes text, "- down: cell (4,4) '!', belief yes, last walk: none, blocked 2 times"
    assert_includes text, "- left: cell (3,3) '.', belief yes, last walk: none, blocked 1 time\n"
    assert_equal build, build(ledger: Koholint::Ledger.new)
  end

  def test_doubt_needs_a_free_belief_and_keeps_objects_visible
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: [163, 16], blocked_at: { row: 3, col: 4, direction: :right }) }
    text = build(ledger:)
    assert_includes text, "- right: cell (3,5) '#', belief no, last walk: none, blocked 2 times"
    assert_includes text, " 3  . . . . @ # . . . ."
    2.times { ledger.record(place: [163, 16], blocked_at: { row: 1, col: 3, direction: :left }) }
    text = build(state: state(x: 52, y: 28), ledger:)
    assert_includes text, "- left: cell (1,2) 'o'"
    assert_includes text, 'blocked 2 times'
  end

  def test_no_objective_and_edge_neighbours
    text = Context.build(state: state(x: 0, y: 8), grid:, objective: nil, history: [], attempts: [], manual: '', last_results: [])
    assert_includes text, 'Current objective: none'
    assert_includes text, "- up: edge of the screen"
    assert_includes text, "- left: edge of the screen"
  end

  def test_cap_drops_history_but_never_grid_objective_or_legend
    objective = { id: 'obj-9', title: 'Current goal', predicate: { kind: 'dialogue_closed' } }
    history = (1..30).map { |i| { id: "obj-#{i}", title: "old goal #{i}", outcome: :achieved, reason: nil } }
    results = (1..6).map { |i| result(frames: i) }
    full = build(objective:, history:, last_results: results, manual: 'm' * 500)
    capped = build(objective:, history:, last_results: results, manual: 'm' * 500, max_chars: 2200)
    assert_operator capped.size, :<=, 2200
    assert_operator full.size, :>, 2200
    %w[Grid Legend: Neighbours Current\ objective Predicate:].each { |part| assert_includes capped, part }
    assert_includes capped, 'old goal 30'
    refute_match(/old goal 1$/, capped)
    tiny = build(objective:, history:, last_results: results, max_chars: 100)
    %w[Grid Legend: Current\ objective].each { |part| assert_includes tiny, part }
    assert_operator tiny.size, :>, 100
  end

  def test_real_manual_keeps_history_and_results_within_the_cap
    manual = File.read(File.expand_path('../docs/AGENT_MANUAL.md', __dir__))
    objective = { id: 'obj-9', title: 'Current goal', predicate: { kind: 'dialogue_closed' } }
    history = (1..8).map { |i| { id: "obj-#{i}", title: "old goal #{i}", outcome: :achieved, reason: nil } }
    attempts = (1..10).map { |i| "walk {\"direction\":\"up\",\"cells\":#{i}} -> blocked" }
    text = build(objective:, attempts:, history:, manual:, last_results: (1..6).map { |i| result(frames: i) })
    assert_operator text.size, :<=, 9000
    assert_includes text, 'Finished objectives:'
    assert_includes text, 'Last skill results:'
    assert_includes text, 'old goal 8'
    assert_includes text, 'Current goal'
  end

  def test_manual_is_cut_first_at_a_line_boundary
    manual = (1..400).map { |i| "rule number #{i} ends here." }.join("\n")
    text = build(manual:)
    notes = text.split("Game manual:\n").last
    assert_operator notes.size, :<=, Context::MANUAL_LIMIT
    assert notes.end_with?('ends here.')
  end

  def test_floor_keeps_five_finished_and_three_results_when_the_cap_is_tiny
    history = (1..12).map { |i| { id: "obj-#{i}", title: "old goal #{i}", outcome: :achieved, reason: nil } }
    text = build(history:, manual: 'm' * 500, last_results: (1..6).map { |i| result(frames: i) }, max_chars: 100)
    assert_equal 5, text.scan('old goal').size
    assert_includes text, 'old goal 12'
    assert_equal 3, text.scan('stopped_by blocked').size
    refute_includes text, 'Game manual:'
  end

  def test_link_above_the_grid_has_no_marker_and_no_neighbours
    text = Context.build(state: state(x: 68, y: 4), grid:, objective: nil, history: [], attempts: [], manual: '', last_results: [])
    refute_match(/^ \d  .*@/, text)
    assert_includes text, 'outside the grid'
    assert_includes text, 'Link is outside the 8x10 grid'
    refute_includes text, '- up:'
  end

  def test_link_in_the_last_column_and_just_past_it
    inside = Context.build(state: state(x: 159, y: 60), grid:, objective: nil, history: [], attempts: [], manual: '', last_results: [])
    assert_includes inside, 'col 9'
    assert_includes inside, '- right: edge of the screen'
    past = Context.build(state: state(x: 160, y: 60), grid:, objective: nil, history: [], attempts: [], manual: '', last_results: [])
    refute_match(/^ \d  .*@/, past)
    assert_includes past, 'outside the grid'
  end

  def test_results_limited_to_last_six
    text = build(last_results: (1..9).map { |i| result(frames: i) })
    assert_equal 6, text.scan('stopped_by blocked').size
    assert_includes text, '9 frames'
    refute_includes text, ' 3 frames'
  end

  def test_dialogue_never_shows_raw_counter
    text = build(state: state(dialog_state: 133))
    assert_includes text, 'Phase: dialogue'
    refute_includes text, '133'
  end

  def test_returns_string_and_leaves_inputs_untouched
    frozen_state = state.freeze
    text = Context.build(state: frozen_state, grid:, objective: { id: 'x', title: 't', predicate: { kind: 'dialogue_closed' }.freeze }.freeze,
                         history: [].freeze, attempts: [].freeze, manual: 'm'.freeze, last_results: [result.freeze].freeze)
    assert_instance_of String, text
  end

  def lead(id, importance, place: [163, 16], quote: 'some words', claim: "claim #{id}")
    { id: "lead-#{id}", place:, source: nil, quote:, claim:, importance: }
  end

  def test_the_goal_line_says_when_none_is_set_and_shows_the_agent_goal
    assert_includes build, "Goal: none set yet — set one in goal when you have a reason"
    assert_includes build(goal: 'find the beach'), "Goal (yours, long-term): find the beach\nCurrent objective: none"
  end

  def test_leads_show_every_high_one_normal_ones_of_this_place_and_never_low_ones
    leads = [lead(1, 'high', place: [1, 1]), lead(2, 'normal'), lead(3, 'normal', place: [1, 1]), lead(4, 'low'), lead(5, 'high', quote: 'q' * 100)]
    text = build(leads:)
    section = text[/Leads from texts.*?(?=\n\n|\z)/m]
    assert_equal ["- [lead-5 high] claim 5 — \"#{'q' * 77}...\"", '- [lead-1 high] claim 1 — "some words"', '- [lead-2 normal] claim 2 — "some words"'],
                 section.lines.drop(1).map(&:chomp)
    refute_includes text, 'lead-3'
    refute_includes text, 'lead-4'
    refute_includes build(leads: [lead(1, 'low')]), 'Leads from texts'
  end

  def test_leads_are_capped_newest_first
    leads = (1..10).map { |i| lead(i, 'high') } + (11..17).map { |i| lead(i, 'normal') }
    shown = build(leads:).scan(/\[(lead-\d+)/).flatten
    assert_equal (3..10).to_a.reverse.map { |i| "lead-#{i}" } + (13..17).to_a.reverse.map { |i| "lead-#{i}" }, shown
  end

  def test_the_budget_trims_the_manual_before_the_goal_and_the_leads
    text = build(manual: "line\n" * 2000, goal: 'g', leads: [lead(1, 'high')], max_chars: 2500)
    assert_includes text, 'Goal (yours, long-term): g'
    assert_includes text, '[lead-1 high]'
    assert_operator text.size, :<, 2500 + 100
  end

  def screen_header(**over) = Context.build(state: state(**over), grid:, objective: nil, history: [], attempts: [], manual: '', last_results: [])

  def test_a_screen_is_named_with_how_to_leave_it_from_the_catalogue
    text = screen_header(link_motion_state: 7, game_over_stage: 4, menu_option: 1)
    assert_includes text, 'Phase: game_over'
    assert_includes text, 'Screen: game_over (game_over)'
    assert_includes text, "To leave: #{Koholint::Modes.catalogue.find { |m| m.name == 'game_over' }.exit['text']}"
    assert_includes text, 'Options (choose_option): 0 save and continue, 2 continue without saving'
    refute_includes text, 'quit'
    assert_includes text, 'Cursor: menu option 1 of 0..2'
    refute_includes screen_header, 'Screen:'
  end

  def test_an_uncatalogued_screen_says_only_press_and_wait_work
    text = screen_header(game_mode: 0x0D, game_submode: 1)
    assert_includes text, 'Phase: unknown'
    assert_includes text, 'An uncatalogued screen is open (game mode 13, submode 1); only press and wait work here.'
  end
end
