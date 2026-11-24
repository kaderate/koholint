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

  def test_a_thing_never_tried_seen_while_link_held_other_items_is_offered_away_nearest_first_until_tried
    talk_log = Koholint::TalkLog.new
    catalogued = Koholint::Entities.catalogue.keys.first
    cards = { [3, 0] => { people: [{ type: 70, cell: [1, 1] }] },
              [4, 0] => { people: [], unknown: [{ type: 64, cell: [3, 4] }, { type: catalogued, cell: [5, 5] }], held: [1, 4] } }
    stamp = ->(items) { Koholint::Dialogues.stamp(milestone: :sword, items:, leads: 0) }
    away = ->(items) { build(cards:, talk_log:, stamp: stamp.(items)).select { |c| c[:id].start_with?('person-', 'examine-') } }
    assert_equal %w[person-3-0-t70], away.([1, 4]).map { |c| c[:id] }, 'seen with the items held now, it is not offered'
    found = away.([1, 4, 12])
    assert_equal %w[person-3-0-t70 examine-4-0-t64], found.map { |c| c[:id] }, 'nearest first, and a catalogued type never'
    assert_equal({ kind: 'person', place: [4, 0], type: 64, cell: [3, 4] }, found[1][:target])
    assert_equal({ kind: 'reach_place', place: [4, 0] }, found[1][:predicate])
    assert_match(/2 moves away, never tried; Link holds other items than when it was seen/, found[1][:label])
    talk_log.record(place: [4, 0], row: 3, col: 4, talked: false, entity: 64)
    assert_equal %w[person-3-0-t70], away.([1, 4, 12]).map { |c| c[:id] }
  end

  def test_a_surveyed_place_with_a_thing_never_tried_is_a_place_with_work
    explore_log = log
    explore_log.absorb({ from: { room: 3, map: 0 }, survey: { sides: {}, doors: [], pending: false } })
    refute(build(explore_log:).any? { |c| c[:id] == 'place-3-0' })
    explore_log.card([3, 0], [64])
    assert_match(/go to place 3-0, 1 move away: it has a thing never tried \(type 64\)/, build(explore_log:).find { |c| c[:id] == 'place-3-0' }[:label])
  end

  def asking(leads, talk_log, place, type, stamp, text: 'Il me faut une chose de la forêt, tu sais.')
    talk_log.remember(place:, cell: [3, 4], text:, stamp:, entity: type)
    leads.absorb([{ 'quote' => text, 'claim' => 'the speaker asks for a thing', 'importance' => 'high', 'need' => true }],
                 transcription: text, place:, source: { row: 3, col: 4, entity: type })
  end

  def test_every_person_who_asked_for_something_is_offered_once_link_holds_other_items_until_a_new_text_answers
    leads = Koholint::Leads.new
    talk_log = Koholint::TalkLog.new
    explore_log = Koholint::ExploreLog.new
    places = [[3, 0], [4, 0], [5, 0], [6, 0], [7, 0]]
    [HERE, *places].each_cons(2) { |from, to| explore_log.absorb({ from: { room: from[0], map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: }] }) }
    before = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0)
    after = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12], leads: 0)
    places.each_with_index { |where, i| asking(leads, talk_log, where, 60 + i, before, text: "Il me faut une chose numéro #{i}, tu sais.") }
    needs = ->(stamp) { build(leads:, talk_log:, explore_log:, stamp:).select { |c| c[:id].start_with?('need-') } }
    assert_empty needs.(before), 'with the items held at the talk, nothing new to offer'
    found = needs.(after)
    assert_equal %w[need-3-0-t60 need-4-0-t61 need-5-0-t62 need-6-0-t63 need-7-0-t64], found.map { |c| c[:id] }, 'every need-speaker, not only 4'
    assert_equal({ kind: 'person', place: [7, 0], type: 64, cell: [3, 4] }, found.last[:target])
    assert_match(/5 moves away, who asked for something \(lead-5: « Il me faut une chose numéro 4, tu sais. »\)/, found.last[:label])
    talk_log.remember(place: [3, 0], cell: [3, 4], text: 'Il me faut une chose numéro 0, tu sais.', stamp: after, entity: 60)
    assert_equal 'need-4-0-t61', needs.(after).first[:id], 'talked to with the new items, offered again only after another change'
    later = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12, 2], leads: 0)
    assert_equal 'need-3-0-t60', needs.(later).first[:id], 'the same text again leaves the need open'
    talk_log.remember(place: [3, 0], cell: [3, 4], text: 'Oh merci, voilà pour toi!', stamp: later, entity: 60)
    refute(needs.(Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12, 2, 5], leads: 0)).any? { |c| c[:id] == 'need-3-0-t60' }, 'a new text answers the need')
  end

  def test_a_need_speaker_here_comes_first_and_is_not_listed_twice
    leads = Koholint::Leads.new
    talk_log = Koholint::TalkLog.new
    before = Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0)
    asking(leads, talk_log, HERE, 64, before)
    entities = [{ type: 64, kind: 'npc', cell: [3, 4] }, { type: 70, kind: 'npc', cell: [5, 5] }]
    ids = build(leads:, talk_log:, entities:, stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12], leads: 0)).map { |c| c[:id] }
    assert_equal %w[need-t64 person-t70], ids.first(2)
    refute_includes ids, 'person-t64'
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

  # 81/0 in the 21b0 lineage: its top led to 99/0, the raccoon there spoke of the forest, and the owl's key is hidden in the forest.
  def test_a_puzzle_place_an_open_lead_points_to_comes_first_until_offered_or_benched_conclusively
    puzzled = Koholint::ExploreLog.new
    puzzled.absorb({ from: { room: 97, map: 0 }, exits: [{ row: 0, col: 6, direction: :up, outcome: :left, to: [81, 0] }] })
    puzzled.absorb({ from: { room: 81, map: 0 }, exits: [{ row: 0, col: 3, direction: :up, outcome: :left, to: [99, 0] }] })
    leads = Koholint::Leads.new
    leads.name_place([144, 0], 'Forêt Enchantée')
    leads.restore({ 'id' => 'lead-20', 'place' => [128, 0], 'quote' => 'Vas-y avec la Clé cachée dans la Forêt.', 'claim' => 'a key', 'importance' => 'high' })
    first = -> { Koholint::Candidates.build(place: [97, 0], grid: OpenGrid.new, explore_log: puzzled, talk_log: Koholint::TalkLog.new, leads:).first }
    refute_equal 'puzzle-81-0', first.()[:id], 'no text ties 81/0 to the lead yet'
    leads.note_read('Hé hé! Tu vas te perdre dans la Forêt.', place: [81, 0])
    assert_equal [[144, 0], [81, 0]], leads.region(leads.all.first)
    puzzle = first.()
    assert_equal ['puzzle-81-0', { kind: 'new_place' }, { kind: 'place', place: [81, 0] }], puzzle.values_at(:id, :predicate, :target)
    assert_match(/lead-20 « Vas-y avec la Clé cachée dans la Forêt. » points there/, puzzle[:label])
    puzzled.use_bench({ edges: {}, status: {}, benches: { [81, 0] => { 'status' => 'incomplete' } } })
    assert_equal 'puzzle-81-0', first.()[:id], 'a bench with a way never reached concludes nothing'
    puzzled.use_bench({ edges: {}, status: {}, benches: { [81, 0] => { 'status' => 'depends_on_context' } } })
    refute_equal 'puzzle-81-0', first.()[:id], 'a conclusive bench in this context ends it'
    puzzled.use_bench({ edges: {}, status: {}, benches: {} })
    puzzled.offer_puzzle([81, 0])
    refute_equal 'puzzle-81-0', first.()[:id], 'and so does one offer in this run and context'
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

  def test_the_side_known_only_as_the_way_back_says_so_and_comes_after_the_place_s_other_exits_and_doors
    found = Koholint::Candidates.build(place: [3, 0], grid: OpenGrid.new, explore_log: log, talk_log: Koholint::TalkLog.new, leads: Koholint::Leads.new,
                                       signs: [{ kind: 'door', cell: [3, 5], object: 226 }])
    leaving = found.map { |c| c[:id] }.grep(/\A(exit|door)-/)
    assert_equal %w[exit-left exit-right door-3-5 exit-down], leaving, 'up was crossed; down is only the assumed way back to 1-0'
    back = found.find { |c| c[:id] == 'exit-down' }
    assert_match(/, the way back to place 1-0 you came in by \(assumed, never crossed\)\z/, back[:label])
    refute_match(/way back/, found.find { |c| c[:id] == 'exit-left' }[:label])
    assert_equal({ kind: 'exit', place: [3, 0], direction: 'down' }, back[:target])
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

  def test_a_closed_chest_is_offered_only_while_a_route_reaches_the_cell_below_it
    chests = [{ kind: 'chest', cell: [3, 4], object: 160, reachable: true }, { kind: 'chest', cell: [5, 6], object: 160, reachable: false },
              { kind: 'chest', cell: [1, 1], object: 161, open: true }]
    found = build(signs: chests).select { |c| c[:id].start_with?('chest') }
    assert_equal %w[chest-3-4], found.map { |c| c[:id] }
    assert_equal({ kind: 'chest', place: HERE, cell: [3, 4] }, found[0][:target])
    assert_equal({ kind: 'new_text' }, found[0][:predicate])
    assert_match(/walk up into it from \(4,4\) and press A/, found[0][:label])
    away = build(cards: { [3, 0] => { chests: [[2, 2]] } }).find { |c| c[:id] == 'chest-3-0-2-2' }
    assert_equal({ kind: 'chest', place: [3, 0], cell: [2, 2], remote: true }, away[:target])
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
    assert_equal({ kind: 'new_text' }, by_id['sign-3-0-2-2'][:predicate], 'reaching the place does not read the sign')
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

end
