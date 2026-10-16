require_relative 'test_helper'
require 'stringio'
require 'tmpdir'
require 'koholint/cli'
require 'koholint/engine'
require 'koholint/policies/walk_and_talk'

class LockTest < Minitest::Test
  FLOW = Koholint::FLOW_VERSION

  def with_run
    Dir.mktmpdir { |dir| yield dir, Koholint::Run.create(root: dir, flow_version: FLOW, budget: {}) }
  end

  def test_emulator_file_loads_without_the_umbrella_require
    out = IO.popen([RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', "require 'koholint/emulator'; print Koholint::Error"], &:read)
    assert_equal 'Koholint::Error', out
  end

  def test_second_run_on_the_same_dir_is_refused
    with_run do |_dir, run|
      holder = Koholint::Run.open(run.dir, flow_version: FLOW)
      holder.lock!
      other = Koholint::Run.open(run.dir, flow_version: FLOW)
      error = assert_raises(Koholint::Error) { other.lock! }
      assert_match(/already in use/, error.message)
      refute_includes error.message, "\n"
      holder.unlock!
      other.lock!
      other.unlock!
    end
  end

  def test_resume_on_a_locked_run_is_refused_before_touching_the_trace
    skip_without_rom!
    with_run do |_dir, run|
      holder = Koholint::Run.open(run.dir, flow_version: FLOW)
      holder.lock!
      before = File.binread(File.join(run.dir, 'trace.jsonl'))
      assert_raises(Koholint::Error) do
        Koholint::Engine.resume(run.dir, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new(frames: 30))
      end
      assert_equal before, File.binread(File.join(run.dir, 'trace.jsonl'))
    end
  end

  def test_lock_is_released_after_the_engine_stops
    skip_without_rom!
    with_run do |_dir, run|
      Koholint::Engine.new(run: run, policy: Koholint::Policies::WalkAndTalk.new, budget: Koholint::Budget.new(frames: 30)).run
      again = Koholint::Run.open(run.dir, flow_version: FLOW)
      again.lock!
      again.unlock!
    end
  end
end
