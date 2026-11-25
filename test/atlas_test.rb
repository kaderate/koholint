require_relative 'test_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'koholint/atlas'
require 'koholint/cli'

class AtlasTest < Minitest::Test
  RUNS = File.expand_path('../runs', __dir__)
  SWORD = '20261111-194737-9ba1'.freeze
  VAL = '20261120-151729-2ce4'.freeze
  VAL_PARENT = '20261114-093702-a0dc'.freeze
  VAL_FORK = 90_638

  def with_root(*ids, parent: false)
    Dir.mktmpdir do |root|
      ids.each { |id| FileUtils.cp_r(File.join(RUNS, id), root) }
      if parent
        FileUtils.mkdir_p(File.join(root, VAL_PARENT))
        File.write(File.join(root, VAL_PARENT, 'manifest.json'), JSON.generate('flow_version' => 'flow-65'))
        File.write(File.join(root, VAL_PARENT, 'trace.jsonl'), '')
      end
      yield root
    end
  end

  def atlas_of(*ids, parent: false) = with_root(*ids, parent:) { |root| Koholint::Atlas.build([root]) }

  def place(atlas, label) = atlas[:places].find { |entry| entry[:label] == label }

  def test_overworld_screens_carry_their_map_label_and_interiors_their_ids
    assert_equal 'B10', Koholint::Atlas.label([145, 0])
    assert_equal 'A1', Koholint::Atlas.label([0, 0])
    assert_equal 'P16', Koholint::Atlas.label([255, 0])
    assert_equal '189/10', Koholint::Atlas.label([189, 10])
  end

  def test_a_fork_counts_only_its_events_from_the_fork_frame_when_its_parent_is_read
    events = Koholint::Trace.read(File.join(RUNS, VAL, 'trace.jsonl'))
    own = events.select { |e| e['type'] == 'decision' && e['frame'] >= VAL_FORK }
    alone = atlas_of(VAL)
    forked = atlas_of(VAL, parent: true)
    assert_equal 2, forked[:runs]
    assert_in_delta own.sum { |e| e['cost_usd'].to_f }, forked[:totals][:dollars], 0.01
    assert_equal events.map { |e| e['frame'] }.max - VAL_FORK, forked[:totals][:frames]
    assert_in_delta alone[:totals][:dollars], forked[:totals][:dollars], 0.001
    assert_operator alone[:totals][:overworld], :>, forked[:totals][:overworld]
  end

  def test_heat_counts_where_link_stood_in_the_runs_own_events_and_sums_across_runs
    heat = ->(atlas) { atlas[:places].sum { |entry| entry[:heat].sum } }
    alone = atlas_of(VAL)
    assert_operator heat.(atlas_of(VAL, parent: true)), :<, heat.(alone)
    assert_equal heat.(atlas_of(SWORD)) + heat.(alone), heat.(atlas_of(SWORD, VAL))
    assert(alone[:places].all? { |entry| entry[:heat].size == Koholint::Atlas::HEAT_COLS * Koholint::Atlas::HEAT_ROWS })
  end

  def test_places_merge_across_runs_with_first_visit_and_counts
    atlas = atlas_of(SWORD, VAL)
    assert_equal 2, atlas[:runs]
    assert_equal VAL, atlas[:last_run]
    house = place(atlas, '163/16')
    assert_equal ['C11'], house[:opens_from]
    assert_equal SWORD, house[:first][:run]
    assert_equal 2, house[:runs]
    assert_operator house[:texts].size, :>, 0
    assert(house[:texts].all? { |text| text[:run] && text[:frame] })
    assert_equal atlas[:places].count { |entry| entry[:grid] }, atlas[:totals][:overworld]
  end

  def test_the_open_puzzle_names_screens_by_label
    puzzle = place(atlas_of(VAL), 'B6')[:puzzles].first
    assert_equal({ kind: 'unexpected_arrival', way: 'up', expected: 'B5', observed: 'D7' }, puzzle.slice(:kind, :way, :expected, :observed))
  end

  def test_a_place_name_is_kept_only_with_a_text_read_there_that_carries_it
    atlas = atlas_of(SWORD, VAL)
    named = atlas[:places].flat_map { |entry| entry[:names] }
    refute_empty named
    named.each do |name|
      words = Koholint::Atlas.fold(name[:name]).scan(/\p{L}+/).select { |word| word.length >= Koholint::Atlas::NAME_WORD }
      assert(words.any? { |word| Koholint::Atlas.fold(name[:source][:text]).include?(word) }, name[:name])
    end
    assert_operator atlas[:totals][:names_withheld], :>, 0
  end

  def test_the_source_must_share_a_word_of_the_name
    talks = [{ text: 'Bienvenue à la Forêt Enchantée', frame: 3 }]
    assert_equal 3, Koholint::Atlas.source_text('Foret enchantee', talks)[:frame]
    assert_nil Koholint::Atlas.source_text('Fishing pond', talks)
    assert_nil Koholint::Atlas.source_text('Hut', talks)
  end

  def test_exits_join_neighbours_or_doors_only
    exits = atlas_of(VAL)[:places].flat_map { |entry| entry[:exits].map { |exit| exit[:way] } }.uniq
    assert_empty exits - %w[up down left right door]
  end

  def test_untried_people_have_no_try_and_unknown_types_count_apart_without_enemies
    atlas = atlas_of(SWORD, VAL)
    atlas[:places].each do |entry|
      tried = entry[:tried].map { |t| t[:type] }
      assert_empty entry[:untried] & tried
      assert_empty entry[:untried] - entry[:seen].fetch('people', [])
      assert_empty entry[:unknown_untried] & (tried | entry[:seen].fetch('enemies', []) | entry[:seen].fetch('creatures', []))
    end
    house = place(atlas, '163/16')[:tried].find { |t| t[:type] == 62 }
    assert_operator house[:tries], :>=, house[:answered]
    assert_operator house[:answered], :>, 0
  end

  def test_a_digest_is_plain_data_holding_no_events
    digest = Koholint::Atlas.digest(File.join(RUNS, VAL))
    assert Marshal.dump(digest)
  end

  def test_cost_counts_each_fork_from_its_fork_frame_even_without_its_parent
    events = Koholint::Trace.read(File.join(RUNS, VAL, 'trace.jsonl'))
    own = events.select { |e| e['type'] == 'decision' && e['frame'] >= VAL_FORK }.sum { |e| e['cost_usd'].to_f }
    alone = atlas_of(VAL)
    assert_in_delta own, alone[:totals][:dollars], 0.01
    assert_equal events.map { |e| e['frame'] }.max - VAL_FORK, alone[:totals][:frames]
  end

  def test_a_respawn_after_a_death_is_no_way_even_onto_a_neighbour
    Dir.mktmpdir do |root|
      dir = File.join(root, 'r1')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-80'))
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      state = { 'game_mode' => 0x0B, 'game_submode' => 7, 'room_id' => 101, 'map_id' => 0 }
      trace.emit(:perception, frame: 10, state:, state_hash: 'h')
      trace.emit(:notable, frame: 20, kind: 'death', detail: 'game over: save and continue')
      trace.emit(:perception, frame: 30, state: state.merge('room_id' => 100), state_hash: 'h')
      trace.emit(:perception, frame: 40, state: state.merge('room_id' => 101), state_hash: 'h')
      trace.emit(:perception, frame: 50, state: state.merge('room_id' => 112), state_hash: 'h')
      atlas = Koholint::Atlas.build([root])
      assert_equal 1, place(atlas, 'F7')[:deaths]
      assert_empty place(atlas, 'F7')[:exits]
      assert_equal [{ way: 'right', to: 'F7', count: 1 }], place(atlas, 'E7')[:exits]
      assert_empty place(atlas, 'A8')[:exits]
    end
  end

  def test_left_and_right_stay_in_one_row
    assert_equal 'right', Koholint::Atlas.way([14, 0], [15, 0])
    assert_nil Koholint::Atlas.way([15, 0], [16, 0])
    assert_nil Koholint::Atlas.way([16, 0], [15, 0])
    assert_equal 'door', Koholint::Atlas.way([162, 0], [163, 16])
  end

  def test_types_sort_with_mixed_kinds
    assert_equal [5, 40, 'npc'], Koholint::Atlas.order(['npc', 40, 5])
  end

  def test_leads_merge_by_quote_with_their_best_status_and_first_reading
    atlas = atlas_of(SWORD, VAL)
    keys = atlas[:leads].map { |lead| Koholint::Dialogues.key(lead[:quote]) }
    assert_equal keys.uniq, keys
    owl = atlas[:leads].find { |lead| lead[:quote].include?('Viens me voir dans la Forêt') }
    assert_equal 'tested', owl[:status]
    assert_equal 'C16', owl[:place]
    assert_operator owl[:achieved], :>, 0
    assert(atlas[:leads].all? { |lead| lead[:first][:run] && lead[:runs].between?(1, 2) && Koholint::Atlas::STATUSES.include?(lead[:status]) })
    contact = atlas[:leads].select { |lead| lead[:contact] }
    refute_empty contact
    assert(contact.all? { |lead| lead[:claim].start_with?('Contact with') })
  end

  def test_a_fork_reads_only_the_leads_of_its_own_segment_when_its_parent_is_read
    with_root(VAL, parent: true) do |root|
      events = Koholint::Trace.read(File.join(RUNS, VAL, 'trace.jsonl'))
      own = events.count { |e| e['type'] == 'lead' && e['frame'] >= VAL_FORK }
      assert_equal own, Koholint::Atlas.build([root])[:leads].size
    end
  end

  def test_flows_sum_their_runs_and_place_each_first_reach_once
    atlas = atlas_of(SWORD, VAL)
    assert_equal %w[inherited flow-37 flow-78], atlas[:flows].map { |flow| flow[:flow] }
    assert_in_delta atlas[:totals][:dollars], atlas[:flows].sum { |flow| flow[:dollars] }, 0.02
    assert_equal atlas[:totals][:texts], atlas[:flows].sum { |flow| flow[:texts] }
    inherited = atlas[:flows].first
    assert_equal [0, 0, 0.0], inherited.values_at(:runs, :frames, :dollars)
    first = atlas[:places].to_h { |place| [place[:label], place[:first]] }
    forks = { SWORD => 52_200, VAL => VAL_FORK }
    inherited[:screens].each { |label| assert_operator first[label][:frame], :<, forks.fetch(first[label][:run]) }
    atlas[:flows].drop(1).flat_map { |flow| flow[:screens] }.each { |label| assert_operator first[label][:frame], :>=, forks.fetch(first[label][:run]) }
    assert_equal atlas[:totals][:overworld], atlas[:flows].sum { |flow| flow[:screens].size }
    assert_equal atlas[:totals][:interiors], atlas[:flows].sum { |flow| flow[:interiors].size }
    assert_equal atlas[:leads].size, atlas[:flows].sum { |flow| flow[:leads] }
    assert_equal ['shield'], inherited[:items]
    assert_equal ['sword'], atlas[:flows][1][:items]
  end

  def test_facts_list_every_data_file_with_status_checks_and_provenance
    facts = Koholint::Atlas.facts
    assert_equal Koholint::Atlas::FACTS.map { |name| "data/#{name}.json" }, facts.reject { |file| file[:skipped] }.map { |file| file[:file] }
    facts.each do |file|
      refute_empty file[:rows], file[:file]
      assert_equal file[:rows].size, file[:statuses].values.sum
      assert(file[:rows].all? { |row| row[:label] && row[:source] }, file[:file])
    end
    addresses = facts.find { |file| file[:file] == 'data/addresses.json' }
    data = JSON.parse(File.read(File.join(Koholint::Atlas::DATA, 'addresses.json')))
    assert_equal data.map { |entry| entry['confidence'] }.tally, addresses[:statuses]
    exits = facts.find { |file| file[:file] == 'data/exits.json' }[:rows]
    assert_includes exits.map { |row| row[:label] }, 'B6 up → D7'
    capabilities = JSON.parse(File.read(File.join(Koholint::Atlas::DATA, 'capabilities.json')))
    rows = facts.find { |file| file[:file] == 'data/capabilities.json' }[:rows]
    assert_equal(capabilities.map { |entry| Koholint::Capabilities.success_places(entry).size }, rows.map { |row| row[:verified_count] })
    assert(rows.all? { |row| row[:derived] })
  end

  def test_facts_read_a_given_directory_and_skip_missing_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'items.json'), JSON.generate([{ 'id' => 4, 'name' => 'shield', 'source' => 'probe', 'confidence' => 'hypothesis', 'verified_count' => 1 }]))
      assert_equal [{ file: 'data/items.json', rows: [{ label: '4 shield', status: 'hypothesis', verified_count: 1, source: 'probe', note: nil }], statuses: { 'hypothesis' => 1 } }],
                   Koholint::Atlas.facts(dir)
    end
  end

  def test_a_broken_data_file_is_listed_with_its_error_and_the_others_still_read
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'addresses.json'), '')
      File.write(File.join(dir, 'entities.json'), JSON.generate({ 'type' => 3 }))
      File.write(File.join(dir, 'items.json'), JSON.generate([{ 'id' => 4, 'name' => 'shield', 'source' => 'probe', 'confidence' => 'hypothesis', 'verified_count' => 1 }]))
      File.write(File.join(dir, 'music.json'), '[]')
      facts = Koholint::Atlas.facts(dir).to_h { |file| [file[:file], file] }
      assert_match(/ParserError/, facts['data/addresses.json'][:error])
      assert facts['data/entities.json'][:error]
      assert_equal 1, facts['data/items.json'][:rows].size
      assert facts['data/music.json'][:skipped]
    end
  end

  def test_a_nested_confidence_shows_next_to_its_entry
    rows = Koholint::Atlas.facts.find { |file| file[:file] == 'data/entities.json' }[:rows]
    mixed = rows.find { |row| row[:status] == 'verified' && row[:subfacts]&.any? { |sub| sub[:status] == 'hypothesis' } }
    assert_equal 'sword_hits', mixed[:subfacts].first[:name]
  end

  def test_a_root_with_no_run_is_an_error
    Dir.mktmpdir do |root|
      err = StringIO.new
      assert_equal 1, Koholint::CLI.run(['atlas', '--root', File.join(root, 'nothing')], out: StringIO.new, err:)
      assert_match(/no runs under/, err.string)
    end
  end

  def test_screenshots_come_from_a_run_that_has_one
    atlas = atlas_of(SWORD, VAL)
    shot = atlas[:places].find { |entry| entry[:screen] }
    assert shot
    assert_includes [SWORD, VAL], shot[:screen]
  end

  def test_the_command_writes_the_atlas_and_prints_totals
    with_root(SWORD) do |root|
      Dir.mktmpdir do |work|
        out = StringIO.new
        Dir.chdir(work) { assert_equal 0, Koholint::CLI.run(['atlas', '--root', root], out:) }
        assert_match(/atlas: 1 runs from #{Regexp.escape(root)} \(0 unreadable\), last #{SWORD}/, out.string)
        assert_match(/wrote tmp\/atlas.json/, out.string)
        assert_match(/facts: \d+ entries in 11 data files, \d+ verified/, out.string)
        assert_equal 1, JSON.parse(File.read(File.join(work, Koholint::Atlas::OUT)))['runs']
      end
    end
  end

  def test_an_unreadable_run_is_counted_and_skipped
    with_root(SWORD) do |root|
      FileUtils.mkdir_p(File.join(root, 'broken'))
      File.write(File.join(root, 'broken', 'manifest.json'), '{')
      atlas = Koholint::Atlas.build([root])
      assert_equal 1, atlas[:runs]
      assert_equal 1, atlas[:unreadable]
    end
  end
end
