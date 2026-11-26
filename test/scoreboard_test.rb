require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'koholint'
require 'koholint/checkpoints'
require 'koholint/trace'
require_relative '../tools/scoreboard/alert'
require_relative '../tools/scoreboard/debt'
require_relative '../tools/scoreboard/measure'
require_relative '../tools/scoreboard/run'
require_relative '../tools/scoreboard/runs'

class ScoreboardTest < Minitest::Test
  STATE = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'sword', 'game_mode' => 0x0B, 'game_submode' => 7, 'item_a' => 1, 'item_b' => 4,
            'inventory' => Array.new(10, 0) }.freeze

  def decision(trace, frame, agent: 'claude', hp: 24, usd: 0.1, why: 'x')
    trace.emit(:decision, frame:, decision_point: 'choose_skill', input: { 'hp' => hp }, options: [], choice: {}, justification: why, confidence: 1.0, agent:, latency_ms: 0, cost_usd: usd)
  end

  def perceive(trace, frame, room, **state) = trace.emit(:perception, frame:, state: STATE.merge('room_id' => room, 'map_id' => 0, **state), state_hash: 'h')

  def make_run(root, id, parent: nil, dirty: false, tag: 'scoreboard-boot')
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', 'tag' => tag, 'harness_sha' => 'abcdef123', 'harness_dirty' => dirty, **(parent ? { 'parent' => parent } : {})))
    trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    yield trace if block_given?
    dir
  end

  def played(root, id = '20261126-000001-aaaa', **options)
    make_run(root, id, **options) do |trace|
      perceive(trace, 10, 1)
      perceive(trace, 50, 2)
      decision(trace, 60, usd: 0.2)
      decision(trace, 70, hp: 6, usd: 0.3)
      decision(trace, 80, agent: 'delegated', usd: 0, why: 'autopilot: fight type 27')
      trace.emit(:item_gained, frame: 90, item: 4, name: 'shield', place: [2, 0], held: [4])
      trace.emit(:notable, frame: 100, kind: 'death', detail: 'x')
      perceive(trace, 5000, 3)
      perceive(trace, 9500, 3, 'inventory' => [12] + Array.new(9, 0))
      trace.emit(:stop, frame: 10_000, reason: 'dollars')
    end
  end

  def test_measure_reads_the_progress_vector_cost_deaths_stalls_and_rules
    Dir.mktmpdir do |root|
      result = Scoreboard::Measure.run(played(root))
      assert_equal 3, result[:progress][:places_seen]
      assert_equal 'sword', result[:progress][:highest_milestone]
      assert_nil result[:progress][:instruments]
      assert_nil result[:progress][:dungeons]
      assert_equal %w[sword shield mushroom?], result[:progress][:key_items].map { |item| item[:name] }
      assert_equal({ usd: 0.5, calls: 2, calls_per_1000f: 0.2, calls_at_one_heart: 1 }, result[:cost])
      assert_equal [1, 0.1], [result[:deaths], result[:deaths_per_1000f]]
      assert_equal [3, 6.0], [result[:new_places], result[:new_places_per_usd]]
      assert_equal({ count: 2, longest_frames: 5000 }, result[:stalls])
      assert_equal({ 'fight on sight (90/100)' => 1 }, result[:rules])
      assert_equal ['shield'], result[:items_gained]
      assert_equal false, result[:harness_dirty]
    end
  end

  def with_catalogues(places, items)
    place_kinds = Koholint::PlaceKinds.method(:catalogue)
    item_catalogue = Koholint::Items.method(:catalogue)
    Koholint::PlaceKinds.define_singleton_method(:catalogue) { places }
    Koholint::Items.define_singleton_method(:catalogue) { items }
    yield
  ensure
    Koholint::PlaceKinds.define_singleton_method(:catalogue, place_kinds)
    Koholint::Items.define_singleton_method(:catalogue, item_catalogue)
  end

  def test_dungeons_entered_and_their_optional_key_come_only_from_catalogued_data_and_gain_events
    items = { 50 => { 'id' => 50, 'name' => 'small key', 'confidence' => 'observed' } }
    Dir.mktmpdir do |root|
      dir = make_run(root, '20261126-000003-cccc') do |trace|
        perceive(trace, 10, 1)
        trace.emit(:perception, frame: 20, state: STATE.merge('room_id' => 9, 'map_id' => 7), state_hash: 'h')
        trace.emit(:perception, frame: 30, state: STATE.merge('room_id' => 4, 'map_id' => 8), state_hash: 'h')
        trace.emit(:item_gained, frame: 40, item: 50, name: 'small key', place: [4, 8], held: [50])
        trace.emit(:stop, frame: 50, reason: 'frames')
      end
      with_catalogues({ 7 => { 'kind' => 'dungeon' }, 8 => { 'kind' => 'dungeon' } }, items) do
        progress = Scoreboard::Measure.run(dir)[:progress]
        assert_equal 2, progress[:dungeons]
        assert_equal({ '7' => false, '8' => true }, progress[:dungeon_keys])
      end
      with_catalogues({}, items) { assert_nil Scoreboard::Measure.run(dir)[:progress][:dungeon_keys] }
    end
  end

  def test_a_fork_counts_places_before_its_parent_frame_as_seen_and_costs_only_its_own_segment
    Dir.mktmpdir do |root|
      dir = make_run(root, '20261126-000002-bbbb', parent: { 'id' => 'p', 'frame' => 100 }) do |trace|
        perceive(trace, 10, 1)
        decision(trace, 50, usd: 9.0)
        perceive(trace, 120, 1)
        perceive(trace, 130, 2)
        decision(trace, 140, usd: 0.4)
        trace.emit(:stop, frame: 200, reason: 'frames')
      end
      result = Scoreboard::Measure.run(dir)
      assert_equal [100, 0.4, 1], [result[:frames], result[:cost][:usd], result[:new_places]]
      assert_equal 2, result[:progress][:places_seen]
    end
  end

  def test_the_table_lists_a_row_per_run
    Dir.mktmpdir do |root|
      table = Scoreboard::Measure.table([Scoreboard::Measure.run(played(root))])
      assert_match(/\A\| run \| flow \|.*\n\|---/, table)
      assert_includes table, '| 20261126-000001-aaaa | flow-9 | 10000 | 0.5 |'
    end
  end

  def test_the_supervisor_stops_on_deaths_a_stall_or_the_wall_clock
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'trace.jsonl')
      trace = Koholint::Trace.new(path)
      perceive(trace, 100, 1)
      watch = ->(**limits) { Scoreboard::Run::Supervisor.new(trace: path, max_seconds: 100, max_deaths: 2, stall: 4000, **limits) }
      supervisor = watch.call
      assert_nil supervisor.poll(1.0)
      trace.emit(:notable, frame: 200, kind: 'death', detail: 'x')
      assert_nil supervisor.poll(2.0)
      trace.emit(:notable, frame: 300, kind: 'death', detail: 'x')
      assert_equal 'deaths', supervisor.poll(3.0)
      assert_equal [300, 2], [supervisor.frame, supervisor.deaths]
      stalled = watch.call
      perceive(trace, 4100, 1)
      assert_equal 'deaths', stalled.poll(0.0)
      calm = Scoreboard::Run::Supervisor.new(trace: path, max_seconds: 100, max_deaths: 9, stall: 4000)
      assert_equal 'stall', calm.poll(0.0)
      assert_equal 'wall', Scoreboard::Run::Supervisor.new(trace: File.join(dir, 'none'), max_seconds: 10, max_deaths: 3, stall: 4000).poll(11.0)
    end
  end

  def test_a_play_runs_the_command_supervises_it_measures_it_and_appends_one_history_line
    Dir.mktmpdir do |root|
      fake = File.join(root, 'fake_koholint.rb')
      File.write(fake, <<~RUBY)
        require 'json'
        require 'fileutils'
        $LOAD_PATH.unshift(#{File.expand_path('../lib', __dir__).inspect})
        require 'koholint/trace'
        args = ARGV.dup
        abort 'unexpected command' unless args.shift == 'run'
        root = args[args.index('--root') + 1]
        dir = File.join(root, '20261126-010101-cccc')
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', 'tag' => args[args.index('--tag') + 1], 'harness_sha' => 'abc', 'harness_dirty' => false))
        trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
        trace.emit(:perception, frame: 5, state: { 'hp' => 24, 'milestone' => 'none', 'room_id' => 1, 'map_id' => 0, 'game_mode' => 11, 'game_submode' => 7, 'inventory' => [] }, state_hash: 'h')
        trace.emit(:decision, frame: 6, decision_point: 'x', input: { 'hp' => 24 }, options: [], choice: {}, justification: 'x', confidence: 1.0, agent: 'claude', latency_ms: 0, cost_usd: 1.0)
        trace.emit(:stop, frame: 7, reason: 'dollars')
        raise Interrupt if args.include?('--max-dollars') && args[args.index('--max-dollars') + 1] != '3.5'
      RUBY
      history = File.join(root, 'out', 'history.jsonl')
      repo = File.expand_path('..', __dir__)
      line = Scoreboard::Run.play(froms: ['boot'], root: File.join(root, 'runs'), koholint: fake, repo:, history:, day: '20261126', roots: [File.join(root, 'runs')],
                                  out: StringIO.new, budget: 3.5, poll: 0.05)
      assert_equal 1, File.readlines(history).size
      assert_equal line, JSON.parse(File.read(history))
      assert_equal ['boot'], line['froms']
      assert_equal [1.0, 'boot'], [line['usd'], line['primary']['from']]
      assert_equal 1, line['runs'].size
      assert_equal 'scoreboard-boot-20261126', line['runs'].first['tag']
      assert_operator line['branches'], :>, 0
    end
  end

  def test_a_checkpoint_run_forks_the_checkpoint_run_then_resumes_the_fork
    Dir.mktmpdir do |root|
      point = Koholint::Checkpoints.catalogue.fetch('post-gain-172')
      make_run(File.join(root, 'old'), point['run'])
      fake = File.join(root, 'fake.rb')
      File.write(fake, <<~RUBY)
        require 'json'
        require 'fileutils'
        $LOAD_PATH.unshift(#{File.expand_path('../lib', __dir__).inspect})
        require 'koholint/trace'
        args = ARGV.dup
        command = args.shift
        if command == 'fork'
          abort 'wrong parent' unless File.basename(args[0]) == #{point['run'].inspect} && args[args.index('--at-frame') + 1] == #{point['frame'].to_s.inspect}
          dir = File.join(args[args.index('--root') + 1], '20261126-020202-dddd')
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', 'tag' => args[args.index('--tag') + 1], 'parent' => { 'id' => #{point['run'].inspect}, 'frame' => #{point['frame']} }))
          puts "run \#{dir}"
        else
          abort 'wrong command' unless command == 'resume'
          trace = Koholint::Trace.new(File.join(args[0], 'trace.jsonl'))
          trace.emit(:decision, frame: #{point['frame'] + 5}, decision_point: 'x', input: { 'hp' => 24 }, options: [], choice: {}, justification: 'x', confidence: 1.0, agent: 'claude', latency_ms: 0, cost_usd: 0.5)
        end
      RUBY
      history = File.join(root, 'history.jsonl')
      line = Scoreboard::Run.play(froms: ['post-gain-172'], root: File.join(root, 'runs'), koholint: fake, repo: File.expand_path('..', __dir__), history:, day: '20261126',
                                  roots: [File.join(root, 'old')], out: StringIO.new, poll: 0.05)
      assert_equal [0.5, 'post-gain-172'], [line['usd'], line['primary']['from']]
      assert_equal [point['run'], point['frame']], line['runs'].first['parent'].values
    end
  end

  def fork_run(root, id)
    make_run(root, id, parent: { 'id' => 'p', 'frame' => 5000 }) do |trace|
      perceive(trace, 10, 1)
      3.times { |n| trace.emit(:notable, frame: 100 + n, kind: 'death', detail: 'x') }
      perceive(trace, 900, 2)
      perceive(trace, 5000, 3)
      perceive(trace, 5030, 1)
      yield trace if block_given?
    end
  end

  def test_a_fork_supervisor_ignores_the_parent_prefix_and_counts_from_the_fork_frame
    Dir.mktmpdir do |root|
      defaults = Scoreboard::Run::DEFAULTS
      watch = Scoreboard::Run.watcher(fork_run(root, '20261126-000005-aaaa'), defaults)
      assert_nil watch.poll(1.0)
      assert_equal [0, 5030], [watch.deaths, watch.frame]
      assert_equal 'stall', Scoreboard::Run.watcher(fork_run(root, '20261126-000005-bbbb') { |trace| perceive(trace, 9100, 1) }, defaults).poll(1.0)
      deaths = fork_run(root, '20261126-000005-cccc') { |trace| 3.times { |n| trace.emit(:notable, frame: 5040 + n, kind: 'death', detail: 'x') } }
      assert_equal 'deaths', Scoreboard::Run.watcher(deaths, defaults).poll(1.0)
    end
  end

  def fake_boot(root, create: true, hang: true, wait: 0)
    fake = File.join(root, 'fake_boot.rb')
    File.write(fake, <<~RUBY)
      require 'json'
      require 'fileutils'
      $LOAD_PATH.unshift(#{File.expand_path('../lib', __dir__).inspect})
      require 'koholint/trace'
      args = ARGV.dup
      File.write(#{File.join(root, 'pid').inspect}, Process.pid.to_s)
      File.open(#{File.join(root, 'budgets').inspect}, 'a') { |file| file.puts(args[args.index('--max-dollars') + 1]) }
      trap('INT') { exit }
      sleep #{wait}
      if #{create}
        dir = File.join(args[args.index('--root') + 1], "20261126-#{'#'}{Process.pid}")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', 'tag' => args[args.index('--tag') + 1]))
        Koholint::Trace.new(File.join(dir, 'trace.jsonl')).emit(:stop, frame: 7, reason: 'dollars')
      end
      sleep 60 if #{hang}
    RUBY
    fake
  end

  def gone?(pid)
    50.times do
      return true unless Scoreboard::Run.alive?(pid)

      sleep 0.1
    end
    false
  end

  def play(root, fake, **options)
    Scoreboard::Run.play(froms: ['boot'], root: File.join(root, 'runs'), koholint: fake, repo: File.expand_path('..', __dir__), history: File.join(root, 'history.jsonl'), day: '20261126',
                         roots: [File.join(root, 'runs')], out: StringIO.new, poll: 0.05, **options)
  end

  def test_the_budget_is_the_total_split_over_the_runs_and_the_daily_cap_refuses_a_start
    Dir.mktmpdir do |root|
      fake = fake_boot(root, hang: false)
      line = Scoreboard::Run.play(froms: %w[boot boot], root: File.join(root, 'runs'), koholint: fake, repo: File.expand_path('..', __dir__), history: File.join(root, 'history.jsonl'),
                                  day: '20261126', roots: [File.join(root, 'runs')], out: StringIO.new, poll: 0.05, budget: 3.0, jobs: 1)
      assert_equal %w[1.5 1.5], File.readlines(File.join(root, 'budgets'), chomp: true)
      assert_equal [3.0, 0.0], [line['budget'], line['overshoot']]
      File.write(File.join(root, 'history.jsonl'), JSON.generate('date' => Time.new(2026, 11, 26, 12).utc.iso8601, 'usd' => 18.0) + "\n")
      error = assert_raises(Scoreboard::Run::Refused) { play(root, fake, budget: 3.0) }
      assert_match(/18.00 USD already spent today plus a budget of 3.00 is above the 20.00 USD daily cap/, error.message)
      assert_equal 1, File.readlines(File.join(root, 'history.jsonl')).size
      assert play(root, fake, budget: 3.0, daily_cap: 25.0)
    end
  end

  def test_a_boot_run_that_never_creates_its_folder_is_killed
    Dir.mktmpdir do |root|
      line = play(root, fake_boot(root, create: false), appear: 0.5)
      assert_match(/did not start/, line['runs'].first['error'])
      assert gone?(File.read(File.join(root, 'pid')).to_i)
    end
  end

  def test_a_boot_run_adopts_the_folder_created_after_its_start_not_an_earlier_one_with_the_same_tag
    Dir.mktmpdir do |root|
      make_run(File.join(root, 'runs'), '20261126-000001-old0', tag: 'scoreboard-boot-20261126') { |trace| trace.emit(:stop, frame: 3, reason: 'dollars') }
      line = play(root, fake_boot(root, hang: false, wait: 0.3))
      assert_match(/\A20261126-\d+\z/, line['runs'].first['run'])
    end
  end

  def test_a_signal_on_the_scoreboard_stops_the_run_it_started
    Dir.mktmpdir do |root|
      fake = fake_boot(root)
      board = Process.spawn(RbConfig.ruby, File.expand_path('../tools/scoreboard/scoreboard.rb', __dir__), 'run', '--koholint', fake, '--root', File.join(root, 'runs'),
                            '--history', File.join(root, 'history.jsonl'), '--runs-root', File.join(root, 'none'), out: File::NULL, err: File::NULL)
      100.times { break if Dir.glob(File.join(root, 'runs', '*', 'trace.jsonl')).any? || sleep(0.1).nil? }
      pid = File.read(File.join(root, 'pid')).to_i
      assert Scoreboard::Run.alive?(pid)
      Process.kill('TERM', board)
      Process.wait(board)
      assert gone?(pid)
    ensure
      Process.kill('KILL', pid) if pid && Scoreboard::Run.alive?(pid)
    end
  end

  def test_the_run_never_uses_more_than_two_processes
    assert_equal 2, Scoreboard::Run::MAX_JOBS
    assert_equal ['--agent', '--root', '/r', '--tag', 't', '--max-dollars', '4.0', '--frames', '10', '--minutes', '5'], Scoreboard::Run.flags(tag: 't', root: '/r', budget: 4.0, frames: 10, minutes: 5)
  end

  def entry(branches, places, deaths = 1.0, calls = 10.0)
    { 'branches' => branches, 'primary' => { 'deaths_per_1000f' => deaths, 'calls_per_1000f' => calls,
                                             'progress' => { 'places_seen' => places, 'key_items' => [], 'highest_milestone' => 'sword' } } }
  end

  def test_alert_trips_on_spend_dirty_harness_and_rising_rates
    Dir.mktmpdir do |root|
      today = Date.new(2026, 11, 26)
      make_run(root, '20261126-000001-aaaa', dirty: true) { |trace| decision(trace, 5, usd: 21.0) }
      make_run(root, '20261125-000001-bbbb') { |trace| decision(trace, 5, usd: 99.0) }
      rows = Scoreboard::Runs.rows([root])
      reasons = Scoreboard::Alert.reasons(rows:, history: [entry(100, 5), entry(100, 5, 1.6, 15.1)], day: today)
      assert_equal ['daily spend 21.00 USD is above 20 USD', 'harness_dirty on 20261126-000001-aaaa'], reasons.first(2)
      assert_match(/deaths_per_1000f rose from 1.00 to 1.60 \(\+60%\)/, reasons[2])
      assert_match(/calls_per_1000f rose from 10.00 to 15.10/, reasons[3])
      assert_equal 4, reasons.size
      assert_empty Scoreboard::Alert.reasons(rows: Scoreboard::Runs.rows([root]), history: [entry(100, 5), entry(100, 5, 1.4, 14.9)], day: Date.new(2026, 11, 27))
    end
  end

  def test_alert_skips_lines_without_a_primary_run_and_never_alerts_from_a_zero_base_below_the_floor
    history = [entry(100, 5, 0.0, 10.0), { 'branches' => 100, 'primary' => nil }, entry(100, 5, 0.07, 10.0)]
    assert_empty Scoreboard::Alert.reasons(rows: [], history:, day: Date.new(2026, 11, 26))
    reasons = Scoreboard::Alert.reasons(rows: [], history: [entry(100, 5, 0.0), entry(100, 5, 0.7)], day: Date.new(2026, 11, 26))
    assert_equal ['deaths_per_1000f rose from 0.00 to 0.70 between the last two scoreboard runs'], reasons
    assert_empty Scoreboard::Alert.reasons(rows: [], history: [entry(100, 5, 1.0), entry(100, 5, 1.4)], day: Date.new(2026, 11, 26))
  end

  def test_alert_trips_on_branch_growth_with_no_progress_over_two_batches
    flat = [entry(100, 5), entry(110, 5), entry(121, 5)]
    assert_match(/branch conditions grew from 100 to 121/, Scoreboard::Alert.piled(flat).first)
    assert_empty Scoreboard::Alert.piled([entry(100, 5), entry(110, 6), entry(121, 6)])
    assert_empty Scoreboard::Alert.piled([entry(100, 5), entry(105, 5), entry(119, 5)])
    assert_empty Scoreboard::Alert.piled(flat.first(2))
  end

  def git(repo, *args) = system('git', '-C', repo, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(' ')}")

  def test_debt_counts_branch_conditions_and_the_rework_of_functions_across_flow_versions
    Dir.mktmpdir do |repo|
      git(repo, 'init', '-q', '-b', 'main')
      git(repo, 'config', 'user.email', 'a@b.c')
      git(repo, 'config', 'user.name', 'x')
      FileUtils.mkdir_p(File.join(repo, 'lib/koholint/policies'))
      write = lambda do |flow, body|
        File.write(File.join(repo, 'lib/koholint.rb'), "FLOW_VERSION = 'flow-#{flow}'\n")
        File.write(File.join(repo, 'lib/koholint/policies/delegated.rb'), body)
        git(repo, 'add', '-A')
        git(repo, 'commit', '-qm', "flow #{flow}")
      end
      write.call(1, "def a\n  1\nend\n")
      write.call(2, "def a\n  1 if x && y\nend\n")
      write.call(3, "def a\n  1 if x && y || z\nend\ndef b\n  2\nend\n")
      assert_equal 0, Scoreboard::Debt.branches(repo, 'HEAD~2')
      assert_equal 3, Scoreboard::Debt.branches(repo, 'HEAD')
      report = Scoreboard::Debt.report(repo:, ref: 'HEAD', window: 2, roots: [File.join(repo, 'none')], history: [])
      assert_equal [3, 3, 2], [report[:tip], report[:branches], report[:window]]
      assert_equal 33.3, report[:rework_pct]
      assert_nil report[:rules_never_fired]
      assert_equal false, report[:alarm]
      assert_includes Scoreboard::Debt.text(report), '1 decision-layer branch conditions: 3'
    end
  end

  def test_debt_lists_the_rules_that_fired_in_none_of_the_last_scoreboard_runs
    Dir.mktmpdir do |repo|
      git(repo, 'init', '-q', '-b', 'main')
      git(repo, 'config', 'user.email', 'a@b.c')
      git(repo, 'config', 'user.name', 'x')
      FileUtils.mkdir_p(File.join(repo, 'lib/koholint'))
      File.write(File.join(repo, 'lib/koholint.rb'), "FLOW_VERSION = 'flow-1'\n")
      git(repo, 'add', '-A')
      git(repo, 'commit', '-qm', 'one')
      history = [{ 'runs' => [{ 'rules' => { 'souvenir (102)' => 3 } }] }, { 'runs' => [{ 'rules' => { 'retreat (100)' => 1 } }] }]
      report = Scoreboard::Debt.report(repo:, ref: 'HEAD', window: 5, roots: [File.join(repo, 'none')], history:, last: 5)
      refute_includes report[:rules_never_fired], 'souvenir (102)'
      refute_includes report[:rules_never_fired], 'retreat (100)'
      assert_includes report[:rules_never_fired], 'loop break (100/101)'
    end
  end

  def test_the_families_name_a_harness_rule_and_the_model
    assert_equal ['rule', 'souvenir (102)'], Scoreboard::Measure.family('take souvenir-80-0', 'delegated')
    assert_equal %w[model model], Scoreboard::Measure.family('anything', 'claude')
    assert_equal ['rule', 'harness override of model'], Scoreboard::Measure.family("harness replaces the model's choice", 'claude')
    assert_equal ['base', 'boot script'], Scoreboard::Measure.family('boot script', 'start_game')
    assert_equal ['rule', 'other harness text'], Scoreboard::Measure.family('new words', 'delegated')
  end
end
