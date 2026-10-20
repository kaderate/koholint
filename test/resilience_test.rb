require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'json'
require 'koholint/cli'
require 'koholint/engine'
require 'koholint/policies/walk_and_talk'

class ResilienceTest < Minitest::Test
  FLOW = Koholint::FLOW_VERSION

  def with_run(rom_dir: nil)
    Dir.mktmpdir do |dir|
      yield dir, Koholint::Run.create(root: dir, flow_version: FLOW, budget: {})
    end
  end

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    [Koholint::CLI.run(argv, out: out, err: err), out.string, err.string]
  end

  def new_engine(run, **options)
    Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new, **options)
  end

  def frames_of(run) = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).map { |e| e['frame'] }

  def crash_after(run, frames)
    engine = new_engine(run, budget: Koholint::Budget.new, keyframe_every: 120)
    engine.send(:iterate) while engine.instance_variable_get(:@emulator).frame < frames
  end

  def test_resume_after_a_crash_truncates_the_trace_to_the_journal
    skip_without_rom!
    with_run do |dir, run|
      crash_after(run, 300)
      journal = Koholint::InputLog.load(File.join(run.dir, 'inputs.log')).frames
      Koholint::Engine.resume(run.dir, policy: Koholint::Policies::WalkAndTalk.new,
                                       budget: Koholint::Budget.new(frames: 60)).run
      frames = frames_of(run)
      assert_equal frames.sort, frames, 'trace frames must never jump backwards'
      reopened = Koholint::Run.open(run.dir, flow_version: FLOW)
      assert_equal journal + 60, reopened.inputs.frames
      assert_equal journal + 60, Koholint::Summary.for(reopened)[:frames]
      assert_equal 0, cli('verify', run.dir)[0]
    end
  end

  def test_verify_ignores_checkpoints_beyond_the_journal
    skip_without_rom!
    with_run do |_dir, run|
      new_engine(run, budget: Koholint::Budget.new(frames: 90)).run
      run.trace.emit(:perception, frame: 5000, state: {}, state_hash: 'beyond')
      results = Koholint::Replay.verify(run, every: 1)
      assert(results.none? { |frame, _| frame == 5000 })
    end
  end

  def test_exception_in_policy_still_takes_the_stop_path
    skip_without_rom!
    boom = Class.new { def decide(*) = raise('policy exploded') }.new
    with_run do |_dir, run|
      error = assert_raises(RuntimeError) { Koholint::Engine.new(run: run, policy: boom, budget: Koholint::Budget.new).run }
      assert_equal 'policy exploded', error.message
      stops = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl')).select { |e| e['type'] == 'stop' }
      assert_equal ['error'], stops.map { |e| e['reason'] }
      assert_equal 'crashed', JSON.parse(File.read(File.join(run.dir, 'manifest.json')))['status']
    end
  end

  def test_steps_flag_must_be_positive
    code, _out, err = cli('run', '--steps', '0')
    assert_equal 2, code
    assert_match(/usage/i, err)
  end

  def test_missing_run_dir_is_a_one_line_error
    code, _out, err = cli('summary', '/nope/run')
    assert_equal 1, code
    assert_equal 1, err.lines.size
    assert_match(%r{/nope/run}, err)
  end

  def test_corrupt_manifest_is_a_one_line_error
    with_run do |_dir, run|
      File.write(File.join(run.dir, 'manifest.json'), '{broken')
      code, _out, err = cli('summary', run.dir)
      assert_equal [1, 1], [code, err.lines.size]
    end
  end

  def test_missing_arguments_are_usage_errors
    assert_equal 2, cli('verify')[0]
    assert_equal 2, cli('fork', '/x')[0]
  end

  def test_corrupt_input_log_is_a_koholint_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'inputs.log')
      File.binwrite(path, "\x01not zlib at all")
      assert_raises(Koholint::Error) { Koholint::InputLog.load(path) }
    end
  end

  def test_writes_are_atomic_and_leave_no_temp_files
    skip_without_rom!
    with_run do |_dir, run|
      new_engine(run, budget: Koholint::Budget.new(frames: 60)).run
      assert_empty Dir.glob(File.join(run.dir, '**', '*.tmp'))
    end
  end

  def test_fork_rejects_out_of_range_frames
    skip_without_rom!
    with_run do |_dir, run|
      new_engine(run, budget: Koholint::Budget.new(frames: 90)).run
      assert_raises(Koholint::Error) { run.fork(at_frame: 91, flow_version: 'x') }
      assert_raises(Koholint::Error) { run.fork(at_frame: -1, flow_version: 'x') }
    end
  end

  def test_fork_history_matches_the_parent_up_to_the_fork_point
    skip_without_rom!
    with_run do |_dir, run|
      new_engine(run, budget: Koholint::Budget.new(frames: 400), keyframe_every: 120).run
      child = run.fork(at_frame: 240, flow_version: 'x')
      events = Koholint::Trace.read(File.join(child.dir, 'trace.jsonl'))
      assert(events.none? { |e| %w[stop budget_stop].include?(e['type']) })
      assert(events.none? { |e| e['frame'] == 240 && %w[perception decision].include?(e['type']) })
      assert_operator events.map { |e| e['frame'] }.max, :<=, 240
      events.select { |e| e['type'] == 'save' }.each do |save|
        assert File.file?(File.join(child.dir, 'save', save['path'])), "save #{save['path']} missing in the fork"
      end
      assert_equal 'progressing', Koholint::Summary.for(child)[:health]
    end
  end
end
