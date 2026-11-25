require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'koholint/viewer/island'

class IslandTest < Minitest::Test
  RUNS = File.expand_path('../runs', __dir__)
  SWORD = '20261111-194737-9ba1'.freeze
  VAL = '20261120-151729-2ce4'.freeze

  def island
    Dir.mktmpdir do |root|
      [SWORD, VAL].each { |id| FileUtils.cp_r(File.join(RUNS, id), root) }
      return Koholint::Viewer::Island.build([root])
    end
  end

  def test_the_first_gain_of_each_item_is_placed_on_the_screen_it_was_found_from
    gains = island[:gains]
    assert_equal [[4, 'shield', '163/16', 'C11', '2026-11-11'], [1, 'sword', 'C16', 'C16', '2026-11-11']],
                 gains.map { |gain| gain.values_at(:item, :name, :place, :screen, :date) }
  end

  def test_the_furthest_run_holds_the_most_items_and_its_open_leads_come_by_importance
    built = island
    assert_equal 2, built[:runs]
    assert_equal SWORD, built[:furthest]
    assert_equal [1, 4], built[:held]
    importances = built[:next].map { |lead| lead[:importance] }
    assert_equal importances.sort_by { |importance| Koholint::Viewer::Island::IMPORTANCE.index(importance) }, importances
    assert_includes built[:next].map { |lead| lead[:quote] }, 'réveiller le Poisson-Rêve'
    assert_equal 'C11', built[:next].find { |lead| lead[:place] == '163/16' }[:screen]
    assert(built[:items].any? { |item| item[:id] == 1 && item[:name] == 'sword' })
  end

  def test_places_carry_deaths_heat_and_exits_without_doors
    places = island[:places].to_h { |place| [place[:label], place] }
    assert_equal 2, places['B15'][:deaths]
    c11 = places['C11']
    assert_equal 2, c11[:runs]
    assert_equal '2026-11-11', c11[:first][:date]
    assert_operator c11[:heat].sum, :>, 0
    assert_equal Koholint::Atlas::HEAT_COLS * Koholint::Atlas::HEAT_ROWS, c11[:heat].size
    assert(c11[:exits].all? { |to, count| places.key?(to) && count.positive? })
    refute_includes c11[:exits].map(&:first), '163/16'
  end
end
