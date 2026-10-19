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
      { type: :action, result: { stopped_by: 'blocked', blocked_at: blocked, from: { room: 163, map: 16 } } },
      { type: :action, result: { frames: 3 } },
      { type: :action, result: { stopped_by: 'blocked', blocked_at: blocked, from: { room: 163, map: 16 } } },
      { type: :screen }
    ]
    parsed = JSON.parse(events.to_json)
    [events, parsed].each do |source|
      ledger = Koholint::Ledger.from_events(source)
      assert_equal 2, ledger.count(PLACE, [3, 4], :up)
      assert ledger.doubtful?(PLACE, [3, 4], :up)
    end
  end

  def test_from_events_resets_on_any_place_change
    a = { room: 163, map: 16 }
    b = { room: 9, map: 1 }
    block = { stopped_by: 'blocked', blocked_at: blocked, from: a, to: a }
    events = [
      { type: 'action', result: block }, { type: 'action', result: block },
      { type: 'action', result: { stopped_by: 'room_change', from: a, to: b } },
      { type: 'action', result: { stopped_by: 'done', from: b, to: a } }
    ]
    assert_equal 0, Koholint::Ledger.from_events(events).count(PLACE, [3, 4], :up)
    assert_equal 2, Koholint::Ledger.from_events(events.first(2)).count(PLACE, [3, 4], :up)
  end

  def test_from_events_counts_any_result_carrying_blocked_at
    a = { room: 163, map: 16 }
    events = [{ type: 'action', result: { stopped_by: :done, blocked_at: blocked, from: a, to: a } },
              { type: 'action', result: { stopped_by: :blocked, blocked_at: blocked, from: a, to: a } }]
    assert_equal 2, Koholint::Ledger.from_events(events).count(PLACE, [3, 4], :up)
  end

  def test_malformed_blocked_at_is_ignored
    ledger = Koholint::Ledger.new
    [nil, {}, { row: 1, col: 2 }, { row: 1, direction: :up }].each { |bad| ledger.record(place: PLACE, blocked_at: bad) }
    assert_equal 0, ledger.count(PLACE, [1, 2], :up)
    a = { room: 163, map: 16 }
    events = [{ type: 'action', result: { stopped_by: 'blocked', blocked_at: nil, from: a, to: a } }]
    Koholint::Ledger.from_events(events)
  end

  def test_entered_leaves_other_edges
    ledger = Koholint::Ledger.new
    ledger.record(place: PLACE, blocked_at: blocked)
    ledger.record(place: PLACE, blocked_at: blocked(direction: :left))
    ledger.entered(place: PLACE, cell: [3, 4], direction: :up)
    assert_equal 1, ledger.count(PLACE, [3, 4], :left)
  end

  def test_on_doubt_fires_once_at_the_second_record
    calls = []
    ledger = Koholint::Ledger.new(on_doubt: ->(**args) { calls << args })
    ledger.record(place: PLACE, blocked_at: blocked)
    assert_empty calls
    ledger.record(place: PLACE, blocked_at: blocked)
    assert_equal [{ place: PLACE, cell: [3, 4], direction: :up, count: 2 }], calls
    ledger.record(place: PLACE, blocked_at: blocked)
    assert_equal 1, calls.size
  end
end
