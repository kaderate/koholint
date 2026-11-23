require_relative 'test_helper'
require 'json'
require 'open3'

class PageTest < Minitest::Test
  PAGE = File.read(File.expand_path('../lib/koholint/viewer/page.html', __dir__))

  VIEWER = File.expand_path('../lib/koholint/viewer', __dir__)

  def pure_source(page = PAGE)
    page[%r{// pure:begin\n(.*?)// pure:end}m, 1] or flunk 'page has no pure section'
  end

  def evaluate(expression, page: PAGE)
    unless system('which node > /dev/null 2>&1')
      flunk 'node is not installed and CI is set' if ENV['CI']
      skip 'node is not installed: page formatting tests not run'
    end
    out, status = Open3.capture2('node', '-e', "#{pure_source(page)}\nconsole.log(JSON.stringify(#{expression}));")
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

  def test_three_columns_on_desktop_and_one_column_in_reading_order_on_a_phone
    base = PAGE.index('#cols { display: grid; grid-template-columns: 400px minmax(0, 1fr) 330px')
    media = PAGE.index('@media (max-width: 1100px)')
    phone = PAGE.index('#cols, #lower { grid-template-columns: minmax(0, 1fr)', media)
    assert base < media, 'the base #cols rule must come before the media query'
    assert media < phone
    ids = %w[strip game reasoning objective dialogues-block symptoms-block place-card leads-block map-block header-block]
    positions = ids.map { |id| PAGE.index(%(id="#{id}")) }
    assert(positions.all?, 'every block is on the page')
    assert_equal positions.sort, positions
    assert_operator PAGE.index('id="strip"'), :<, PAGE.index('id="cols"')
    assert_match(/#strip \{ position: sticky; top: 0/, PAGE)
  end

  def test_the_cockpit_helpers_read_hearts_overlay_boxes_ladder_and_kpis
    assert_equal %w[full half empty], evaluate('heartsView({hp: 12, max_hp: 24})').then { |a| a.size == 3 ? %w[full half empty] : a }
    assert_equal %w[full half empty], evaluate('heartsView({hp: 12, max_hp: 24})')
    assert_equal [], evaluate('heartsView({hp: 0, max_hp: 0})')
    assert_equal({ 'left' => 30, 'top' => 100.0 / 9 * 2, 'width' => 10, 'height' => 100.0 / 9 }, evaluate('cellBox(2, 3)'))
    ladder = evaluate("ladderView({ladder: [{name: 'shield', reached: true}, {name: 'sword', reached: false}]})")
    assert_equal [['Bouclier', 'step done'], ['Épée', 'step next']], ladder.map { |s| [s['text'], s['className']] }
    view = evaluate("kpiView({spent: 3.42, cap: 10, calls: 118, free: 500, calls_per_1000f: 5.1, usd_per_1000f: 0.08, minutes: 41, cap_minutes: 180, places: 31})")
    assert_equal ['$3.42 / 10', 34, '31'], view.values_at('cost', 'percent', 'places')
    assert_includes view['detail'], '41 min sur 180'
    assert_equal '-', evaluate('kpiView({}).places')
    assert_includes evaluate('kpiView({spent: 1, inherited_cost_usd: 4}).detail'), '$4.00 hérités des runs parents'
  end

  def test_the_health_band_follows_the_hearts_and_a_bubble_flags_tips_and_repeats
    segments = evaluate("healthSegments({points: [{frame: 0, hp: 24, max_hp: 24}, {frame: 500, hp: 4, max_hp: 24}]}, 1000, 1000)")
    assert_equal [[0, 500, '#2b6a4f'], [500, 500, '#7a2a2a']], segments.map { |s| [s['x'], s['w'], s['color']] }
    bubble = evaluate("bubbleView({frame: 9, talk: 2, new_text: false, tip: true, text: '<b>x</b>'})")
    assert_equal ['f9 · talk 2 · répété · conseil', 'bub dim tipped', '<b>x</b>'], bubble.values_at('head', 'className', 'text')
    assert_equal({ 'text' => 'à revoir', 'className' => 'badge b-warn' }, evaluate("verdictBadge('revisit')"))
    assert_equal 'personne type 62', evaluate('personLabel({type: 62})')
    assert_equal 'Tarkin', evaluate("personLabel({type: 62, name: 'Tarkin'})")
    assert_equal ['choisi', 'cand picked'], evaluate("candidateView({id: 'c3', label: 'x', picked: true})").values_at('note', 'className')
    assert_equal 'laisse des PNJ non épuisés', evaluate("candidateView({id: 'c5', label: 'x', leaves_unexhausted: true})")['note']
    group = { name: 'Tarkin', talks: [{ text: 'La route du Sud' }] }
    assert_equal [true, false, true], %w[tark plage sud].map { |f| evaluate("groupMatches(#{JSON.generate(group)}, '#{f}')") }
    assert_equal({ 'parent' => 'Village', 'door' => ' · porte 226 en (4,5)' }, evaluate("interiorLink({parent: [1, 0], parent_name: 'Village', door: {object: 226, cell: [4, 5]}})"))
    assert_equal 'entrée inconnue', evaluate('interiorLink({})')
  end

  def test_a_decision_shows_its_reasoning_as_visible_text
    event = { frame: 9, type: 'decision', agent: 'claude', justification: "  go left <b>x</b>  \n" }
    assert_equal 'go left <b>x</b>', evaluate("formatReason(#{JSON.generate(event)})")
    assert_equal '', evaluate("formatReason({type: 'action', justification: 'x'})")
    assert_equal '', evaluate("formatReason({type: 'decision'})")
    assert_equal 600, evaluate("formatReason({type: 'decision', justification: 'a'.repeat(900)}).length")
  end

  def test_dialogues_are_listed_with_frame_place_and_source_as_plain_text
    assert_includes PAGE, '<div id="dialogues" class="scroll"></div>'
  end

  def test_the_goal_and_the_leads_are_shown_as_plain_lines
    status = { goal: 'find <b>it</b>', leads: [{ id: 'lead-2', importance: 'high', claim: 'x' * 200 }, { id: 'lead-1', importance: 'normal', claim: 'go up' }, { id: 'bad' }] }
    view = evaluate("memoryView(#{JSON.generate(status)})")
    assert_equal 'goal: find <b>it</b>', view['goal']
    assert_equal ["[high] #{'x' * 159}…", '[normal] go up'], view['leads']
    assert_equal({ 'goal' => 'goal: none yet', 'leads' => [] }, evaluate('memoryView({})'))
    assert_includes PAGE, '<div id="goal"></div>'
    assert_includes PAGE, '<div id="plan"></div>'
    assert_includes PAGE, '<ul id="leads"></ul>'
    assert_includes PAGE, 'item.textContent = text;'
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
    assert_equal 'read a new text', evaluate("predicateInWords({kind: 'new_text'})")
    assert_equal 'find item', evaluate("predicateInWords({kind: 'find_item'})")
    assert_equal '', evaluate('predicateInWords(null)')
  end

  def test_meter_percentage_is_clamped_and_hidden_without_a_cap
    assert_equal 50, evaluate('meterPercent(1, 2)')
    assert_equal 100, evaluate('meterPercent(5, 2)')
    assert_equal 0, evaluate('meterPercent(-1, 2)')
    assert_nil evaluate('meterPercent(1, null)')
    assert_nil evaluate('meterPercent(1, 0)')
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

  def test_the_page_finds_its_run_in_the_path_or_the_query
    assert_nil evaluate("runFromLocation('/', '')")
    assert_equal '20261020-085011-8330', evaluate("runFromLocation('/run/20261020-085011-8330', '')")
    assert_equal 'a b', evaluate("runFromLocation('/run/a%20b', '')")
    assert_equal 'x&y', evaluate("runFromLocation('/', '?t=1&run=x%26y')")
    assert_nil evaluate("runFromLocation('/run/%E0%A4%A', '')")
    assert_nil evaluate("runFromLocation('/run/a/b', '')")
  end

  def test_requests_carry_the_run_encoded
    assert_equal '/state.json', evaluate("withRun('/state.json', null)")
    assert_equal '/state.json?run=a%26b%3Dc', evaluate("withRun('/state.json', 'a&b=c')")
    assert_equal '/frame.png?t=3&run=r1', evaluate("withRun('/frame.png?t=3', 'r1')")
  end

  def test_replay_label_shows_speed_pause_and_end
    assert_equal 'Replay playing at 4x, f10 / 100', evaluate("replayLabel({frame: 10, journal_frames: 100, speed: 4, paused: false})")
    assert_equal 'Replay paused at f10 / 100', evaluate("replayLabel({frame: 10, journal_frames: 100, speed: 4, paused: true})")
    assert_equal 'Replay finished at f100 / 100', evaluate("replayLabel({frame: 100, journal_frames: 100, speed: 1})")
    assert_equal 'Replay playing at 1x, f0', evaluate('replayLabel(null)')
  end

  def test_every_page_has_the_same_top_navigation
    [PAGE, RUNS, COMPARE].each do |html|
      nav = html[%r{<nav id="nav">.*?</nav>}m] or flunk 'page has no nav'
      assert_match(%r{<a[^>]*href="/">Live</a>}, nav)
      assert_match(%r{<a[^>]*href="/runs">Historique</a>}, nav)
      assert_match(/id="compare"|id="nav-compare"/, nav)
      assert_includes nav, 'Comparer</a>'
      assert_match(/name="viewport"/, html)
    end
    assert_includes PAGE, '<span id="nav-badge" class="badge">replay</span>'
    assert_match(/compare\.hidden = !href/, PAGE)
    assert_match(/compareLink\.hidden = !href/, RUNS)
    assert_includes RUNS, "localStorage.setItem('koholint.picked'"
    assert_includes PAGE, "stored('koholint.picked')"
  end

  def test_compare_href_needs_two_string_ids
    assert_equal '/compare/a/b%2Fc', evaluate("compareHref(['a', 'b/c'])")
    assert_nil evaluate("compareHref(['a'])")
    assert_nil evaluate('compareHref(null)')
    assert_nil evaluate("compareHref(['a', 3])")
  end

  def test_mode_badge_and_alerts
    assert_equal({ 'text' => 'mode: dialogue', 'className' => 'badge phase-dialogue' }, evaluate("modeBadge({phase: 'dialogue', name: 'dialogue'})"))
    assert_equal 'mode: playing (play)', evaluate("modeBadge({phase: 'playing', name: 'play'}).text")
    assert_equal 'badge phase-unknown', evaluate(%q(modeBadge({phase: '" onclick="x'}).className))
    assert_equal 'mode: unknown', evaluate('modeBadge(null).text')
    alerts = [{ kind: 'unknown_mode', frame: 5, detail: 'game_mode=9' }, { kind: 'stuck_boot', frame: 9, detail: 'run stopped: stuck_boot' }, { frame: 1 }]
    assert_equal ['f5 · unknown mode: game_mode=9', 'f9 · stuck at boot: run stopped: stuck_boot'], evaluate("alertsView({alerts: #{JSON.generate(alerts)}})")
    assert_equal [], evaluate('alertsView({})')
    assert_match(/id="mode-badge"/, PAGE)
    assert_match(/id="alerts"/, PAGE)
  end

  def test_timeline_marks_are_laid_out_by_frame_and_lane
    timeline = { frames: 1000, markers: [{ frame: 500, kind: 'call', skill: 'walk', label: '<b>x</b>', count: 1 },
                                         { frame: 1000, kind: 'objective', status: 'failed', label: 'o', count: 3 },
                                         { frame: 10, kind: 'bogus' }, { kind: 'call' }] }
    marks = evaluate("timelineMarks(#{JSON.generate(timeline)}, 1000, 130)")
    assert_equal [500, 1000], marks.map { |m| m['x'] }
    assert_equal ['f500 · <b>x</b>', 'f1000 · o'], marks.map { |m| m['label'] }
    assert_equal [evaluate("skillColor('walk')"), '#f44'], marks.map { |m| m['color'] }
    assert_equal [2, 4], marks.map { |m| m['w'] }
    assert_operator marks[0]['y'], :>, marks[1]['y']
    assert_equal evaluate("skillColor('explore')"), evaluate("skillColor('explore')")
    assert_equal 0, evaluate('markerX(5, 0, 100)')
    assert_equal 100, evaluate('markerX(500, 100, 100)')
    assert_match(/control\('seek=' \+/, PAGE)
  end

  def test_map_view_places_nodes_and_links
    map = { current: [2, 0], places: [{ place: [1, 0], order: 1, x: 0, y: 0, coverage: 40, people: [{}], leads: [] },
                                     { place: [2, 0], order: 2, x: 1, y: 0, coverage: nil, people: [], leads: [{}, {}] }, { place: 'bad' }],
            links: [{ a: [1, 0], b: [2, 0], count: 2 }, { a: [1, 0], b: [9, 9] }] }
    view = evaluate("mapView(#{JSON.generate(map)})")
    assert_equal 2, view['nodes'].size
    assert_equal [{ 'x1' => 56, 'y1' => 51, 'x2' => 160, 'y2' => 51, 'count' => 2 }], view['lines']
    assert_equal [216, 102, nil], view.values_at('width', 'height', 'lane')
    assert_equal 145, evaluate("mapView({lane: 2, places: []}).lane")
    assert_equal({ 'title' => '#1 [1,0]', 'detail' => '40% known · 1 person' }, evaluate("nodeLines(#{JSON.generate(map[:places][0])})"))
    assert_equal({ 'title' => '#2 [2,0]', 'detail' => 'no grid · 2 leads' }, evaluate("nodeLines(#{JSON.generate(map[:places][1])})"))
    house = { place: [163, 16], order: 1, kind: 'interior', parent: [162, 0], first_frame: 260, arrivals: 1, coverage: 23 }
    assert_equal 'interior #1 [163,16]', evaluate("nodeLines(#{JSON.generate(house)}).title")
    assert_equal 'visit #1 [163,16] · interior · entered from [162,0] · first f260 · 1 arrival', evaluate("nodeTip(#{JSON.generate(house)})")
    world = { place: [162, 0], order: 2, kind: 'world', cell: [2, 10], first_frame: 9, arrivals: 3 }
    assert_equal 'visit #2 [162,0] · world · world cell (2, 10) · first f9 · 3 arrivals', evaluate("nodeTip(#{JSON.generate(world)})")
    assert_equal '#2 [162,0]', evaluate("nodeLines(#{JSON.generate(world)}).title")
    assert_equal '/screens/163-16.png', evaluate("screenshotUrl({place: [163, 16], screenshot: true})")
    assert_nil evaluate("screenshotUrl({place: [163, 16], screenshot: false})")
    assert_nil evaluate("screenshotUrl({place: [163, '../x'], screenshot: true})")
    assert_nil evaluate('screenshotUrl(null)')
    assert_equal '(4, 7) · 2 talks, 1 text · exhausted', evaluate("personText({row: 4, col: 7, attempts: 2, texts: 1, state: 'exhausted'})")
    assert_equal({ 'nodes' => [], 'boxes' => {}, 'lines' => [], 'width' => 0, 'height' => 0, 'lane' => nil }, evaluate('mapView(null)'))
    assert_equal %w[free blocked mixed doubtful unknown], evaluate('legendEntries()').map { |e| e['word'] }
  end

  def test_run_header_rows_and_line
    header = { run_id: 'r1', tag: '<i>t</i>', flow_version: 'flow-9', model: 'sonnet', harness_sha: 'b66f33e0fc91c96', highest_milestone: 'shield',
               places_seen: 8, frames: 13_175, dollars: 1.51346, stop_reason: 'dollars' }
    rows = evaluate("headerRows(#{JSON.generate(header)})")
    assert_equal %w[tag flow model harness milestone places frames dollars stop], rows.map { |r| r['label'] }
    assert_equal ['<i>t</i>', 'flow-9', 'sonnet', 'b66f33e0', 'shield', '8', '13175', '$1.5135', 'dollars'], rows.map { |r| r['text'] }
    assert_equal 'Run r1 · <i>t</i> · flow-9 · $1.51 · stop: dollars', evaluate("headerLine(#{JSON.generate(header)})")
    assert_equal '-', evaluate('headerRows({})[0].text')
    assert_includes PAGE, '<textarea id="notes" maxlength="8192" disabled></textarea>'
    assert_includes PAGE, "withRun('/notes', notesRun)"
  end

  SINKS = [/\.innerHTML\b/, /\.outerHTML\b/, /insertAdjacentHTML/, /document\.write/, /\beval\(/, /new Function/, /srcdoc/, /javascript:/,
           /setAttribute\(\s*['"]on/, /\.on[a-z]+\s*=/].freeze

  def test_no_page_puts_data_through_an_html_or_code_sink
    { 'page.html' => PAGE, 'runs.html' => RUNS, 'compare.html' => COMPARE, 'atlas.html' => ATLAS }.each do |name, html|
      SINKS.each { |sink| refute_match sink, html, "#{name} uses #{sink.source}" }
    end
  end

  RUNS = File.read(File.join(VIEWER, 'runs.html'))
  COMPARE = File.read(File.join(VIEWER, 'compare.html'))
  ATLAS = File.read(File.join(VIEWER, 'atlas.html'))
  PLACE = { key: '163-16', label: '163/16', grid: false, opens_from: ['C11'], first: { run: 'r1', frame: 351 }, visits: 3, runs: 2, deaths: 1,
            seen: { people: [62, 63], unknown: [70, 71] }, signs: 0, doors: 1, tried: [{ type: 62, tries: 3, answered: 1 }], untried: [63], unknown_untried: [71], exits: [{ way: 'door', to: 'C11', count: 2 }],
            names: [{ name: "Marine's house", run: 'r1', frame: 1719, source: { text: "Je suis\nMarine", frame: 801 } }], names_withheld: 1,
            items: [{ name: 'shield', run: 'r1', frame: 3906 }], puzzles: [], texts: [], screen: 'r1' }.freeze

  def atlas_eval(expression) = evaluate(expression, page: ATLAS)

  def test_atlas_cells_follow_the_map_labels
    assert_equal %w[A1 B10 P16], atlas_eval('[cellLabel(0), cellLabel(145), cellLabel(255)]')
  end

  def test_atlas_card_shows_a_name_with_its_source_and_counts_the_withheld_ones
    rows = atlas_eval("cardRows(#{JSON.generate(PLACE)})").to_h { |row| [row['label'], row['text']] }
    assert_equal "Marine's house — « Je suis Marine » (r1, frame 801) · 1 nom proposé par le modèle sans texte lu qui le porte, non affiché", rows['nom']
    assert_equal 'type 62 (3 essais, 1 réponse)', rows['talk_to tentés']
    assert_equal 'type 63', rows['personnes sans talk_to']
    assert_equal '1 (type 71)', rows['inconnus sans talk_to']
    assert_equal 'porte → C11 ×2', rows['sorties prises']
    assert_equal 'shield (r1, frame 3906)', rows['objets obtenus']
    assert_equal '163/16 · intérieur qui part de C11', atlas_eval("title(#{JSON.generate(PLACE)})")
  end

  def test_atlas_badges_and_interiors_hang_on_the_screen_they_open_from
    places = [PLACE, { label: 'C11', grid: true, untried: [], deaths: 2, puzzles: [{ id: 'x' }] }]
    marks = atlas_eval("badges(indexPlaces(#{JSON.generate(places)}).C11).map(function (b) { return b.text; })")
    assert_equal ['✝2', '?', '⌂'], marks
    assert_equal '/screens/163-16.png?run=r1', atlas_eval("screenUrl(#{JSON.generate(PLACE)})")
    assert_nil atlas_eval("screenUrl({ key: '1-0' })")
  end

  def test_atlas_shows_a_visited_screen_without_a_capture
    place = PLACE.merge(key: '210-0', label: 'C14', grid: true, opens_from: [], screen: nil)
    assert_equal ['c k n', 'c k', 'c'], atlas_eval("[cellClass(#{JSON.generate(place)}), cellClass(#{JSON.generate(PLACE)}), cellClass(undefined)]")
    rows = atlas_eval("cardRows(#{JSON.generate(place)})").to_h { |row| [row['label'], row['text']] }
    assert_equal 'vu, sans capture : aucun screens/210-0.png dans les runs lus', rows['capture']
    assert_equal 'r1, frame 351', rows['première visite']
    assert_equal 'C14', atlas_eval("title(#{JSON.generate(place)})")
    assert_equal 'screens/163-16.png (r1)', atlas_eval("cardRows(#{JSON.generate(PLACE)})").find { |row| row['label'] == 'capture' }['text']
  end

  def test_atlas_leads_sort_by_importance_then_status_and_read_as_text
    leads = [{ quote: 'b', importance: 'normal', status: 'open', first: { run: 'r1', frame: 5 }, runs: 1, tried: 0, achieved: 0 },
             { quote: 'a', claim: 'c', importance: 'high', status: 'tested', place: 'C16', first: { run: 'r2', frame: 9 }, runs: 2, tried: 3, achieved: 1 },
             { quote: 'z', importance: 'high', status: 'open', first: { run: 'r3', frame: 1 }, runs: 1, tried: 0, achieved: 0 }]
    rows = atlas_eval("leadRows(#{JSON.generate(leads)})")
    assert_equal %w[z a b], rows.map { |row| row['cells'][2] }
    assert_equal ['testée', 'haute', 'a', 'modèle : c', 'C16', 'r2, frame 9', '2', '1 atteint sur 3'], rows[1]['cells']
    assert_equal 'moteur : x', atlas_eval("leadRows([{ quote: 'q', claim: 'x', contact: true, first: { run: 'r', frame: 1 }, runs: 1, tried: 0, achieved: 0 }])[0].cells[3]")
  end

  def test_atlas_flow_rows_give_the_cost_per_new_screen
    flows = [{ flow: 'flow-3', runs: 2, frames: 100, dollars: 3, calls: 9, screens: %w[B10 B11], interiors: [], texts: 4, leads: 1, items: ['shield'] },
             { flow: 'flow-4', runs: 1, frames: 50, dollars: 1, calls: 2, screens: [], interiors: ['163/16'], texts: 0, leads: 0, items: [] }]
    assert_equal 'hérité (parent non lu)', atlas_eval("flowRows([{ flow: 'inherited', runs: 0, frames: 0, dollars: 0, screens: ['A1'] }])[0][0]")
    assert_equal [['flow-3', '2', '100', '$3.00', '2 (B10, B11)', '0', '4', '1', 'shield', '$1.50'], ['flow-4', '1', '50', '$1.00', '0', '163/16', '0', '0', '—', '—']],
                 atlas_eval("flowRows(#{JSON.generate(flows)})")
  end

  def test_atlas_facts_read_as_a_summary_and_plain_cells
    file = { file: 'data/items.json', statuses: { 'verified' => 2, '-' => 1 }, rows: [1, 2, 3] }
    assert_equal 'data/items.json — 3 entrées · verified 2, sans statut 1', atlas_eval("factSummary(#{JSON.generate(file)})")
    assert_equal ['1 sword', 'verified', '2', 'probe', '—'], atlas_eval("factCells({ label: '1 sword', status: 'verified', verified_count: 2, source: 'probe', note: null })")
    assert_equal ['a', '—', '—', '—', '—'], atlas_eval("factCells({ label: 'a' })")
    assert_equal '2 (dérivé)', atlas_eval("factCells({ label: 'c', status: 'operational', verified_count: 2, derived: true })[2]")
    status = atlas_eval("factStatus({ status: 'verified', subfacts: [{ name: 'sword_hits', status: 'hypothesis' }] })")
    assert_equal({ 'text' => 'verified · sword_hits : hypothesis', 'cls' => 'f-mixed' }, status)
    assert_equal 'data/x.json — illisible : boom', atlas_eval("factSummary({ file: 'data/x.json', error: 'boom' })")
    assert_equal 'data/m.json — non lu par l\'atlas', atlas_eval("factSummary({ file: 'data/m.json', skipped: true })")
    assert_match(/au moins 2 vérifications.* 3 lieux de succès.* 4 lignées/, atlas_eval('factRules({ verified: 2, places: 3, lineages: 4 })'))
  end

  def test_atlas_kpis_read_the_totals
    atlas = { runs: 2, roots: ['runs'], last_run: 'r2', unreadable: 0, totals: { overworld: 55, interiors: 12, texts: 75, deaths: 8, items: { shield: 2 }, puzzles: 1, dollars: 47.614, calls: 10, frames: 99 } }
    assert_equal ['55 / 256', '12', '75', '8', 'shield ×2', '1', '$47.61'], atlas_eval("kpis(#{JSON.generate(atlas)}).map(function (k) { return k.value; })")
    assert_equal '2 runs lus dans runs · dernier r2', atlas_eval("scopeText(#{JSON.generate(atlas)})")
  end
  SAMPLE = [{ run_id: 'r1', tag: 'Agent-x', dollars: 0.5, milestone_rank: 0, highest_milestone: 'none', starred: false, frames: 10 },
            { run_id: 'r2', tag: nil, dollars: 1.5, milestone_rank: 1, highest_milestone: 'shield', starred: true, frames: nil },
            { run_id: 'r3', tag: 'other', dollars: nil, milestone_rank: nil, highest_milestone: nil, starred: false, frames: 30 }].freeze

  def runs_eval(expression) = evaluate("(function () { var runs = #{JSON.generate(SAMPLE)}; return #{expression}; })()", page: RUNS)

  def test_runs_filters
    ids = ->(filters) { runs_eval("filterRuns(runs, #{JSON.generate(filters)}).map(function (r) { return r.run_id; })") }
    assert_equal %w[r1 r2 r3], ids.call({})
    assert_equal %w[r2], ids.call(minRank: 1)
    assert_equal %w[r1 r2], ids.call(minRank: 0)
    assert_equal %w[r1], ids.call(maxDollars: 1)
    assert_equal %w[r1], ids.call(tag: 'agent')
    assert_equal %w[r2], ids.call(starredOnly: true)
  end

  def test_runs_sort_puts_missing_values_last
    sorted = ->(key, desc) { runs_eval("sortRuns(runs, '#{key}', #{desc}).map(function (r) { return r.run_id; })") }
    assert_equal %w[r1 r3 r2], sorted.call('frames', false)
    assert_equal %w[r3 r1 r2], sorted.call('frames', true)
    assert_equal %w[r2 r1 r3], sorted.call('highest_milestone', true)
    assert_equal %w[r3 r2 r1], sorted.call('run_id', true)
  end

  def test_runs_milestone_options_follow_the_ladder
    assert_equal [{ 'name' => 'none', 'rank' => 0 }, { 'name' => 'shield', 'rank' => 1 }], runs_eval('milestoneOptions(runs)')
  end

  def test_compare_link_needs_exactly_two_runs
    assert_includes RUNS, '<a id="compare" href="#" hidden>Comparer</a>'
    assert_nil runs_eval("compareHref(['a'])")
    assert_equal '/compare/a/b%2Fc', runs_eval("compareHref(['a', 'b/c'])")
  end

  def test_run_cells_are_plain_text
    assert_equal '0.5000', runs_eval("cellText(runs[0], {key: 'dollars'})")
    assert_equal '0.0123', evaluate("cellText({usd_per_call: 0.01234}, {key: 'usd_per_call'})", page: RUNS)
    assert_equal '★', runs_eval("cellText(runs[1], {key: 'starred'})")
    assert_equal '', runs_eval("cellText(runs[1], {key: 'tag'})")
    assert_equal '<b>x</b>', evaluate("cellText({tag: '<b>x</b>'}, {key: 'tag'})", page: RUNS)
  end

  def test_compare_page_reads_its_ids_and_marks_differences
    assert_equal %w[a b], evaluate("idsFromPath('/compare/a/b')", page: COMPARE)
    assert_nil evaluate("idsFromPath('/compare/a')", page: COMPARE)
    data = { a: { summary: { tag: 'x', frames: 1 } }, b: { summary: { tag: 'x', frames: 2 } }, differences: ['frames'] }
    assert_equal [{ 'field' => 'tag', 'a' => 'x', 'b' => 'x', 'diff' => false }, { 'field' => 'frames', 'a' => '1', 'b' => '2', 'diff' => true }],
                 evaluate("summaryRows(#{JSON.generate(data)})", page: COMPARE)
    usage = { a: { talks: 2, leads: { high: 1 } }, b: { talks: 3, dialogues: 1 }, differences: %w[talks leads dialogues] }
    assert_equal [{ 'field' => 'talks', 'a' => '2', 'b' => '3', 'diff' => true }, { 'field' => 'leads', 'a' => '{"high":1}', 'b' => '-', 'diff' => true },
                  { 'field' => 'dialogues', 'a' => '-', 'b' => '1', 'diff' => true }],
                 evaluate("sectionRows(#{JSON.generate(usage)})", page: COMPARE)
    cost = { a: { walk: { calls: 3, usd: 0.25 } }, b: { walk: { calls: 3, usd: 0.25 } }, differences: [] }
    assert_equal [{ 'field' => 'walk', 'a' => '3 calls, $0.2500', 'b' => '3 calls, $0.2500', 'diff' => false }],
                 evaluate("sectionRows(#{JSON.generate(cost)}, costText)", page: COMPARE)
    assert_equal [], evaluate('sectionRows(undefined)', page: COMPARE)
    assert_equal 'never', evaluate('frameText(null)', page: COMPARE)
    assert_equal '[3,1]', evaluate('placeText([3, 1])', page: COMPARE)
  end
end
