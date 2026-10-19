require_relative 'test_helper'
require 'koholint/decision'
require 'koholint/game_state'
require 'koholint/policies/walk_and_talk'
require 'koholint/policies/with_fallback'

class DecisionTest < Minitest::Test
  def state(frame) = Koholint::GameState.new(frame: frame, milestone: :none)

  def test_invalid_choice_raises
    decision_point = Koholint::DecisionPoint.move
    assert_raises(Koholint::DecisionPoint::Invalid) { decision_point.validate({ buttons: [:b], frames: 5 }) }
    assert_equal decision_point.options.first, decision_point.validate(decision_point.options.first)
  end

  def test_walk_and_talk_is_deterministic_for_same_frame
    decision_point = Koholint::DecisionPoint.move
    policy = Koholint::Policies::WalkAndTalk.new
    first = policy.decide(decision_point, state(95), {})
    assert_equal first, policy.decide(decision_point, state(95), {})
    assert_includes decision_point.options, first[:choice]
    assert_equal 'walk_and_talk', first[:agent]
  end

  def test_walk_and_talk_presses_a_every_tenth_cycle
    decision_point = Koholint::DecisionPoint.move
    policy = Koholint::Policies::WalkAndTalk.new
    assert_equal({ buttons: [:up], frames: 30 }, policy.decide(decision_point, state(0), {})[:choice])
    assert_equal({ buttons: [:right], frames: 30 }, policy.decide(decision_point, state(30), {})[:choice])
    assert_equal({ buttons: [:a], frames: 2 }, policy.decide(decision_point, state(30 * 9), {})[:choice])
  end

  class BadPrimary
    attr_reader :calls

    def initialize = @calls = 0

    def decide(_decision_point, _state, _context)
      @calls += 1
      { choice: { buttons: [:b], frames: 1 }, justification: 'x', confidence: 1.0, agent: 'bad' }
    end
  end

  def test_fallback_used_after_one_retry
    decision_point = Koholint::DecisionPoint.move
    primary = BadPrimary.new
    result = Koholint::Policies::WithFallback.new(primary, Koholint::Policies::WalkAndTalk.new).decide(decision_point, state(0), {})
    assert_equal 2, primary.calls
    assert result[:fallback]
    assert_equal 'walk_and_talk', result[:agent]
  end

  def test_valid_primary_is_not_flagged
    decision_point = Koholint::DecisionPoint.move
    result = Koholint::Policies::WithFallback.new(Koholint::Policies::WalkAndTalk.new, BadPrimary.new).decide(decision_point, state(0), {})
    refute result[:fallback]
  end
end
