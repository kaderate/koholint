require_relative 'test_helper'
require 'koholint/autopilot'
require 'koholint/game_state'

class AutopilotTest < Minitest::Test
  FLOOR = Struct.new(:none) do
    def floor?(*) = true
    def static_sprite(*) = 'heart'
  end.new.freeze

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

  def test_a_still_entity_whose_try_gave_nothing_is_walked_onto_once_per_visit
    pilot = primed
    never = ->(_) { false }
    one = [{ kind: :unknown, type: 58, cell: [3, 2], x: 40, y: 64 }]
    pilot.try_choice(state: state(frame: 400), objective:, entities: one, tried: never)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :frame_cap, target_type: 58 })
    result = pilot.touch_choice(state: state(frame: 500), objective:, entities: one)
    assert_equal({ skill: 'touch', params: { row: 3, col: 2, type: 58 } }, result[:choice])
    assert_equal [0.0, true], result.values_at(:cost_usd, :autopilot)
    pilot.acted(skill: 'touch', outcome: { stopped_by: :done })
    assert_nil pilot.touch_choice(state: state(frame: 600), objective:, entities: one), 'once per visit'
    assert_equal({ skill: 'explore', params: {} }, pilot.next_choice(state: state(frame: 600), objective:)[:choice], 'a touch is a benign stop')
  end

  def test_only_a_try_that_gave_nothing_and_left_the_thing_where_it_was_leads_to_a_touch
    never = ->(_) { false }
    at = { kind: :unknown, type: 58, cell: [3, 2], x: 40, y: 64 }
    { done: [at], damage: [at], no_response: [at.merge(cell: [5, 5])], no_path: [at.merge(kind: :enemy)], blocked: [at.merge(moves: true)] }.each do |stop, now|
      pilot = primed
      pilot.try_choice(state: state(frame: 400), objective:, entities: [at], tried: never)
      pilot.acted(skill: 'talk_to', outcome: { stopped_by: stop })
      assert_nil pilot.touch_choice(state: state(frame: 500), objective:, entities: now), stop.to_s
    end
    pilot = primed
    pilot.try_choice(state: state(frame: 400), objective:, entities: [at], tried: never)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response })
    assert_nil pilot.touch_choice(state: state(frame: 500, room_id: 164), objective:, entities: [at]), 'leaving forgets it'
    assert_nil pilot.touch_choice(state: state(frame: 600), objective:, entities: [at]), 'and coming back does not bring it back'
  end

  def test_touches_and_tries_share_the_six_things_a_visit_allows
    pilot = primed
    never = ->(_) { false }
    many = (90..99).map { |type| { kind: :unknown, type:, cell: [type % 8, 1] } }
    count = 0
    10.times do |i|
      frame = 400 + (i * 10)
      choice = pilot.try_choice(state: state(frame:), objective:, entities: many, tried: never)
      count += 1 if choice
      pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response, target_type: 90 + i }) if choice
      touch = pilot.touch_choice(state: state(frame: frame + 1), objective:, entities: many)
      count += 1 if touch
      pilot.acted(skill: 'touch', outcome: { stopped_by: :no_response }) if touch
    end
    assert_equal Koholint::Autopilot::TRY_LIMIT, count
  end

  def test_a_try_left_untouched_is_not_picked_up_once_the_visit_is_spent
    pilot = primed
    never = ->(_) { false }
    at = { kind: :unknown, type: 58, cell: [3, 2] }
    pilot.try_choice(state: state(frame: 400), objective:, entities: [at], tried: never)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response, target_type: 58 })
    assert_nil pilot.touch_choice(state: state(frame: 410), objective:, entities: []), 'it is off screen'
    pilot.acted(skill: 'explore', outcome: { stopped_by: :untried_object, untried_objects: (1..5).map { |col| { row: 6, col: } } })
    (1..5).each do |i|
      pilot.try_choice(state: state(frame: 500 + i), objective:, entities: [], tried: never)
      pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response })
    end
    assert_nil pilot.touch_choice(state: state(frame: 600), objective:, entities: [at]), 'six tries are spent'
  end

  def test_a_try_on_an_object_cell_is_touched_once_the_result_names_the_type_standing_there
    pilot = primed
    never = ->(_) { false }
    at = { kind: :unknown, type: 58, cell: [3, 2], x: 40, y: 64 }
    pilot.acted(skill: 'explore', outcome: { stopped_by: :untried_object, untried_objects: [{ row: 3, col: 2 }] })
    assert_equal({ skill: 'talk_to', params: { row: 3, col: 2 } }, pilot.try_choice(state: state(frame: 400), objective:, entities: [], tried: never)[:choice])
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :frame_cap, target_type: 58 })
    assert_equal({ skill: 'touch', params: { row: 3, col: 2, type: 58 } }, pilot.touch_choice(state: state(frame: 500), objective:, entities: [at])[:choice])
  end

  def test_no_try_aims_at_an_object_cell_a_catalogued_enemy_stands_on
    pilot = primed
    never = ->(_) { false }
    pilot.acted(skill: 'explore', outcome: { stopped_by: :untried_object, untried_objects: [{ row: 5, col: 2 }] })
    enemy = [{ kind: :enemy, type: 25, cell: [5, 2] }]
    assert_nil pilot.try_choice(state: state(frame: 400), objective:, entities: enemy, tried: never)
    assert_equal({ skill: 'talk_to', params: { row: 5, col: 2 } }, pilot.try_choice(state: state(frame: 500), objective:, entities: [], tried: never)[:choice],
                 'the object is tried once the enemy is gone')
  end

  def test_tries_are_bounded_per_visit_by_the_autopilot_itself_and_leave_the_chain_alone
    pilot = primed
    never = ->(_) { false }
    one = [{ kind: :unknown, type: 79, cell: [1, 1] }]
    refute_nil pilot.try_choice(state: state(frame: 400), objective:, entities: one, tried: never)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_path })
    assert_nil pilot.try_choice(state: state(frame: 410), objective:, entities: one, tried: never), 'the aimed type is remembered without the result'
    many = (90..99).map { |type| { kind: :unknown, type:, cell: [type % 8, 1] } }
    tries = (1..10).map do |i|
      choice = pilot.try_choice(state: state(frame: 500 + i), objective:, entities: many, tried: never)
      pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response }) if choice
      choice
    end
    assert_equal Koholint::Autopilot::TRY_LIMIT - 1, tries.compact.size
    assert_equal 0, pilot.chain
    refute_nil pilot.try_choice(state: state(frame: 700, room_id: 164), objective:, entities: many, tried: never), 'a new visit starts a new count'
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
    pilot.acted(skill: 'goto', outcome: { stopped_by: :done })
    assert_nil pilot.next_choice(state: state, objective: objective)
    fresh = Koholint::Autopilot.new
    fresh.acted(skill: 'explore', outcome: { stopped_by: :new_place })
    assert_equal 'no model call yet', fresh.hold_reason(state: state, objective: objective)
  end

  def test_a_dialogue_that_ended_without_news_continues_and_one_with_news_holds
    pilot = primed
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :done })
    pilot.acted(skill: 'advance_dialogue', outcome: { stopped_by: :done })
    pilot.acted(skill: 'wait', outcome: { stopped_by: :done })
    assert_equal({ skill: 'explore', params: {} }, pilot.next_choice(state: state, objective: objective)[:choice])
    pilot = primed
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_response })
    assert_nil pilot.hold_reason(state: state, objective: objective)
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :no_path })
    assert_equal 'last stop not an explore', pilot.hold_reason(state: state, objective: objective)
    pilot = primed
    pilot.acted(skill: 'advance_dialogue', outcome: { stopped_by: :done })
    assert_equal 'last stop not an explore', pilot.hold_reason(state: state, objective: objective), 'a dialogue the model did not ask for'
    person = objective('new_text').merge(target: { kind: 'person', place: [1, 0] })
    news = Koholint::Autopilot.new
    news.model_called(state: state, objective: person, news: true)
    news.acted(skill: 'talk_to', outcome: { stopped_by: :done })
    news.acted(skill: 'advance_dialogue', outcome: { stopped_by: :done })
    assert_equal 'new lead or goal', news.hold_reason(state: state, objective: person)
  end

  def test_a_try_stays_benign_whatever_it_met_and_through_its_dialogue
    entities = [{ kind: :unknown, type: 79, cell: [1, 1] }]
    %i[done no_response no_path frame_cap].each do |stop|
      pilot = primed
      pilot.try_choice(state: state(frame: 400), objective:, entities:, tried: ->(_) { false })
      pilot.acted(skill: 'talk_to', outcome: { stopped_by: stop })
      pilot.acted(skill: 'advance_dialogue', outcome: { stopped_by: :done })
      pilot.acted(skill: 'wait', outcome: { stopped_by: :done })
      assert_nil pilot.hold_reason(state: state(frame: 500), objective:), stop
    end
  end

  def test_a_try_does_not_fire_under_a_targeted_objective_after_an_arrival
    person = objective('new_text').merge(target: { kind: 'person', place: [146, 0] })
    pilot = Koholint::Autopilot.new
    pilot.model_called(state: state, objective: person)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place })
    assert_nil pilot.hold_reason(state: state, objective: person), 'the arrival itself continues'
    assert_nil pilot.try_choice(state: state(frame: 400), objective: person, entities: [{ kind: :unknown, type: 79, cell: [1, 1] }], tried: ->(_) { false })
  end

  def test_an_arrival_continues_when_the_objective_target_cannot_be_followed_from_here
    person = objective('new_text').merge(target: { kind: 'person', place: [146, 0] })
    pilot = Koholint::Autopilot.new
    pilot.model_called(state: state, objective: person)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place })
    assert_nil pilot.hold_reason(state: state, objective: person)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :untried_object })
    assert_equal 'no way to follow the target', pilot.hold_reason(state: state, objective: person)
  end

  def test_a_goto_that_ends_below_a_door_steps_through_it_once
    pilot = primed
    below = state(x: 88, y: 92)
    row, col = below.cell
    door = [row - 1, col]
    assert_nil pilot.door_choice(state: below, doors: [door]), 'no goto yet'
    pilot.acted(skill: 'goto', outcome: { stopped_by: :done })
    pilot.acted(skill: 'wait', outcome: { stopped_by: :done })
    assert_nil pilot.door_choice(state: below, doors: [[row - 1, col + 1]])
    result = pilot.door_choice(state: below, doors: [door])
    assert_equal [{ skill: 'walk', params: { direction: 'up', cells: 2 } }, 0.0, true], result.values_at(:choice, :cost_usd, :autopilot)
    assert_nil pilot.door_choice(state: below, doors: [door]), 'once per goto'
    pilot.acted(skill: 'goto', outcome: { stopped_by: :no_path })
    assert_nil pilot.door_choice(state: below, doors: [door])
    pilot.acted(skill: 'goto', outcome: { stopped_by: :done })
    assert_nil pilot.door_choice(state: state(x: 88, y: 92, hp: 20), doors: [door]), 'a model trigger holds it'
    news = primed(news: true)
    news.acted(skill: 'goto', outcome: { stopped_by: :done })
    assert_nil news.door_choice(state: below, doors: [door])
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
    assert_equal 'target followed', pilot.hold_reason(state: state, objective: person, follow: talk)
    pilot.model_called(state: state, objective: target)
    pilot.acted(skill: 'walk', outcome: { stopped_by: :done })
    assert_equal 'last stop not an explore', pilot.hold_reason(state: state, objective: target, follow:)
  end

  # Run 20261125-173713-76f7: the model's explore reached 83/0 for a thing to try, and the talk the target called for was held as already followed.
  def test_a_target_reached_by_the_models_explore_is_talked_to_then_touched_once_each
    talk = { skill: 'talk_to', params: { row: 3, col: 5 } }
    touch = { skill: 'touch', params: { row: 3, col: 5, type: 132 } }
    thing = objective('reach_place').merge(target: { kind: 'person', place: [83, 0], type: 132, try: true })
    pilot = Koholint::Autopilot.new
    pilot.model_called(state: state, objective: thing)
    pilot.acted(skill: 'explore', outcome: { stopped_by: :known_place })
    assert_equal talk, pilot.next_choice(state: state, objective: thing, follow: talk)[:choice]
    pilot.acted(skill: 'talk_to', outcome: { stopped_by: :frame_cap })
    assert_equal touch, pilot.next_choice(state: state, objective: thing, follow: touch)[:choice]
    pilot.acted(skill: 'touch', outcome: { stopped_by: :done })
    assert pilot.hold_reason(state: state, objective: thing, follow: touch), 'one touch'
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

  def test_below_full_health_the_nearest_heart_outside_contact_zones_is_walked_to_once_per_slot
    pilot = primed
    near = { slot: 5, kind: :creature, type: 45, x: 40, y: 56, cell: [3, 2], heals: 8 }
    far = { slot: 6, kind: :creature, type: 45, x: 136, y: 120, cell: [7, 8], heals: 8 }
    assert_nil pilot.heart_choice(state: state(frame: 400), entities: [near, far], grid: FLOOR), 'full health'
    result = pilot.heart_choice(state: state(frame: 400, hp: 16), entities: [near, far], grid: FLOOR)
    assert_equal({ skill: 'touch', params: { row: 3, col: 2, type: 45, safe: true, slot: 5 } }, result[:choice])
    assert_equal [0.0, true], result.values_at(:cost_usd, :autopilot)
    assert_equal({ row: 7, col: 8, type: 45, safe: true, slot: 6 }, pilot.heart_choice(state: state(frame: 500, hp: 16), entities: [near, far], grid: FLOOR)[:choice][:params])
    assert_nil pilot.heart_choice(state: state(frame: 600, hp: 16), entities: [near, far], grid: FLOOR), 'each slot once'
    assert_equal({ row: 3, col: 2, type: 45, safe: true, slot: 5 }, pilot.heart_choice(state: state(frame: 700, hp: 16, room_id: 164), entities: [near], grid: FLOOR)[:choice][:params], 'a new visit')
  end

  def test_at_one_heart_a_heart_in_the_ring_the_planner_adds_to_every_zone_is_not_aimed_at
    enemy = { slot: 1, kind: :enemy, type: 9, x: 40, y: 94, cell: [5, 2] }
    heart = { slot: 5, kind: :creature, type: 45, x: 40, y: 56, cell: [3, 2], heals: 8 }
    assert primed.heart_choice(state: state(frame: 400, hp: 16), entities: [enemy, heart], grid: FLOOR)
    assert_nil primed.heart_choice(state: state(frame: 400, hp: 8), entities: [enemy, heart], grid: FLOOR)
  end

  def test_a_visit_at_full_health_elsewhere_still_starts_a_new_visit
    pilot = primed
    heart = { slot: 5, kind: :creature, type: 45, x: 40, y: 56, cell: [3, 2], heals: 8 }
    assert pilot.heart_choice(state: state(frame: 400, hp: 16), entities: [heart], grid: FLOOR)
    assert_nil pilot.heart_choice(state: state(frame: 500, room_id: 164), entities: [], grid: FLOOR)
    assert pilot.heart_choice(state: state(frame: 600, hp: 16), entities: [heart], grid: FLOOR), 'back in the first place after a full-health visit elsewhere'
  end

  def test_no_heart_is_aimed_at_inside_a_contact_zone_past_the_limit_or_without_a_verified_heal
    enemy = { slot: 1, kind: :enemy, type: 9, x: 40, y: 72, cell: [4, 2] }
    heart = { slot: 5, kind: :creature, type: 45, x: 40, y: 56, cell: [3, 2], heals: 8 }
    assert_nil primed.heart_choice(state: state(frame: 400, hp: 16), entities: [enemy, heart], grid: FLOOR), 'in reach of an enemy'
    assert_nil primed.heart_choice(state: state(frame: 400, hp: 16), entities: [heart.except(:heals)], grid: FLOOR), 'no heal'
    assert_nil primed.heart_choice(state: state(frame: 400, hp: 16), entities: [heart], grid: Struct.new(:none) { def static_sprite(*) = nil }.new), 'hidden under a pot or a bush, with no sprite'
    assert_nil primed.heart_choice(state: state(frame: 400, hp: 16), entities: [heart], grid: Struct.new(:none) { def static_sprite(*) = 'pot'
                                                                                                                 def floor?(*) = false }.new), 'a sprite on a tile never walked'
    assert_nil Koholint::Autopilot.new.heart_choice(state: state(frame: 400, hp: 16), entities: [heart], grid: FLOOR), 'no model call yet'
    pilot = primed
    hearts = (5..7).map { |slot| heart.merge(slot:) }
    2.times { assert pilot.heart_choice(state: state(frame: 400, hp: 16), entities: hearts, grid: FLOOR) }
    assert_nil pilot.heart_choice(state: state(frame: 500, hp: 16), entities: hearts, grid: FLOOR), 'two per visit'
  end

  def test_at_one_heart_with_an_enemy_in_touch_the_pilot_steps_away_before_the_model
    pilot = primed
    result = pilot.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(70, 64)])
    assert_equal({ skill: 'walk', params: { direction: 'up', cells: 1 } }, result[:choice])
    assert_equal [0.0, 'delegated', true], result.values_at(:cost_usd, :agent, :autopilot)
    assert_equal 'left', pilot.disengage_choice(state: state(frame: 210, hp: 4, x: 68, y: 60), entities: [threat(74, 60)])[:choice][:params][:direction]
  end

  # Run f741, 172/10: up was walled, so the step went right, beside the type 155 below, and took a hit (8 -> 4 hp).
  def test_a_disengage_step_that_takes_link_no_farther_from_the_enemy_is_not_taken
    pilot = primed
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    pilot.acted(skill: 'walk', outcome: { stopped_by: :blocked, params: { direction: :up, cells: 1 }, from: { room: 163, map: 16, row: 3, col: 4 } })
    assert_nil pilot.disengage_choice(state: link, entities: [threat(66, 84, type: 155)])
  end

  def test_a_disengage_step_never_lands_in_or_beside_another_hostiles_contact_zone
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    assert_equal 'up', primed.disengage_choice(state: link, entities: [threat(68, 72)])[:choice][:params][:direction]
    step = primed.disengage_choice(state: link, entities: [threat(68, 72), threat(68, 20).merge(slot: 4)])[:choice][:params][:direction]
    assert_includes %w[left right], step
  end

  # Run 5e81, 172/10: up was walled at (2,4), a model call in between forgot it, and the second walk up took a hit (8 -> 4 hp).
  def test_a_disengage_step_into_a_wall_is_not_tried_again_from_that_cell_even_after_a_model_call
    pilot = primed
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    assert_equal 'up', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    pilot.acted(skill: 'walk', outcome: { stopped_by: :blocked, params: { direction: :up, cells: 1 }, from: { room: 163, map: 16, row: 3, col: 4 } })
    assert_equal 'left', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    pilot.model_called(state: link, objective: objective)
    assert_equal 'left', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    pilot.acted(skill: 'walk', outcome: { stopped_by: :blocked, params: { direction: :right, cells: 3 }, from: { room: 163, map: 16, row: 3, col: 2 },
                                          blocked_at: { row: 3, col: 4, direction: :right } })
    assert_equal 'down', pilot.disengage_choice(state: link, entities: [threat(60, 64)])[:choice][:params][:direction], 'a longer walk is barred where it stopped'
    moved = state(frame: 300, hp: 8, x: 52, y: 60)
    assert_equal 'up', pilot.disengage_choice(state: moved, entities: [threat(54, 64)])[:choice][:params][:direction], 'from another cell up is tried'
  end

  def test_a_disengage_step_the_grid_shows_blocked_is_not_taken
    grid = Struct.new(:none) { def passable(row, col, direction) = [row, col, direction] == [2, 4, :up] ? :no : :yes }.new
    assert_equal 'left', primed.disengage_choice(state: state(frame: 200, hp: 8, x: 68, y: 60), entities: [threat(70, 64)], grid:)[:choice][:params][:direction]
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

  def test_a_danger_stop_or_a_blocked_walk_without_its_cell_is_not_counted_as_walled
    link = state(frame: 200, hp: 8, x: 68, y: 60)
    here = { room: 163, map: 16, row: 3, col: 4 }
    pilot = primed
    pilot.acted(skill: 'walk', outcome: { stopped_by: :danger, frames: 0, params: { direction: :up, cells: 1 }, from: here })
    assert_equal 'up', pilot.disengage_choice(state: link, entities: [threat(70, 64)])[:choice][:params][:direction]
    other = primed
    other.acted(skill: 'walk', outcome: { stopped_by: :blocked, params: { direction: :up, cells: 1 } })
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

  def sighted(dx, dy, slot: 4, hits: 1, verified: false) = { slot:, type: 25, kind: 'enemy', sword_hits: hits, sword_verified: verified, cell: [3 + (dy / 16), 4 + (dx / 16)], x: 68 + dx, y: 60 + dy }

  def test_above_one_heart_a_one_strike_enemy_within_two_cells_is_fought_on_sight
    result = primed.fight_choice(state: state(frame: 200), entities: [sighted(32, 0, slot: 5), sighted(16, 0)])
    assert_equal({ skill: 'attack', params: { row: 3, col: 5 } }, result[:choice])
    assert_match(/fight type 25 at \(3,5\)/, result[:justification])
    assert_nil primed.fight_choice(state: state(frame: 200), entities: [sighted(33, 0)])
    assert_nil primed.fight_choice(state: state(frame: 200), entities: [sighted(16, 0, hits: 2), sighted(0, 16, hits: nil)])
    assert_nil primed.fight_choice(state: state(frame: 200, hp: 4), entities: [sighted(16, 0)])
    assert_nil primed.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)], objects: [{ kind: 'crumbling', cell: [3, 4] }])
    refute_nil primed.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)], objects: [{ kind: 'crumbling', cell: [3, 5] }])
  end

  # Run 5442, 66/0: two type 27s (two hits, verified) cost Link 16 hp beside him while the fight hook only took one-strike enemies.
  def test_an_enemy_two_verified_strikes_kill_is_fought_on_sight
    result = primed.fight_choice(state: state(frame: 200), entities: [sighted(16, 0, hits: 2, verified: true)])
    assert_equal({ skill: 'attack', params: { row: 3, col: 5 } }, result[:choice])
    assert_match(/a 2-strike kill/, result[:justification])
    assert_nil primed.fight_choice(state: state(frame: 200), entities: [sighted(16, 0, hits: 3, verified: true)])
  end

  def test_an_enemy_an_attack_missed_and_a_place_where_one_cost_health_are_not_fought_on_sight_again
    pilot = primed
    pilot.acted(skill: 'attack', outcome: { stopped_by: :hole, target: { slot: 4, type: 25, cell: [3, 5] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)])
    assert_equal({ row: 4, col: 4 }, pilot.fight_choice(state: state(frame: 200), entities: [sighted(16, 0), sighted(0, 16, slot: 6)])[:choice][:params])
    pilot.acted(skill: 'attack', outcome: { stopped_by: :damage, target: { slot: 6, type: 25, cell: [4, 4] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(0, 16, slot: 7)])
  end

  # Run 5e81, 172/10: the attack on the second type 155 ended out_of_reach, and the explore after it walked into that 155 at 12 hp.
  def test_an_enemy_an_attack_could_only_not_reach_is_fought_again_once_within_a_cell
    pilot = primed
    pilot.acted(skill: 'attack', outcome: { stopped_by: :out_of_reach, target: { slot: 4, type: 155, cell: [3, 6] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(32, 0)]), 'still two cells away'
    assert_equal({ row: 3, col: 5 }, pilot.fight_choice(state: state(frame: 210), entities: [sighted(16, 0)])[:choice][:params])
  end

  def test_an_enemy_only_out_of_reach_is_fought_again_at_most_twice_a_visit
    pilot = primed
    miss = { stopped_by: :out_of_reach, target: { slot: 4, type: 155, cell: [3, 5] }, from: { room: 163, map: 16 } }
    2.times do
      pilot.acted(skill: 'attack', outcome: miss)
      refute_nil pilot.fight_choice(state: state(frame: 210), entities: [sighted(16, 0)])
    end
    pilot.acted(skill: 'attack', outcome: miss)
    assert_nil pilot.fight_choice(state: state(frame: 220), entities: [sighted(16, 0)])
  end

  def test_a_fight_on_sight_never_starts_the_chain_of_fights_after_a_kill
    pilot = primed
    refute_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)])
    pilot.acted(skill: 'attack', outcome: { stopped_by: :done, target: { slot: 4, type: 25, cell: [3, 5] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [foe(4, 5, slot: 6)])
  end

  def test_the_slot_just_struck_is_not_fought_on_sight_while_it_dies
    pilot = primed
    pilot.acted(skill: 'attack', outcome: { stopped_by: :done, target: { slot: 4, type: 25, cell: [3, 5] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)])
  end

  def test_a_place_where_a_fight_cost_health_stays_without_fights_for_the_visit_across_model_calls
    pilot = primed
    pilot.acted(skill: 'attack', outcome: { stopped_by: :damage, target: { slot: 6, type: 25, cell: [4, 4] }, from: { room: 163, map: 16 } })
    pilot.model_called(state: state(frame: 150), objective: objective)
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(16, 0)])
    assert_nil pilot.fight_choice(state: state(frame: 210, room_id: 164), entities: [])
    refute_nil pilot.fight_choice(state: state(frame: 220), entities: [sighted(16, 0)])
  end

  # Gate run 38bd, 66/0: a struck type 27 charged into Link during the swing (24 to 20 hp) and no fight started there again, so the way to the right exit stayed closed.
  def test_above_half_health_one_damage_stop_keeps_fights_with_verified_enemies_until_a_second_or_half_health
    pilot = primed
    hurt = { stopped_by: :damage, target: { slot: 4, type: 27, cell: [3, 5] }, from: { room: 163, map: 16 } }
    pilot.acted(skill: 'attack', outcome: hurt)
    assert_equal({ row: 3, col: 5 }, pilot.fight_choice(state: state(frame: 200, hp: 20), entities: [sighted(16, 0, hits: 2, verified: true)])[:choice][:params])
    assert_nil pilot.fight_choice(state: state(frame: 200, hp: 20), entities: [sighted(16, 0, slot: 6)]), 'unverified'
    assert_nil pilot.fight_choice(state: state(frame: 200, hp: 12), entities: [sighted(16, 0, hits: 2, verified: true)]), 'half health'
    pilot.acted(skill: 'attack', outcome: hurt)
    assert_nil pilot.fight_choice(state: state(frame: 200, hp: 16), entities: [sighted(16, 0, hits: 2, verified: true)]), 'second damage'
  end

  def test_an_enemy_an_attack_could_not_reach_is_not_fought_on_sight_again_there_beyond_a_cell
    pilot = primed
    pilot.acted(skill: 'attack', outcome: { stopped_by: :out_of_reach, target: { slot: 4, type: 25, cell: [3, 5] }, from: { room: 163, map: 16 } })
    pilot.acted(skill: 'attack', outcome: { stopped_by: :no_target, target: { slot: 7, type: 25, cell: [1, 1] }, from: { room: 163, map: 16 } })
    assert_nil pilot.fight_choice(state: state(frame: 200), entities: [sighted(32, 0)])
  end
end
