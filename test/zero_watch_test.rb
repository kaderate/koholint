require_relative 'test_helper'
require 'koholint/zero_watch'

class ZeroWatchTest < Minitest::Test
  def action(skill, stop, frames, room: 164, cells: nil, to: room)
    { 'type' => 'action', 'skill' => skill,
      'result' => { 'from' => { 'room' => room, 'map' => 17 }, 'to' => { 'room' => to, 'map' => 17 }, 'stopped_by' => stop, 'frames' => frames, 'cells_walked' => cells }.compact }
  end

  def test_explores_that_walk_no_cell_count_over_a_visit_whatever_is_done_between_them
    idle = action('explore', 'no_frontier', 40, cells: 0)
    goto = action('goto', 'done', 60)
    watch = Koholint::ZeroWatch.from_events([idle, goto, action('explore', 'no_frontier', 1), goto, idle])
    assert watch.due?([164, 17])
    assert_equal({ skill: 'explore', stop: 'no_frontier', count: 3, mark: Koholint::ZeroWatch::IDLE_MARK }, watch.streak)
    refute Koholint::ZeroWatch.from_events([idle, goto, idle, goto]).due?([164, 17]), 'only right after the idle explore'
    refute Koholint::ZeroWatch.from_events([idle, idle, action('explore', 'no_frontier', 90, cells: 4), idle]).due?([164, 17]), 'an explore that walked resets'
    refute Koholint::ZeroWatch.from_events([idle, idle, action('walk', 'room_change', 20, to: 165), idle]).due?([164, 17]), 'leaving the place resets'
    watch = Koholint::ZeroWatch.from_events([idle, goto, idle, goto, idle, cap('explore'), idle])
    refute watch.due?([164, 17]), 'the harness answer was already given'
    refute watch.explore?, 'its explore walked no cell'
    assert Koholint::ZeroWatch.from_events([idle, goto, idle, goto, idle, cap('explore'), idle, goto, idle]).due?([164, 17])
    decision = ->(held) { { 'type' => 'decision', 'input' => { 'milestone' => 'sword', 'item_a' => held, 'inventory' => [] }, 'choice' => { 'skill' => 'explore' } } }
    resets = { 'an item' => [decision.(1), idle, idle, decision.(2), idle], 'a lead' => [idle, idle, { 'type' => 'lead', 'id' => 'l1' }, idle],
               'a goal' => [idle, idle, { 'type' => 'goal', 'text' => 'g' }, idle], 'a longer skill' => [idle, idle, action('talk_to', 'done', 61), idle] }
    resets.each { |what, events| refute Koholint::ZeroWatch.from_events(events).due?([164, 17]), what }
    assert Koholint::ZeroWatch.from_events([decision.(1), idle, action('talk_to', 'no_path', 2), decision.(1), idle, idle]).due?([164, 17]), 'a short skill and the same context keep the count'
  end

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
