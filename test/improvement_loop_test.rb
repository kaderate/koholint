require 'minitest/autorun'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'koholint'
require 'koholint/trace'
require_relative '../tools/scoreboard/diagnose'
require_relative '../tools/scoreboard/improvements'
require_relative '../tools/scoreboard/pair'

class ImprovementLoopTest < Minitest::Test
  STATE = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'none', 'game_mode' => 0x0B, 'game_submode' => 7, 'inventory' => Array.new(10, 0) }.freeze

  def perceive(trace, frame, room) = trace.emit(:perception, frame:, state: STATE.merge('room_id' => room, 'map_id' => 0), state_hash: 'h')

  def decide(trace, frame, agent: 'claude', why: 'x', usd: 0.1)
    trace.emit(:decision, frame:, decision_point: 'choose_skill', input: { 'hp' => 24 }, options: [], choice: {}, justification: why, confidence: 1.0, agent:, latency_ms: 0, cost_usd: usd)
  end

  def make_run(root, id, parent: nil)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', **(parent ? { 'parent' => parent } : {})))
    yield Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    dir
  end

  # Four stalls of 5000 frames after the intro (rooms 1 and 2): one per template, then one no template fits.
  def stalled(root)
    make_run(root, '20261127-000001-aaaa') do |trace|
      perceive(trace, 10, 1)
      perceive(trace, 100, 2)
      decide(trace, 200)
      3.times { |n| decide(trace, 300 + n, agent: 'delegated', why: 'Explore 1-0 is guarded (2 hostiles)', usd: 0) }
      perceive(trace, 5100, 3)
      decide(trace, 5200)
      3.times { |n| trace.emit(:action, frame: 5300 + n, skill: 'attack', params: {}, result: { 'stopped_by' => 'refused' }) }
      perceive(trace, 10_100, 4)
      trace.emit(:objective, frame: 10_150, id: 'obj-1', status: 'started', title: 'Reach the east side', predicate: { 'kind' => 'reach_cell' })
      decide(trace, 10_200, usd: 0.5)
      trace.emit(:objective, frame: 15_050, id: 'obj-1', status: 'abandoned', title: 'Reach the east side', predicate: { 'kind' => 'reach_cell' }, reason: 'stall')
      perceive(trace, 15_100, 5)
      decide(trace, 15_200)
      trace.emit(:stop, frame: 20_100, reason: 'dollars')
    end
  end

  def test_diagnose_classes_each_stall_by_the_first_template_that_fits
    Dir.mktmpdir do |root|
      stalls = Scoreboard::Diagnose.run(stalled(root))
      assert_equal [[100, 5100], [5100, 10_100], [10_100, 15_100], [15_100, 20_100]], stalls.map { |stall| [stall[:from], stall[:to]] }
      assert_equal %w[override skill direction unclassified], stalls.map { |stall| stall[:class] }
      assert_equal({ 'guarded place (101)' => 3 }, stalls.first[:rules])
      assert_equal ['10150 Reach the east side'], stalls[2][:aims]
      assert_equal [0.5, 1, %w[E1]], stalls[2].values_at(:usd, :calls, :screens)
      table = Scoreboard::Diagnose.table(stalls)
      assert_match(/\| 20261127-000001-aaaa \| 10100-15100 \| 5000 \| 0.5 \| 1 \| E1 \| direction \|/, table.lines[2])
      assert_includes table, '| override | 1 | 5000 | 25% | 0.1 |'
    end
  end

  def test_diagnose_counts_a_fork_from_its_fork_frame
    Dir.mktmpdir do |root|
      dir = make_run(root, '20261127-000002-bbbb', parent: { 'id' => 'p', 'frame' => 1000 }) do |trace|
        perceive(trace, 10, 1)
        perceive(trace, 20, 2)
        decide(trace, 1500)
        trace.emit(:stop, frame: 5500, reason: 'dollars')
      end
      assert_equal [[1000, 5500, 'unclassified']], Scoreboard::Diagnose.run(dir).map { |stall| stall.values_at(:from, :to, :class) }
    end
  end

  def candidate(**changes)
    { 'id' => 'b32c-close-objective', 'kind' => 'rule', 'stall' => { 'run' => '20261127-001021-b32c', 'from' => 15_520, 'to' => 19_686, 'class' => 'direction' },
      'status' => 'proposed', 'change' => 'x', 'trials' => [], 'verdict' => nil, 'evidence' => 'diagnose' }.merge(changes)
  end

  def trial(arm) = { 'run' => '20261127-140000-cccc', 'arm' => arm, 'from' => 15_520, 'frames' => 4000, 'usd' => 0.7, 'calls' => 20, 'new_places' => 3, 'longest_stall' => 1800 }

  def test_the_registry_on_disk_is_valid_and_the_validator_refuses_a_bad_candidate
    Scoreboard::Improvements.load
    Scoreboard::Improvements.validate!(candidate)
    Scoreboard::Improvements.validate!(candidate('status' => 'published', 'verdict' => 'shorter stall', 'trials' => [trial('candidate'), trial('candidate'), trial('baseline')]))
    bad = [candidate('kind' => 'prompt'), candidate('status' => 'done'), candidate('status' => 'failed'), candidate('verdict' => 'early'),
           candidate('status' => 'published', 'verdict' => 'one trial', 'trials' => [trial('candidate')]), candidate('trials' => [trial('other')]),
           candidate('stall' => { 'run' => 'b32c', 'from' => 1, 'to' => 2, 'class' => 'direction' }), candidate('stall' => candidate['stall'].merge('class' => 'luck')),
           candidate('evidence' => ' '), candidate.merge('extra' => 1)]
    bad.each { |entry| assert_raises(Scoreboard::Improvements::Invalid, entry.inspect) { Scoreboard::Improvements.validate!(entry) } }
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'improvements.json')
      File.write(path, JSON.generate([candidate, candidate]))
      assert_raises(Scoreboard::Improvements::Invalid) { Scoreboard::Improvements.load(path) }
    end
  end

  def fake_koholint(root)
    fake = File.join(root, 'fake.rb')
    File.write(fake, <<~RUBY)
      require 'json'
      require 'fileutils'
      $LOAD_PATH.unshift(#{File.expand_path('../lib', __dir__).inspect})
      require 'koholint/trace'
      args = ARGV.dup
      command = args.shift
      File.open(#{File.join(root, 'calls').inspect}, 'a') { |file| file.puts(([command] + args).join(' ')) }
      if command == 'fork'
        tag = args[args.index('--tag') + 1]
        dir = File.join(args[args.index('--root') + 1], "20261127-\#{format('%06d', tag[/\\d+\\z/].to_i)}-dddd")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-9', 'tag' => tag, 'parent' => { 'id' => 'p', 'frame' => 1000 }))
        File.write(File.join(dir, 'trace.jsonl'), File.readlines(File.join(args[0], 'trace.jsonl')).first(2).join)
        puts "run \#{dir}"
      else
        trace = Koholint::Trace.new(File.join(args[0], 'trace.jsonl'))
        trace.emit(:perception, frame: 1500, state: #{STATE.merge('room_id' => 9, 'map_id' => 0).inspect}, state_hash: 'h')
        trace.emit(:decision, frame: 1600, decision_point: 'x', input: { 'hp' => 24 }, options: [], choice: {}, justification: 'x', confidence: 1.0, agent: 'claude', latency_ms: 0, cost_usd: 0.25)
      end
    RUBY
    fake
  end

  def test_pair_forks_the_parent_at_the_frame_caps_each_fork_and_reports_the_recorded_baseline
    Dir.mktmpdir do |root|
      parent = make_run(root, '20261127-000003-eeee') do |trace|
        perceive(trace, 10, 1)
        perceive(trace, 20, 2)
        decide(trace, 2000, usd: 0.4)
        trace.emit(:stop, frame: 6000, reason: 'dollars')
      end
      out = StringIO.new
      rows = Scoreboard::Pair.play(parent:, at_frame: 1000, max_dollars: 0.7, root: File.join(root, 'runs'), koholint: fake_koholint(root), repo: File.expand_path('..', __dir__),
                                   history: File.join(root, 'history.jsonl'), day: '20261127', out:, poll: 0.05)
      assert_match(/2 fork\(s\) per arm of 20261127-000003-eeee at frame 1000, 0.7 USD each, 1.4 USD at most/, out.string.lines.first)
      assert_equal %w[baseline candidate candidate], rows.map { |row| row[:arm] }
      assert_equal [[0.4, 0, 5000], [0.25, 1, 600], [0.25, 1, 600]], rows.map { |row| [row[:cost][:usd], row[:new_places], row[:frames]] }
      calls = File.readlines(File.join(root, 'calls'), chomp: true)
      assert_equal 2, calls.count { |call| call.start_with?("fork #{parent} --at-frame 1000 --tag pair-eeee-1000-candidate-") }
      assert_equal 2, calls.count { |call| call.start_with?('resume ') && call.include?('--max-dollars 0.7') }
      assert_includes out.string, 'A/B pair-eeee-1000'
      assert_equal [['pair', 0.5]], File.readlines(File.join(root, 'history.jsonl')).map { |line| JSON.parse(line).values_at('kind', 'usd') }
    end
  end

  def test_pair_refuses_without_a_dollar_cap_and_over_the_daily_cap
    Dir.mktmpdir do |root|
      script = File.expand_path('../tools/scoreboard/scoreboard.rb', __dir__)
      refused = system(RbConfig.ruby, script, 'pair', root, '--at-frame', '10', '--history', File.join(root, 'h.jsonl'), %i[out err] => File::NULL)
      refute refused
      File.write(File.join(root, 'h.jsonl'), "#{JSON.generate('date' => Time.new(2026, 11, 27, 12).utc.iso8601, 'usd' => 19.0)}\n")
      assert_raises(Scoreboard::Run::Refused) do
        Scoreboard::Pair.play(parent: root, at_frame: 10, max_dollars: 0.7, root:, koholint: 'none', repo: root, history: File.join(root, 'h.jsonl'), day: '20261127', out: StringIO.new)
      end
    end
  end
end
