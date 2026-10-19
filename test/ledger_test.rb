require_relative 'test_helper'
require 'json'
require 'koholint/ledger'

class LedgerTest < Minitest::Test
  PLACE = [163, 16].freeze

  def blocked(row: 3, col: 4, direction: :up) = { row:, col:, direction: }

  def test_doubtful_at_two_not_at_one
    ledger = Koholint::Ledger.new
    ledger.record(place: PLACE, blocked_at: blocked)
    refute ledger.doubtful?(PLACE, [3, 4], :up)
    ledger.record(place: PLACE, blocked_at: blocked(direction: 'up'))
    assert ledger.doubtful?(PLACE, [3, 4], :up)
    assert_equal 2, ledger.count(PLACE, [3, 4], 'up')
    assert_equal 0, ledger.count(PLACE, [3, 4], :down)
  end

  def test_entered_clears_the_edge
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: blocked) }
    ledger.entered(place: PLACE, cell: [3, 4], direction: :up)
    refute ledger.doubtful?(PLACE, [3, 4], :up)
    assert_equal 0, ledger.count(PLACE, [3, 4], :up)
  end

  def test_changing_place_resets
    ledger = Koholint::Ledger.new
    2.times { ledger.record(place: PLACE, blocked_at: blocked) }
    ledger.reset_unless(PLACE)
    assert ledger.doubtful?(PLACE, [3, 4], :up)
    ledger.reset_unless([1, 2])
    assert_equal 0, ledger.count(PLACE, [3, 4], :up)
  end

  def test_from_events_equals_the_incremental_ledger_including_json_keys
    events = [
      { type: :action, result: { blocked_at: blocked, from: { room: 163, map: 16 } } },
      { type: :action, result: { frames: 3 } },
      { type: :action, result: { blocked_at: blocked, from: { room: 163, map: 16 } } },
      { type: :screen }
    ]
    parsed = JSON.parse(events.to_json)
    [events, parsed].each do |source|
      ledger = Koholint::Ledger.from_events(source)
      assert_equal 2, ledger.count(PLACE, [3, 4], :up)
      assert ledger.doubtful?(PLACE, [3, 4], :up)
    end
  end
end
