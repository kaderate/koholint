require_relative 'test_helper'
require 'koholint/probes/sword_census'
require 'koholint/talk_log'

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

  def test_measured_sword_hits_reach_the_entity_catalogue_with_their_own_confidence
    catalogue = Koholint::Entities.catalogue
    assert_equal [1, true], catalogue[9].values_at(:sword_hits, :sword_verified)
    assert_equal [2, false], catalogue[198].values_at(:sword_hits, :sword_verified)
    assert_equal [2, false], catalogue[14].values_at(:sword_hits, :sword_verified)
  end

  def test_a_verified_sword_fact_needs_two_checks
    fact = { 'value' => 2, 'confidence' => 'verified', 'verified_count' => 1, 'source' => 'one room' }
    assert_raises(Koholint::Entities::Invalid) { Koholint::Entities.validate_fact!(fact, 'sword_hits') }
    Koholint::Entities.validate_fact!(fact.merge('confidence' => 'hypothesis'), 'sword_hits')
  end

  def test_the_listing_marks_an_unverified_hit_count
    log = Koholint::TalkLog.new
    assert_includes log.send(:entity_label, [1, 0], { type: 198, kind: :enemy, sword_hits: 2, sword_verified: false }), 'sword hits to kill 2 (unverified)'
    assert_includes log.send(:entity_label, [1, 0], { type: 9, kind: :enemy, sword_hits: 1, sword_verified: true }), 'sword hits to kill 1)'
  end
end
