require_relative 'test_helper'
require 'tempfile'
require 'koholint/game_state'
require 'koholint/items'
require 'koholint/perception'
require 'koholint/agents/context'

class ItemsTest < Minitest::Test
  Items = Koholint::Items

  def state(**fields)
    Koholint::GameState.new(frame: 0, room_id: 163, map_id: 16, game_mode: 0x0B, game_submode: 7, item_a: 0, item_b: 0,
                            inventory: Array.new(10, 0), **fields)
  end

  def test_catalogue_names_verified_items_plainly_and_marks_hypotheses
    assert_equal 'shield', Items.name(4)
    assert_equal 'sword', Items.name(1)
    assert_equal 'bombs?', Items.name(2)
    assert_equal 'unknown item 99', Items.name(99)
    assert_equal 'empty', Items.label(0)
    assert_equal :sword, Items.milestone(1)
    assert_equal 4, Items.find('shield')
    assert_equal 1, Items.find('Sword?')
    assert_equal 7, Items.find('7')
    assert_nil Items.find('lamp')
  end

  def test_catalogue_rejects_a_verified_item_checked_once
    Tempfile.create(['items', '.json']) do |file|
      file.write('[{"id": 4, "name": "shield", "source": "x", "confidence": "verified", "verified_count": 1}]')
      file.flush
      assert_raises(Items::Invalid) { Items.catalogue(file.path) }
    end
  end

  def test_held_items_cover_both_buttons_and_the_slots
    held = state(item_b: 4, inventory: [0, 0, 2, 0, 0, 0, 0, 0, 0, 0])
    assert_equal [4, 2], Items.held(held)
    assert_equal :b, Items.button_of(held, 4)
    assert_equal 2, Items.slot_of(held, 2)
    assert_nil Items.button_of(held, 2)
  end

  def test_milestone_comes_from_the_shield_level_or_a_milestone_item
    assert_equal :none, Koholint::Perception.milestone_for(0, [])
    assert_equal :shield, Koholint::Perception.milestone_for(1, [])
    assert_equal :shield, Koholint::Perception.milestone_for(0, [4])
    assert_equal :sword, Koholint::Perception.milestone_for(1, [4, 1])
  end

  def test_watch_emits_each_new_item_once_after_the_first_play_frame
    watch = Koholint::ItemWatch.new
    assert_empty watch.observe(state(game_mode: 0, item_b: 7))
    assert_empty watch.observe(state(item_a: 9))
    gained = watch.observe(state(item_a: 9, item_b: 4))
    assert_equal [{ item: 4, name: 'shield', place: [163, 16], held: [4, 9] }], gained
    assert_empty watch.observe(state(item_a: 9, inventory: [4] + Array.new(9, 0)))
    assert_empty watch.observe(state(item_a: 9, item_b: 4))
    assert_equal [1], watch.observe(state(item_a: 1, item_b: 4)).map { |g| g[:item] }
  end

  def test_watch_resumes_from_the_trace
    watch = Koholint::ItemWatch.from_events([{ 'type' => 'item_gained', 'item' => 4 }])
    watch.observe(state)
    assert_empty watch.observe(state(item_b: 4))
  end

  def test_context_lists_the_buttons_and_the_filled_slots
    text = Koholint::Agents::Context.send(:items_line, state(item_b: 4, inventory: [0, 0, 2, 0, 0, 0, 0, 0, 0, 0]))
    assert_equal 'Items (a ? marks a name not yet measured): A empty, B shield (id 4); inventory slots: 2 bombs? (id 2)', text
    assert_includes Koholint::Agents::Context.send(:items_line, state), 'inventory slots: all empty'
  end
end
