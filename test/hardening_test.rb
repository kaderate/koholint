require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'koholint/cli'
require 'koholint/engine'
require 'koholint/policies/walk_and_talk'

class HardeningTest < Minitest::Test
  FLOW = Koholint::FLOW_VERSION

  def with_run
    Dir.mktmpdir { |dir| yield dir, Koholint::Run.create(root: dir, flow_version: FLOW, budget: {}) }
  end

  def policy = Koholint::Policies::WalkAndTalk.new

  def engine(run, budget: Koholint::Budget.new, **options)
    Koholint::Engine.new(run: run, policy: policy, budget: budget, **options)
  end

  def trace(run) = Koholint::Trace.read(File.join(run.dir, 'trace.jsonl'))

  def cli(*argv)
    out = StringIO.new
    err = StringIO.new
    [Koholint::CLI.run(argv, out: out, err: err), out.string, err.string]
  end

  def test_resume_after_kill_keeps_trace_consistent_with_journal
    skip_without_rom!
    with_run do |_dir, run|
      crashed = engine(run, keyframe_every: 120)
      crashed.send(:iterate) while crashed.instance_variable_get(:@emulator).frame < 300
      Koholint::Engine.resume(run.dir, policy: policy, budget: Koholint::Budget.new(frames: 90), keyframe_every: 120).run
      reopened = Koholint::Run.open(run.dir, flow_version: FLOW)
      frames = trace(reopened).map { |e| e['frame'] }
      assert_equal frames.sort, frames
      assert_operator frames.max, :<=, reopened.inputs.frames
      assert_equal [], Koholint::Replay.verify(reopened, every: 1).reject(&:last)
      assert_equal 0, cli('verify', run.dir)[0]
    end
  end

  def test_stop_does_not_duplicate_a_keyframe_already_taken
    skip_without_rom!
    with_run do |_dir, run|
      engine(run, budget: Koholint::Budget.new(frames: 600), keyframe_every: 300).run
      frames = trace(run).select { |e| e['type'] == 'keyframe' }.map { |e| e['frame'] }
      assert_equal frames.uniq, frames
    end
  end
end
