require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/summary'
require 'support/emulator_cache'

class StartGameTest < Minitest::Test
  def state(frame, hp: 0, x: 0) = Koholint::GameState.new(frame: frame, hp: hp, x: x, milestone: :none)

  def policy = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new)

  def test_macro_point_validates_free_form_macros_only
    point = Koholint::DecisionPoint.macro(:boot)
    assert_equal({ buttons: [:start], frames: 3 }, point.validate({ buttons: [:start], frames: 3 }))
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ buttons: [:bogus], frames: 3 }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ buttons: [:a], frames: 0 }) }
    assert_raises(Koholint::DecisionPoint::Invalid) { point.validate({ buttons: [:a], frames: 100_000 }) }
  end

  def test_uses_the_boot_script_until_link_is_controllable
    point = policy.point_for(state(0))
    assert_equal :boot, point.name
    result = policy.decide(point, state(0), {})
    assert_equal({ buttons: [:start], frames: 10 }, result[:choice])
    assert_equal 'start_game', result[:agent]
  end

  def test_hands_over_to_the_walking_policy_once_link_has_hp_and_a_position
    controllable = state(6201, hp: 24, x: 80)
    assert_equal :move, policy.point_for(controllable).name
    assert_equal 'walk_and_talk', policy.decide(policy.point_for(controllable), controllable, {})[:agent]
  end

  def run_from(emulator, frames)
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      Koholint::Engine.new(run: run, policy: policy, emulator: emulator, budget: Koholint::Budget.new(frames: frames)).run
      yield Koholint::Summary.for(run), Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).select { |e| e['type'] == 'perception' }
    end
  end

  def test_engine_run_from_the_title_screen_reaches_a_playable_state
    skip_without_rom!
    run_from(EmulatorCache.at(5900), 700) do |summary, states|
      assert_equal [5900, 0], [states.first['frame'], states.first['state']['hp']]
      assert_equal 3.0, summary[:hearts]
      assert_equal [163, 16], states.last['state'].values_at('room_id', 'map_id')
    end
  end

  def test_full_boot_reaches_a_playable_state
    skip 'set E2E=1 to run the full boot from frame 0' unless ENV['E2E']
    skip_without_rom!
    run_from(Koholint::Emulator.boot, 6600) do |summary, states|
      assert_equal 3.0, summary[:hearts]
      assert_empty states.select { |e| e['frame'] < 6000 && e['state']['hp'].positive? }
    end
  end
end
