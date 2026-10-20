require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'open3'
require 'koholint/archive'
require 'koholint/cli'
require 'koholint/run'

class ArchiveTest < Minitest::Test
  GITIGNORE = File.expand_path('../.gitignore', __dir__)
  PLAYING = { 'hp' => 24, 'max_hp' => 24, 'milestone' => 'none', 'room_id' => 3, 'map_id' => 1, 'game_mode' => 0x0B, 'game_submode' => 7 }.freeze

  def make_run(root, id, stop: true, tag: nil)
    dir = File.join(root, id)
    %w[prompts keyframes save].each { |name| FileUtils.mkdir_p(File.join(dir, name)) }
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-3', 'status' => 'stopped', 'tag' => tag))
    File.binwrite(File.join(dir, 'inputs.log'), "\x02")
    File.write(File.join(dir, 'world.json'), '{}')
    File.write(File.join(dir, 'prompts', '10-choose_skill.txt'), 'prompt')
    File.write(File.join(dir, 'keyframes', 'kf-000000010.zlib'), 'kf')
    File.write(File.join(dir, 'save', 'game-10.sav'), 'sav')
    File.write(File.join(dir, 'activity.json'), '{}')
    trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    trace.emit(:perception, frame: 0, state: PLAYING, state_hash: 'h')
    trace.emit(:decision, frame: 0, decision_point: 'choose_skill', input: {}, options: [], choice: {}, justification: 'j', confidence: 1.0,
                          agent: 'claude', latency_ms: 3000, cost_usd: 0.02)
    trace.emit(:stop, frame: 500, reason: 'frames') if stop
    dir
  end

  def capture
    out = StringIO.new
    code = yield out
    [code, out.string]
  end

  def sh(dir, *command)
    output, status = Open3.capture2e(*command, chdir: dir)
    assert status.success?, output
    output
  end

  def with_repo
    Dir.mktmpdir do |repo|
      Dir.mktmpdir do |live|
        sh(repo, 'git', 'init', '-q')
        sh(repo, 'git', 'config', 'user.email', 'test@example.com')
        sh(repo, 'git', 'config', 'user.name', 'Test')
        FileUtils.cp(GITIGNORE, File.join(repo, '.gitignore'))
        sh(repo, 'git', 'add', '.gitignore')
        sh(repo, 'git', 'commit', '-q', '-m', 'Start')
        yield File.join(repo, 'runs'), live, repo
      end
    end
  end

  def test_import_copies_the_light_bundle_and_leaves_the_source_untouched
    Dir.mktmpdir do |base|
      root = File.join(base, 'runs')
      live = File.join(base, 'live')
      source = make_run(live, '20261020-000001-aaaa', tag: 'exp')
      before = Dir.glob('**/*', base: source).sort
      code, out = capture { |o| Koholint::Archive.archive(root:, from: live, out: o) }
      assert_equal 0, code
      assert_match(/archived 20261020-000001-aaaa/, out)
      assert_equal before, Dir.glob('**/*', base: source).sort
      dest = File.join(root, '20261020-000001-aaaa')
      assert_equal %w[inputs.log manifest.json summary.json trace.jsonl.gz world.json], Dir.children(dest).sort
      assert_equal 3, Koholint::Trace.read(File.join(dest, 'trace.jsonl')).size
      summary = JSON.parse(File.read(File.join(dest, 'summary.json')))
      assert_equal ['exp', 1, 500, 'frames', 1], summary.values_at('tag', 'calls', 'frames', 'stop_reason', 'places_seen')
      index = File.read(File.join(base, 'docs', 'runs', 'index.md'))
      assert_includes index, '| [20261020-000001-aaaa](../../runs/20261020-000001-aaaa/) | exp | flow-3 | 500 | 0.0200 | 1 | 0.0400 | none | 1 | frames |  |'
    end
  end

  def test_unfinished_and_live_runs_are_skipped
    Dir.mktmpdir do |base|
      root = File.join(base, 'runs')
      live = File.join(base, 'live')
      make_run(live, '20261020-000001-aaaa', stop: false)
      locked = make_run(live, '20261020-000002-bbbb')
      lock = File.open(File.join(locked, 'run.lock'), File::CREAT | File::RDWR)
      lock.flock(File::LOCK_EX)
      _code, out = capture { |o| Koholint::Archive.archive(root:, from: live, out: o) }
      lock.close
      assert_match(/skip 20261020-000001-aaaa: no stop event/, out)
      assert_match(/skip 20261020-000002-bbbb: in use/, out)
      assert_empty Dir.children(root)
    end
  end

  def test_archiving_in_place_gzips_the_trace_and_is_idempotent
    Dir.mktmpdir do |base|
      root = File.join(base, 'runs')
      dir = make_run(root, '20261020-000001-aaaa')
      Koholint::Archive.archive(root:, out: StringIO.new)
      refute File.exist?(File.join(dir, 'trace.jsonl'))
      assert File.file?(File.join(dir, 'trace.jsonl.gz'))
      assert File.directory?(File.join(dir, 'prompts'))
      snapshot = Dir.glob('**/*', base:).sort.to_h { |path| [path, File.file?(File.join(base, path)) && File.binread(File.join(base, path))] }
      _code, out = capture { |o| Koholint::Archive.archive(root:, out: o) }
      assert_equal '', out
      assert_equal snapshot, Dir.glob('**/*', base:).sort.to_h { |path| [path, File.file?(File.join(base, path)) && File.binread(File.join(base, path))] }
    end
  end

  def test_commit_adds_only_the_light_bundles_and_the_index_in_one_commit
    with_repo do |root, live, repo|
      make_run(live, '20261020-000001-aaaa')
      make_run(live, '20261020-000002-bbbb')
      make_run(root, '20261020-000003-cccc')
      _code, out = capture { |o| Koholint::Archive.archive(root:, from: live, commit: true, out: o) }
      assert_match(/committed: Archive runs 20261020-000001-aaaa..20261020-000002-bbbb/, out)
      assert_equal "Archive runs 20261020-000001-aaaa..20261020-000002-bbbb", sh(repo, 'git', 'log', '-1', '--format=%B').rstrip
      files = sh(repo, 'git', 'show', '--name-only', '--format=', 'HEAD').lines.map(&:strip).sort
      expected = %w[aaaa 000001 bbbb 000002].each_slice(2).flat_map do |suffix, n|
        %w[inputs.log manifest.json summary.json trace.jsonl.gz world.json].map { |name| "runs/20261020-#{n}-#{suffix}/#{name}" }
      end
      assert_equal ['docs/runs/index.md', *expected].sort, files
      assert_match(/\?\? runs\/20261020-000003-cccc/, sh(repo, 'git', 'status', '--porcelain'))
      head = sh(repo, 'git', 'rev-parse', 'HEAD')
      _code, out = capture { |o| Koholint::Archive.archive(root:, from: live, commit: true, out: o) }
      assert_equal "nothing to commit\n", out
      assert_equal head, sh(repo, 'git', 'rev-parse', 'HEAD')
    end
  end

  def test_full_force_adds_the_prompts_of_a_single_run
    with_repo do |root, live, repo|
      make_run(live, '20261020-000001-aaaa')
      Koholint::Archive.archive(root:, from: live, commit: true, full: true, out: StringIO.new)
      assert_equal "Archive run 20261020-000001-aaaa (with prompts)", sh(repo, 'git', 'log', '-1', '--format=%B').rstrip
      files = sh(repo, 'git', 'show', '--name-only', '--format=', 'HEAD')
      assert_includes files, 'runs/20261020-000001-aaaa/prompts/10-choose_skill.txt'
      refute_includes files, 'keyframes'
    end
  end

  def test_without_commit_nothing_is_committed
    with_repo do |root, live, repo|
      make_run(live, '20261020-000001-aaaa')
      head = sh(repo, 'git', 'rev-parse', 'HEAD')
      Koholint::Archive.archive(root:, from: live, out: StringIO.new)
      assert_equal head, sh(repo, 'git', 'rev-parse', 'HEAD')
      assert_equal '', sh(repo, 'git', 'diff', '--cached', '--name-only')
    end
  end

  def test_star_marks_the_run_and_its_summary
    Dir.mktmpdir do |base|
      root = File.join(base, 'runs')
      dir = make_run(root, '20261020-000001-aaaa')
      Koholint::Archive.archive(root:, out: StringIO.new)
      code, out = capture { |o| Koholint::Archive.star(dir, 'first exit', out: o) }
      assert_equal [0, "starred 20261020-000001-aaaa\n"], [code, out]
      star = JSON.parse(File.read(File.join(dir, 'star.json')))
      assert_equal [true, 'first exit'], star.values_at('starred', 'why')
      assert Time.iso8601(star['at'])
      assert JSON.parse(File.read(File.join(dir, 'summary.json')))['starred']
      Koholint::Archive.archive(root:, out: StringIO.new)
      assert_match(/\| frames \| ★ \|/, File.read(File.join(base, 'docs', 'runs', 'index.md')))
      assert_raises(Koholint::Error) { Koholint::Archive.star(File.join(root, 'nope'), 'x') }
    end
  end

  def test_prune_heavy_keeps_recent_and_starred_runs
    Dir.mktmpdir do |root|
      dirs = (1..4).map { |n| make_run(root, "20261020-00000#{n}-aaaa") }
      File.write(File.join(dirs[0], 'star.json'), '{}')
      code, out = capture { |o| Koholint::Archive.prune_heavy(root:, keep: 2, out: o) }
      assert_equal 0, code
      assert_equal ["would delete #{dirs[1]}/prompts", "would delete #{dirs[1]}/keyframes", '2 directories to delete (pass --yes)'], out.lines.map(&:chomp)
      assert File.directory?(File.join(dirs[1], 'prompts'))
      Koholint::Archive.prune_heavy(root:, keep: 2, yes: true, out: StringIO.new)
      refute File.exist?(File.join(dirs[1], 'prompts'))
      refute File.exist?(File.join(dirs[1], 'keyframes'))
      assert File.file?(File.join(dirs[1], 'trace.jsonl'))
      [dirs[0], dirs[2], dirs[3]].each { |dir| assert File.directory?(File.join(dir, 'prompts')) }
    end
  end

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    [Koholint::CLI.run(argv, out:, err:), out.string, err.string]
  end

  def test_cli_commands
    Dir.mktmpdir do |base|
      root = File.join(base, 'runs')
      live = File.join(base, 'live')
      make_run(live, '20261020-000001-aaaa')
      assert_equal 0, cli('archive', '--from', live, '--root', root)[0]
      dir = File.join(root, '20261020-000001-aaaa')
      assert File.file?(File.join(dir, 'summary.json'))
      assert_equal 0, cli('star', dir, 'why')[0]
      assert_equal 2, cli('star', dir)[0]
      code, out, = cli('prune-heavy', '--root', live, '--keep', '0')
      assert_equal 0, code
      assert_match(/would delete/, out)
      assert_equal 2, cli('prune-heavy', '--keep', '-1')[0]
    end
  end
end
