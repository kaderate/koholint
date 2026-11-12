require_relative 'test_helper'
require 'koholint/probes/sword_census'

class SwordCensusTest < Minitest::Test
  SC = Koholint::Probes::SwordCensus

  def test_spot_puts_link_in_front_or_behind_with_a_sideways_offset
    assert_equal [66, 50], SC.spot(50, 50, :left, 16)
    assert_equal [50, 66], SC.spot(50, 50, :up, 16)
    assert_equal [34, 50], SC.spot(50, 50, :left, 16, behind: true)
    assert_equal [66, 46], SC.spot(50, 50, :left, 16, lateral: -4)
  end

  def test_spots_off_the_screen_are_not_tried
    refute SC.on_screen?({ x: 6, y: 60 }, :right, 10)
    assert SC.on_screen?({ x: 6, y: 60 }, :left, 10)
  end

  def test_the_kill_gap_is_the_median_hitting_distance
    assert_equal 20, SC.gap_for({ up: [14, 16, 18], left: [20, 22, 24] })
    assert_equal SC::LATERAL_GAP, SC.gap_for({ up: [] })
  end

  def test_measured_sword_hits_reach_the_entity_catalogue
    assert_equal 2, Koholint::Entities.catalogue.dig(198, :sword_hits)
    assert_equal 1, Koholint::Entities.catalogue.dig(9, :sword_hits)
    assert_nil Koholint::Entities.catalogue.dig(14, :sword_hits)
  end
end
