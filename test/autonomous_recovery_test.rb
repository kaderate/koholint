# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/autonomous_recovery"

class AutonomousRecoveryTest < Minitest::Test
  include Koholint::AutonomousRecovery

  Checkpoints = Struct.new(:restored) do
    def restore(name)
      self.restored = name
    end
  end

  def test_blocked_task_survives_a_fresh_context
    Dir.mktmpdir do |dir|
      store = Store.new(File.join(dir, "research.json"))
      blocked = BlockedResult.new(
        goal: "open the door", location: "A", checkpoint: "start",
        attempts: 2, blocker_type: "unknown_route"
      )
      task = ResearchTask.new(
        id: "r1", goal: blocked.goal, blocker: blocked.to_h,
        hypotheses: [Hypothesis.new(id: "h1", statement: "The key is in room B")]
      )
      store.save(task)

      reloaded = Store.new(store.instance_variable_get(:@path)).load
      context = Context.project(reloaded, world_facts: [{"room" => "B"}])

      assert_equal "open the door", context["goal"]
      assert_equal "The key is in room B", context["hypotheses"].first["statement"]
      assert_equal 3, context["budget"]["remaining_experiments"]
    end
  end

  def test_experiment_restores_checkpoint_before_execution
    checkpoints = Checkpoints.new
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      executor: ->(action) { {observation: "key found", outcome: "supports", state_fingerprint: "after"} }
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect B", cost: 1)

    result = runner.run(experiment, checkpoint: "start")

    assert_equal "start", checkpoints.restored
    assert_equal "key found", result.observation
    assert_equal "supports", result.outcome
  end

  def test_blocked_research_exhaustion_escalates
    task = ResearchTask.new(id: "r1", goal: "door", blocker: {}, budget: {"max_experiments" => 1})
    task.experiments << Experiment.new(id: "e1", hypothesis_id: "h1", action: "x")

    assert_equal "escalate", Router.mode(execution: {status: "blocked"}, research_task: task)
    assert_equal "research", Router.mode(
      execution: {status: "blocked"},
      research_task: ResearchTask.new(id: "r2", goal: "door", blocker: {})
    )
  end
end
