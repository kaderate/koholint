require 'koholint/agents/context'
require 'koholint/agents/prompts'
require 'koholint/decision'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'

module Koholint
  module Policies
    class Delegated
      RESULT_LIMIT = 6
      FALLBACK_CHOICE = { skill: 'wait', params: { frames: 30 } }.freeze

      def initialize(client:, registry:, objectives:, manual: '')
        @client = client
        @registry = registry
        @objectives = objectives
        @manual = manual.to_s
        @last_results = []
        @skill_point = DecisionPoint.choose_skill(registry)
      end

      def decision_point_for(_state) = @objectives.current ? @skill_point : DecisionPoint.choose_objective

      def decide(decision_point, state, context)
        reply = ask(decision_point, state, context)
        raise reply.error if reply.error

        choice = decision_point.validate(reply.output).slice(*decision_point.output_schema)
        @objectives.start(frame: state.frame, title: choice[:title], predicate: choice[:predicate]) if decision_point.name == :choose_objective
        answer(choice, reply, reply.output)
      rescue StandardError => e
        { choice: FALLBACK_CHOICE, justification: e.message, confidence: 0.0, agent: 'claude', latency_ms: 0,
          cost_usd: cost_of(reply), fallback: true, decision_point: @skill_point }
      end

      def after_action(choice:, outcome:, state:, frame:)
        return unless choice.key?(:skill)

        @last_results << outcome
        @last_results.shift while @last_results.size > RESULT_LIMIT
        @objectives.record_attempt(skill: choice[:skill], params: choice[:params], result_summary: summary(outcome))
        @objectives.update(state, frame:)
      end

      private

      def ask(decision_point, state, context)
        prompt = Agents::Context.build(state:, grid: grid_for(context), objective: @objectives.current, history: @objectives.history,
                                       attempts: @objectives.attempts_for_prompt, manual: @manual, last_results: @last_results)
        @client.call(system: Agents::Prompts.system_for(decision_point), prompt:, schema: decision_point.json_schema)
      end

      def grid_for(context)
        @last_grid = context[:grid] if context[:grid]
        @last_grid ||= Vision::Grid.new(cells: Array.new(Vision::Grid::ROWS) { Array.new(Vision::Grid::COLS) }, static_sprites: [],
                                        beliefs: Vision::Beliefs.new, capabilities: Vision::Capabilities.new)
      end

      def answer(choice, reply, output)
        { choice:, justification: output['justification'].to_s, confidence: output['confidence']&.to_f, agent: 'claude',
          latency_ms: reply.latency_ms.to_i, cost_usd: reply.cost_usd.to_f }
      end

      def cost_of(reply) = reply.respond_to?(:cost_usd) ? reply.cost_usd.to_f : 0.0

      def summary(outcome)
        "stopped_by #{outcome[:stopped_by]}, moved #{outcome[:moved_cells]} cells, room_changed #{outcome[:room_changed]}, hp_delta #{outcome[:hp_delta]}"
      end
    end
  end
end
