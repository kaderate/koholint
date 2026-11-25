require_relative 'test_helper'
require 'json'
require 'tmpdir'
require 'koholint/pickup_check'

class PickupCheckTest < Minitest::Test
  def run_dir(root, id, parent: nil, tag: 'x', gains: [[12, [80, 0], 93790], [4, [163, 16], 3906]])
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate({ 'id' => id, 'tag' => tag, **parent ? { 'parent' => { 'id' => parent, 'frame' => 90581 } } : {} }))
    File.write(File.join(dir, 'trace.jsonl'), gains.map do |item, place, frame|
      JSON.generate({ 'v' => 1, 'type' => 'item_gained', 'frame' => frame, 'item' => item, 'name' => 'x', 'place' => place, 'held' => [1, 4, item] })
    end.join("\n") + "\n")
    dir
  end

  def data(root, confidence, verified_count)
    path = File.join(root, 'items.json')
    File.write(path, JSON.generate([{ 'id' => 12, 'name' => 'mushroom', 'source' => 'x', 'confidence' => 'hypothesis', 'verified_count' => 0,
                                      'pickups' => { 'value' => [], 'confidence' => confidence, 'verified_count' => verified_count, 'source' => 'x' } }]))
    path
  end

  def check(root, dirs, confidence: 'observed', count: 1)
    out = StringIO.new
    code = Koholint::PickupCheck.check(dirs, out:, data: data(root, confidence, count))
    [code, out.string]
  end

  def test_two_runs_of_one_checkpoint_measure_one_lineage
    Dir.mktmpdir do |root|
      dirs = [run_dir(root, 'a', parent: 'ck', tag: 'one'), run_dir(root, 'b', parent: 'ck', tag: 'two')]
      code, text = check(root, dirs)
      assert_equal 0, code
      assert_includes text, 'item 12 (mushroom?): 2 gain(s) in 2 run(s), 1 lineage(s) (ck) holding [[1, 4, 12]], so the data may claim observed with verified_count 1'
      assert_includes text, '2 item(s) gained across 2 run(s)'
    end
  end

  def test_two_lineages_agreeing_on_the_held_set_may_claim_verified
    Dir.mktmpdir do |root|
      code, text = check(root, [run_dir(root, 'a', parent: 'ck1'), run_dir(root, 'b', parent: 'ck2')], confidence: 'verified', count: 2)
      assert_equal 0, code
      assert_includes text, '2 lineage(s) (ck1, ck2) holding [[1, 4, 12]], so the data may claim verified with verified_count 2'
    end
  end

  def test_a_reused_checkpoint_deep_in_the_roots_still_counts_as_one_lineage
    Dir.mktmpdir do |root|
      run_dir(root, 'ck') if true
      File.write(File.join(root, 'ck', 'manifest.json'), JSON.generate({ 'id' => 'ck' }))
      code, text = check(root, [run_dir(root, 'a', parent: 'ck'), run_dir(root, 'b', parent: 'ck')])
      assert_equal 0, code
      assert_includes text, '1 lineage(s) (ck)'
    end
  end

  def test_two_runs_from_boot_are_two_lineages
    Dir.mktmpdir do |root|
      code, text = check(root, [run_dir(root, 'a'), run_dir(root, 'b')], confidence: 'verified', count: 2)
      assert_equal 0, code
      assert_includes text, '2 lineage(s) (a, b) holding [[1, 4, 12]], so the data may claim verified with verified_count 2'
    end
  end

  def test_a_run_from_boot_beside_a_fork_is_its_own_lineage
    Dir.mktmpdir do |root|
      code, text = check(root, [run_dir(root, 'a'), run_dir(root, 'b', parent: 'ck')], confidence: 'verified', count: 2)
      assert_equal 0, code
      assert_includes text, '2 lineage(s) (a, ck)'
    end
  end

  def test_data_that_claims_more_than_the_runs_measured_exits_one
    Dir.mktmpdir do |root|
      code, text = check(root, [run_dir(root, 'a', parent: 'ck'), run_dir(root, 'b', parent: 'ck')], confidence: 'verified', count: 2)
      assert_equal 1, code
      assert_includes text, 'MISMATCH item 12: data claims verified with verified_count 2, these runs measure observed from 1 lineage(s)'
    end
  end
end
