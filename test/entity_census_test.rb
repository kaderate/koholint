require_relative 'test_helper'
require 'koholint/probes/entity_census'

class EntityCensusTest < Minitest::Test
  EC = Koholint::Probes::EntityCensus

  def test_relative_follows_the_way_link_faces
    assert_equal :up, EC.relative(:up, :front)
    assert_equal :down, EC.relative(:up, :behind)
    assert_equal :left, EC.relative(:up, :left)
    assert_equal :down, EC.relative(:left, :left)
    assert_equal :up, EC.relative(:right, :left)
  end

  def test_motion_summary_ignores_jumps_and_counts_moving_frames
    rows = [[10, 5, 0], [11, 5, 0], [11, 5, 1], [12, 5, 0], [80, 5, 0], [80, 6, 0]]
    summary = EC.motion_summary(rows)
    assert_equal 3, summary[:moving_frames]
    assert_equal({ x: 2, y: 1 }, summary[:axes])
    assert_equal 4, summary[:frames]
  end
end
