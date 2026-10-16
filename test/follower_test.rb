require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/engine'
require 'koholint/replay'
require 'koholint/policies/start_game'
require 'koholint/policies/walk_and_talk'
require 'koholint/viewer/follower'

class FollowerTest < Minitest::Test
  def with_recorded_run(frames: 600, keyframe_every: 300)
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      policy = Koholint::Policies::StartGame.new(Koholint::Policies::WalkAndTalk.new)
      Koholint::Engine.new(run:, policy:, budget: Koholint::Budget.new(frames:), keyframe_every:).run
      yield run
    end
  end

  def journal(run) = File.join(run.dir, 'inputs.log')

  def drain(follower)
    nil while follower.step_available(max_frames: 200).positive?
  end

  def test_follows_a_finished_run_to_the_same_state_as_replay
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      assert_equal 600, follower.frame
      assert_equal 600, follower.journal_frames
      assert_equal 0, follower.lag
      assert_equal Koholint::Replay.to(run, 600).state_hash, follower.state_hash
      assert_equal :in_sync, follower.sync
      assert_operator follower.frame_png.bytesize, :>, 100
    end
  end

  def test_live_start_restores_a_keyframe_at_or_below_the_edge
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir)
      assert_operator follower.frame, :>, 0
      assert_operator follower.frame, :<=, 600
      drain(follower)
      assert_equal 600, follower.frame
      assert_equal Koholint::Replay.to(run, 600).state_hash, follower.state_hash
    end
  end

  def test_picks_up_appended_journal_entries
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      File.binwrite(journal(run), [0, 30].pack('CV'), mode: 'ab')
      assert_equal 630, follower.journal_frames
      assert_equal 30, follower.lag
      assert_equal 10, follower.step_available(max_frames: 10)
      assert_equal 610, follower.frame
      assert_equal 20, follower.step_available(max_frames: 60)
      assert_equal 630, follower.frame
    end
  end

  def test_partial_trailing_entry_is_ignored
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      File.binwrite(journal(run), [0, 30].pack('CV')[0, 3], mode: 'ab')
      assert_equal 0, follower.step_available
      assert_equal 600, follower.frame
    end
  end

  def test_empty_run_sits_at_frame_zero
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run = Koholint::Run.create(root: dir, flow_version: Koholint::FLOW_VERSION, budget: {})
      follower = Koholint::Viewer::Follower.new(run.dir)
      assert_equal 0, follower.frame
      assert_equal 0, follower.step_available
      assert_equal :unknown, follower.sync
    end
  end

  def test_tampered_perception_hash_is_diverged
    with_recorded_run do |run|
      path = File.join(run.dir, 'trace.jsonl')
      lines = File.readlines(path).map do |line|
        event = JSON.parse(line)
        event['state_hash'] = 'tampered' if event['type'] == 'perception' && event['frame'] == 0
        JSON.generate(event)
      end
      File.write(path, "#{lines.join("\n")}\n")
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      assert_equal :diverged, follower.sync
    end
  end

  def test_large_lag_jumps_to_a_keyframe
    with_recorded_run do |run|
      File.binwrite(journal(run), [0, 4000].pack('CV'), mode: 'ab')
      last_keyframe = Dir.children(File.join(run.dir, 'keyframes')).map { |name| name[/\d+/].to_i }.max
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start, max_lag_frames: 1800)
      assert_equal 0, follower.frame
      follower.step_available(max_frames: 1)
      assert_operator follower.frame, :>=, last_keyframe
      assert_operator follower.lag, :<, 4600
    end
  end

  def test_missing_or_garbled_run_dir_raises
    Dir.mktmpdir do |dir|
      assert_raises(Koholint::Error) { Koholint::Viewer::Follower.new(File.join(dir, 'nope')) }
      File.write(File.join(dir, 'manifest.json'), '{garbage')
      error = assert_raises(Koholint::Error) { Koholint::Viewer::Follower.new(dir) }
      refute_includes error.message, "\n"
    end
  end
end
