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
    entities = [entity(115, [5, 2], :npc), entity(117, [5, 7], :npc, verified: false), entity(110, [2, 2], :unknown, moves: true),
                entity(9, [6, 6], :enemy), entity(45, [6, 1], :object), entity(1, nil, :npc)]
    objects = [{ object: 212, cell: [3, 3], kind: :sign, verified: true }, { object: 40, cell: [1, 1], kind: :object, verified: false },
               { object: 226, cell: [4, 5], kind: :door, verified: true }]
    Koholint::PlaceCard.build(place: PLACE, entities:, objects:, grid: grid(true))
  end

  def test_a_card_sorts_entities_and_room_objects_by_kind_and_lists_open_border_cells
    assert_equal({ place: PLACE, people: [{ type: 115, cell: [5, 2], verified: true }, { type: 117, cell: [5, 7], verified: false }],
                   enemies: [{ type: 9, cell: [6, 6] }], unknown: [{ type: 110, cell: [2, 2], moves: true }],
                   signs: [{ cell: [3, 3], object: 212, verified: true }], objects: [{ cell: [6, 1], type: 45 }, { cell: [1, 1], object: 40 }],
                   doors: [{ cell: [4, 5], object: 226, verified: true }], exits: { up: [[0, 4], [0, 5]], right: [[3, 9]] } }, card)
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

  def test_the_trace_requires_the_card_fields
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:place_card, frame: 1, **card.except(:signs)) }
    end
  end
end
