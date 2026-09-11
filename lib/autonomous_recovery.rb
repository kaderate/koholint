# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

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
          "status" => "blocked", "goal" => goal, "location" => location,
          "checkpoint" => checkpoint, "attempts" => attempts,
          "blocker_type" => blocker_type, "observations" => observations,
          "failed_actions" => failed_actions, "known_constraints" => known_constraints
        }
      end
    end

    Hypothesis = Struct.new(:id, :statement, :status, :evidence, keyword_init: true) do
      STATUSES = %w[open supported refuted].freeze

      def initialize(**kwargs)
        super(status: "open", evidence: [], **kwargs)
        raise ArgumentError, "invalid hypothesis status" unless STATUSES.include?(status)
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
      STATUSES = %w[open resolved exhausted].freeze

      def initialize(**kwargs)
        super(
          hypotheses: [], experiments: [], budget: {"max_experiments" => 3},
          status: "open", promoted_facts: [], **kwargs
        )
        validate!
      end

      def exhausted?
        experiments.length >= budget.fetch("max_experiments")
      end

      def record_experiment!(experiment)
        raise ArgumentError, "research task is not open" unless status == "open"
        raise ArgumentError, "research budget exhausted" if exhausted?
        if experiments.any? { |e| e.hypothesis_id == experiment.hypothesis_id && e.action == experiment.action }
          raise ArgumentError, "duplicate research experiment"
        end
        raise ArgumentError, "unknown hypothesis" unless hypotheses.any? { |h| h.id == experiment.hypothesis_id }

        experiments << experiment
      end

      def mark_hypothesis!(id, status, evidence)
        raise ArgumentError, "invalid hypothesis status" unless Hypothesis::STATUSES.include?(status)
        hypothesis = hypotheses.find { |item| item.id == id }
        raise ArgumentError, "unknown hypothesis" unless hypothesis

        hypothesis.status = status
        hypothesis.evidence.concat(Array(evidence))
        self.status = "resolved" if status == "supported"
        self.status = "exhausted" if status == "refuted" && exhausted?
      end

      def to_h
        {
          "id" => id, "goal" => goal, "blocker" => blocker,
          "hypotheses" => hypotheses.map(&:to_h), "experiments" => experiments.map(&:to_h),
          "budget" => budget, "status" => status, "promoted_facts" => promoted_facts
        }
      end

      def validate!
        raise ArgumentError, "missing research task id" if id.to_s.empty?
        raise ArgumentError, "invalid research status" unless STATUSES.include?(status)
        max = budget.fetch("max_experiments")
        raise ArgumentError, "invalid research budget" unless max.is_a?(Integer) && max.positive?
        ids = hypotheses.map(&:id)
        raise ArgumentError, "duplicate hypothesis id" unless ids.uniq.length == ids.length
        raise ArgumentError, "experiment references unknown hypothesis" if experiments.any? { |e| !ids.include?(e.hypothesis_id) }
      end

      def self.from_h(hash)
        new(
          id: hash.fetch("id"), goal: hash.fetch("goal"), blocker: hash.fetch("blocker"),
          hypotheses: hash.fetch("hypotheses", []).map { |h| Hypothesis.new(id: h.fetch("id"), statement: h.fetch("statement"), status: h.fetch("status", "open"), evidence: h.fetch("evidence", [])) },
          experiments: hash.fetch("experiments", []).map { |e| Experiment.new(**e.transform_keys(&:to_sym)) },
          budget: hash.fetch("budget"), status: hash.fetch("status", "open"),
          promoted_facts: hash.fetch("promoted_facts", [])
        )
      end
    end

    class Store
      def initialize(path)
        @path = path
      end

      def save(task)
        task.validate!
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
      MAX_HYPOTHESES = 8
      MAX_EXPERIMENTS = 5
      MAX_FACTS = 40
      MAX_TOOLS = 20

      def self.project(task, world_facts: [], tools: [])
        total = task.budget.fetch("max_experiments")
        {
          "goal" => task.goal,
          "blocker" => task.blocker,
          "hypotheses" => task.hypotheses.select { |h| h.status == "open" }.first(MAX_HYPOTHESES).map(&:to_h),
          "recent_experiments" => task.experiments.last(MAX_EXPERIMENTS).map(&:to_h),
          "world_facts" => world_facts.last(MAX_FACTS),
          "tools" => tools.first(MAX_TOOLS),
          "budget" => {"remaining_experiments" => [total - task.experiments.length, 0].max}
        }
      end
    end

    class ExperimentRunner
      def initialize(checkpoints:, executor:, max_frames: 10_000)
        raise ArgumentError, "max_frames must be positive" unless max_frames.is_a?(Integer) && max_frames.positive?
        @checkpoints = checkpoints
        @executor = executor
        @max_frames = max_frames
      end

      def run(experiment, checkpoint:)
        @checkpoints.restore(checkpoint)
        before = durable_fingerprint
        result = @executor.call(experiment.action, max_frames: @max_frames)
        frames = result.fetch(:frames, 0)
        raise ArgumentError, "experiment frame budget exceeded" if frames > @max_frames
        after = durable_fingerprint
        raise ArgumentError, "experiment mutated durable state" unless before == after

        Experiment.new(**experiment.to_h.transform_keys(&:to_sym).merge(
          checkpoint: checkpoint,
          observation: result.fetch(:observation),
          outcome: result.fetch(:outcome),
          cost: frames,
          state_fingerprint: result[:state_fingerprint],
          created_at: Time.now.utc.iso8601
        ))
      end

      private

      def durable_fingerprint
        return @checkpoints.durable_fingerprint if @checkpoints.respond_to?(:durable_fingerprint)

        nil
      end
    end

    class RecoveryCoordinator
      def initialize(store:, runner:, researcher:)
        @store = store
        @runner = runner
        @researcher = researcher
      end

      def handle(execution:, research_task: nil)
        return {mode: "execute", task: research_task} if execution[:status] == "success"
        raise ArgumentError, "unsupported execution status" unless execution[:status] == "blocked"

        task = research_task || new_task(execution)
        return {mode: "escalate", task: task} if task.exhausted?

        proposal = @researcher.call(Context.project(task))
        experiment = Experiment.new(
          id: SecureRandom.hex(8),
          hypothesis_id: proposal.fetch(:hypothesis_id),
          action: proposal.fetch(:action),
          checkpoint: execution.fetch(:checkpoint)
        )
        result = @runner.run(experiment, checkpoint: execution.fetch(:checkpoint))
        task.record_experiment!(result)
        update_hypothesis(task, result)
        @store.save(task)

        {
          mode: task.status == "resolved" ? "execute" : (task.exhausted? ? "escalate" : "research"),
          task: task,
          experiment: result
        }
      end

      private

      def new_task(execution)
        blocked = BlockedResult.new(**execution.reject { |key, _| key == :status })
        ResearchTask.new(
          id: SecureRandom.hex(8), goal: blocked.goal, blocker: blocked.to_h,
          hypotheses: Array(execution[:hypotheses]).map do |hypothesis|
            Hypothesis.new(id: hypothesis.fetch(:id), statement: hypothesis.fetch(:statement))
          end
        )
      end

      def update_hypothesis(task, experiment)
        case experiment.outcome
        when "supports"
          task.mark_hypothesis!(experiment.hypothesis_id, "supported", [experiment.observation])
        when "refutes"
          task.mark_hypothesis!(experiment.hypothesis_id, "refuted", [experiment.observation])
        end
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
