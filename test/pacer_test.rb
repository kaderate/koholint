require_relative 'test_helper'
require 'tmpdir'
require 'koholint/engine'
require 'koholint/pacer'
require 'koholint/policies/walk_and_talk'

class PacerTest < Minitest::Test
  class FakeClock
    attr_accessor :now, :slept

    def initialize = (@now = 100.0
                      @slept = [])
    def sleeper = ->(seconds) { @slept << seconds; @now += seconds }
    def clock = -> { @now }
  end

  def test_sleeps_to_hold_sixty_frames_per_second
    fake = FakeClock.new
    pacer = Koholint::Pacer.new(fps: 60, clock: fake.clock, sleeper: fake.sleeper)
    pacer.pace(30)
    assert_in_delta 0.5, fake.slept.sum, 1e-9
    pacer.pace(90)
    assert_in_delta 2.0, fake.slept.sum, 1e-9
  end

  def test_does_not_sleep_when_behind_schedule
    fake = FakeClock.new
    pacer = Koholint::Pacer.new(fps: 60, clock: fake.clock, sleeper: fake.sleeper)
    pacer.pace(60)
    fake.now += 1.9
    fake.slept.clear
    pacer.pace(60)
    assert_empty fake.slept
  end

  def test_reanchors_after_a_long_stall
    fake = FakeClock.new
    pacer = Koholint::Pacer.new(fps: 60, clock: fake.clock, sleeper: fake.sleeper)
    pacer.pace(60)
    fake.now += 30
    fake.slept.clear
    pacer.pace(60)
    assert_in_delta 1.0, fake.slept.sum, 1e-9
    pacer.pace(60)
    assert_in_delta 2.0, fake.slept.sum, 1e-9
  end

  def test_realtime_does_not_change_journal_or_state
    skip_without_rom!
    Dir.mktmpdir do |dir|
      results = [nil, true].map do |paced|
        run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
        fake = FakeClock.new
        pacer = paced && Koholint::Pacer.new(clock: fake.clock, sleeper: fake.sleeper)
        engine = Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new,
                                      budget: Koholint::Budget.new(frames: 200), pacer: pacer)
        engine.run
        assert_operator fake.slept.sum, :>, 3.0 if paced
        [File.binread(File.join(run.dir, 'inputs.log')), engine.instance_variable_get(:@emulator).state_hash]
      end
      assert_equal results[0], results[1]
    end
  end
end
