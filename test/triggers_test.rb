require_relative 'test_helper'
require 'koholint/triggers'

class TriggersTest < Minitest::Test
  PLACE = [163, 16].freeze

  def result(before: false, after: true, row: 3, col: 4, place: PLACE)
    spot = { room: place[0], map: place[1], row:, col: }
    { from: spot, to: spot, dialog_before: before, dialog_after: after }
  end

  def action(skill, params, result) = { 'type' => 'action', 'skill' => skill, 'params' => params, 'result' => result.transform_keys(&:to_s) }

  def test_records_and_counts_per_place_and_cell
    triggers = Koholint::Triggers.new
    2.times { triggers.record(place: PLACE, cell: [3, 4], skill: 'walk', direction: 'up') }
    triggers.record(place: PLACE, cell: [3, 4], skill: 'goto')
    assert_equal 3, triggers.count(PLACE, [3, 4])
    assert_equal 0, triggers.count(PLACE, [3, 5])
    assert_equal 0, triggers.count([1, 2], [3, 4])
  end

  def test_reset_unless_keeps_only_the_given_place
    triggers = Koholint::Triggers.new
    triggers.record(place: PLACE, cell: [3, 4], skill: 'walk')
    triggers.record(place: [1, 2], cell: [3, 4], skill: 'walk')
    triggers.reset_unless([1, 2])
    assert_equal 0, triggers.count(PLACE, [3, 4])
    assert_equal 1, triggers.count([1, 2], [3, 4])
  end

  def test_scripted_rule
    scripted = ->(skill, params = {}, res = result) { Koholint::Triggers.scripted?(skill:, params:, result: res) }
    assert scripted.call('walk')
    assert scripted.call('goto')
    assert scripted.call('wait')
    assert scripted.call('press', { button: :b, frames: 3 })
    refute scripted.call('press', { button: :a, frames: 3 })
    refute scripted.call('press', { 'button' => 'a', 'frames' => 3 })
    refute scripted.call('advance_dialogue')
    refute scripted.call('talk_to', { row: 1, col: 1 })
    refute scripted.call('walk', {}, result(before: true))
    refute scripted.call('walk', {}, result(after: false))
  end

  def test_from_events_with_string_keys_and_a_place_change
    events = [action('walk', { 'direction' => 'up' }, result), action('goto', { 'row' => 1, 'col' => 1 }, result),
              action('talk_to', { 'row' => 1, 'col' => 1 }, result), action('advance_dialogue', {}, result),
              action('press', { 'button' => 'a', 'frames' => 3 }, result), action('walk', {}, result(before: true))]
    triggers = Koholint::Triggers.from_events(events)
    assert_equal 2, triggers.count(PLACE, [3, 4])
    other = result(place: [9, 9])
    moved = action('walk', {}, { from: result[:from], to: other[:to], dialog_before: false, dialog_after: false })
    assert_equal 0, Koholint::Triggers.from_events(events + [moved]).count(PLACE, [3, 4])
  end
end
