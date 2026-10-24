require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/place_kinds'

class PlaceKindsTest < Minitest::Test
  WORLD = { 'kind' => 'world', 'map_ids' => [0], 'layout' => 'grid16', 'source' => 's', 'confidence' => 'hypothesis', 'verified_count' => 1 }.freeze

  def load(entries)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'place_kinds.json')
      File.write(path, JSON.generate(entries))
      Koholint::PlaceKinds.load(path)
    end
  end

  def test_the_catalogue_loads_and_maps_each_map_id_to_one_kind
    kinds = Koholint::PlaceKinds.load
    assert_equal 'world', kinds.dig(0, 'kind')
    assert_equal 'interior', kinds.dig(16, 'kind')
    assert_equal 'other', Koholint::PlaceKinds.kind([1, 200], kinds)
    assert_equal [3, 10], Koholint::PlaceKinds.cell([163, 0])
  end

  def test_bad_entries_are_refused
    bad = [WORLD.merge('kind' => 'castle'), WORLD.merge('layout' => 'attached'), WORLD.merge('kind' => 'cave'), WORLD.merge('map_ids' => [256]),
           WORLD.merge('map_ids' => []), WORLD.merge('confidence' => 'verified'), WORLD.except('source'), WORLD.merge('extra' => 1)]
    bad.each { |entry| assert_raises(Koholint::PlaceKinds::Invalid, entry.inspect) { load([entry]) } }
    assert_raises(Koholint::PlaceKinds::Invalid) { load([WORLD, WORLD.merge('kind' => 'interior', 'layout' => 'attached')]) }
    assert_raises(Koholint::PlaceKinds::Invalid) { load({}) }
    assert_equal({ 0 => { 'kind' => 'world', 'layout' => 'grid16' } }, load([WORLD]))
  end
end
