require_relative 'test_helper'
require 'tmpdir'
require 'support/emulator_cache'

class EmulatorCacheTest < Minitest::Test
  def with_cache_dir
    Dir.mktmpdir do |dir|
      old = EmulatorCache.dir
      EmulatorCache.dir = dir
      yield dir
    ensure
      EmulatorCache.dir = old
    end
  end

  def test_second_call_loads_the_cached_state_and_matches_a_fresh_build
    skip_without_rom!
    with_cache_dir do |dir|
      built = EmulatorCache.at(120)
      assert_equal 1, Dir.children(dir).size
      loaded = EmulatorCache.at(120)
      assert_equal built.state_hash, loaded.state_hash
      assert_equal 120, loaded.frame
    end
  end

  def test_corrupt_cache_file_is_rebuilt
    skip_without_rom!
    with_cache_dir do |dir|
      expected = EmulatorCache.at(90).state_hash
      File.binwrite(File.join(dir, Dir.children(dir).first), 'garbage')
      assert_equal expected, EmulatorCache.at(90).state_hash
    end
  end

  def test_cache_state_follows_the_boot_policy
    skip_without_rom!
    with_cache_dir do
      direct = Koholint::Emulator.boot
      while direct.frame < 120
        macro = Koholint::BootScript.macro_for(Koholint::Perception.read(direct))
        [macro[:frames], 120 - direct.frame].min.times { direct.step(macro[:buttons]) }
      end
      assert_equal direct.state_hash, EmulatorCache.at(120).state_hash
    end
  end

  def test_playable_state_is_controllable_and_cached
    skip_without_rom!
    with_cache_dir do |dir|
      state = Koholint::Perception.read(EmulatorCache.playable)
      assert state.controllable?
      assert_equal [163, 16], [state.room_id, state.map_id]
      assert_equal 1, Dir.children(dir).size
      assert_equal state.frame, Koholint::Perception.read(EmulatorCache.playable).frame
    end
  end

  def test_interactive_state_is_free_and_cached
    skip_without_rom!
    with_cache_dir do
      emulator = EmulatorCache.interactive
      before = Koholint::Perception.read(emulator)
      copy = Koholint::Emulator.restore(emulator.dump)
      40.times { copy.step([:down]) }
      assert_operator Koholint::Perception.read(copy).y, :>, before.y
      assert_equal before.frame, Koholint::Perception.read(EmulatorCache.interactive).frame
    end
  end

  def test_key_changes_with_the_source_list_and_includes_the_cache_builder
    skip_without_rom!
    assert_equal EmulatorCache.send(:key_for, ['a']), EmulatorCache.send(:key_for, ['a'])
    refute_equal EmulatorCache.send(:key_for, ['a']), EmulatorCache.send(:key_for, ['b'])
    assert_includes EmulatorCache.send(:key_sources), File.read(File.expand_path('support/emulator_cache.rb', __dir__))
    assert_includes EmulatorCache.send(:key_sources), File.read(File.expand_path('../lib/koholint/emulator.rb', __dir__))
  end
end
