require_relative 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'koholint/viewer/island'

class IslandTest < Minitest::Test
  PLAYING = { 'hp' => 24, 'max_hp' => 24, 'game_mode' => 0x0B, 'game_submode' => 7, 'x' => 40, 'y' => 56 }.freeze
  FIRST = '20261101-100000-aaaa'.freeze
  FORK = '20261102-100000-bbbb'.freeze

  def make_run(root, id, events, parent: nil)
    dir = File.join(root, id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'manifest.json'), JSON.generate({ 'flow_version' => 'flow-1', 'parent' => parent }.compact))
    trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
    events.each { |type, fields| trace.emit(type, **fields) }
  end

  def at(frame, room, map = 0, **state) = [:perception, { frame:, state: PLAYING.merge('room_id' => room, 'map_id' => map).merge(state.transform_keys(&:to_s)), state_hash: 'h' }]

  def island
    Dir.mktmpdir do |root|
      make_run(root, FIRST, [at(1, 162), at(5, 163, 16), [:item_gained, { frame: 6, place: [163, 16], item: 4, name: 'shield', held: [4] }],
                        [:notable, { frame: 7, kind: 'death', detail: {} }], at(8, 162, x: 120), at(9, 161), [:notable, { frame: 10, kind: 'death', detail: {} }]])
      make_run(root, FORK, [at(1, 161), at(60, 162), at(61, 163), [:item_gained, { frame: 62, place: [163, 0], item: 1, name: 'sword', held: [1, 4] }]],
          parent: { 'id' => FIRST, 'frame' => 50 })
      return Koholint::Viewer::Island.build([root])
    end
  end

  def test_the_first_gain_of_each_item_is_placed_on_the_screen_it_was_found_from
    assert_equal [[4, 'shield', '163/16', 'C11', '2026-11-01'], [1, 'sword', 'D11', 'D11', '2026-11-02']],
                 island[:gains].map { |gain| gain.values_at(:item, :name, :place, :screen, :date) }
  end

  def test_the_furthest_run_holds_the_most_items
    built = island
    assert_equal [2, FORK, [1, 4]], built.values_at(:runs, :furthest, :held)
    assert(built[:items].any? { |item| item[:id] == 1 && item[:name] == 'sword' })
  end

  def test_screens_carry_their_interiors_deaths_heat_and_ways
    places = island[:places].to_h { |place| [place[:label], place] }
    assert_equal ['C11'], places['163/16'][:opens_from]
    assert_equal [1, 1], places.values_at('C11', 'B11').map { |place| place[:deaths] }
    assert_equal [2, '2026-11-01'], [places['C11'][:runs], places['C11'][:first][:date]]
    heat = places['C11'][:heat]
    assert_equal Koholint::Atlas::HEAT_COLS * Koholint::Atlas::HEAT_ROWS, heat.size
    assert_equal [2, 1], [heat[(3 * Koholint::Atlas::HEAT_COLS) + 2], heat[(3 * Koholint::Atlas::HEAT_COLS) + 7]]
    assert_equal [['B11', 1], ['D11', 1]], places['C11'][:exits]
  end

  def test_next_leads_take_each_leads_newest_verdict_and_come_by_importance
    lead = ->(key, status, importance) { { key:, quote: key, status:, importance:, place: 'C11' } }
    furthest = { run: FORK, parent: FIRST, leads: [lead.('owl', 'tested', 'high')] }
    first = { run: FIRST, leads: [lead.('owl', 'open', 'high'), lead.('beach', 'open', 'low'), lead.('fish', 'open', 'high')] }
    leads = Koholint::Viewer::Island.next_leads(furthest, [furthest, first], { 'C11' => 'C11' })
    assert_equal [%w[fish high], %w[beach low]], leads.map { |found| found.values_at(:quote, :importance) }
  end
end
