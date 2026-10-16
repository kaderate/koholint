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
end
