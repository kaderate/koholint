require_relative 'test_helper'
require 'tmpdir'
require 'koholint/run'
require 'koholint/keyframes'
require 'koholint/replay'

class ReplayTest < Minitest::Test
  FRAMES = 900
  SCRIPT = Array.new(FRAMES) { |i| i < 10 ? [:start] : (i % 97 < 5 ? [:a] : (i % 200 < 100 ? [:down] : [])) }

  def live_run(dir)
    run = Koholint::Run.create(root: dir, flow_version: 'f1', budget: {})
    keyframes = Koholint::Keyframes.new(File.join(run.dir, 'keyframes'))
    emulator = Koholint::Emulator.boot
    hashes = {}
    SCRIPT.each_with_index do |buttons, i|
      emulator.step(buttons)
      run.inputs.append(buttons)
      hashes[emulator.frame] = emulator.state_hash if [450, 700, FRAMES].include?(emulator.frame)
      keyframes.save(emulator) if i + 1 == 450
    end
    run.inputs.flush
    [run, hashes]
  end

  def test_replay_to_frame_equals_live_state_hash
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run, hashes = live_run(dir)
      assert_equal hashes[700], Koholint::Replay.to(run, 700).state_hash
      FileUtils.rm_rf(File.join(run.dir, 'keyframes'))
      FileUtils.mkdir_p(File.join(run.dir, 'keyframes'))
      assert_equal hashes[700], Koholint::Replay.to(run, 700).state_hash
    end
  end

  def test_nearest_keyframe_at_or_before
    Dir.mktmpdir do |dir|
      keyframes = Koholint::Keyframes.new(dir)
      File.write(File.join(dir, 'kf-000000450.zlib'), 'x')
      File.write(File.join(dir, 'kf-000001800.zlib'), 'x')
      assert_nil keyframes.nearest_at_or_before(100)
      assert_equal 450, keyframes.nearest_at_or_before(1000).first
      assert_equal 1800, keyframes.nearest_at_or_before(1800).first
    end
  end

  def test_fork_is_independent
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run, = live_run(dir)
      before = Dir.glob("#{run.dir}/**/*").select { |f| File.file?(f) }.to_h { |f| [f, File.binread(f)] }
      child = run.fork(at_frame: 600, flow_version: 'f2')
      after = Dir.glob("#{run.dir}/**/*").select { |f| File.file?(f) }.to_h { |f| [f, File.binread(f)] }
      assert_equal before, after
      assert_equal 600, child.inputs.frames
      assert_equal({ 'id' => run.id, 'frame' => 600 }, child.manifest['parent'])
      assert_equal 'f2', child.manifest['flow_version']
      assert_equal Koholint::Replay.to(run, 600).state_hash, Koholint::Replay.to(child, 600).state_hash
    end
  end

  def test_verify_matches_recorded_perception_hashes
    skip_without_rom!
    Dir.mktmpdir do |dir|
      run, hashes = live_run(dir)
      run.trace.emit(:perception, frame: 450, state: {}, state_hash: hashes[450])
      run.trace.emit(:perception, frame: 700, state: {}, state_hash: 'wrong')
      assert_equal [[450, true], [700, false]], Koholint::Replay.verify(run, every: 100)
    end
  end

  def test_keyframes_dir_is_gitignored
    assert system('git', 'check-ignore', '-q', 'runs/abc/keyframes/kf-000000001.zlib')
  end
end
