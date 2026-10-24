require_relative 'test_helper'
require 'koholint/budget'

class BudgetTest < Minitest::Test
  class FakeClock
    attr_accessor :now

    def initialize = @now = 0.0
    def call(*) = @now
  end

  def budget(clock, **limits) = Koholint::Budget.new(clock: clock, **limits)

  def test_first_limit_reached_wins
    clock = FakeClock.new
    b = budget(clock, frames: 100, dollars: 1.0)
    b.tick(frames: 60, cost: 1.5)
    assert_equal :dollars, b.exhausted
    b.tick(frames: 60)
    assert_equal :frames, b.exhausted
  end

  def test_unlimited_never_exhausted_until_stop
    clock = FakeClock.new
    b = budget(clock)
    assert b.unlimited?
    b.tick(frames: 10_000_000, cost: 99)
    assert_nil b.exhausted
    b.stop!
    assert_equal :stopped, b.exhausted
  end

  def test_sleep_gap_is_excluded
    clock = FakeClock.new
    b = budget(clock, active_seconds: 60, sleep_gap: 120)
    b.tick
    clock.now += 3600
    b.tick
    assert_nil b.exhausted
    clock.now += 61
    b.tick
    assert_equal :time, b.exhausted
  end

  def test_steps_count
    b = budget(FakeClock.new, steps: 2)
    b.step_done
    assert_nil b.exhausted
    b.step_done
    assert_equal :steps, b.exhausted
  end

  def test_dollars_accumulate
    b = budget(FakeClock.new, dollars: 0.10)
    3.times { b.tick(cost: 0.04) }
    assert_equal :dollars, b.exhausted
  end

  def test_the_first_stop_reason_wins
    b = budget(FakeClock.new)
    b.stop!
    b.stop!(:agent_failures)
    assert_equal :stopped, b.exhausted
  end

  def test_stop_remembers_its_reason
    b = budget(FakeClock.new)
    b.stop!(:agent_failures)
    assert_equal :agent_failures, b.exhausted
    other = budget(FakeClock.new)
    other.stop!
    assert_equal :stopped, other.exhausted
  end

  def test_nearly_exhausted_by_a_share_or_a_frame_margin
    budget = Koholint::Budget.new(frames: 10_000, dollars: 1.0, clock: ->(*) { 0 })
    refute budget.nearly_exhausted?(frames: 1800, share: 0.05)
    budget.tick(frames: 8300)
    assert budget.nearly_exhausted?(frames: 1800, share: 0.05)
    refute budget.nearly_exhausted?(share: 0.05)
    budget.tick(cost: 0.96)
    assert budget.nearly_exhausted?(share: 0.05)
    refute Koholint::Budget.new.nearly_exhausted?(frames: 1800, share: 0.05)
  end
end
