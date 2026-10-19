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
      TRANSCRIPTION_LIMIT = 500
      Failure = Class.new(StandardError)
      FALLBACK_CHOICE = { skill: 'wait', params: { frames: 30 } }.freeze
      HEMMED_WAIT = { skill: 'wait', params: { frames: 120 } }.freeze
      HEMMED_DIRECTIONS = 4
      HEMMED_WAIT_LIMIT = 1800 / HEMMED_WAIT[:params][:frames]

      def initialize(client:, registry:, objectives:, manual: '', on_step: nil)
        @client = client
        @registry = registry
        @objectives = objectives
        @manual = manual.to_s
        @on_step = on_step
        @last_results = []
        @walks = []
        @hemmed = nil
        @page = 0
        @skill_point = DecisionPoint.choose_skill(registry)
      end

      def decision_point_for(_state) = @objectives.current ? @skill_point : DecisionPoint.choose_objective

      def observe(state, frame:)
        release_hemmed(state)
        track { @objectives.update(state, frame:) }
      end

      def cancel = (@client.cancel if @client.respond_to?(:cancel))

      def decide(decision_point, state, context)
        @prompt = @image = nil
        if decision_point.name == :choose_skill && hemmed?(state)
          return hemmed_wait if @hemmed[:waits] < HEMMED_WAIT_LIMIT

          clear_hemmed
        end

        reply = ask(decision_point, state, context)
        raise Failure, reply.error if reply.error

        choice = decision_point.validate(reply.output).slice(*decision_point.output_schema)
        start_objective(choice, state) if decision_point.name == :choose_objective
        answer(choice, reply, reply.output).merge(transcription_for(reply.output, state, decision_point))
      rescue NameError, TypeError
        raise
      rescue StandardError => e
        { choice: FALLBACK_CHOICE, justification: e.is_a?(Failure) ? e.message : "#{e.class}: #{e.message}", confidence: 0.0, agent: 'claude', latency_ms: 0,
          cost_usd: cost_of(reply), fallback: true, decision_point: @skill_point, prompt: @prompt, image: @image }
      end

      def after_action(choice:, outcome:, state:, frame:)
        return unless choice.key?(:skill)

        @page += 1 if choice[:skill] == 'advance_dialogue'
        @page = 0 unless state.phase == :dialogue
        @last_results << outcome
        @last_results.shift while @last_results.size > RESULT_LIMIT
        note_walk(choice, outcome, state)
        unless @waiting
          @objectives.record_attempt(skill: choice[:skill], params: choice[:params], result_summary: summary(outcome))
        end
        @waiting = false
        track { @objectives.update(state, frame:) }
      end

      private

      def track
        before = @objectives.history.size
        yield
        @on_step&.call if @objectives.history.size > before
      end

      def start_objective(choice, state)
        predicate = Objectives.normalize(choice[:predicate])
        place = [state.room_id, state.map_id]
        if predicate[:kind].to_s == 'leave_place' && predicate[:place] != place
          raise Failure, "leave_place must name the current place #{place.inspect}, not #{predicate[:place].inspect}"
        end
        raise Failure, 'predicate is already true in the current state' if satisfied?(predicate, state, place)
        raise Failure, 'dialogue_closed needs an open dialogue' if predicate[:kind].to_s == 'dialogue_closed' && !state.dialog_open?

        clear_hemmed
        @objectives.start(frame: state.frame, title: choice[:title], predicate: choice[:predicate])
      end

      def satisfied?(predicate, state, place)
        case predicate[:kind].to_s
        when 'reach_place' then predicate[:place] == place
        when 'reach_cell' then predicate[:place] == place && state.cell == [predicate[:row], predicate[:col]]
        else false
        end
      end

      def note_walk(choice, outcome, state)
        @walks << (choice[:skill] == 'walk' ? { direction: choice[:params][:direction] || choice[:params]['direction'], stopped_by: outcome[:stopped_by].to_s,
                                                 moved: outcome[:moved_cells].to_i, pos: [state.x, state.y] } : nil)
        @walks.shift while @walks.size > HEMMED_DIRECTIONS
        latch_hemmed(state)
      end

      def latch_hemmed(state)
        return if state.dialog_open? || @walks.size < HEMMED_DIRECTIONS || @walks.any?(&:nil?)
        return unless @walks.map { |w| w[:direction].to_s }.uniq.size == HEMMED_DIRECTIONS
        return unless @walks.all? { |w| w[:stopped_by] == 'blocked' && w[:moved].zero? && w[:pos] == @walks.first[:pos] }

        @hemmed = { pos: @walks.first[:pos], place: [state.room_id, state.map_id], waits: 0 }
      end

      def hemmed?(state) = !!@hemmed && !state.dialog_open? && [state.x, state.y] == @hemmed[:pos] && [state.room_id, state.map_id] == @hemmed[:place]

      def release_hemmed(state)
        return unless @hemmed && !state.loading?

        clear_hemmed unless hemmed?(state)
      end

      def clear_hemmed
        @hemmed = nil
        @walks.clear
      end

      def hemmed_wait
        @waiting = true
        @hemmed[:waits] += 1
        { choice: HEMMED_WAIT, justification: 'deterministic hemmed-in wait: four directions blocked without movement at the same position',
          confidence: 1.0, agent: 'delegated', latency_ms: 0, cost_usd: 0.0, fallback: false, prompt: nil, image: nil }
      end

      def ask(decision_point, state, context)
        @prompt = Agents::Context.build(state:, grid: grid_for(state, context), objective: @objectives.current, history: @objectives.history,
                                       attempts: @objectives.attempts_for_prompt, manual: @manual, last_results: @last_results)
        @image = context[:dialogue_shot]&.call if state.phase == :dialogue && decision_point.name == :choose_skill
        @client.call(system: Agents::Prompts.system_for(decision_point), prompt: @prompt, schema: decision_point.json_schema, image: @image)
      end

      def clean(text) = text.gsub(/[^\P{Cntrl}\n]/, '').strip[0, TRANSCRIPTION_LIMIT]

      def transcription_for(output, state, decision_point)
        text = output['transcription']
        return {} unless decision_point.name == :choose_skill && state.phase == :dialogue && text.is_a?(String) && !clean(text).empty?

        { transcription: { text: clean(text), page: @page } }
      end

      def grid_for(state, context)
        place = [state.room_id, state.map_id]
        @last_grid = nil unless @last_place == place
        @last_place = place
        @last_grid = context[:grid] if context[:grid]
        @last_grid ||= Vision::Grid.new(cells: Array.new(Vision::Grid::ROWS) { Array.new(Vision::Grid::COLS) }, static_sprites: [],
                                        beliefs: Vision::Beliefs.new, capabilities: Vision::Capabilities.new)
      end

      def answer(choice, reply, output)
        { choice:, justification: output['justification'].to_s, confidence: output['confidence']&.to_f, agent: 'claude',
          latency_ms: reply.latency_ms.to_i, cost_usd: reply.cost_usd.to_f, prompt: @prompt, image: @image }
      end

      def cost_of(reply) = reply.respond_to?(:cost_usd) ? reply.cost_usd.to_f : 0.0

      def summary(outcome)
        "stopped_by #{outcome[:stopped_by]}, moved #{outcome[:moved_cells]} cells, room_changed #{outcome[:room_changed]}, hp_delta #{outcome[:hp_delta]}"
      end
    end
  end
end
