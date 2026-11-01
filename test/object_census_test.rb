require_relative 'test_helper'
require 'tmpdir'
require 'koholint/probes/object_census'
require 'koholint/probes/door_census'
require 'support/emulator_cache'

class ObjectCensusTest < Minitest::Test
  STARTING_HOUSE_RUN = File.expand_path('../runs/20261020-085011-8330', __dir__)
  DOOR_RUN = File.expand_path('../runs/20261024-184627-b97e', __dir__)

  def test_the_starting_house_dresser_answers_a_from_below_only_and_people_are_cleared
    skip_without_rom!
    emulator = EmulatorCache.replayed(STARTING_HOUSE_RUN, 2500)
    Dir.mktmpdir do |dir|
      report = Koholint::Probes::ObjectCensus.scan(emulator, cells: [[1, 7], [3, 4], [4, 7]], out: dir)
      assert_equal [163, 16], report[:place]
      assert_equal 153, report[:objects][0][7]
      assert_equal [[[1, 7], :up, 154, false]], report[:hits].map { |hit| hit.values_at(:cell, :side, :object, :control) }
      assert File.file?(File.join(dir, 'pages', report[:hits].first[:page]))
    end
  end

  def test_the_starting_house_door_takes_link_inside_and_the_wall_above_it_does_not
    skip_without_rom!
    emulator = EmulatorCache.replayed(DOOR_RUN, 5900)
    report = Koholint::Probes::DoorCensus.scan(emulator, cells: [[4, 5], [3, 5], [4, 4]])
    assert_equal [162, 0], report[:place]
    assert_equal 226, report[:objects][4][5]
    assert_equal [[[4, 5], 226, [163, 16]]], report[:tries].select { |t| t[:entered] }.map { |t| t.values_at(:cell, :object, :entered) }
  end
end
