require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/viewer'
require 'koholint/engine'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'

class RegistryTest < Minitest::Test
  class StubFollower
    attr_reader :frame, :requests

    def initialize(total: 10_000, fail: false)
      @frame = 0
      @total = total
      @fail = fail
      @requests = []
    end

    def journal_frames = @total
    def lag = @total - @frame
    def sync = :unknown
    def frame_png = "png#{@frame}"

    def step_available(max_frames:)
      raise Koholint::Error, 'replay broke' if @fail

      @requests << max_frames
      count = [max_frames, lag].min
      @frame += count
      count
    end
  end

  def setup
    @now = 0.0
    @built = []
  end

  def registry(max: 3, idle: 300, follower: -> { StubFollower.new }, err: StringIO.new)
    factory = lambda do |dir|
      @built << dir
      follower.call
    end
    Koholint::Viewer::Registry.new(factory:, clock: -> { @now }, max:, idle:, err:)
  end

  def test_a_follower_is_built_once_per_run_and_reused
    reg = registry
    first = reg.fetch('a').follower
    assert_same first, reg.fetch('a').follower
    assert_equal %w[a], @built
  end

  def test_the_least_recently_used_replay_is_evicted_past_the_cap
    reg = registry(max: 3)
    %w[a b c].each { |dir| reg.fetch(dir) }
    reg.fetch('a')
    reg.fetch('d')
    assert_equal %w[c a d], reg.dirs
    assert_raises(Koholint::Viewer::Registry::Expired) { reg.fetch('b') }
    reg.open('b')
    reg.fetch('b')
    assert_equal %w[a b c d b], @built
  end

  def test_an_idle_replay_is_evicted_on_the_next_tick
    reg = registry(idle: 300)
    reg.fetch('a')
    @now = 200.0
    reg.fetch('b')
    @now = 301.0
    reg.tick
    assert_equal %w[b], reg.dirs
    error = assert_raises(Koholint::Viewer::Registry::Expired) { reg.state('a') }
    assert_equal 'replay expired: reload the page', error.message
    assert_equal %w[a b], @built
  end

  def test_tick_advances_in_real_time_at_the_chosen_speed
    reg = registry
    follower = reg.fetch('a').follower
    @now = 0.5
    reg.tick
    assert_equal 30, follower.frame
    reg.control('a', speed: 4)
    @now = 1.0
    reg.tick
    assert_equal 150, follower.frame
    assert(follower.requests.all? { |n| n <= Koholint::Viewer::Registry::STEP_CHUNK })
  end

  def test_owed_frames_are_capped_to_one_second
    reg = registry
    follower = reg.fetch('a').follower
    reg.control('a', speed: 16)
    @now = 100.0
    reg.fetch('a')
    reg.tick
    assert_equal 960, follower.frame
  end

  def test_a_paused_replay_does_not_advance_and_resumes_from_now
    reg = registry
    follower = reg.fetch('a').follower
    assert_equal({ speed: 1, paused: true }, reg.control('a', paused: true))
    @now = 1.0
    reg.tick
    assert_equal 0, follower.frame
    reg.control('a', paused: false)
    @now = 1.5
    reg.tick
    assert_equal 30, follower.frame
  end

  def test_an_unknown_speed_is_refused
    assert_raises(ArgumentError) { registry.control('a', speed: 2) }
  end

  def test_a_failing_replay_is_dropped_with_one_line
    err = StringIO.new
    reg = registry(follower: -> { StubFollower.new(fail: true) }, err:)
    reg.fetch('/runs/a')
    @now = 1.0
    reg.tick
    assert_empty reg.dirs
    assert_equal "koholint: replay of a: replay broke\n", err.string
  end

  def test_state_is_the_feed_up_to_the_follower_frame_with_controls
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'manifest.json'), JSON.generate('flow_version' => 'f', 'status' => 'stopped'))
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:action, frame: 10, skill: 'press', params: {}, result: {})
      trace.emit(:action, frame: 90, skill: 'press', params: {}, result: {})
      reg = registry
      reg.fetch(dir)
      @now = 0.5
      reg.tick
      state = reg.state(dir)
      assert_equal [10], state[:events].map { |e| e[:frame] }
      assert_equal({ speed: 1, paused: false }, state[:replay].slice(:speed, :paused))
      assert_equal 30, state[:replay][:frame]
    end
  end

  def test_a_slow_build_does_not_block_other_replays_and_a_duplicate_is_discarded
    entered = Queue.new
    release = Queue.new
    followers = []
    factory = lambda do |dir|
      if dir == 'slow'
        entered << true
        release.pop
      end
      StubFollower.new.tap { |follower| followers << follower }
    end
    reg = Koholint::Viewer::Registry.new(factory:, clock: -> { @now })
    first = Thread.new { reg.fetch('slow') }
    second = Thread.new { reg.fetch('slow') }
    2.times { entered.pop }
    assert_equal %w[fast], [reg.fetch('fast').dir]
    2.times { release << true }
    assert_same first.value, second.value
    assert_equal 3, followers.size
    assert_equal %w[fast slow], reg.dirs
  end

  def test_a_failure_does_not_drop_a_newer_replay_of_the_same_run
    reg = nil
    replacement = StubFollower.new
    failing = StubFollower.new(fail: true)
    failing.define_singleton_method(:step_available) do |max_frames:|
      reg.send(:expire, 'a')
      reg.open('a')
      raise Koholint::Error, "replay broke at #{max_frames}"
    end
    built = [failing, replacement]
    reg = Koholint::Viewer::Registry.new(factory: ->(_dir) { built.shift }, clock: -> { @now }, err: StringIO.new)
    reg.fetch('a')
    @now = 1.0
    reg.instance_variable_get(:@entries)['a'].owed = 0.0
    reg.tick
    assert_equal %w[], reg.dirs
    assert_same replacement, reg.fetch('a').follower
    assert_equal %w[a], reg.dirs
  end

  def test_a_real_replay_starts_at_frame_zero_even_with_keyframes
    skip_without_rom!
    Dir.mktmpdir do |root|
      run = Koholint::Run.create(root:, flow_version: Koholint::FLOW_VERSION, budget: {})
      policy = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new)
      Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new(frames: 2400), keyframe_every: 300).run
      refute_empty Dir.children(File.join(run.dir, 'keyframes'))
      reg = Koholint::Viewer::Registry.new(clock: -> { @now })
      follower = reg.fetch(run.dir).follower
      assert_equal 0, follower.frame
      @now = 0.5
      reg.tick
      assert_equal 30, follower.frame
      @now = 1.0
      reg.tick
      assert_equal 60, follower.frame
    end
  end
end
