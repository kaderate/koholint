require_relative 'support/delegated_helpers'

class DelegatedTriggersTest < Minitest::Test
  include DelegatedHelpers

  SPOT = { room: 163, map: 16, row: 3, col: 4 }.freeze

  def sprite_grid
    cells = Array.new(8) { Array.new(10) { 'floor' } }
    sprites = [{ 'x' => 40, 'y' => 32, 'pattern' => 'a' }, { 'x' => 120, 'y' => 80, 'pattern' => 'b' }]
    Koholint::Vision::Grid.new(cells:, static_sprites: sprites, beliefs: Koholint::Vision::Beliefs.new, capabilities: Koholint::Vision::Capabilities.new)
  end

  def finish(p, skill, params, frame, **over)
    outcome = { skill:, params:, frames: 8, moved_cells: 0, room_changed: false, hp_delta: 0, stopped_by: 'done', from: SPOT, to: SPOT,
                dialog_before: false, dialog_after: true, blocked_at: nil, **over }
    p.after_action(choice: { skill:, params: }, outcome:, state: state, frame:)
  end

  def tour(p, client)
    p.decide(p.decision_point_for(state), state, { grid: sprite_grid })
    client.calls.last[:prompt]
  end

  def setup_policy
    client = ScriptedClient.new(objective: objective(kind: 'reach_place', place: [1, 2]), skill: walk, default: walk)
    [policy(client), client]
  end

  def test_pressing_a_or_talking_does_not_count_as_a_trigger
    p, client = setup_policy
    tour(p, client)
    finish(p, 'press', { button: 'a', frames: 3 }, 101)
    finish(p, 'talk_to', { row: 1, col: 2 }, 102, talked: true)
    finish(p, 'advance_dialogue', {}, 103)
    refute_includes tour(p, client), 'opened by itself'
  end

  def test_the_things_section_tracks_what_was_talked_to
    p, client = setup_policy
    assert_includes tour(p, client), "- at (1,2): never tried\n- at (4,7): never tried"
    finish(p, 'talk_to', { row: 1, col: 2 }, 101, talked: true)
    assert_includes tour(p, client), "- at (1,2): talked to 1 time (dialogue opened 1)\n- at (4,7): never tried"
    finish(p, 'talk_to', { row: 1, col: 2 }, 102, talked: false, dialog_after: false)
    assert_includes tour(p, client), '- at (1,2): talked to 2 times (dialogue opened 1)'
  end

  def test_a_second_talk_to_on_the_same_object_excludes_the_side_that_gave_no_response
    p, client = setup_policy
    tour(p, client)
    context = { grid: sprite_grid }
    p.decide(p.decision_point_for(state), state, context)
    assert_equal [], context[:talk_log].failed_sides(SPOT.values_at(:room, :map), [1, 2])
    finish(p, 'talk_to', { row: 1, col: 2 }, 101, talked: false, stopped_by: 'no_response', standing_cell: { row: 2, col: 2 },
                                                  standing_cells_tried: [{ row: 2, col: 2, outcome: 'no_response' }])
    context = { grid: sprite_grid }
    p.decide(p.decision_point_for(state), state, context)
    assert_equal [[2, 2]], context[:talk_log].failed_sides(SPOT.values_at(:room, :map), [1, 2])
    assert_includes client.calls.last[:prompt], '- at (1,2): talked to 1 time (dialogue opened 0); no response from (2,2)'
  end

  def test_the_summary_and_the_live_prompt_show_scripted_openings_on_one_cell
    p, client = setup_policy
    tour(p, client)
    finish(p, 'walk', { direction: 'up', cells: 1 }, 101)
    assert_includes @objectives.attempts_for_prompt.last, ', dialogue opened by itself x1'
    refute_includes tour(p, client), 'opened by itself 1 times'
    refute_includes client.calls.last[:prompt], 'while Link was on this cell'
    finish(p, 'walk', { direction: 'up', cells: 1 }, 102)
    assert_includes tour(p, client), 'A dialogue opened by itself 2 times while Link was on this cell'
    finish(p, 'walk', { direction: 'up', cells: 1 }, 103, dialog_after: false)
    refute_includes @objectives.attempts_for_prompt.last, 'opened by itself'
  end

  def test_a_walk_interrupted_by_the_trigger_records_the_input_for_the_next_tours
    p, client = setup_policy
    tour(p, client)
    finish(p, 'walk', { direction: 'right', cells: 1 }, 101, trigger_input: [:down])
    refute_includes tour(p, client), 'A dialogue opened by itself'
    context = { grid: sprite_grid }
    p.decide(p.decision_point_for(state), state, context)
    assert_equal [:down], context[:triggers].forbidden([163, 16], [3, 4])
    assert_includes client.calls.last[:prompt], 'Pressing down while Link was on this cell opened a dialogue by itself 1 time (the game triggers it; other inputs did not; goto and talk_to routes avoid it, an explicit walk, step or press is not filtered).'
    finish(p, 'goto', { row: 3, col: 6 }, 102, trigger_input: ['down'])
    assert_includes tour(p, client), 'opened a dialogue by itself 2 times (the game triggers it'
    finish(p, 'walk', { direction: 'up', cells: 1 }, 103)
    assert_includes tour(p, client), 'Pressing down'
  end

  def test_place_of_falls_back_to_the_state_place
    p, = setup_policy
    assert_equal [163, 16], p.send(:place_of, {}, :to, state)
    assert_equal [1, 2], p.send(:place_of, { to: { room: 1, map: 2 } }, :to, state)
  end
end
