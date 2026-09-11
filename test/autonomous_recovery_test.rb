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

  def test_default_store_has_a_canonical_path
    assert_equal ".koholint/research_task.json", Store.default.path
  end

  def test_blocked_task_survives_a_fresh_process
    Dir.mktmpdir do |dir|
      path = File.join(dir, "research.json")
      script = <<~RUBY
        require #{File.expand_path("lib/autonomous_recovery", Dir.pwd).inspect}
        store = Koholint::AutonomousRecovery::Store.new(ARGV.fetch(0))
        task = Koholint::AutonomousRecovery::ResearchTask.new(
          id: "r1", goal: "open the door", blocker: {"status" => "blocked", "checkpoint" => "start"},
          hypotheses: [Koholint::AutonomousRecovery::Hypothesis.new(id: "h1", statement: "The key is in room B")]
        )
        store.save(task)
        store.save_handoff(task)
      RUBY
      system(RbConfig.ruby, "-e", script, path, exception: true)

      store = Store.new(path)
      reloaded = store.load
      context = Context.project(reloaded, world_facts: Array.new(100) { |i| {"room" => i} }, tools: Array.new(50, "tool"))
      handoff = store.load_handoff

      assert_equal "open the door", context["goal"]
      assert_equal "The key is in room B", context["hypotheses"].first["statement"]
      assert_equal 40, context["world_facts"].length
      assert_equal 20, context["tools"].length
      assert_equal 3, context["budget"]["remaining_experiments"]
      assert_equal "r1", handoff["research_task_id"]
      assert_equal "start", handoff["checkpoint"]
    end
  end

  def test_context_handoff_is_compact_and_points_to_durable_state
    task = ResearchTask.new(
      id: "r1", goal: "open the door", blocker: {"checkpoint" => "start"},
      hypotheses: [Hypothesis.new(id: "h1", statement: "The key is in B")]
    )

    handoff = Context.handoff(task, required_reads: %w[AGENTS.md NEXT.md DECISIONS.md data/world_model.json])

    assert_equal "r1", handoff["research_task_id"]
    assert_equal "research", handoff["mode"]
    assert_equal "open the door", handoff["original_goal"]
    assert_equal "start", handoff["checkpoint"]
    assert_equal "fresh", handoff["context_policy"]
    assert_equal 3, handoff["remaining_experiments"]
    assert_equal "choose_one_bounded_experiment", handoff["next_step"]
    assert_equal %w[AGENTS.md NEXT.md DECISIONS.md data/world_model.json], handoff["required_reads"]
    refute handoff.key?("conversation")
  end

  def test_handoff_rejects_a_task_without_checkpoint
    task = ResearchTask.new(id: "r1", goal: "door", blocker: {})

    assert_raises(ArgumentError) { Context.handoff(task) }
  end

  def test_resolved_handoff_returns_to_original_goal
    task = ResearchTask.new(
      id: "r1", goal: "open the door", blocker: {"checkpoint" => "start"},
      hypotheses: [Hypothesis.new(id: "h1", statement: "The key is in B", status: "supported")],
      status: "resolved"
    )

    handoff = Context.handoff(task)

    assert_equal "resume", handoff["mode"]
    assert_equal "resume_original_goal", handoff["next_step"]
  end

  def test_new_task_can_add_a_hypothesis_durably
    task = ResearchTask.new(id: "r1", goal: "door", blocker: {"checkpoint" => "start"})

    hypothesis = task.add_hypothesis!(id: "h1", statement: "Object X sets the interaction flag")

    assert_equal "h1", hypothesis.id
    assert_equal "Object X sets the interaction flag", task.hypotheses.first.statement
    assert_raises(ArgumentError) { task.add_hypothesis!(id: "h1", statement: "duplicate") }
  end

  def test_experiment_is_bounded_and_preserves_durable_state
    checkpoints = Checkpoints.new("none", "same")
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      max_frames: 10,
      executor: ->(_action, max_frames:) do
        assert_equal 10, max_frames
        {observation: "key found", outcome: "supports", frames: 7, state_fingerprint: "same"}
      end
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect B")

    result = runner.run(experiment, checkpoint: "start")

    assert_equal "start", checkpoints.restored
    assert_equal 7, result.cost
    assert_equal "key found", result.observation
    assert_equal "supports", result.outcome
    assert_equal "same", result.state_fingerprint
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
    assert_equal "before", checkpoints.fingerprint
  end

  def test_experiment_restores_durable_state_when_executor_raises
    checkpoints = Checkpoints.new("none", "before")
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      executor: ->(_action, max_frames:) do
        checkpoints.fingerprint = "after"
        raise "executor failed"
      end
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "write")

    assert_raises(RuntimeError) { runner.run(experiment, checkpoint: "start") }
    assert_equal "start", checkpoints.restored
    assert_equal "before", checkpoints.fingerprint
  end

  def test_experiment_rejects_reported_fingerprint_mismatch
    checkpoints = Checkpoints.new("same", "same")
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      executor: ->(_action, max_frames:) { {observation: "ok", outcome: "supports", frames: 1, state_fingerprint: "wrong"} }
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect")

    assert_raises(ArgumentError) { runner.run(experiment, checkpoint: "start") }
  end

  def test_runner_requires_durable_fingerprint_by_default
    checkpoints = Object.new
    def checkpoints.restore(_name); end
    runner = ExperimentRunner.new(
      checkpoints: checkpoints,
      executor: ->(_action, max_frames:) { {observation: "ok", outcome: "supports", frames: 1} }
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect")

    assert_raises(ArgumentError) { runner.run(experiment, checkpoint: "start") }
  end

  def test_research_task_requires_repeated_support_and_refutes_immediately
    task = ResearchTask.new(
      id: "r1", goal: "door", blocker: {},
      hypotheses: [Hypothesis.new(id: "h1", statement: "inspect")],
      budget: {"max_experiments" => 3, "min_supporting_experiments" => 2}
    )

    first = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect-left", outcome: "supports", observation: "maybe")
    second = Experiment.new(id: "e2", hypothesis_id: "h1", action: "inspect-right", outcome: "supports", observation: "confirmed")
    task.record_experiment!(first)
    refute task.mark_hypothesis!("h1", "supported", [first.observation])
    assert_equal "open", task.status

    task.record_experiment!(second)
    assert task.mark_hypothesis!("h1", "supported", [second.observation])
    assert_equal "resolved", task.status

    refuted = ResearchTask.new(
      id: "r2", goal: "door", blocker: {},
      hypotheses: [Hypothesis.new(id: "h2", statement: "wrong")]
    )
    experiment = Experiment.new(id: "e3", hypothesis_id: "h2", action: "test", outcome: "refutes", observation: "no")
    refuted.record_experiment!(experiment)
    assert refuted.mark_hypothesis!("h2", "refuted", [experiment.observation])
    assert_equal "open", refuted.status
  end

  def test_research_task_rejects_duplicate_experiments_and_enforces_budget
    task = ResearchTask.new(
      id: "r1", goal: "door", blocker: {},
      hypotheses: [Hypothesis.new(id: "h1", statement: "inspect")],
      budget: {"max_experiments" => 1, "min_supporting_experiments" => 1}
    )
    experiment = Experiment.new(id: "e1", hypothesis_id: "h1", action: "inspect")

    task.record_experiment!(experiment)
    assert_raises(ArgumentError) { task.record_experiment!(experiment) }
    assert task.exhausted?
    assert_raises(ArgumentError) do
      task.record_experiment!(Experiment.new(id: "e2", hypothesis_id: "h1", action: "different"))
    end
  end

  def test_recovery_coordinator_handles_a_fresh_blocker_without_preseeded_hypotheses
    Dir.mktmpdir do |dir|
      store = Store.new(File.join(dir, "research.json"))
      checkpoints = Checkpoints.new("none", "same")
      runner = ExperimentRunner.new(
        checkpoints: checkpoints,
        executor: ->(_action, max_frames:) { {observation: "tested", outcome: "refutes", frames: 2, state_fingerprint: "same"} }
      )
      coordinator = RecoveryCoordinator.new(
        store: store,
        runner: runner,
        researcher: ->(_context) { {hypothesis_id: "h1", statement: "Object X sets the flag", action: "inspect X"} }
      )

      result = coordinator.handle(execution: {
        status: "blocked", goal: "open the door", location: "A", checkpoint: "start", hypotheses: []
      })

      assert_equal "research", result[:mode]
      assert_equal "Object X sets the flag", store.load.hypotheses.first.statement
      assert_equal 1, store.load.experiments.length
    end
  end

  def test_recovery_coordinator_runs_two_independent_supporting_iterations_and_persists_them
    Dir.mktmpdir do |dir|
      store = Store.new(File.join(dir, "research.json"))
      checkpoints = Checkpoints.new("none", "same")
      runner = ExperimentRunner.new(
        checkpoints: checkpoints,
        executor: ->(action, max_frames:) { {observation: "found #{action}", outcome: "supports", frames: 2, state_fingerprint: "same"} }
      )
      calls = 0
      coordinator = RecoveryCoordinator.new(
        store: store,
        runner: runner,
        researcher: ->(_context) do
          calls += 1
          {hypothesis_id: "h1", action: calls == 1 ? "inspect B" : "inspect C"}
        end
      )

      execution = {
        status: "blocked", goal: "open the door", location: "A", checkpoint: "start",
        hypotheses: [{id: "h1", statement: "The key is in B"}]
      }
      first = coordinator.handle(execution: execution)
      assert_equal "research", first[:mode]
      assert_equal "open", first[:task].status

      second = coordinator.handle(execution: execution, research_task: store.load)
      assert_equal "execute", second[:mode]
      assert_equal "resolved", second[:task].status
      assert_equal 2, second[:task].experiments.length
      assert_equal "resolved", store.load.status
    end
  end

  def test_persistence_failure_after_execution_leaves_a_durable_pending_attempt
    Dir.mktmpdir do |dir|
      path = File.join(dir, "research.json")
      store = Class.new(Store) do
        def initialize(path)
          super
          @saves = 0
        end

        def save(task)
          @saves += 1
          raise IOError, "disk full" if @saves == 4

          super
        end
      end.new(path)
      checkpoints = Checkpoints.new("none", "same")
      executed = false
      runner = ExperimentRunner.new(
        checkpoints: checkpoints,
        executor: ->(_action, max_frames:) do
          executed = true
          {observation: "tested", outcome: "supports", frames: 1, state_fingerprint: "same"}
        end
      )
      coordinator = RecoveryCoordinator.new(
        store: store,
        runner: runner,
        researcher: ->(_context) { {hypothesis_id: "h1", statement: "test", action: "inspect"} }
      )

      assert_raises(IOError) do
        coordinator.handle(execution: {
          status: "blocked", goal: "door", location: "A", checkpoint: "start", hypotheses: []
        })
      end

      assert executed
      pending = Store.new(path).load.experiments.first
      assert_nil pending.outcome
      assert_equal "inspect", pending.action
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
      budget: {"max_experiments" => 1, "min_supporting_experiments" => 1}
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
