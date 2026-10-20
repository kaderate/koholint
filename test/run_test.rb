require_relative 'test_helper'
require 'tmpdir'
require 'koholint/run'

class RunTest < Minitest::Test
  def with_env
    Dir.mktmpdir do |dir|
      rom = File.join(dir, 'game.gbc')
      File.binwrite(rom, 'fake rom bytes')
      yield dir, rom
    end
  end

  def test_create_makes_layout
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: { frames: 10 }, rom_path: rom)
      %w[manifest.json trace.jsonl inputs.log world.json suggestions.md].each do |name|
        assert File.file?(File.join(run.dir, name)), name
      end
      %w[save keyframes].each { |name| assert File.directory?(File.join(run.dir, name)), name }
      assert_equal 'created', run.manifest['status']
      assert_equal 'f1', run.manifest['flow_version']
      assert_equal({ 'frames' => 10 }, run.manifest['budget'])
    end
  end

  def test_truncate_prompts_drops_prompt_files_from_the_truncation_frame_on
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      FileUtils.mkdir_p(File.join(run.dir, 'prompts'))
      %w[90-choose_skill.txt 100-choose_skill.txt 100-choose_skill.png 150-choose_objective.txt].each { |n| File.write(File.join(run.dir, 'prompts', n), 'x') }
      run.truncate_prompts!(100)
      assert_equal ['90-choose_skill.txt'], Dir.children(File.join(run.dir, 'prompts'))
    end
  end

  def test_open_with_other_flow_version_raises
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      assert_raises(Koholint::Run::VersionMismatch) { Koholint::Run.open(run.dir, flow_version: 'f2', rom_path: rom) }
    end
  end

  def test_open_with_other_rom_hash_raises
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      File.binwrite(rom, 'another rom')
      assert_raises(Koholint::Run::RomMismatch) { Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom) }
    end
  end

  def test_open_returns_same_manifest
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      assert_equal run.manifest, Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom).manifest
    end
  end

  def test_ids_do_not_collide_in_same_second
    with_env do |dir, rom|
      ids = Array.new(40) { Koholint::Run.create(root: dir, flow_version: 'f', budget: {}, rom_path: rom).id }
      assert_equal 40, ids.uniq.size
    end
  end

  def test_status_is_persisted
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      run.status = 'stopped'
      assert_equal 'stopped', Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom).manifest['status']
    end
  end

  def test_write_activity_is_atomic_and_skips_unchanged_states
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      path = File.join(run.dir, 'activity.json')
      run.write_activity(kind: 'deciding', label: 'asking', frame: 3, detail: { model: 'sonnet' })
      first = JSON.parse(File.read(path))
      assert_equal %w[kind label frame detail started_at].sort, first.keys.sort
      assert_kind_of Float, first['started_at']
      refute File.exist?("#{path}.tmp")
      run.write_activity(kind: 'deciding', label: 'asking', frame: 9, detail: { model: 'sonnet' })
      assert_equal 3, JSON.parse(File.read(path))['frame']
      run.write_activity(kind: 'idle', label: 'between', frame: 9, detail: {})
      assert_equal 'idle', JSON.parse(File.read(path))['kind']
      refute File.exist?("#{path}.tmp")
    end
  end

  def test_activity_is_ignored_by_fork_and_open
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      File.write(File.join(run.dir, 'activity.json'), 'garbage{')
      reopened = Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom)
      child = reopened.fork(at_frame: 0, flow_version: 'f1', rom_path: rom)
      refute File.exist?(File.join(child.dir, 'activity.json'))
      reopened.truncate_trace!(0)
    end
  end

  def test_write_activity_never_raises_and_leaves_no_temp_file
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      path = File.join(run.dir, 'activity.json')
      [Float::NAN, "bad\xFF".b.force_encoding('UTF-8'), Object.new].each_with_index do |value, i|
        run.write_activity(kind: 'acting', label: 'x', frame: 1, detail: { params: value, n: i })
        refute File.exist?("#{path}.tmp")
      end
      FileUtils.rm_f(path)
      FileUtils.mkdir_p(File.join(path, 'blocker'))
      run.write_activity(kind: 'idle', label: 'x', frame: 1, detail: {})
      refute File.exist?("#{path}.tmp")
      FileUtils.rm_rf(run.dir)
      run.write_activity(kind: 'stopped', label: 'x', frame: 1, detail: {})
    end
  end

  def test_manifest_records_tag_model_and_versions
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom, tag: 'exp', model: 'sonnet')
      assert_equal %w[exp sonnet], run.manifest.values_at('tag', 'model')
      assert_match(/\A\h{40}\z/, run.manifest['harness_sha'])
      assert_equal Koholint::Agents::Prompts.digest, run.manifest['prompts_sha']
      assert_match(/\A\h{64}\z/, run.manifest['prompts_sha'])
      child = run.fork(at_frame: 0, flow_version: 'f1', rom_path: rom)
      assert_equal %w[exp sonnet], child.manifest.values_at('tag', 'model')
    end
  end

  def test_an_older_manifest_without_the_new_keys_still_opens_and_forks
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      path = File.join(run.dir, 'manifest.json')
      File.write(path, JSON.generate(JSON.parse(File.read(path)).except('tag', 'harness_sha', 'prompts_sha', 'model')))
      child = Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom).fork(at_frame: 0, flow_version: 'f1', rom_path: rom)
      assert_nil child.manifest['tag']
    end
  end

  def test_an_archived_trace_is_decompressed_before_it_is_written_again
    with_env do |dir, rom|
      run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {}, rom_path: rom)
      run.trace.emit(:stop, frame: 5, reason: 'frames')
      path = File.join(run.dir, 'trace.jsonl')
      Koholint::Trace.compress(path)
      File.delete(path)
      reopened = Koholint::Run.open(run.dir, flow_version: 'f1', rom_path: rom)
      child = reopened.fork(at_frame: 0, flow_version: 'f1', rom_path: rom)
      assert File.file?(File.join(child.dir, 'trace.jsonl'))
      reopened.truncate_trace!(5)
      reopened.trace.emit(:stop, frame: 9, reason: 'frames')
      refute File.exist?("#{path}.gz")
      assert_equal [5, 9], Koholint::Trace.read(path).map { |e| e['frame'] }
    end
  end
end
