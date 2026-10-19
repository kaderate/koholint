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

  def objective_point = Koholint::DecisionPoint.choose_objective

  def test_choose_objective_accepts_good_outputs
    point = objective_point
    assert_equal :choose_objective, point.name
    assert_nil point.options
    assert_equal %i[title predicate], point.output_schema
    good = { title: 'Leave', predicate: { kind: 'leave_place', place: [163, 16] } }
    assert_equal good, point.validate(good)
    point.validate({ title: 'Talk', predicate: { 'kind' => 'dialogue_closed' } })
    point.validate({ title: 'Go', predicate: { kind: 'reach_cell', place: [1, 2], row: 3, col: 4 } })
  end

  def test_choose_objective_rejects_bad_outputs
    point = objective_point
    [{ title: '', predicate: { kind: 'dialogue_closed' } }, { title: 7, predicate: { kind: 'dialogue_closed' } },
     { title: 'x', predicate: { kind: 'win' } }, { title: 'x', predicate: { kind: 'reach_cell', place: [1, 2] } },
     { title: 'x', predicate: { kind: 'leave_place', place: 'x' } }, { title: 'x' }].each do |choice|
      assert_raises(Koholint::DecisionPoint::Invalid, choice.inspect) { point.validate(choice) }
    end
  end

  def test_choose_objective_json_schema
    schema = objective_point.json_schema
    assert_equal 'object', schema[:type]
    assert_equal %w[title predicate justification confidence], schema[:required]
    kinds = schema[:properties][:predicate][:oneOf].map { |p| p[:properties][:kind][:enum] }
    assert_equal [%w[leave_place], %w[reach_place], %w[reach_cell], %w[dialogue_closed]], kinds
    reach_cell = schema[:properties][:predicate][:oneOf][2]
    assert_equal %w[kind place row col], reach_cell[:required]
    assert_equal false, reach_cell[:additionalProperties]
    JSON.parse(JSON.generate(schema))
  end
end
