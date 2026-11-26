require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'koholint/atlas'
require 'koholint/viewer/digest_cache'

class DigestCacheTest < Minitest::Test
  PLAYING = { 'hp' => 24, 'max_hp' => 24, 'game_mode' => 0x0B, 'game_submode' => 7, 'room_id' => 162, 'map_id' => 0 }.freeze

  def make_run(root, id)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'flow-1'))
    Koholint::Trace.new(File.join(dir, 'trace.jsonl')).emit(:perception, frame: 1, state: PLAYING, state_hash: 'h')
    dir
  end

  def test_a_new_cache_reads_the_digests_from_disk_until_a_trace_changes
    Dir.mktmpdir do |root|
      dir = make_run(root, '20261101-100000-aaaa')
      cache = File.join(root, '.cache', 'digests')
      _, first = Koholint::Atlas.read([root], cache: Koholint::Viewer::DigestCache.new(cache))
      assert_equal 1, Dir.children(cache).size
      original = Koholint::Atlas.method(:digest)
      Koholint::Atlas.define_singleton_method(:digest) { |*| raise 'recomputed' }
      _, again = Koholint::Atlas.read([root], cache: Koholint::Viewer::DigestCache.new(cache))
      Koholint::Atlas.define_singleton_method(:digest, original)
      assert_equal first, again
      Koholint::Trace.new(File.join(dir, 'trace.jsonl')).emit(:perception, frame: 9, state: PLAYING.merge('room_id' => 163), state_hash: 'h')
      _, changed = Koholint::Atlas.read([root], cache: Koholint::Viewer::DigestCache.new(cache))
      assert_equal %w[162-0 163-0], changed.first[:places].keys.map { |place| place.join('-') }.sort
    end
  end

  def test_digests_written_by_other_code_are_recomputed_and_those_of_deleted_runs_are_pruned
    Dir.mktmpdir do |root|
      make_run(root, '20261101-100000-aaaa')
      gone = make_run(root, '20261102-100000-bbbb')
      cache = File.join(root, '.cache', 'digests')
      Koholint::Atlas.read([root], cache: Koholint::Viewer::DigestCache.new(cache, identity: 'old'))
      calls = 0
      original = Koholint::Atlas.method(:digest)
      Koholint::Atlas.define_singleton_method(:digest) { |*args, **kw| (calls += 1) && original.call(*args, **kw) }
      store = Koholint::Viewer::DigestCache.new(cache, identity: 'new')
      Koholint::Atlas.read([root], cache: store)
      Koholint::Atlas.define_singleton_method(:digest, original)
      assert_equal 2, calls
      FileUtils.rm_rf(gone)
      dirs, = Koholint::Atlas.read([root], cache: store)
      store.prune(dirs)
      assert_equal 1, Dir.children(cache).size
    end
  end
end
