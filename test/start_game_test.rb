require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/summary'

class StartGameTest < Minitest::Test
  def state(frame: 0, hp: 0, x: 0, mode: 0, sub: 0, name_length: 0)
    Koholint::GameState.new(frame:, hp:, x:, game_mode: mode, game_submode: sub, name_length:, milestone: :none)
  end

  def policy = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new)

  def test_macro_point_validates_free_form_macros_only
    decision_point = Koholint::DecisionPoint.macro(:boot)
    assert_equal({ buttons: [:start], frames: 3 }, decision_point.validate({ buttons: [:start], frames: 3 }))
    assert_raises(Koholint::DecisionPoint::Invalid) { decision_point.validate({ buttons: [:bogus], frames: 3 }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { decision_point.validate({ buttons: [:a], frames: 0 }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { decision_point.validate({ buttons: [:a], frames: 100_000 }) }
  end

  def test_follows_the_game_mode_until_link_is_controllable
    s = state(mode: 2, sub: 7)
    decision_point = policy.decision_point_for(s)
    assert_equal :boot, decision_point.name
    result = policy.decide(decision_point, s, {})
    assert_equal({ buttons: [:a], frames: 3 }, result[:choice])
    assert_equal 'start_game', result[:agent]
  end

  def test_hands_over_to_the_walking_policy_once_link_has_hp_and_a_position
    controllable = state(frame: 400, hp: 24, x: 80, mode: 0x0B)
    assert_equal :move, policy.decision_point_for(controllable).name
    assert_equal 'walk_and_talk', policy.decide(policy.decision_point_for(controllable), controllable, {})[:agent]
  end

  def test_ready_policy_hands_over_only_after_two_boot_ticks_at_the_same_position
    inner = Class.new do
      attr_reader :observed

      def observe(state, **) = (@observed = state.x)
      def decision_point_for(_state) = Koholint::DecisionPoint.move
    end.new
    wrapper = Koholint::Policies::StartGame.new(inner, ready: ->(s) { s.game_mode == 0x0B })
    moving = state(frame: 300, hp: 24, x: 80, mode: 0x0B)
    wrapper.observe(moving, frame: 300)
    assert_equal :boot, wrapper.decision_point_for(moving).name
    shifted = state(frame: 305, hp: 24, x: 81, mode: 0x0B)
    wrapper.observe(shifted, frame: 305)
    assert_equal :boot, wrapper.decision_point_for(shifted).name
    assert_equal 81, inner.observed
    wrapper.observe(shifted, frame: 310)
    assert_equal :move, wrapper.decision_point_for(shifted).name
    assert_equal({ buttons: [], frames: 5 }, wrapper.decide(Koholint::DecisionPoint.macro(:boot), state(mode: 1), {})[:choice])
  end

  def test_ready_policy_hands_over_anyway_after_24_ready_ticks_of_a_moving_link
    wrapper = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new, ready: ->(s) { s.game_mode == 0x0B })
    23.times { |i| wrapper.observe(state(frame: i, hp: 24, x: 80 + i, mode: 0x0B), frame: i) }
    assert_equal :boot, wrapper.decision_point_for(state(hp: 24, x: 200, mode: 0x0B)).name
    wrapper.observe(state(frame: 24, hp: 24, x: 150, mode: 0x0B), frame: 24)
    assert_equal :move, wrapper.decision_point_for(state(hp: 24, x: 150, mode: 0x0B)).name
  end

  def test_engine_run_from_a_cold_boot_reaches_a_playable_state_quickly
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      Koholint::Engine.new(run: run, policy: policy, budget: Koholint::Budget.new(frames: 900)).run
      states = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).select { |e| e['type'] == 'perception' }
      playable = states.find { |e| e['state']['hp'].positive? && e['state']['x'].positive? }
      assert playable, 'never became controllable'
      assert_operator playable['frame'], :<, 700
      assert_equal [163, 16], playable['state'].values_at('room_id', 'map_id')
      assert_equal 3.0, Koholint::Summary.for(run)[:hearts]
      modes = states.map { |e| e['state']['game_mode'] }.uniq
      assert_equal [0, 2, 3], modes.first(3)
    end
  end
end
