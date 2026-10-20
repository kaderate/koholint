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
      assert_operator follower.compared_frames, :>, 1
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
      first_stepped = Koholint::Trace.read(path).select { |e| e['type'] == 'perception' && e['frame'].positive? }.first['frame']
      lines = File.readlines(path).map do |line|
        event = JSON.parse(line)
        event['state_hash'] = 'tampered' if event['type'] == 'perception' && event['frame'] == first_stepped
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

  def perception(run, frame, hash)
    Koholint::Trace.new(File.join(run.dir, 'trace.jsonl')).emit(:perception, frame:, state: {}, state_hash: hash)
  end

  def test_late_perception_at_the_current_frame_is_compared
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      compared = follower.compared_frames
      perception(run, 600, follower.state_hash)
      follower.step_available
      assert_equal compared + 1, follower.compared_frames
      assert_equal :in_sync, follower.sync
    end
  end

  def test_late_wrong_perception_at_the_current_frame_is_diverged
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      perception(run, 600, 'wrong')
      follower.step_available
      assert_equal :diverged, follower.sync
    end
  end

  def test_lag_jump_compares_the_landing_frame
    with_recorded_run do |run|
      File.binwrite(journal(run), [0, 4000].pack('CV'), mode: 'ab')
      landing = Dir.children(File.join(run.dir, 'keyframes')).map { |name| name[/\d+/].to_i }.max
      perception(run, landing, 'wrong')
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      follower.step_available(max_frames: 1)
      assert_equal :diverged, follower.sync
    end
  end

  def test_trace_is_read_incrementally_and_partial_lines_wait
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      path = File.join(run.dir, 'trace.jsonl')
      assert_equal File.size(path), follower.instance_variable_get(:@trace_offset)
      line = "#{JSON.generate({ v: 1, type: 'perception', frame: 0, state: {}, state_hash: 'late' })}\n"
      File.binwrite(path, line[0, 20], mode: 'ab')
      follower.step_available(max_frames: 0)
      assert_equal File.size(path) - 20, follower.instance_variable_get(:@trace_offset)
      File.binwrite(path, line[20..], mode: 'ab')
      follower.step_available(max_frames: 0)
      assert_equal File.size(path), follower.instance_variable_get(:@trace_offset)
      assert_equal :diverged, follower.sync
    end
  end

  def test_concurrent_readers_do_not_corrupt_the_follower
    with_recorded_run do |run|
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      errors = Queue.new
      readers = Array.new(3) do
        Thread.new do
          10.times do
            20.times do
              follower.lag
              follower.journal_frames
            end
            follower.frame_png
            Thread.pass
          end
        rescue StandardError => e
          errors << e
        end
      end
      writer = Thread.new do
        [0, 2, 0, 16].each do |mask|
          File.binwrite(journal(run), [mask, 50].pack('CV'), mode: 'ab')
          Thread.pass
        end
      end
      stepper = Thread.new do
        follower.step_available(max_frames: 25) while follower.frame < 800 || writer.alive?
      rescue StandardError => e
        errors << e
      end
      stepper.join
      writer.join
      readers.each(&:join)
      assert_predicate errors, :empty?
      assert_equal 800, follower.frame
      reopened = Koholint::Run.open(run.dir, flow_version: Koholint::FLOW_VERSION)
      assert_equal Koholint::Replay.to(reopened, 800).state_hash, follower.state_hash
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

  def keyframe_files(run) = Dir.glob(File.join(run.dir, 'keyframes', 'kf-*.zlib')).sort

  def test_corrupt_newest_keyframe_falls_back_to_an_older_one_at_start
    with_recorded_run do |run|
      files = keyframe_files(run)
      assert_operator files.size, :>=, 2
      File.binwrite(files.last, 'not a keyframe')
      follower = Koholint::Viewer::Follower.new(run.dir)
      assert_equal files[-2][/kf-(\d+)/, 1].to_i, follower.frame
    end
  end

  def test_all_keyframes_corrupt_boots_from_frame_zero
    with_recorded_run do |run|
      keyframe_files(run).each { |file| File.binwrite(file, '') }
      follower = Koholint::Viewer::Follower.new(run.dir)
      assert_equal 0, follower.frame
      assert_operator follower.step_available(max_frames: 5), :>, 0
    end
  end

  def test_corrupt_keyframe_does_not_kill_a_lag_jump
    with_recorded_run do |run|
      File.binwrite(journal(run), [0, 4000].pack('CV'), mode: 'ab')
      keyframe_files(run).each { |file| File.binwrite(file, 'garbage') }
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start, max_lag_frames: 1800)
      assert_equal 10, follower.step_available(max_frames: 10)
      assert_equal 10, follower.frame
      assert_equal 10, follower.step_available(max_frames: 10)
      assert_equal 20, follower.frame
    end
  end

  def test_non_object_manifest_is_a_one_line_error
    %w[[] null "x" 5].each do |content|
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'manifest.json'), content)
        File.binwrite(File.join(dir, 'inputs.log'), [2].pack('C'))
        error = assert_raises(Koholint::Error) { Koholint::Viewer::Follower.new(dir) }
        refute_includes error.message, "\n"
      end
    end
  end

  def test_follows_an_archived_run_from_its_gzipped_trace
    with_recorded_run do |run|
      path = File.join(run.dir, 'trace.jsonl')
      Koholint::Trace.compress(path)
      File.delete(path)
      follower = Koholint::Viewer::Follower.new(run.dir, from: :start)
      drain(follower)
      assert_equal :in_sync, follower.sync
      assert_operator follower.compared_frames, :>, 1
    end
  end
end
