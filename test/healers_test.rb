require_relative 'test_helper'
require 'koholint/healers'

class HealersTest < Minitest::Test
  def decision(frame, room, hp, dialog = 0) = { 'type' => 'decision', 'frame' => frame, 'input' => { 'room_id' => room, 'map_id' => 0, 'hp' => hp, 'dialog_state' => dialog } }

  def walk(frame) = { 'type' => 'action', 'frame' => frame, 'skill' => 'explore', 'result' => { 'moved_cells' => 2 } }

  # Run abbe: a talk in 83/0 at 88340 took Link from 16 to 24 hp; in 81/0 a heart he walked onto after the owl spoke gave 4 hp at 74615.
  def test_health_rising_after_a_talk_before_a_cell_is_walked_makes_a_healer_and_a_heart_walked_onto_does_not
    events = [decision(1, 81, 20, 1), decision(2, 81, 20), walk(3), decision(4, 81, 24),
              decision(5, 83, 16), decision(6, 83, 16, 1), decision(7, 83, 16), decision(8, 83, 24)]
    assert_equal [[83, 0]], Koholint::Healers.from_events(events).places
  end

  def heal(frame) = { 'type' => 'objective', 'frame' => frame, 'status' => 'started', 'target' => { 'kind' => 'place', 'place' => [83, 0], 'heal_below' => 8 } }

  # Run d871: 16 to 8 hp in 84/0 at 98204, the largest drop of the lineage; 4-hp hits came earlier. A heal by a talk opens new detours.
  def test_the_largest_hp_drop_between_decisions_is_the_hit_and_a_heal_resets_the_detours
    events = [decision(1, 84, 24), decision(2, 84, 20), decision(3, 84, 16), decision(4, 84, 8), heal(5), heal(6)]
    healers = Koholint::Healers.from_events(events)
    assert_equal [8, 2], [healers.hit, healers.detours]
    healers = Koholint::Healers.from_events(events + [decision(7, 83, 8, 1), decision(8, 83, 24)])
    assert_equal [8, 0, [[83, 0]]], [healers.hit, healers.detours, healers.places]
  end

  def test_leaving_the_place_before_the_health_rises_makes_no_healer
    events = [decision(1, 83, 16, 1), decision(2, 82, 16), decision(3, 82, 24)]
    assert_empty Koholint::Healers.from_events(events).places
  end
end
