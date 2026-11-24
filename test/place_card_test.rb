require_relative 'test_helper'
require 'tmpdir'
require 'koholint/leads'
require 'koholint/place_card'
require 'koholint/trace'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'

class PlaceCardTest < Minitest::Test
  PLACE = [162, 0].freeze

  def entity(type, cell, kind, slot: type, verified: true, moves: false) = { slot:, type:, x: 0, y: 0, cell:, kind:, verified:, moves: }

  def grid(free)
    beliefs = Koholint::Vision::Beliefs.new
    capabilities = Koholint::Vision::Capabilities.new
    beliefs.record(appearance: 'floor', action: :walk, direction: nil, result: :yes, method: :probe, context: capabilities, frame: 1, source: 'test') if free
    cells = Array.new(8) { |row| Array.new(10) { |col| (row.zero? && col.between?(4, 5)) || (col == 9 && row == 3) ? 'floor' : 'wall' } }
    Koholint::Vision::Grid.new(cells:, static_sprites: [], beliefs:, capabilities:)
  end

  def card
    entities = [entity(115, [5, 2], :npc), entity(117, [5, 7], :npc, verified: false), entity(110, [2, 2], :creature, moves: true),
                entity(47, [1, 4], :unknown, moves: nil), entity(9, [6, 6], :enemy), entity(45, [6, 1], :object), entity(1, nil, :npc)]
    objects = [{ object: 212, cell: [3, 3], kind: :sign, verified: true }, { object: 40, cell: [1, 1], kind: :object, verified: false },
               { object: 226, cell: [4, 5], kind: :door, verified: true }, { object: 160, cell: [2, 8], kind: :chest, verified: true },
               { object: 161, cell: [6, 8], kind: :chest, verified: true, open: true }]
    Koholint::PlaceCard.build(place: PLACE, entities:, objects:, grid: grid(true))
  end

  def test_a_card_sorts_entities_and_room_objects_by_kind_and_lists_open_border_cells
    assert_equal({ place: PLACE, people: [{ type: 115, cell: [5, 2], verified: true }, { type: 117, cell: [5, 7], verified: false }],
                   enemies: [{ type: 9, cell: [6, 6] }], unknown: [{ type: 47, cell: [1, 4], moves: nil }],
                   creatures: [{ type: 110, cell: [2, 2], moves: true }],
                   signs: [{ cell: [3, 3], object: 212, verified: true }], objects: [{ cell: [6, 1], type: 45 }, { cell: [1, 1], object: 40 }],
                   doors: [{ cell: [4, 5], object: 226, verified: true }], chests: [{ cell: [2, 8], open: false }, { cell: [6, 8], open: true }],
                   exits: { up: [[0, 4], [0, 5]], right: [[3, 9]] } }, card)
  end

  def test_latest_cards_keep_the_closed_chests_not_opened_since
    events = [{ 'type' => 'place_card', 'frame' => 10, 'place' => [1, 0], 'people' => [], 'signs' => [],
                'chests' => [{ 'cell' => [2, 3], 'open' => false }, { 'cell' => [4, 5], 'open' => false }, { 'cell' => [6, 7], 'open' => true }] },
              { 'type' => 'chest_opened', 'frame' => 40, 'place' => [1, 0], 'cell' => [4, 5] },
              { 'type' => 'place_card', 'frame' => 50, 'place' => [2, 0], 'people' => [], 'signs' => [] }]
    cards = Koholint::PlaceCard.latest(events)
    assert_equal [[2, 3]], cards[[1, 0]][:chests]
    assert_equal [], cards[[2, 0]][:chests]
  end

  def test_unknown_passability_gives_no_exit
    assert_equal({}, Koholint::PlaceCard.build(place: PLACE, entities: [], objects: [], grid: grid(false))[:exits])
    assert_equal({}, Koholint::PlaceCard.build(place: PLACE, entities: [], objects: [], grid: nil)[:exits])
  end

  def test_world_places_keep_the_last_card_with_visits_and_engagement_status
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:place_card, frame: 10, **card.merge(signs: []))
      trace.emit(:place_card, frame: 90, **card)
      talk = { skill: 'talk_to', params: { row: 3, col: 3 }, result: { talked: true, stopped_by: 'done', from: { room: 162, map: 0 } } }
      trace.emit(:action, frame: 100, **talk)
      trace.emit(:dialogue, frame: 100, place: PLACE, text: 'A sign says hello.', source: 'agent', page: 1)
      trace.emit(:action, frame: 200, **talk.merge(params: { row: 5, col: 2 }, result: talk[:result].merge(entity: { type: 115 })))
      trace.emit(:dialogue, frame: 200, place: PLACE, text: 'Hi there.', source: 'agent', page: 1, speaker: 'Kid')
      Koholint::Leads.write_world(dir)
      place = JSON.parse(File.read(File.join(dir, 'world.json'))).fetch('places').fetch('162-0')
      assert_equal [2, 10, 90], place.values_at('visits', 'first_frame', 'last_frame')
      assert_equal [{ 'cell' => [3, 3], 'object' => 212, 'verified' => true, 'status' => 'read' }], place['signs']
      assert_equal [{ 'type' => 115, 'cell' => [5, 2], 'verified' => true, 'name' => 'Kid', 'status' => 'new' },
                    { 'type' => 117, 'cell' => [5, 7], 'verified' => false, 'status' => 'never' }], place['people']
      assert_equal [{ 'up' => [[0, 4], [0, 5]], 'right' => [[3, 9]] }], [place['exits']]
      assert_equal [{ 'cell' => [4, 5], 'object' => 226, 'verified' => true }], place['doors']
    end
  end

  def test_world_unknown_entities_carry_their_tries_answers_and_movement_and_places_their_items
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:place_card, frame: 10, **card)
      trace.emit(:action, frame: 50, skill: 'talk_to', params: { row: 1, col: 4 },
                          result: { stopped_by: 'no_response', talked: false, tracked: 1, target_type: 47, from: { room: 162, map: 0 } })
      trace.emit(:item_gained, frame: 60, item: 4, name: 'shield', place: PLACE, held: [4])
      trace.emit(:place_card, frame: 90, **card)
      Koholint::Leads.write_world(dir)
      place = JSON.parse(File.read(File.join(dir, 'world.json'))).fetch('places').fetch('162-0')
      assert_equal [{ 'type' => 47, 'tries' => 1, 'answered' => 0, 'moved' => true }], place['unknown_types']
      assert_equal [[47, [1, 4]]], place['unknown'].map { |entity| entity.values_at('type', 'cell') }
      assert_equal ['shield'], place['items_gained']
    end
  end

  def test_touches_are_counted_per_type_and_a_pickup_type_is_verified_only_from_two_places
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      touch = ->(frame, room, picked) { trace.emit(:action, frame:, skill: 'touch', params: { row: 1, col: 4, type: 47 }, result: { stopped_by: 'done', target_type: 47, from: { room:, map: 0 }, settled: true, picked_up: picked, items_before: { held: [], rupees: 0 }, items_after: { held: [], rupees: picked ? 1 : 0 } }) }
      trace.emit(:place_card, frame: 10, **card)
      touch.(50, 162, false)
      touch.(60, 162, true)
      Koholint::Leads.write_world(dir)
      world = JSON.parse(File.read(File.join(dir, 'world.json')))
      assert_equal [{ 'type' => 47, 'tries' => 0, 'answered' => 0, 'moved' => false, 'touched' => 2, 'picked_up' => 1 }], world.dig('places', '162-0', 'unknown_types')
      assert_equal [[47, 'observed', 1]], world['pickups'].map { |entry| entry.values_at('type', 'confidence', 'verified_count') }
      assert_equal [{ 'place' => [162, 0], 'frame' => 60, 'cell' => [1, 4], 'items_before' => { 'held' => [], 'rupees' => 0 }, 'items_after' => { 'held' => [], 'rupees' => 1 } }], world['pickups'].first['touches']
      touch.(70, 162, true)
      Koholint::Leads.write_world(dir)
      assert_equal 'observed', JSON.parse(File.read(File.join(dir, 'world.json')))['pickups'].first['confidence'], 'one place twice is one check'
      touch.(80, 163, true)
      Koholint::Leads.write_world(dir)
      assert_equal [['verified', 2]], JSON.parse(File.read(File.join(dir, 'world.json')))['pickups'].map { |entry| entry.values_at('confidence', 'verified_count') }
    end
  end

  def test_a_touch_ended_by_a_text_is_judged_once_the_game_settles_after_the_harness_read_it
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      seen = ->(frame, dialog, frozen, inventory) { trace.emit(:perception, frame:, state: { 'game_mode' => 11, 'dialog_state' => dialog, 'link_frozen' => frozen, 'item_a' => 1, 'item_b' => 4, 'inventory' => inventory, 'rupees' => 2 }) }
      touch = ->(frame) { trace.emit(:action, frame:, skill: 'touch', params: { row: 1, col: 4, type: 47 }, result: { stopped_by: 'dialogue', target_type: 47, from: { room: 162, map: 0 }, settled: false, arrival_frame: frame - 5, items_before: { held: [1, 4], rupees: 2 }, items_after: { held: [1, 4], rupees: 2 } }) }
      trace.emit(:place_card, frame: 10, **card)
      touch.(100)
      seen.(130, 134, 17, [0] * 10)
      trace.emit(:action, frame: 130, skill: 'advance_dialogue', params: {}, result: { stopped_by: 'done' })
      seen.(400, 0, 1, [12] + [0] * 9)
      seen.(420, 0, 0, [12] + [0] * 9)
      touch.(2000)
      trace.emit(:action, frame: 2050, skill: 'explore', params: {}, result: { stopped_by: 'budget' })
      seen.(2100, 0, 0, [12, 7] + [0] * 8)
      Koholint::Leads.write_world(dir)
      world = JSON.parse(File.read(File.join(dir, 'world.json')))
      assert_equal [{ 'place' => [162, 0], 'frame' => 100, 'cell' => [1, 4], 'items_before' => { 'held' => [1, 4], 'rupees' => 2 }, 'items_after' => { 'held' => [1, 4, 12], 'rupees' => 2 } }],
                   world['pickups'].first['touches'], 'the second touch is undecided: a skill of its own came before any settled read'
      assert_equal [2, 1], world.dig('places', '162-0', 'unknown_types').first.values_at('touched', 'picked_up')
    end
  end

  def test_world_tries_are_stored_once_per_type_and_moved_only_when_talk_to_chased_it
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      two = card.merge(unknown: [{ type: 47, cell: [1, 4], moves: nil }, { type: 47, cell: [2, 6], moves: nil }])
      trace.emit(:place_card, frame: 10, **two)
      trace.emit(:action, frame: 50, skill: 'talk_to', params: { row: 1, col: 4 },
                          result: { stopped_by: 'done', talked: true, target_type: 47, from: { room: 162, map: 0 } })
      trace.emit(:place_card, frame: 90, **card.merge(unknown: [{ type: 47, cell: [3, 3], moves: nil }]))
      Koholint::Leads.write_world(dir)
      place = JSON.parse(File.read(File.join(dir, 'world.json'))).fetch('places').fetch('162-0')
      assert_equal [{ 'type' => 47, 'tries' => 1, 'answered' => 1, 'moved' => false }], place['unknown_types']
      refute place['unknown'].first.key?('tries')
    end
  end

  def test_the_trace_requires_the_card_fields
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:place_card, frame: 1, **card.except(:signs)) }
    end
  end
end
