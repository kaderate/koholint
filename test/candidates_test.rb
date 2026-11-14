require_relative 'test_helper'
require 'koholint/candidates'
require 'koholint/explore_log'
require 'koholint/leads'
require 'koholint/talk_log'

class CandidatesTest < Minitest::Test
  class OpenGrid
    def passable(*) = :yes
    def static_sprite(*) = nil
  end

  HERE = [1, 0].freeze

  class SpriteGrid < OpenGrid
    def static_sprite(row, col) = [[2, 2], [6, 8]].include?([row, col]) || nil
  end

  def test_unidentified_things_are_offered_nearest_first_until_tried
    talk_log = Koholint::TalkLog.new
    entities = [{ type: 47, kind: 'unknown', cell: [6, 6] }, { type: 9, kind: 'enemy', cell: [6, 8] }]
    found = build(grid: SpriteGrid.new, entities:, talk_log:, link: [6, 5]).select { |c| c[:id].start_with?('examine') }
    assert_equal %w[examine-6-6 examine-2-2], found.map { |c| c[:id] }
    assert_equal({ kind: 'examine', place: HERE, cell: [2, 2] }, found[1][:target])
    assert_match(/not known whether it is a person or hostile/, found[0][:label])
    refute_match(/talk to|person \(type/, found[0][:label])
    talk_log.record(place: HERE, row: 2, col: 2, talked: false)
    talk_log.record(place: HERE, row: 6, col: 6, talked: false, entity: 47)
    assert_empty(build(grid: SpriteGrid.new, entities:, talk_log:, link: [6, 5]).select { |c| c[:id].start_with?('examine') })
  end

  def test_a_person_away_exhausted_before_link_held_other_items_is_offered_once
    talk_log = Koholint::TalkLog.new
    before = Koholint::Dialogues.stamp(milestone: :shield, items: [4], leads: 0)
    2.times { talk_log.remember(place: [3, 0], cell: [2, 2], text: 'Bonjour, petit!', stamp: before, entity: 81) }
    cards = { [3, 0] => { people: [{ type: 81, cell: [2, 2] }] } }
    away = ->(stamp) { build(cards:, talk_log:, stamp:).select { |c| c[:id] == 'person-3-0-t81' } }
    assert_empty away.(Koholint::Dialogues.stamp(milestone: :shield, items: [4], leads: 3)), 'new leads alone do not reopen an exhausted person'
    after = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0)
    assert_match(/Link holds other items than at the last talk/, away.(after).first[:label])
    talk_log.remember(place: [3, 0], cell: [2, 2], text: 'Bonjour, petit!', stamp: after, entity: 81)
    assert_empty away.(after)
  end

  def log
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [3, 0] }] })
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: [4, 0] }], survey: { sides: { up: [{ row: 0, col: 5 }] }, doors: [] } })
    log
  end

  def build(**over)
    Koholint::Candidates.build(place: HERE, grid: OpenGrid.new, explore_log: log, talk_log: Koholint::TalkLog.new, leads: Koholint::Leads.new, **over)
  end

  def test_exits_skip_sides_already_left_and_doors_people_and_signs_of_this_place_are_listed
    entities = [{ type: 62, kind: 'npc', cell: [2, 3] }, { type: 62, kind: 'npc', cell: [2, 6] }, { type: 9, kind: 'enemy', cell: [4, 4] },
                { type: 110, kind: 'creature', cell: [1, 1] }, { type: 47, kind: 'unknown', cell: [6, 6] }]
    signs = [{ kind: 'door', cell: [3, 5], object: 226 }, { kind: 'sign', cell: [5, 1], object: 212 }]
    found = build(entities:, signs:)
    ids = found.map { |candidate| candidate[:id] }
    assert_equal %w[person-t62 sign-5-1 examine-6-6 exit-down exit-left exit-right door-3-5 place-4-0], ids
    assert_equal({ kind: 'person', type: 47, place: HERE, cell: [6, 6] }, found[2][:target])
    exit = found[3]
    assert_equal({ kind: 'leave_place', place: HERE }, exit[:predicate])
    assert_equal({ kind: 'exit', place: HERE, direction: 'down' }, exit[:target])
    assert_equal({ kind: 'new_text' }, found[0][:predicate])
    assert_equal({ kind: 'reach_place', place: [4, 0] }, found.last[:predicate])
    assert_match(/2 moves away/, found.last[:label])
    assert_equal '- door-3-5: enter the door at (3,5), never entered (leaves unexhausted people here: person (type 62))', Koholint::Candidates.lines(found)[6]
    assert_equal found[0], Koholint::Candidates.find(found, ' person-t62 ')
    assert(found.drop(3).all? { |candidate| candidate[:label].end_with?('(leaves unexhausted people here: person (type 62))') })
    [[3, 5], [4, 5]].each { |link| refute_includes build(signs:, link:).map { |c| c[:id] }, 'door-3-5' }
    assert_includes build(signs:, link: [5, 5]).map { |c| c[:id] }, 'door-3-5'
  end

  def test_the_offered_list_keeps_id_label_warning_and_pick_for_the_trace
    entities = [{ type: 62, kind: 'npc', cell: [2, 3] }]
    found = build(entities:)
    offered = Koholint::Candidates.offered(found, found.last)
    assert_equal found.map { |c| c[:id] }, offered.map { |c| c[:id] }
    assert_equal [false] * (found.size - 1) + [true], offered.map { |c| c[:picked] }
    assert_equal [false] + [true] * (found.size - 1), offered.map { |c| c[:leaves_unexhausted] }
  end

  def test_exits_are_marked_until_every_person_here_is_exhausted
    talk_log = Koholint::TalkLog.new
    stamp = ['none', 1]
    entities = [{ type: 62, kind: 'npc', cell: [2, 3] }, { type: 63, kind: 'npc', cell: [4, 7] }]
    2.times { talk_log.remember(place: HERE, cell: [2, 3], text: 'Follow the south road.', stamp:, entity: 62, conversation: 'm' * 16) }
    talk_log.remember(place: HERE, cell: [4, 7], text: 'Take this shield.', stamp:, entity: 63, conversation: 't' * 16)
    found = Koholint::Candidates.build(place: HERE, grid: OpenGrid.new, explore_log: log, talk_log:, leads: Koholint::Leads.new, entities:, stamp:)
    assert_equal 'person-t63', found.first[:id]
    refute(found.any? { |candidate| candidate[:id] == 'person-t62' })
    assert_match(/leaves unexhausted people here: person \(type 63\)\)\z/, found.find { |candidate| candidate[:id] == 'exit-down' }[:label])
    talk_log.remember(place: HERE, cell: [4, 7], text: 'Take this shield.', stamp:, entity: 63, conversation: 't' * 16)
    found = Koholint::Candidates.build(place: HERE, grid: OpenGrid.new, explore_log: log, talk_log:, leads: Koholint::Leads.new, entities:, stamp:)
    refute(found.any? { |candidate| candidate[:label].include?('unexhausted') })
  end

  def test_people_and_signs_of_other_places_and_lead_places_use_names_and_routes
    leads = Koholint::Leads.new
    leads.name_place([3, 0], 'Beach')
    leads.absorb([{ 'quote' => 'go to the beach', 'claim' => 'the beach matters', 'importance' => 'high', 'where' => 'beach' },
                  { 'quote' => 'the far tower', 'claim' => 'a tower', 'importance' => 'normal', 'where' => '9-0' }],
                 transcription: 'go to the beach and the far tower', place: HERE, source: nil)
    cards = { [3, 0] => { people: [{ type: 70, cell: [1, 1] }], signs: [{ cell: [2, 2] }] } }
    found = build(leads:, cards:)
    by_id = found.to_h { |candidate| [candidate[:id], candidate] }
    assert_equal({ kind: 'person', place: [3, 0], type: 70, cell: [1, 1] }, by_id['person-3-0-t70'][:target])
    assert_match(/in Beach \(3-0\), 1 move away/, by_id['person-3-0-t70'][:label])
    assert_equal({ kind: 'reach_place', place: [3, 0] }, by_id['sign-3-0-2-2'][:predicate])
    assert_equal({ kind: 'lead', place: [3, 0], lead: 'lead-1' }, by_id['lead-1'][:target])
    assert_match(/no known route/, by_id['lead-2'][:label])
    refute by_id.key?('place-3-0')
    leads.note_objective({ id: 'obj-1', title: 'Leave by the up side', outcome: :achieved, ended_frame: 40, predicate: { kind: 'leave_place', place: HERE }, because: 'lead-1' })
    assert_equal 'tested', leads.status(leads.all[0])[:status]
    assert build(leads:, cards:).any? { |candidate| candidate[:id] == 'lead-1' }, 'a lead tested somewhere else stays a candidate'
    leads.note_objective({ id: 'obj-2', title: 'Go to Beach', outcome: :achieved, ended_frame: 50, target: { kind: 'lead', place: [3, 0], lead: 'lead-1' } })
    refute build(leads:, cards:).any? { |candidate| candidate[:id] == 'lead-1' }, 'a lead whose place was reached is no longer a candidate'
    2.times { |n| leads.note_objective({ id: "obj-#{3 + n}", title: 'Go to the tower', outcome: :failed, ended_frame: 60 + n, because: 'lead-2' }) }
    refute build(leads:, cards:).any? { |candidate| candidate[:id] == 'lead-2' }, 'a refuted lead is no longer a candidate'
  end

  def test_low_health_lists_the_nearest_known_interior_first
    log = self.log
    log.absorb({ from: { room: 3, map: 0 }, exits: [{ row: 7, col: 4, direction: :up, outcome: :left, to: [165, 16] }] })
    log.absorb({ from: { room: 4, map: 0 }, exits: [{ row: 7, col: 4, direction: :up, outcome: :left, to: [166, 16] }] })
    first = build(explore_log: log, low_health: true).first
    assert_equal 'shelter-165-16', first[:id]
    assert_equal({ kind: 'shelter', place: [165, 16] }, first[:target])
    assert_match(/\ALOW HEALTH: take shelter in place 165-16, 2 moves away/, first[:label])
    refute(build(explore_log: log).any? { |candidate| candidate[:id].start_with?('shelter') })
    assert_empty(build(place: [165, 16], explore_log: log, low_health: true).select { |candidate| candidate[:id].start_with?('shelter') })
  end
end
