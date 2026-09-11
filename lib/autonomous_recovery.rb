# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"

module Koholint
  module AutonomousRecovery
    BlockedResult = Struct.new(
      :goal, :location, :checkpoint, :attempts, :blocker_type,
      :observations, :failed_actions, :known_constraints,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super(
          attempts: 0,
          blocker_type: "unknown",
          observations: [],
          failed_actions: [],
          known_constraints: [],
          **kwargs
        )
      end

      def to_h
        {
          "status" => "blocked",
          "goal" => goal,
          "location" => location,
          "checkpoint" => checkpoint,
          "attempts" => attempts,
          "blocker_type" => blocker_type,
          "observations" => observations,
          "failed_actions" => failed_actions,
          "known_constraints" => known_constraints
        }
      end
    end

    Hypothesis = Struct.new(:id, :statement, :status, :evidence, keyword_init: true) do
      def initialize(**kwargs)
        super(status: "open", evidence: [], **kwargs)
      end

      def to_h
        {"id" => id, "statement" => statement, "status" => status, "evidence" => evidence}
      end
    end

    Experiment = Struct.new(
      :id, :hypothesis_id, :checkpoint, :action, :observation, :outcome,
      :cost, :state_fingerprint, :created_at, keyword_init: true
    ) do
      def to_h
        {
          "id" => id, "hypothesis_id" => hypothesis_id, "checkpoint" => checkpoint,
          "action" => action, "observation" => observation, "outcome" => outcome,
          "cost" => cost, "state_fingerprint" => state_fingerprint, "created_at" => created_at
        }
      end
    end

    ResearchTask = Struct.new(
      :id, :goal, :blocker, :hypotheses, :experiments, :budget, :status,
      :promoted_facts, keyword_init: true
    ) do
      def initialize(**kwargs)
        super(
          hypotheses: [], experiments: [], budget: {"max_experiments" => 3},
          status: "open", promoted_facts: [], **kwargs
        )
      end

      def exhausted?
        experiments.length >= budget.fetch("max_experiments", 3)
      end

      def to_h
        {
          "id" => id, "goal" => goal, "blocker" => blocker,
          "hypotheses" => hypotheses.map(&:to_h), "experiments" => experiments.map(&:to_h),
          "budget" => budget, "status" => status, "promoted_facts" => promoted_facts
        }
      end

      def self.from_h(hash)
        new(
          id: hash.fetch("id"), goal: hash.fetch("goal"), blocker: hash.fetch("blocker"),
          hypotheses: hash.fetch("hypotheses", []).map { |h| Hypothesis.new(id: h["id"], statement: h["statement"], status: h["status"], evidence: h["evidence"]) },
          experiments: hash.fetch("experiments", []).map { |e| Experiment.new(**e.transform_keys(&:to_sym)) },
          budget: hash.fetch("budget", {"max_experiments" => 3}), status: hash.fetch("status", "open"),
          promoted_facts: hash.fetch("promoted_facts", [])
        )
      end
    end

    class Store
      def initialize(path)
        @path = path
      end

      def save(task)
        FileUtils.mkdir_p(File.dirname(@path))
        tmp = "#{@path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
        File.write(tmp, JSON.pretty_generate(task.to_h) + "\n")
        File.rename(tmp, @path)
        task
      ensure
        File.delete(tmp) if tmp && File.exist?(tmp)
      end

      def load
        return nil unless File.file?(@path)

        ResearchTask.from_h(JSON.parse(File.read(@path)))
      end
    end

    class Context
      def self.project(task, world_facts: [], tools: [], max_experiments: nil)
        {
          "goal" => task.goal,
          "blocker" => task.blocker,
          "hypotheses" => task.hypotheses.select { |h| h.status == "open" }.map(&:to_h),
          "recent_experiments" => task.experiments.last(5).map(&:to_h),
          "world_facts" => world_facts,
          "tools" => tools,
          "budget" => {
            "remaining_experiments" => [
              max_experiments || task.budget.fetch("max_experiments", 3) - task.experiments.length,
              0
            ].max
          }
        }
      end
    end

    class ExperimentRunner
      def initialize(checkpoints:, executor:)
        @checkpoints = checkpoints
        @executor = executor
      end

      def run(experiment, checkpoint:)
        @checkpoints.restore(checkpoint)
        result = @executor.call(experiment.action)
        Experiment.new(**experiment.to_h.transform_keys(&:to_sym).merge(
          checkpoint: checkpoint,
          observation: result.fetch(:observation),
          outcome: result.fetch(:outcome),
          state_fingerprint: result[:state_fingerprint],
          created_at: Time.now.utc.iso8601
        ))
      end
    end

    class Router
      MODES = %w[execute explore research escalate].freeze

      def self.mode(execution:, research_task: nil)
        return "execute" if execution[:status] == "success"
        return "research" if execution[:status] == "blocked" && research_task && !research_task.exhausted?
        return "escalate" if execution[:status] == "blocked"

        "execute"
      end
    end
  end
end
