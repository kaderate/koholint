require_relative 'test_helper'
require 'json'
require 'open3'

class PageTest < Minitest::Test
  PAGE = File.read(File.expand_path('../lib/koholint/viewer/page.html', __dir__))

  def pure_source
    PAGE[%r{// pure:begin\n(.*?)// pure:end}m, 1] or flunk 'page has no pure section'
  end

  def evaluate(expression)
    unless system('which node > /dev/null 2>&1')
      flunk 'node is not installed and CI is set' if ENV['CI']
      skip 'node is not installed: page formatting tests not run'
    end
    out, status = Open3.capture2('node', '-e', "#{pure_source}\nconsole.log(JSON.stringify(#{expression}));")
    assert status.success?
    JSON.parse(out)
  end

  def test_decisions_read_as_a_sentence
    event = { frame: 5, type: 'decision', agent: 'start_game', choice: { buttons: %w[a b], frames: 58 }, confidence: 1 }
    assert_equal 'f5 · start_game decides a+b 58f', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_low_confidence_is_shown_as_a_percentage
    event = { frame: 5, type: 'decision', agent: 'jev', choice: { buttons: [], frames: 30 }, confidence: 0.5 }
    assert_equal 'f5 · jev decides idle 30f (50%)', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_actions_read_as_what_was_pressed
    event = { frame: 8, type: 'action', skill: 'press', params: { buttons: %w[start], frames: 3 } }
    assert_equal 'f8 · press start 3f', evaluate("formatEventPretty(#{JSON.generate(event)})")
  end

  def test_the_phone_layout_overrides_the_base_left_column_width
    base = PAGE.index("#left { flex: none; width: 480px")
    media = PAGE.index('@media (max-width: 800px)')
    phone = PAGE.index('#left { width: auto', media)
    assert base < media, 'the base #left rule must come before the media query'
    assert media < phone
  end

  def test_a_decision_shows_its_reasoning_as_visible_text
    event = { frame: 9, type: 'decision', agent: 'claude', justification: "  go left <b>x</b>  \n" }
    assert_equal 'go left <b>x</b>', evaluate("formatReason(#{JSON.generate(event)})")
    assert_equal '', evaluate("formatReason({type: 'action', justification: 'x'})")
    assert_equal '', evaluate("formatReason({type: 'decision'})")
    assert_equal 600, evaluate("formatReason({type: 'decision', justification: 'a'.repeat(900)}).length")
  end

  def test_a_decision_shows_its_plan_as_visible_text
    event = { frame: 9, type: 'decision', plan: '  talk to <b>him</b> ' }
    assert_equal 'plan: talk to <b>him</b>', evaluate("formatPlan(#{JSON.generate(event)})")
    assert_equal '', evaluate("formatPlan({type: 'action', plan: 'x'})")
    assert_equal '', evaluate("formatPlan({type: 'decision'})")
    assert_equal '', evaluate("formatPlan({type: 'decision', plan: 5})")
  end

  def test_unknown_event_types_still_get_a_line
    assert_equal 'f1 · budget_stop', evaluate("formatEventPretty({frame: 1, type: 'budget_stop'})")
  end

  def test_json_mode_is_the_raw_event
    event = { frame: 8, type: 'action', skill: 'press', params: { buttons: %w[a], frames: 3 } }
    assert_equal JSON.generate(event), evaluate("formatEventJson(#{JSON.generate(event)})")
  end

  def test_the_mode_toggle_alternates_and_rejects_garbage
    assert_equal 'json', evaluate("nextMode('pretty')")
    assert_equal 'pretty', evaluate("nextMode('json')")
    assert_equal 'pretty', evaluate("normalizeMode('whatever')")
    assert_equal 'json', evaluate("normalizeMode('json')")
  end

  def test_page_has_a_toggle_that_remembers_the_choice
    assert_match(/id="mode"/, PAGE)
    assert_match(/localStorage/, PAGE)
  end

  def test_each_poll_keeps_its_own_error
    assert_match(/frameError/, PAGE)
    assert_match(/stateError/, PAGE)
  end

  def test_empty_buttons_read_as_idle
    assert_equal 'idle 58f', evaluate('formatChoice({buttons: [], frames: 58})')
  end

  def test_other_choices_never_render_as_object_object
    refute_includes evaluate('formatChoice({to: 3})').to_s, '[object Object]'
    assert_equal 'wait', evaluate("formatChoice('wait')")
  end

  def test_hearts_show_a_dash_before_the_game_starts
    assert_equal '-', evaluate('formatHearts({status: {hearts: null, max_hearts: null}})')
    assert_equal '-', evaluate('formatHearts({status: {hearts: 0, max_hearts: 0}})')
    assert_equal '2/3', evaluate('formatHearts({status: {hearts: 2, max_hearts: 3}})')
  end

  def test_unknown_health_is_styled_neutrally
    assert_match(/health-unknown/, PAGE)
  end

  def test_error_field_of_a_failed_response_is_shown
    assert_match(/\.error/, PAGE)
  end

  def test_cell_states_map_to_semi_transparent_colors
    colors = %w[yes no mixed stale unknown].map { |state| evaluate("cellColor('#{state}')") }
    assert_equal 5, colors.uniq.size
    assert(colors.all? { |c| c.start_with?('rgba(') })
    assert_equal colors.last, evaluate("cellColor('garbage')")
  end

  def test_cell_geometry_is_48_px_from_the_top_left
    assert_equal({ 'left' => 96, 'top' => 48, 'size' => 48 }, evaluate('cellRect(1, 2)'))
    assert_equal({ 'width' => 480, 'height' => 384 }, evaluate('gridExtent(8, 10)'))
  end

  def test_cell_titles_and_legend
    assert_equal '3,4 ab12 mixed', evaluate("cellTitle(3, 4, 'ab12', 'mixed')")
    assert_equal %w[yes no mixed stale unknown], evaluate('legendEntries()').map { |entry| entry['state'] }
    assert_equal 'Grid (no data)', evaluate('gridButtonLabel(true, null)')
    assert_equal 'Grid: on', evaluate('gridButtonLabel(true, {cells: []})')
    assert_equal 'Grid: off', evaluate('gridButtonLabel(false, {cells: []})')
  end

  def test_page_has_a_grid_toggle_that_remembers_the_choice
    assert_match(/id="grid"/, PAGE)
    assert_match(/koholint\.grid/, PAGE)
  end

  def fmt(event) = evaluate("formatEventPretty(#{JSON.generate(event)})")

  def test_a_skill_decision_reads_as_a_sentence
    event = { frame: 1234, type: 'decision', agent: 'claude', choice: { skill: 'walk', params: { direction: 'up', cells: 2 } },
              justification: 'door is north', confidence: 1 }
    assert_equal 'f1234 · claude decides walk up 2', fmt(event)
    assert_equal 'door is north', evaluate("eventTitle(#{JSON.generate(event)})")
  end

  def test_fallback_decisions_are_marked
    event = { frame: 2, type: 'decision', agent: 'claude', choice: { buttons: [], frames: 30 }, fallback: true }
    assert_equal 'f2 · claude decides idle 30f [fallback]', fmt(event)
  end

  def test_objective_choices_show_the_title
    event = { frame: 3, type: 'decision', agent: 'claude', choice: { title: 'Leave the house', predicate: { kind: 'leave_place' } } }
    assert_equal 'f3 · claude decides objective "Leave the house"', fmt(event)
  end

  def test_decisions_with_missing_fields_do_not_throw
    assert_equal 'f4 · ? decides', fmt({ frame: 4, type: 'decision' })
    assert_equal 'f4 · claude decides walk', fmt({ frame: 4, type: 'decision', agent: 'claude', choice: { skill: 'walk' } })
  end

  def test_skill_results_read_as_what_happened
    result = { skill: 'walk', moved_cells: 1, stopped_by: 'blocked' }
    assert_equal 'f9 · walked 1 cell, stopped: blocked', fmt({ frame: 9, type: 'action', skill: 'walk', params: {}, result: result })
    result = { skill: 'walk', moved_cells: 2, stopped_by: 'done', hp_delta: -1, room_changed: true }
    assert_equal 'f9 · walked 2 cells, done, room changed, hp -1', fmt({ frame: 9, type: 'action', skill: 'walk', params: {}, result: result })
    assert_equal 'f9 · walked 0 cells, stopped: damage', fmt({ frame: 9, type: 'action', skill: 'walk', result: { moved_cells: 0, stopped_by: 'damage' } })
  end

  def test_goto_and_step_read_as_what_was_asked_and_what_happened
    decision = { frame: 1, type: 'decision', agent: 'delegated', choice: { skill: 'goto', params: { row: 3, col: 4 } } }
    assert_equal 'f1 · delegated decides goto (3, 4)', fmt(decision)
    assert_equal 'f1 · delegated decides step up 8 px', fmt(decision.merge(choice: { skill: 'step', params: { direction: 'up', pixels: 8 } }))
    done = { skill: 'goto', params: { row: 3, col: 4 }, result: { moved_cells: 3, stopped_by: 'done' } }
    assert_equal 'f2 · goto (3, 4) · walked 3 cells, stopped: done', fmt({ frame: 2, type: 'action' }.merge(done))
    one = { skill: 'goto', params: { row: 3, col: 4 }, result: { moved_cells: 1, stopped_by: 'no_path' } }
    assert_equal 'f2 · goto (3, 4) · walked 1 cell, stopped: no_path', fmt({ frame: 2, type: 'action' }.merge(one))
    blocked = { skill: 'goto', params: { row: 3, col: 4 },
                result: { moved_cells: 2, stopped_by: 'blocked', blocked_at: { row: 2, col: 5, direction: 'up' } } }
    assert_equal 'f2 · goto (3, 4) · walked 2 cells, stopped: blocked, blocked at (2,5) up', fmt({ frame: 2, type: 'action' }.merge(blocked))
    step = { skill: 'step', params: { direction: 'up', pixels: 8 }, result: { moved_px: 6, stopped_by: 'blocked' } }
    assert_equal 'f3 · step up 8 px · moved 6 px, stopped: blocked', fmt({ frame: 3, type: 'action' }.merge(step))
  end

  def test_automatic_dialogue_advance_and_new_place_objectives
    event = { frame: 4, type: 'decision', agent: 'delegated', justification: 'automatic dialogue advance', choice: { buttons: %w[a], frames: 3 } }
    assert_equal 'f4 · automatic dialogue advance', fmt(event)
    started = { frame: 5, type: 'objective', id: 'obj-1', status: 'started', predicate: { kind: 'new_place' } }
    assert_equal 'f5 · objective: new_place started', fmt(started)
    abandoned = started.merge(status: 'abandoned', reason: 'unreachable')
    assert_equal 'f5 · objective: new_place abandoned (unreachable)', fmt(abandoned)
  end

  def test_a_locked_wait_reads_as_a_label
    event = { frame: 9, type: 'decision', agent: 'delegated', justification: 'locked: waiting for Link to be free', choice: { skill: 'wait', params: { frames: 30 } } }
    assert_equal 'f9 · locked: waiting for Link to be free', fmt(event)
  end

  def test_objective_events_read_with_status_and_reason
    event = { frame: 5, type: 'objective', id: 'o1', status: 'started', predicate: { kind: 'leave_place', place: [163, 16] } }
    assert_equal 'f5 · objective: leave_place [163,16] started', fmt(event)
    event = { frame: 6, type: 'objective', id: 'o1', status: 'abandoned', reason: 'stall', predicate: { kind: 'leave_place', place: [163, 16] } }
    assert_equal 'f6 · objective: leave_place [163,16] abandoned (stall)', fmt(event)
    assert_equal 'f7 · objective: o2 failed', fmt({ frame: 7, type: 'objective', id: 'o2', status: 'failed' })
  end

  def test_dialogue_is_a_quoted_line
    assert_equal 'f8 · dialogue: "Hello, Link!"', fmt({ frame: 8, type: 'dialogue', text: 'Hello, Link!', place: [1, 2] })
    assert_equal 'f8 · dialogue', fmt({ frame: 8, type: 'dialogue' })
  end

  def test_status_bar_formats
    assert_equal '$0.12', evaluate('formatDollars(0.1234)')
    assert_equal '$0.00', evaluate('formatDollars(null)')
    assert_equal 'none', evaluate('formatObjective({status: {objective: null}})')
    assert_equal 'o1', evaluate("formatObjective({status: {objective: 'o1'}})")
    assert_equal 'Leave the house', evaluate("formatObjective({status: {objective: 'o1', objective_title: 'Leave the house'}})")
    long = evaluate("formatObjective({status: {objective: 'o1', objective_title: '#{'x' * 80}'}})")
    assert_equal 40, long.length
    assert long.end_with?('…')
    assert_equal 3, evaluate('formatCalls({status: {calls: 3}})')
    assert_equal 0, evaluate('formatCalls({status: {}})')
  end

  PAYLOAD = %q(<script>alert(1)</script>"'&)

  def test_untrusted_text_comes_out_verbatim_from_the_formatters
    p = JSON.generate(PAYLOAD)
    assert_equal PAYLOAD, evaluate("eventTitle({type: 'decision', justification: #{p}})")
    assert_equal PAYLOAD, evaluate("eventTitle({type: 'dialogue', text: #{p}})")
    assert_equal PAYLOAD, evaluate("eventTitle({type: 'objective', title: #{p}})")
    assert_equal %(f1 · dialogue: "#{PAYLOAD}"), fmt({ frame: 1, type: 'dialogue', text: PAYLOAD })
    assert_equal %(f1 · c decides objective "#{PAYLOAD}"), fmt({ frame: 1, type: 'decision', agent: 'c', choice: { title: PAYLOAD } })
    assert_equal "f1 · c decides walk #{PAYLOAD}", fmt({ frame: 1, type: 'decision', agent: 'c', choice: { skill: 'walk', params: { a: PAYLOAD } } })
    assert_equal PAYLOAD, evaluate("formatObjective({status: {objective: 'o', objective_title: #{p}}})")
  end

  def test_event_titles_do_not_leak_other_fields
    assert_equal '', evaluate("eventTitle({type: 'action', justification: 'x', text: 'y'})")
    assert_equal '', evaluate("eventTitle({type: 'decision', justification: {a: 1}})")
  end

  def test_agent_text_is_never_assigned_as_html
    refute_match(/innerHTML|outerHTML|insertAdjacentHTML|document\.write/, PAGE)
  end

  def test_long_dialogue_is_truncated_in_the_row_and_whole_in_the_title
    text = 'y' * 300
    line = fmt({ frame: 1, type: 'dialogue', text: text })
    assert_equal 'f1 · dialogue: "'.length + 200 + 1, line.length
    assert_includes line, '…'
    assert_equal text, evaluate("eventTitle({type: 'dialogue', text: '#{text}'})")
  end

  def test_multi_param_skills_other_than_walk_show_their_keys
    skill = { skill: 'talk', params: { npc: 'old man', times: 2 } }
    assert_equal 'f1 · c decides talk npc=old man times=2', fmt({ frame: 1, type: 'decision', agent: 'c', choice: skill })
    assert_equal 'f1 · c decides use sword', fmt({ frame: 1, type: 'decision', agent: 'c', choice: { skill: 'use', params: { item: 'sword' } } })
  end

  def test_elapsed_time_reads_in_seconds_then_minutes
    assert_equal '4.2 s', evaluate('formatElapsed(4250)')
    assert_equal '0.0 s', evaluate('formatElapsed(-5)')
    assert_equal '59.9 s', evaluate('formatElapsed(59999)')
    assert_equal '1 min 05 s', evaluate('formatElapsed(65000)')
    assert_equal '12 min 30 s', evaluate('formatElapsed(750000)')
  end

  def test_activity_label_falls_back_for_unknown_kinds
    assert_equal 'asking', evaluate("activityLabel({kind: 'deciding', label: 'asking'})")
    assert_equal 'Mapping the screen', evaluate("activityLabel({kind: 'mapping'})")
    assert_equal 'teleporting', evaluate("activityLabel({kind: 'teleporting'})")
    assert_equal 'Working', evaluate('activityLabel({})')
    assert_equal 'Waiting for the engine...', evaluate('activityLabel(null)')
  end

  def test_elapsed_follows_the_server_clock_between_polls
    assert_equal 3500, evaluate('elapsedSince({started_at: 100}, 102, 5000, 6500)')
    assert_equal 0, evaluate('elapsedSince({started_at: 200}, 102, 5000, 6500)')
    assert_equal 0, evaluate('elapsedSince(null, 102, 5000, 6500)')
  end

  def test_activity_detail_shows_model_images_and_last_call
    a = { kind: 'deciding', detail: { model: 'sonnet', images: 2 } }
    assert_equal 'model sonnet · 2 images · last call 4.2 s', evaluate("activityDetail(#{JSON.generate(a)}, {last_ms: 4200})")
    acting = { kind: 'acting', detail: { skill: 'goto', params: { row: 1, col: 2 } } }
    assert_equal 'goto {"row":1,"col":2}', evaluate("activityDetail(#{JSON.generate(acting)}, null)")
    assert_equal 'reason: frames', evaluate("activityDetail({kind: 'stopped', detail: {reason: 'frames'}}, null)")
  end

  def test_predicates_read_in_words
    assert_equal 'reach cell (3, 4) in [1,2]', evaluate("predicateInWords({kind: 'reach_cell', row: 3, col: 4, place: [1, 2]})")
    assert_equal 'leave [1,2]', evaluate("predicateInWords({kind: 'leave_place', place: [1, 2]})")
    assert_equal 'close the open dialogue', evaluate("predicateInWords({kind: 'dialogue_closed'})")
    assert_equal 'find item', evaluate("predicateInWords({kind: 'find_item'})")
    assert_equal '', evaluate('predicateInWords(null)')
  end

  def test_meter_percentage_is_clamped_and_hidden_without_a_cap
    assert_equal 50, evaluate('meterPercent(1, 2)')
    assert_equal 100, evaluate('meterPercent(5, 2)')
    assert_equal 0, evaluate('meterPercent(-1, 2)')
    assert_nil evaluate('meterPercent(1, null)')
    assert_nil evaluate('meterPercent(1, 0)')
    assert_equal '$0.75 / $1.50 · 3 calls · median 4.0 s', evaluate('formatBudgetLine({spent: 0.75, cap: 1.5, calls: 3}, {median_ms: 4000})')
  end

  def test_reasoning_and_objective_panels_come_from_the_events
    events = [{ type: 'objective', id: 'o1', status: 'started', title: 'Go out', predicate: { kind: 'leave_place', place: [1, 2] } },
              { type: 'decision', frame: 3, agent: 'claude', justification: 'older', choice: {} },
              { type: 'action', skill: 'walk' },
              { type: 'decision', frame: 4, agent: 'start_game', justification: 'boot', choice: {} },
              { type: 'decision', frame: 5, agent: 'claude', justification: 'newest', confidence: 0.8, choice: { skill: 'goto', params: { row: 1, col: 2 } } },
              { type: 'action', skill: 'goto' }]
    json = JSON.generate(events)
    assert_equal 'newest', evaluate("latestReasoning(#{json}).justification")
    assert_equal 'f5 · claude decides goto (1, 2) (80%)', evaluate("reasoningHead(latestReasoning(#{json}))")
  end

  def test_objective_panel_uses_the_status_not_the_event_window
    status = { objective: 'o1', objective_title: 'Go out', objective_predicate: { kind: 'leave_place', place: [1, 2] }, objective_attempts: 7 }
    assert_equal({ 'title' => 'Go out', 'predicate' => 'leave [1,2]', 'attempts' => 7 }, evaluate("objectiveView(#{JSON.generate(status)})"))
    assert_equal({ 'title' => 'o1', 'predicate' => '', 'attempts' => nil }, evaluate("objectiveView({objective: 'o1'})"))
    assert_nil evaluate('objectiveView({})')
  end

  def test_a_dead_engine_shows_as_idle_even_if_the_file_says_deciding
    deciding = '{kind: "deciding", label: "asking", started_at: 1}'
    assert_equal 'idle', evaluate("effectiveActivity(#{deciding}, 'stopped').kind")
    assert_equal 'Engine not running (crashed)', evaluate("effectiveActivity(#{deciding}, 'crashed').label")
    assert_equal 'deciding', evaluate("effectiveActivity(#{deciding}, 'running').kind")
    assert_equal 'stopped', evaluate("effectiveActivity({kind: 'stopped'}, 'stopped').kind")
    assert_equal 'No live activity for this run', evaluate("effectiveActivity(null, 'running').label")
  end

  def test_agent_text_never_goes_through_inner_html
    refute_match(/innerHTML|outerHTML|insertAdjacentHTML|document\.write/, PAGE)
  end

  BAR_STATE = { status: { run_id: 'r1', flow_version: 3, health: 'ok', hearts: 2, max_hearts: 3, objective: 'o', objective_title: 'Find the sword',
                          cost_usd: 1.5, calls: 4, budget: 'wall 10m', manifest_status: 'running' },
                replay: { frame: 120, lag: 0, sync: 'ok' },
                events: [{ frame: 5, type: 'objective', id: 'o', status: 'started', predicate: { kind: 'reach_place', place: [1, 2] } }] }.freeze

  def test_bar_items_are_assigned_to_a_group
    items = evaluate("barItems(#{JSON.generate(BAR_STATE)})")
    groups = items.to_h { |i| [i['name'], i['group']] }
    assert_equal %w[run flow health frame lag sync budget manifest], groups.select { |_, g| g == 'harness' }.keys
    assert_equal %w[hearts objective last], groups.select { |_, g| g == 'game' }.keys
  end

  def test_bar_has_no_spent_or_calls
    names = evaluate("barItems(#{JSON.generate(BAR_STATE)})").map { |i| i['name'] }
    refute_includes names, 'spent'
    refute_includes names, 'calls'
  end

  def test_bar_item_formats_are_unchanged
    texts = evaluate("barItems(#{JSON.generate(BAR_STATE)})").to_h { |i| [i['name'], i['text']] }
    assert_equal 'r1', texts['run']
    assert_equal '2/3', texts['hearts']
    assert_equal 'Find the sword', texts['objective']
    assert_equal '120', texts['frame']
    assert_equal 'wall 10m', texts['budget']
    assert_equal 'f5 · objective: reach_place [1,2] started', texts['last']
  end

  def test_budget_line_shows_last_call_latency
    assert_equal '$0.75 / $1.50 · 3 calls · median 4.0 s · last 2.0 s', evaluate('formatBudgetLine({spent: 0.75, cap: 1.5, calls: 3}, {median_ms: 4000, last_ms: 2000})')
  end

  def test_bar_items_survive_missing_data
    items = evaluate("barItems({status: {}, replay: {}})")
    assert_equal '-', items.find { |i| i['name'] == 'hearts' }['text']
    assert_equal '-', items.find { |i| i['name'] == 'last' }['text']
  end
end
