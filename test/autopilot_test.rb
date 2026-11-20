require_relative 'test_helper'
require 'koholint/autopilot'
require 'koholint/game_state'

class AutopilotTest < Minitest::Test
  def state(**over)
    Koholint::GameState.new(frame: 100, room_id: 163, map_id: 16, x: 68, y: 60, direction: :up, hp: 24, max_hp: 24,
                            milestone: :none, game_mode: 0x0B, game_submode: 7, dialog_state: 0, **over)
  end

  def objective(kind = 'new_place', id: 'obj-1') = { id:, predicate: { kind: } }

  def primed(stop: :new_place, news: false, **opts)
    pilot = Koholint::Autopilot.new(**opts)
    pilot.model_called(state: state, objective: objective, news:)
    pilot.acted(skill: 'explore', outcome: { stopped_by: stop })
    pilot
  end

  def test_a_benign_stop_continues_with_an_undirected_free_explore
    %i[new_place known_place budget untried_object].each do |stop|
      result = primed(stop:).next_choice(state: state(frame: 400), objective: objective)
      assert_equal({ skill: 'explore', params: {} }, result[:choice])
      assert_equal [0.0, 'delegated', true, false], result.values_at(:cost_usd, :agent, :autopilot, :fallback)
      assert_match(/\Aautopilot/, result[:justification])
    end
  end

  def test_a_never_tried_unknown_entity_is_tried_nearest_first_and_the_chain_goes_on
    pilot = primed
    entities = [{ kind: :unknown, type: 79, cell: [1, 1] }, { kind: :unknown, type: 80, cell: [3, 5] }, { kind: :npc, type: 5, cell: [3, 3] },
                { kind: :unknown, type: 81, cell: [3, 6] }]
    met = [80]
    tried = ->(type) { met.include?(type) }
    result = pilot.try_choice(state: state(frame: 400), objective:, entities:, tried:)
    assert_equal({ skill: 'talk_to', params: { row: 3, col: 6 } }, result[:choice])
    assert_equal [0.0, true], result.values_at(:cost_usd, :autopilot)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response })
    met << 81
    assert_equal({ row: 1, col: 1 }, pilot.try_choice(state: state(frame: 500), objective:, entities:, tried:)[:choice][:params])
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_path })
    met << 79
    assert_nil pilot.try_choice(state: state(frame: 600), objective:, entities:, tried:)
    assert_equal({ skill: 'explore', params: {} }, pilot.next_choice(state: state(frame: 600), objective:)[:choice])
  end

  def test_the_objects_an_explore_offered_are_tried_before_exploring_on
    pilot = Koholint::Autopilot.new
    pilot.model_called(state:, objective:)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :untried_object, untried_objects: [{ row: 2, col: 4 }] })
    result = pilot.try_choice(state: state(frame: 400), objective:, entities: [], tried: ->(_) { false })
    assert_equal({ skill: 'talk_to', params: { row: 2, col: 4 } }, result[:choice])
    assert_match(/never-tried object at \(2,4\)/, result[:justification])
    assert_nil pilot.try_choice(state: state(frame: 401), objective:, entities: [], tried: ->(_) { false })
  end

  def test_a_try_ignores_the_chain_caps_but_not_health_targets_or_other_stops
    entities = [{ kind: :unknown, type: 79, cell: [1, 1] }]
    tried = ->(_) { false }
    refute_nil primed(chain_limit: 0).try_choice(state: state(frame: 400), objective:, entities:, tried:)
    assert_nil primed.try_choice(state: state(frame: 400, hp: 20), objective:, entities:, tried:)
    assert_nil primed.try_choice(state: state(frame: 400), objective: objective.merge(target: { kind: 'exit' }), entities:, tried:)
    assert_nil primed(stop: :blocked).try_choice(state: state(frame: 400), objective:, entities:, tried:)
  end

  def test_a_return_to_a_known_place_does_not_count_in_the_chain
    pilot = primed(stop: :known_place)
    pilot.next_choice(state: state(frame: 400), objective: objective)
    assert_equal 0, pilot.chain
    pilot.acted(skill: 'explore', outcome: { stopped_by: :new_place })
    pilot.next_choice(state: state(frame: 500), objective: objective)
    assert_equal 1, pilot.chain
  end

  def test_a_third_return_to_the_same_place_goes_back_to_the_model
    pilot = primed(stop: :known_place)
    2.times do |i|
      pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place, to: { room: 147, map: 0 } })
      refute_nil pilot.next_choice(state: state(frame: 400 + i), objective: objective)
    end
    pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place, to: { room: 147, map: 0 } })
    assert_equal 'explore loop', pilot.hold_reason(state: state(frame: 500), objective: objective)
  end

  def test_other_stops_go_back_to_the_model
    %i[dialogue no_frontier blocked stalled locked damage].each do |stop|
      pilot = primed(stop:)
      assert_nil pilot.next_choice(state: state, objective: objective), stop
      assert_equal "last stop #{stop}", pilot.hold_reason(state: state, objective: objective)
    end
  end

  def test_a_non_explore_action_or_no_model_call_yet_holds
    pilot = primed
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :done })
    assert_nil pilot.next_choice(state: state, objective: objective)
    fresh = Koholint::Autopilot.new
    fresh.acted(skill: 'explore', outcome: { stopped_by: :new_place })
    assert_equal 'no model call yet', fresh.hold_reason(state: state, objective: objective)
  end

  def test_each_model_trigger_holds
    assert_equal 'new lead or goal', primed(news: true).hold_reason(state: state, objective: objective)
    assert_equal 'phase dialogue', primed.hold_reason(state: state(dialog_state: 130), objective: objective)
    assert_equal 'hp dropped', primed.hold_reason(state: state(hp: 20), objective: objective)
    assert_equal 'objective changed', primed.hold_reason(state: state, objective: nil)
    assert_equal 'objective changed', primed.hold_reason(state: state, objective: objective(id: 'obj-2'))
    %w[reach_place reach_cell dialogue_closed].each do |kind|
      assert_equal "objective #{kind}", primed.hold_reason(state: state, objective: objective(kind)), kind
    end
    %w[new_place leave_place new_text].each { |kind| assert_nil primed.hold_reason(state: state, objective: objective(kind)), kind }
  end

  def test_one_heart_or_less_holds_the_autopilot_and_a_creature_near_does_not
    [[8, 'low health'], [4, 'low health'], [9, nil]].each do |hp, reason|
      low = primed(stop: :known_place)
      low.model_called(state: state(hp:), objective: objective)
      low.acted(skill: 'explore', outcome: { stopped_by: :known_place })
      hold = low.hold_reason(state: state(hp:), objective: objective)
      reason ? assert_equal(reason, hold, "hp #{hp}") : assert_nil(hold, "hp #{hp}")
    end
    assert_nil primed.hold_reason(state: state, objective: objective, danger: true)
  end

  def test_a_model_call_resets_the_last_stop
    pilot = primed
    pilot.model_called(state: state, objective: objective)
    assert_nil pilot.next_choice(state: state, objective: objective)
  end

  def test_the_chain_is_capped_then_a_model_call_starts_a_new_chain
    pilot = primed(chain_limit: 3)
    3.times do |i|
      assert pilot.next_choice(state: state(frame: 200 + i), objective: objective)
      pilot.acted(skill: 'explore', outcome: { stopped_by: :budget })
    end
    assert_equal 3, pilot.chain
    assert_equal 'chain cap', pilot.hold_reason(state: state(frame: 300), objective: objective)
    pilot.model_called(state: state(frame: 300), objective: objective)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :budget })
    assert pilot.next_choice(state: state(frame: 400), objective: objective)
    assert_equal 1, pilot.chain
  end

  def test_the_chain_is_capped_in_frames_since_the_model_call
    pilot = primed
    assert_nil pilot.hold_reason(state: state(frame: 100 + Koholint::Autopilot::CHAIN_FRAMES - 1), objective: objective)
    assert_equal 'frame cap', pilot.hold_reason(state: state(frame: 100 + Koholint::Autopilot::CHAIN_FRAMES), objective: objective)
  end

  def test_a_target_is_followed_right_after_the_model_call_then_only_by_explores
    target = objective('reach_place').merge(target: { kind: 'place', place: [1, 0] })
    pilot = Koholint::Autopilot.new
    pilot.model_called(state: state, objective: target)
    follow = { skill: 'explore', params: {} }
    assert_nil pilot.next_choice(state: state, objective: target)
    result = pilot.next_choice(state: state, objective: target, follow:)
    assert_equal follow, result[:choice]
    assert_match(/follow the objective target/, result[:justification])
    pilot.acted(skill: 'explore', outcome: { stopped_by: :budget })
    assert pilot.next_choice(state: state, objective: target, follow:)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :blocked })
    assert_equal 'last stop blocked', pilot.hold_reason(state: state, objective: target, follow:)
    talk = { skill: 'talk_to', params: { row: 2, col: 3 } }
    person = objective('new_text').merge(target: { kind: 'person', place: [163, 16] })
    pilot.model_called(state: state, objective: person)
    assert_equal talk, pilot.next_choice(state: state, objective: person, follow: talk)[:choice]
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :done })
    assert_equal 'last stop not an explore', pilot.hold_reason(state: state, objective: person, follow: talk)
    pilot.model_called(state: state, objective: target)
    pilot.acted(skill: 'walk', outcome: { stopped_by: :done })
    assert_equal 'last stop not an explore', pilot.hold_reason(state: state, objective: target, follow:)
  end

  def test_the_next_objective_is_picked_after_a_chain_arrives_and_achieves_the_objective
    pilot = primed
    done = { id: 'obj-1', outcome: :achieved }
    assert_nil pilot.objective_hold(state: state(frame: 400), last: done)
    assert_equal 'last objective not achieved by the chain', pilot.objective_hold(state: state, last: done.merge(outcome: :abandoned))
    assert_equal 'last objective not achieved by the chain', pilot.objective_hold(state: state, last: done.merge(id: 'obj-0'))
    assert_equal 'last stop budget', primed(stop: :budget).objective_hold(state: state, last: done)
    assert_equal 'new lead or goal', primed(news: true).objective_hold(state: state, last: done)
    assert_equal 'frame cap', pilot.objective_hold(state: state(frame: 100 + Koholint::Autopilot::CHAIN_FRAMES), last: done)
    pilot.adopt({ id: 'obj-2' })
    assert pilot.next_choice(state: state(frame: 400), objective: objective(id: 'obj-2'))
  end

  def foe(row, col, type: 9, kind: 'enemy', slot: 3) = { slot:, type:, kind:, cell: [row, col] }

  def fought(stop: :done, type: 9, hp: 24)
    pilot = Koholint::Autopilot.new
    pilot.model_called(state: state(hp:), objective: objective)
    pilot.acted(skill: 'attack', outcome: { stopped_by: stop, target: { slot: 2, type:, cell: [3, 4] }, from: { room: 163, map: 16 } })
    pilot
  end

  # Link stands at (5,4) in these states (x 68, y 60 is cell [3, 4]).
  def test_after_a_kill_the_nearest_enemy_within_two_cells_is_struck_without_a_call
    result = fought.fight_choice(state: state(frame: 200), entities: [foe(5, 4, slot: 5), foe(4, 5, slot: 4), foe(1, 4, slot: 6)])
    assert_equal({ skill: 'attack', params: { row: 4, col: 5 } }, result[:choice])
    assert_equal [0.0, 'delegated', true], result.values_at(:cost_usd, :agent, :autopilot)
    assert_nil fought(stop: :target_gone).fight_choice(state: state(frame: 200), entities: [foe(6, 4)])
  end

  def test_an_unidentified_type_is_fought_only_once_struck_here_and_never_a_person_or_a_measured_creature
    assert_equal({ row: 3, col: 5 }, fought(type: 28).fight_choice(state: state(frame: 200), entities: [foe(3, 5, type: 28, kind: 'unknown')])[:choice][:params])
    assert_nil fought(type: 27).fight_choice(state: state(frame: 200), entities: [foe(3, 5, type: 28, kind: 'unknown')])
    assert_nil fought.fight_choice(state: state(frame: 200), entities: [foe(3, 5, type: 62, kind: 'npc'), foe(3, 3, type: 205, kind: 'creature')])
  end

  def test_the_slot_just_struck_is_never_the_next_target_while_it_dies
    corpse = foe(3, 5, slot: 2)
    assert_nil fought.fight_choice(state: state(frame: 200), entities: [corpse])
    assert_equal({ row: 4, col: 6 }, fought.fight_choice(state: state(frame: 200), entities: [corpse, foe(4, 6, slot: 7)])[:choice][:params])
  end

  def threat(x, y, type: 27) = { slot: 3, type:, kind: 'enemy', x:, y:, contact: 11, cell: [((y - 8) / 16), x / 16] }

  def test_at_one_heart_with_an_enemy_in_touch_the_pilot_steps_away_before_the_model
    pilot = primed
    result = pilot.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(70, 64)])
    assert_equal({ skill: 'walk', params: { direction: 'up', cells: 1 } }, result[:choice])
    assert_equal [0.0, 'delegated', true], result.values_at(:cost_usd, :agent, :autopilot)
    assert_equal 'left', pilot.disengage_choice(state: state(frame: 210, hp: 4, x: 68, y: 60), entities: [threat(74, 60)])[:choice][:params][:direction]
  end

  def test_a_disengage_step_into_a_wall_is_not_tried_again_before_the_next_model_call
    pilot = primed
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    assert_equal 'up', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    pilot.acted(skill: 'walk', outcome: { stopped_by: :blocked, params: { direction: :up, cells: 1 } })
    assert_equal 'left', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    pilot.model_called(state: link, objective: objective)
    assert_equal 'up', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
  end

  class HoledGrid
    def initialize(holes) = @holes = holes
    def hole?(row, col) = @holes.include?([row, col])
    def hole_margin = @holes.flat_map { |row, col| [[row - 1, col], [row + 1, col], [row, col - 1], [row, col + 1]] } - @holes
  end

  def test_a_disengage_step_never_lands_on_a_hole_or_beside_one
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    assert_equal 'left', primed.disengage_choice(state: link, entities: [threat(70, 64)], grid: HoledGrid.new([[1, 4]]))[:choice][:params][:direction]
    assert_equal 'left', primed.disengage_choice(state: link, entities: [threat(70, 64)], grid: HoledGrid.new([[2, 4]]))[:choice][:params][:direction]
  end

  def test_a_walk_refused_at_once_for_danger_counts_as_walled
    pilot = primed
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    pilot.acted(skill: 'walk', outcome: { stopped_by: :danger, frames: 0, params: { direction: :up, cells: 1 } })
    assert_equal 'left', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    other = primed
    other.acted(skill: 'walk', outcome: { stopped_by: :danger, frames: 9, params: { direction: :up, cells: 1 } })
    assert_equal 'up', other.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
  end

  def test_no_disengage_above_one_heart_away_from_enemies_boxed_in_or_past_its_limit
    assert_nil primed.disengage_choice(state: state(frame: 200, hp: 9, x: 68, y: 60), entities: [threat(70, 64)])
    assert_nil primed.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(68, 100)])
    assert_nil primed.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(68, 64, type: 28).merge(kind: 'creature')])
    boxed = [threat(76, 60), threat(60, 60), threat(68, 52), threat(68, 68)]
    assert_nil primed.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: boxed)
    pilot = primed
    Koholint::Autopilot::DISENGAGE_LIMIT.times { refute_nil pilot.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(70, 64)]) }
    assert_nil pilot.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(70, 64)])
  end

  def test_the_types_struck_are_forgotten_once_link_leaves_the_place
    pilot = fought(type: 28)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place, from: { room: 163, map: 16 }, to: { room: 164, map: 16 } })
    pilot.acted(skill: 'attack', outcome: { stopped_by: :done, target: { slot: 2, type: 9, cell: [3, 4] }, from: { room: 163, map: 16 }, to: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [foe(3, 5, type: 28, kind: 'unknown', slot: 6)])
  end

  def test_the_fight_goes_back_to_the_model_on_another_stop_low_health_or_its_caps
    near = [foe(3, 5)]
    %i[damage no_path no_kill out_of_reach].each { |stop| assert_nil fought(stop:).fight_choice(state: state(frame: 200), entities: near), stop }
    refute_nil fought.fight_choice(state: state(frame: 200, hp: 16), entities: near)
    assert_nil fought.fight_choice(state: state(frame: 200, hp: 15), entities: near)
    assert_nil fought(hp: 40).fight_choice(state: state(frame: 200, hp: 31, max_hp: 40), entities: near)
    assert_nil fought.fight_choice(state: state(frame: 100 + Koholint::Autopilot::FIGHT_FRAMES), entities: near)
    pilot = fought
    Koholint::Autopilot::FIGHT_LIMIT.times do |i|
      refute_nil pilot.fight_choice(state: state(frame: 200 + i), entities: near)
      pilot.acted(skill: 'attack', outcome: { stopped_by: :done, target: { slot: 9, type: 9, cell: [3, 6] }, from: { room: 163, map: 16 } })
    end
    assert_nil pilot.fight_choice(state: state(frame: 300), entities: near)
  end
end
