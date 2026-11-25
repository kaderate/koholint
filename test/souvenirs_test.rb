require_relative 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'zlib'
require 'koholint/candidates'
require 'koholint/explore_log'
require 'koholint/leads'
require 'koholint/run'
require 'koholint/souvenirs'
require 'koholint/talk_log'

class SouvenirsTest < Minitest::Test
  HUT = [3, 0].freeze
  NEED = "C' est une perte de temps! Pour ma poudre, il me faut le Champignon de la forêt.".freeze

  def bundle(root, id, events, parent: nil, sealed: true)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate({ 'flow_version' => 'flow-1', 'parent' => parent }))
    lines = events.map { |event| "#{JSON.generate(event)}\n" }.join
    return File.write(File.join(dir, 'trace.jsonl'), lines) unless sealed

    Zlib::GzipWriter.open(File.join(dir, 'trace.jsonl.gz')) { |gz| gz.write(lines) }
    File.write(File.join(dir, 'summary.json'), '{}')
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
      bundle(root, '20261103-000000-cccc', talk(10, 'Je joue encore.', type: 71), sealed: false)
      data = Koholint::Souvenirs.build([root])
      need = data['texts'].find { |entry| entry['entity'] == 64 }
      assert_equal HUT, need['place']
      assert_equal [{ 'run' => '20261101-000000-aaaa', 'frame' => 100, 'held' => [1, 4], 'cell' => [4, 4], 'text' => NEED },
                    { 'run' => '20261102-000000-bbbb', 'frame' => 250, 'held' => [1, 4, 12], 'cell' => [4, 4], 'text' => NEED }], need['seen']
      assert_equal({ '20261101-000000-aaaa' => nil, '20261102-000000-bbbb' => ['20261101-000000-aaaa', 200] }, data['runs'], 'a run still playing is no bundle')
      assert_equal 2, data['texts'].size
    end
  end

  # aaaa from boot; bbbb and cccc fork it at 200 (one batch); eeee forks cccc (a grandchild of the batch); ffff forks aaaa later, at 300.
  RUNS = { '20261101-000000-aaaa' => nil, '20261102-000000-bbbb' => ['20261101-000000-aaaa', 200], '20261102-000001-cccc' => ['20261101-000000-aaaa', 200],
           '20261102-000002-eeee' => ['20261102-000001-cccc', 50], '20261102-000003-ffff' => ['20261101-000000-aaaa', 300],
           '20261102-000004-gggg' => ['20261101-000000-aaaa', 100], '20261103-000000-dddd' => nil }.freeze

  def sighting(run, cell: [1, 1]) = { 'run' => run, 'frame' => 1, 'held' => [], 'cell' => cell, 'text' => "text #{run[-4..]}" }

  def test_a_run_remembers_only_runs_created_before_its_parent_and_never_its_parents_sibling_arms_nor_their_forks
    data = { 'runs' => RUNS, 'texts' => RUNS.keys.each_with_index.map { |run, index| { 'place' => HUT, 'entity' => 60 + index, 'seen' => [sighting(run)] } } }
    remembered = ->(**filter) { Koholint::Souvenirs.for_run(data, **filter).map { |entry| entry['text'] } }
    assert_equal ['text aaaa', 'text bbbb'], remembered.(before: '20261102-000001-cccc')
    assert_equal ['text aaaa', 'text gggg'], remembered.(before: '20261103-000000-dddd', batch: ['20261101-000000-aaaa', 200]),
                 'the batch, its grandchild and a later fork of the same run are out; an earlier fork is another branch'
    assert_equal [], remembered.(before: nil)
  end

  def test_text_and_cell_come_from_the_earliest_sighting_the_run_may_use
    entry = { 'place' => HUT, 'entity' => 64, 'seen' => [sighting('20261102-000000-bbbb', cell: [2, 2]), sighting('20261102-000004-gggg', cell: [5, 5])] }
    kept = Koholint::Souvenirs.for_run({ 'runs' => RUNS, 'texts' => [entry] }, before: '20261103-000000-dddd', batch: ['20261101-000000-aaaa', 200]).first
    assert_equal ['text gggg', [5, 5]], kept.values_at('text', 'cell')
  end

  def test_the_digest_covers_what_play_reads_never_run_ids_or_frames
    entry = { 'place' => HUT, 'entity' => 64, 'cell' => [4, 4], 'text' => NEED, 'seen' => [{ 'run' => '20261101-000000-aaaa', 'frame' => 1, 'held' => [1] }] }
    digest = ->(change) { Koholint::Souvenirs.digest([entry.merge(change)]) }
    assert_equal digest.({}), digest.('seen' => [{ 'run' => '20261102-000000-bbbb', 'frame' => 9, 'held' => [1] }])
    refute_equal digest.({}), digest.('entity' => 65)
    refute_equal digest.({}), digest.('cell' => [3, 3])
    refute_equal digest.({}), digest.('seen' => entry['seen'] + [{ 'run' => '20261102-000000-bbbb', 'frame' => 9, 'held' => [] }]), 'a reader not holding it changes eligibility'
  end

  def test_the_committed_file_is_a_rebuild_of_the_archived_bundles
    assert_equal Koholint::Souvenirs.build, Koholint::Souvenirs.load
  end

  def test_resume_refuses_a_run_recorded_with_other_souvenirs_and_comparisons_refuse_mixed_digests
    entry = { 'place' => HUT, 'entity' => 64, 'seen' => [sighting('20261101-000000-aaaa')] }
    data = { 'runs' => { '20261101-000000-aaaa' => nil }, 'texts' => [entry] }
    Dir.mktmpdir do |dir|
      recorded = Koholint::Souvenirs.record(before: '20261102-000000-bbbb', data:)
      run = Koholint::Run.new(dir, { 'souvenirs' => recorded })
      run.check_souvenirs!(data)
      run.check_souvenirs!(data.merge('texts' => [entry, entry.merge('entity' => 65, 'seen' => [sighting('20261103-000000-cccc')])],
                                      'runs' => data['runs'].merge('20261103-000000-cccc' => nil)))
      assert_raises(Koholint::Run::SouvenirsMismatch) { run.check_souvenirs!(data.merge('texts' => [])) }
      Koholint::Run.new(dir, { 'souvenirs' => false }).check_souvenirs!(data.merge('texts' => []))
      Koholint::Souvenirs.comparable!([{ 'souvenirs' => recorded }, { 'souvenirs' => recorded }])
      assert_raises(Koholint::Error) { Koholint::Souvenirs.comparable!([{ 'souvenirs' => recorded }, { 'souvenirs' => false }]) }
    end
  end

  def test_create_and_fork_record_their_cutoff_and_batch
    Dir.mktmpdir do |root|
      rom = File.join(root, 'rom.gbc')
      File.write(rom, 'rom')
      parent = Koholint::Run.create(root:, flow_version: 'flow-x', budget: {}, rom_path: rom)
      assert_equal({ 'before' => parent.id, 'batch' => nil }, parent.manifest['souvenirs'].slice('before', 'batch'))
      child = parent.fork(at_frame: 0, flow_version: 'flow-x', rom_path: rom)
      assert_equal({ 'before' => parent.id, 'batch' => nil }, child.manifest['souvenirs'].slice('before', 'batch'))
      grandchild = child.fork(at_frame: 0, flow_version: 'flow-x', rom_path: rom)
      assert_equal({ 'before' => child.id, 'batch' => [parent.id, 0] }, grandchild.manifest['souvenirs'].slice('before', 'batch'))
      assert_equal Koholint::Souvenirs.record(before: child.id, batch: [parent.id, 0])['digest'], grandchild.manifest['souvenirs']['digest']
      refute child.fork(at_frame: 0, flow_version: 'flow-x', rom_path: rom, souvenirs: false).manifest['souvenirs']
    end
  end

  class OpenGrid
    def passable(*) = :yes
    def static_sprite(*) = nil
  end

  def menu(souvenirs:, talk_log: Koholint::TalkLog.new, items: [1, 4, 12], log: explore_log, item_names: { 12 => ['Champignon'] })
    Koholint::Candidates.build(place: [1, 0], grid: OpenGrid.new, explore_log: log, talk_log:, leads: Koholint::Leads.new,
                               cards: { HUT => { people: [{ type: 64, cell: [4, 4] }], held: [1, 4] } },
                               stamp: Koholint::Dialogues.stamp(milestone: :sword, items:, leads: 0), souvenirs:, item_names:)
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

  def test_a_souvenir_replaces_a_need_candidate_for_the_same_person
    leads = Koholint::Leads.new
    talk_log = Koholint::TalkLog.new
    asked = 'Il me faut une chose de la forêt, tu sais.'
    talk_log.remember(place: HUT, cell: [4, 4], text: asked, stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4], leads: 0), entity: 64)
    leads.absorb([{ 'quote' => asked, 'claim' => 'asks for a thing', 'importance' => 'high', 'need' => true }], transcription: asked, place: HUT, source: { row: 4, col: 4, entity: 64 })
    build = ->(souvenirs) { Koholint::Candidates.build(place: [1, 0], grid: OpenGrid.new, explore_log:, talk_log:, leads:, souvenirs:, item_names: {},
                                                       stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12], leads: 1)).map { |c| c[:id] } }
    none = build.([])
    assert_includes none, 'need-3-0-t64'
    assert_equal none.map { |id| id == 'need-3-0-t64' ? 'souvenir-3-0-t64' : id }, build.(remembered)
  end

  def test_a_souvenir_replaces_an_unidentified_thing_here
    entities = [{ type: 64, kind: 'unknown', cell: [4, 4] }]
    build = ->(souvenirs) { Koholint::Candidates.build(place: HUT, grid: OpenGrid.new, explore_log:, talk_log: Koholint::TalkLog.new, leads: Koholint::Leads.new, entities:,
                                                       souvenirs:, item_names: {}, stamp: Koholint::Dialogues.stamp(milestone: :sword, items: [1, 4, 12], leads: 0)).map { |c| c[:id] } }
    none = build.([])
    assert_includes none, 'examine-4-4'
    assert_equal none.map { |id| id == 'examine-4-4' ? 'souvenir-3-0-t64' : id }, build.(remembered)
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
    assert_equal %w[souvenir-3-0-t64], ids.(souvenirs: remembered, item_names: {}), 'a name from an observed pickup text in data/items.json'
    boomerang = remembered.map { |entry| entry.merge('text' => 'Rapporte-moi le boomerang, petit.') }
    assert_empty ids.(souvenirs: boomerang, items: [1, 4, 13], item_names: {}), 'a name from general knowledge never matches'
    plural = remembered.map { |entry| entry.merge('text' => 'Tarkin est parti à la champignonnière.') }
    assert_empty ids.(souvenirs: plural), 'whole words only'
  end
end
