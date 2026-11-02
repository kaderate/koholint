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
    entities = [{ type: 62, kind: 'npc', cell: [2, 3] }, { type: 62, kind: 'npc', cell: [2, 6] }, { type: 9, kind: 'enemy', cell: [4, 4] }]
    signs = [{ kind: 'door', cell: [3, 5], object: 226 }, { kind: 'sign', cell: [5, 1], object: 212 }]
    found = build(entities:, signs:)
    ids = found.map { |candidate| candidate[:id] }
    assert_equal %w[exit-down exit-left exit-right door-3-5 person-t62 sign-5-1 place-4-0], ids
    exit = found.first
    assert_equal({ kind: 'leave_place', place: HERE }, exit[:predicate])
    assert_equal({ kind: 'exit', place: HERE, direction: 'down' }, exit[:target])
    assert_equal({ kind: 'new_text' }, found[4][:predicate])
    assert_equal({ kind: 'reach_place', place: [4, 0] }, found.last[:predicate])
    assert_match(/2 moves away/, found.last[:label])
    assert_equal '- door-3-5: enter the door at (3,5), never entered', Koholint::Candidates.lines(found)[3]
    assert_equal found[4], Koholint::Candidates.find(found, ' person-t62 ')
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
  end
end
