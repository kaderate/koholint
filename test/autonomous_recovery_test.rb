# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "rbconfig"
require_relative "../lib/autonomous_recovery"

class AutonomousRecoveryTest < Minitest::Test
  include Koholint::AutonomousRecovery

  Checkpoints = Struct.new(:restored, :fingerprint) do
    def restore(name)
      self.restored = name
    end

    def durable_fingerprint
      fingerprint
    end
  end

  def test_blocked_task_survives_a_fresh_process
    Dir.mktmpdir do |dir|
      path = File.join(dir, "research.json")
      script = <<~RUBY
        require_relative #{File.expand_path("../lib/autonomous_recovery", __dir__).inspect}
        store = Koholint::AutonomousRecovery::Store.new(ARGV.fetch(0))
        task = Koholint::AutonomousRecovery::ResearchTask.new(
          id: "r1", goal: "open the door", blocker: {"status" => "blocked"},
          hypotheses: [Koholint::AutonomousRecovery::Hypothesis.new(id: "h1", statement: "The key is in room B")]
        )
        store.save(task)
      RUBY
      system(RbConfig.ruby, "-e", script, path, exception: true)

      reloaded = Store.new(path).load
      context = Context.project(reloaded, world_facts: Array.new(100) { |i| {"room" => i} }, tools: Array.new(50, "tool"))

      assert_equal "open the door", context["goal"]
      assert_equal "The key is in room B", context["hypotheses"].first["statement"]
      assert_equal 40, context["world_facts"].length
      assert_equal 20, context["tools"].length
      assert_equal 3, context["budget"]["remaining_experiments"]
    end
  end

  def test_experiment_is_bounded_and_preserves_durable_state
    checkpoints = Checkpoints.new("none", "same")
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      max_frames: 10,
      executor: ->(_action, max_frames:) do
        assert_equal 10, max_frames
        {observation: "key found", outcome: "supports", frames: 7, state_fingerprint: "after"}
      end
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect B")

    result = runner.run(experiment, checkpoint: "start")

    assert_equal "start", checkpoints.restored
    assert_equal 7, result.cost
    assert_equal "key found", result.observation
    assert_equal "supports", result.outcome
  end

  def test_experiment_rejects_durable_state_mutation
    checkpoints = Checkpoints.new("none", "before")
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      executor: ->(_action, max_frames:) do
        checkpoints.fingerprint = "after"
        {observation: "changed", outcome: "supports", frames: 1}
      end
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "write")

    assert_raises(ArgumentError) { runner.run(experiment, checkpoint: "start") }
  end

  def test_research_task_rejects_duplicate_experiments_and_enforces_budget
    task = ResearchTask.new(
      id: "r1", goal: "door", blocker: {},
      hypotheses: [Hypothesis.new(id: "h1", statement: "inspect")],
      budget: {"max_experiments" => 1}
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect")

    task.record_experiment!(experiment)
    assert_raises(ArgumentError) { task.record_experiment!(experiment) }
    assert task.exhausted?
    assert_raises(ArgumentError) do
      task.record_experiment!(Experiment.new(id: "e2", hypothesis_id: "h1", action: "different"))
    end
  end

  def test_recovery_coordinator_runs_one_research_iteration_and_persists_it
    Dir.mktmpdir do |dir|
      store = Store.new(File.join(dir, "research.json"))
      checkpoints = Checkpoints.new("none", "same")
      runner = ExperimentRunner.new(
        checkpoints: checkpoints,
        executor: ->(_action, max_frames:) { {observation: "found", outcome: "supports", frames: 2} }
      )
      coordinator = RecoveryCoordinator.new(
        store: store,
        runner: runner,
        researcher: ->(_context) { {hypothesis_id: "h1", action: "inspect B"} }
      )

      result = coordinator.handle(
        execution: {
          status: "blocked", goal: "open the door", location: "A", checkpoint: "start",
          hypotheses: [{id: "h1", statement: "The key is in B"}]
        }
      )

      assert_equal "execute", result[:mode]
      assert_equal "resolved", result[:task].status
      assert_equal 1, result[:task].experiments.length
      assert_equal "supported", result[:task].hypotheses.first.status
      assert_equal "resolved", store.load.status
    end
  end

  def test_research_task_validates_loaded_state
    assert_raises(ArgumentError) do
      ResearchTask.from_h(
        "id" => "r1", "goal" => "door", "blocker" => {},
        "hypotheses" => [], "experiments" => [],
        "budget" => {"max_experiments" => 0}, "status" => "open"
      )
    end
  end

  def test_blocked_research_exhaustion_escalates
    task = ResearchTask.new(
      id: "r1", goal: "door", blocker: {},
      hypotheses: [Hypothesis.new(id: "h1", statement: "x")],
      budget: {"max_experiments" => 1}
    )
    task.experiments << Experiment.new(id: "e1", hypothesis_id: "h1", action: "x")

    assert_equal "escalate", Router.mode(execution: {status: "blocked"}, research_task: task)
    assert_equal "research", Router.mode(
      execution: {status: "blocked"},
      research_task: ResearchTask.new(
        id: "r2", goal: "door", blocker: {},
        hypotheses: [Hypothesis.new(id: "h1", statement: "x")]
      )
    )
  end
end
