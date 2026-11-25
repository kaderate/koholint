require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'koholint/candidates'
require 'koholint/explore_log'
require 'koholint/leads'
require 'koholint/run'
require 'koholint/souvenirs'
require 'koholint/talk_log'

class SouvenirsTest < Minitest::Test
  HUT = [3, 0].freeze
  NEED = "C' est une perte de temps! Pour ma poudre, il me faut le Champignon de la forêt.".freeze

  def bundle(root, id, events, parent: nil)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate({ 'flow_version' => 'flow-1', 'parent' => parent }))
    File.write(File.join(dir, 'trace.jsonl'), events.map { |event| "#{JSON.generate(event)}\n" }.join)
  end

  def talk(frame, text, type: 64, place: HUT, items: [1, 4])
    [{ 'type' => 'perception', 'frame' => frame - 2, 'state' => { 'milestone' => 'sword', 'inventory' => items, 'item_a' => 0, 'item_b' => 0 } },
     { 'type' => 'action', 'frame' => frame - 1, 'skill' => 'talk_to', 'params' => { 'row' => 4, 'col' => 4 }, 'result' => { 'talked' => true, 'entity' => { 'type' => type } } },
     { 'type' => 'dialogue', 'frame' => frame, 'place' => place, 'text' => text }]
  end

  def test_build_counts_each_run_from_its_fork_frame_and_keeps_its_first_sighting_with_what_the_reader_held
    Dir.mktmpdir do |root|
      before = talk(100, NEED)
      bundle(root, '20261101-000000-aaaa', before + talk(300, 'Bonjour!', type: 70))
      bundle(root, '20261102-000000-bbbb', before + talk(250, NEED, items: [1, 4, 12]) + talk(260, NEED), parent: { 'id' => '20261101-000000-aaaa', 'frame' => 200 })
      data = Koholint::Souvenirs.build([root])
      need = data['texts'].find { |entry| entry['entity'] == 64 }
      assert_equal [HUT, [4, 4], NEED], need.values_at('place', 'cell', 'text')
      assert_equal [{ 'run' => '20261101-000000-aaaa', 'frame' => 100, 'held' => [1, 4] }, { 'run' => '20261102-000000-bbbb', 'frame' => 250, 'held' => [1, 4, 12] }], need['seen']
      assert_equal({ '20261101-000000-aaaa' => nil, '20261102-000000-bbbb' => ['20261101-000000-aaaa', 200] }, data['runs'])
      assert_equal 2, data['texts'].size
    end
  end

  def test_a_run_remembers_only_runs_created_before_its_parent_and_outside_its_parents_batch
    data = { 'runs' => { '20261101-000000-aaaa' => nil, '20261102-000000-bbbb' => ['20261101-000000-aaaa', 200], '20261102-000001-cccc' => ['20261101-000000-aaaa', 200],
                         '20261103-000000-dddd' => nil },
             'texts' => %w[aaaa bbbb cccc dddd].each_with_index.map do |run, index|
               { 'place' => HUT, 'entity' => 60 + index, 'cell' => [1, 1], 'text' => "text #{run}", 'seen' => [{ 'run' => data_id(run), 'frame' => 1, 'held' => [] }] }
             end }
    remembered = ->(**filter) { Koholint::Souvenirs.for_run(data, **filter).map { |entry| entry['text'] } }
    assert_equal ['text aaaa', 'text bbbb'], remembered.(before: '20261102-000001-cccc')
    assert_equal ['text aaaa'], remembered.(before: '20261103-000000-dddd', batch: ['20261101-000000-aaaa', 200])
    assert_equal [], remembered.(before: nil)
  end

  def data_id(run) = { 'aaaa' => '20261101-000000-aaaa', 'bbbb' => '20261102-000000-bbbb', 'cccc' => '20261102-000001-cccc', 'dddd' => '20261103-000000-dddd' }.fetch(run)

  def test_the_digest_covers_text_place_and_speaker_never_the_sightings
    entry = { 'place' => HUT, 'entity' => 64, 'cell' => [4, 4], 'text' => NEED, 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [] }] }
    later = entry.merge('seen' => entry['seen'] + [{ 'run' => '20261102-000000-bbbb', 'frame' => 9, 'held' => [1] }])
    assert_equal Koholint::Souvenirs.digest([entry]), Koholint::Souvenirs.digest([later])
    refute_equal Koholint::Souvenirs.digest([entry]), Koholint::Souvenirs.digest([entry.merge('entity' => 65)])
  end

  def test_the_committed_file_is_a_rebuild_of_the_archived_bundles
    assert_equal Koholint::Souvenirs.build, Koholint::Souvenirs.load
  end

  def test_resume_refuses_a_run_recorded_with_other_souvenirs_and_comparisons_refuse_mixed_digests
    entry = { 'place' => HUT, 'entity' => 64, 'cell' => [4, 4], 'text' => NEED, 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [] }] }
    data = { 'runs' => { '20261101-000000-aaaa' => nil }, 'texts' => [entry] }
    Dir.mktmpdir do |dir|
      recorded = Koholint::Souvenirs.record(before: '20261102-000000-bbbb', data:)
      run = Koholint::Run.new(dir, { 'souvenirs' => recorded })
      run.check_souvenirs!(data)
      run.check_souvenirs!(data.merge('texts' => [entry, entry.merge('text' => 'later', 'seen' => [{ 'run' => '20261103-000000-cccc', 'frame' => 1, 'held' => [] }])],
                                      'runs' => data['runs'].merge('20261103-000000-cccc' => nil)))
      assert_raises(Koholint::Run::SouvenirsMismatch) { run.check_souvenirs!(data.merge('texts' => [])) }
      Koholint::Run.new(dir, { 'souvenirs' => false }).check_souvenirs!(data.merge('texts' => []))
      Koholint::Souvenirs.comparable!([{ 'souvenirs' => recorded }, { 'souvenirs' => recorded }])
      assert_raises(Koholint::Error) { Koholint::Souvenirs.comparable!([{ 'souvenirs' => recorded }, { 'souvenirs' => false }]) }
    end
  end

  class OpenGrid
    def passable(*) = :yes
    def static_sprite(*) = nil
  end

  def menu(souvenirs:, talk_log: Koholint::TalkLog.new, items: [1, 4, 12], log: explore_log)
    Koholint::Candidates.build(place: [1, 0], grid: OpenGrid.new, explore_log: log, talk_log:, leads: Koholint::Leads.new,
                               cards: { HUT => { people: [{ type: 64, cell: [4, 4] }], held: [1, 4] } },
                               stamp: Koholint::Dialogues.stamp(milestone: :sword, items:, leads: 0), souvenirs:, item_names: { 12 => ['Champignon'] })
  end

  def explore_log
    log = Koholint::ExploreLog.new
    log.absorb({ from: { room: 1, map: 0 }, exits: [{ row: 0, col: 5, direction: :up, outcome: :left, to: HUT }] })
    log
  end

  def remembered(held: [1, 4], place: HUT) = [{ 'place' => place, 'entity' => 64, 'cell' => [4, 4], 'text' => NEED, 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => held }] }]

  def test_a_souvenir_naming_a_held_item_replaces_the_candidate_for_that_person_and_nothing_else
    none = menu(souvenirs: [])
    before = menu(souvenirs: remembered)
    souvenir = before.find { |candidate| candidate[:id] == 'souvenir-3-0-t64' }
    assert_match(/holding the Champignon: a souvenir of another playthrough, never heard in this one: « .*Champignon de la forêt\. »/, souvenir[:label])
    assert_equal({ kind: 'person', place: HUT, type: 64, cell: [4, 4], try: true, item: 12, name: 'Champignon' }, souvenir[:target])
    assert_equal none.map { |candidate| candidate[:id] == 'person-3-0-t64' ? 'souvenir-3-0-t64' : candidate[:id] }, before.map { |candidate| candidate[:id] }
    assert_equal none.reject { |candidate| candidate[:id] == 'person-3-0-t64' }, before.reject { |candidate| candidate[:id] == 'souvenir-3-0-t64' }
  end

  def test_no_souvenir_without_the_item_a_route_or_once_the_lineage_heard_it_or_talked_holding_the_item
    ids = ->(**over) { menu(**over).map { |candidate| candidate[:id] }.grep(/souvenir/) }
    assert_equal %w[souvenir-3-0-t64], ids.(souvenirs: remembered)
    assert_empty ids.(souvenirs: remembered, items: [1, 4]), 'not holding the item'
    assert_empty ids.(souvenirs: remembered(held: [1, 4, 12])), 'the reader already held it'
    assert_empty ids.(souvenirs: remembered(place: [9, 0])), 'no route of this lineage reaches it'
    heard = Koholint::TalkLog.new
    heard.remember(place: HUT, cell: [4, 4], text: NEED, stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0), entity: 64)
    assert_empty ids.(souvenirs: remembered, talk_log: heard), 'this lineage read it: it is memory, not a souvenir'
    holding = Koholint::TalkLog.new
    holding.remember(place: HUT, cell: [4, 4], text: 'Hi hi hi!', stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12], leads: 0), entity: 64)
    assert_empty ids.(souvenirs: remembered, talk_log: holding), 'talked to holding the item'
    plural = remembered.map { |entry| entry.merge('text' => 'Tarkin est parti chercher des champignons.') }
    assert_empty ids.(souvenirs: plural), 'whole words only'
  end
end
