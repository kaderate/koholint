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

  def test_a_pickup_fact_needs_its_provenance_and_two_lineages_to_become_verified
    entry = '[{"id": 12, "name": "magic powder", "source": "x", "confidence": "hypothesis", "verified_count": 0, "pickups": %s}]'
    [['{"value": [{"place": [80, 0], "held": [1, 4, 12]}], "confidence": "verified", "verified_count": 1, "source": "x"}', /verified needs verified_count >= 2/],
     ['{"value": [], "confidence": "observed", "verified_count": 1}', /missing source/],
     ['{"value": [], "confidence": "seen", "verified_count": 1, "source": "x"}', /unknown confidence seen/]].each do |fact, message|
      Tempfile.create(['items', '.json']) do |file|
        file.write(format(entry, fact))
        file.flush
        assert_raises(Items::Invalid, fact) { Items.catalogue(file.path) }
        assert_match message, assert_raises(Items::Invalid) { Items.catalogue(file.path) }.message
      end
    end
    Tempfile.create(['items', '.json']) do |file|
      file.write(format(entry, '{"value": [{"place": [80, 0], "held": [1, 4, 12]}], "confidence": "observed", "verified_count": 1, "source": "x"}'))
      file.flush
      assert_equal 'observed', Items.catalogue(file.path).fetch(12).dig('pickups', 'confidence')
    end
  end

  def test_a_gained_item_is_named_by_the_capitalised_words_of_its_pickup_text_read_just_before_at_its_place
    assert_equal %w[Champignon], Items.name_words('Tu as trouvé le Champignon! Il sent bon.')
    assert_equal %w[Clé Dorée], Items.name_words('Tu as la Clé Dorée.')
    assert_equal %w[Arc], Items.name_words("Tu as trouvé l'Arc de Link!"), 'a name later in the sentence is not part of it'
    assert_empty Items.name_words('Bonjour, petit!')
    assert_empty Items.name_words("Salut A ! T' es réveillé..."), 'a capital outside the object phrase is no name'
    assert_empty Items.name_words('Tu as trouvé le X!'), 'one letter is no name'
  end

  # Run 626d, 80/0: the pickup sheet opened at 91353, item 12 showed as held at 91615, and the sheet's dialogue events follow the gain.
  def test_a_resumed_run_names_a_gain_by_the_text_transcribed_after_it_and_never_by_an_earlier_one
    events = [{ 'type' => 'dialogue', 'frame' => 91_000, 'place' => [80, 0], 'text' => 'Le Village est au Sud.' },
              { 'type' => 'perception', 'frame' => 91_353 },
              { 'type' => 'item_gained', 'frame' => 91_615, 'place' => [80, 0], 'item' => 12 },
              { 'type' => 'perception', 'frame' => 91_633 },
              { 'type' => 'dialogue', 'frame' => 91_353, 'place' => [80, 0], 'text' => 'Tu as trouvé le Champignon!' },
              { 'type' => 'dialogue', 'frame' => 91_353, 'place' => [80, 0], 'text' => 'Un arôme subtil.' },
              { 'type' => 'item_gained', 'frame' => 92_000, 'place' => [81, 0], 'item' => 13 },
              { 'type' => 'perception', 'frame' => 93_000 },
              { 'type' => 'dialogue', 'frame' => 92_900, 'place' => [81, 0], 'text' => 'Tu as la Clé Dorée.' }]
    assert_equal({ 12 => %w[Champignon] }, Items.pickup_names(events), 'a text transcribed more than PICKUP_FRAMES after its gain names nothing')
  end

  # Lineage of 626d, 163/16: Tarkin's greeting opened at 3259 was transcribed after the shield showed as held at 3906.
  def test_a_text_opened_more_than_pickup_frames_before_the_gain_or_with_no_object_phrase_names_nothing
    events = [{ 'type' => 'item_gained', 'frame' => 3906, 'place' => [163, 16], 'item' => 4 },
              { 'type' => 'dialogue', 'frame' => 3259, 'place' => [163, 16], 'text' => "Ben, c' est gravé sur le Bouclier!" },
              { 'type' => 'dialogue', 'frame' => 3900, 'place' => [163, 16], 'text' => "Salut A ! T' es réveillé..." }]
    assert_empty Items.pickup_names(events)
  end

  def test_only_names_from_an_observed_pickup_text_count_from_data
    names = Items.pickup_text_names
    assert_equal [%w[champignon]], names.fetch(12), 'only the names the quoted pickup text says, not its plural or its gloss'
    refute names.key?(13), 'a hypothesis from general knowledge'
    refute names.key?(1), 'a name measured by another probe than a pickup text'
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

  def test_item_12_is_the_mushroom_until_the_powder_count_names_it_the_magic_powder
    assert_equal 'mushroom?', Items.name(12)
    assert_equal 'mushroom?', Items.name(12, state(item_b: 12, magic_powder: 0))
    assert_equal 'magic powder?', Items.name(12, state(item_b: 12, magic_powder: 20))
    assert_equal 'magic powder?', Items.name(12, { 'magic_powder' => 20 })
    assert_equal 12, Items.find('magic powder')
    assert_includes Items.names(Items.catalogue[12]), 'poudre magique'
  end

  def test_watch_emits_the_magic_powder_when_the_held_mushroom_becomes_it
    watch = Koholint::ItemWatch.new
    watch.observe(state(item_a: 1))
    assert_equal [{ item: 12, name: 'mushroom?', place: [163, 16], held: [1, 12] }], watch.observe(state(item_a: 1, item_b: 12))
    assert_empty watch.observe(state(item_a: 1))
    gained = watch.observe(state(item_a: 1, item_b: 12, magic_powder: 20))
    assert_equal [{ item: 12, name: 'magic powder?', form: 'magic powder', place: [163, 16], held: [1, 12] }], gained
    assert_empty watch.observe(state(item_a: 1, item_b: 12, magic_powder: 19))
  end

  def test_watch_resumes_each_form_from_the_trace
    watch = Koholint::ItemWatch.from_events([{ 'type' => 'item_gained', 'item' => 12, 'name' => 'magic powder?' }])
    watch.observe(state)
    assert_empty watch.observe(state(item_b: 12))
    assert_equal ['magic powder'], watch.observe(state(item_b: 12, magic_powder: 20)).map { |gain| gain[:form] }
    resumed = Koholint::ItemWatch.from_events([{ 'type' => 'item_gained', 'item' => 12, 'form' => 'magic powder' }])
    resumed.observe(state)
    assert_empty resumed.observe(state(item_b: 12, magic_powder: 20))
  end

  def test_a_form_needs_a_name_a_when_and_its_provenance
    [['{"name": "magic powder", "source": "x", "confidence": "observed", "verified_count": 1}', /needs a name and a when/],
     ['{"name": "magic powder", "when": "magic_powder", "confidence": "verified", "verified_count": 1, "source": "x"}', /verified needs verified_count >= 2/]].each do |form, message|
      Tempfile.create(['items', '.json']) do |file|
        file.write(%([{"id": 12, "name": "mushroom", "source": "x", "confidence": "observed", "verified_count": 1, "forms": [#{form}]}]))
        file.flush
        assert_match message, assert_raises(Items::Invalid) { Items.catalogue(file.path) }.message
      end
    end
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
    powder = Koholint::Agents::Context.send(:items_line, state(item_b: 12, magic_powder: 20))
    assert_includes powder, 'B magic powder? (id 12)'
  end
end
