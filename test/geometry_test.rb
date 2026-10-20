require 'test_helper'
require 'support/emulator_cache'
require 'koholint/emulator'
require 'koholint/perception'
require 'koholint/geometry'

class GeometryTest < Minitest::Test
  G = Koholint::Geometry

  def test_cell_for_uses_the_nearest_cell_rule
    assert_equal [1, 4], G.cell_for(72, 32)
    assert_equal [1, 2], G.cell_for(44, 39)
    assert_equal [0, 0], G.cell_for(15, 23)
    assert_equal [1, 1], G.cell_for(16, 24)
    assert_nil G.cell_for(10, 2)
    assert_nil G.cell_for(160, 52)
    assert_nil G.cell_for(70, 136)
    assert_nil G.cell_for(nil, 52)
  end

  def test_center_of_is_the_cell_center_in_link_coordinates
    assert_equal [72, 32], G.center_of(1, 4)
    assert_equal [8, 16], G.center_of(0, 0)
    assert_equal [G.center_of(3, 5)], [G.center_of(*G.cell_for(*G.center_of(3, 5)))]
  end

  def test_offset_and_alignment
    assert_equal [4, 7], G.offset(44, 39, [1, 2])
    refute G.aligned?(44, 39, [1, 2])
    assert G.aligned?(44, 32, [1, 2], axis: :y)
    assert G.aligned?(44, 32, [1, 2])
    refute G.aligned?(44, 37, [1, 2], axis: :y)
    assert G.aligned?(44, 36, [1, 2], axis: :y)
    refute G.aligned?(49, 32, [1, 2], axis: :x)
    assert_raises(ArgumentError) { G.aligned?(44, 32, [1, 2], axis: :z) }
  end

  def test_fact_reads_the_typed_data_with_provenance
    raw = JSON.parse(File.read(G::DEFAULT_PATH)).fetch('link_footprint')
    assert_equal G.fact(:link_footprint), raw['value']
    assert raw['verified_count'].positive?
    refute_empty raw['provenance']
  end
end

class GeometryFootprintTest < Minitest::Test
  def setup
    skip_without_rom!
  end

  def walk_left_from(rise)
    emulator = Koholint::Emulator.restore(EmulatorCache.interactive.dump)
    rise.times { emulator.step([:up]) }
    4.times { emulator.step }
    start = Koholint::Perception.read(emulator)
    70.times { emulator.step([:left]) }
    4.times { emulator.step }
    [start, Koholint::Perception.read(emulator)]
  end

  def test_link_walks_left_past_the_beds_at_y_32_but_not_at_y_39
    start, finish = walk_left_from(20)
    assert_equal 32, start.y
    assert_operator finish.x, :<, 36

    start, finish = walk_left_from(14)
    assert_equal 39, start.y
    assert_operator finish.x, :>, 36
  end
end
