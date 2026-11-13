require_relative 'test_helper'
require 'koholint/zero_watch'

class ZeroWatchTest < Minitest::Test
  def action(skill, stop, frames, room: 164) = { 'type' => 'action', 'skill' => skill, 'result' => { 'from' => { 'room' => room, 'map' => 17 }, 'stopped_by' => stop, 'frames' => frames } }

  def cap(skill) = { 'type' => 'decision', 'agent' => 'delegated', 'choice' => { 'skill' => skill }, 'justification' => "explore ended no_frontier #{Koholint::ZeroWatch::MARK} 3 times here: x" }

  def test_a_resume_rebuilds_the_streak_and_the_harness_answers
    events = Array.new(3) { action('explore', 'no_frontier', 1) }
    watch = Koholint::ZeroWatch.from_events(events)
    assert watch.due?([164, 17])
    assert_equal [[[164, 17], 'explore', 'no_frontier'], 3], [watch.key, watch.count]
    refute watch.due?([160, 0])
    watch = Koholint::ZeroWatch.from_events(events + [cap('explore'), action('explore', 'no_frontier', 1)])
    refute watch.due?([164, 17]), 'the harness answer was already given'
    refute watch.explore?, 'its explore came back instantly'
    watch = Koholint::ZeroWatch.from_events(events + [cap('explore'), action('explore', 'no_frontier', 1), action('explore', 'no_frontier', 1)])
    assert watch.due?([164, 17])
    refute watch.explore?
    refute Koholint::ZeroWatch.from_events(events + [action('walk', 'done', 16)]).due?([164, 17])
  end
end
