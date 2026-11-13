require 'koholint/skills/attack'
require 'koholint/skills/execution'
require 'koholint/skills/use_item'

module Koholint
  module Skills
    # A learned capability: existing skills run one after the other, each started through the registry so Shielded and triggers apply.
    class Composite
      DIRECTIONS = %i[up right down left].freeze
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
      # Skills a capability may compose, with their frame caps; explore (unbounded) and the screen skills are left out.
      CAPS = { 'goto' => Execution::HARD_CAP, 'walk' => Execution::HARD_CAP, 'step' => Execution::HARD_CAP, 'wait' => Execution::HARD_CAP,
               'press' => Execution::HARD_CAP, 'advance_dialogue' => Execution::HARD_CAP, 'talk_to' => Execution::HARD_CAP,
               'use_item' => ItemRun::HARD_CAP, 'guard' => ItemRun::HARD_CAP, 'attack' => Attack::HARD_CAP }.freeze

      class Run < Execution
        def initialize(steps:, context:, capability:, target:, cap:, **rest)
          super(**rest)
          @cap = cap
          @steps = steps
          @context = context.merge(composite: @skill)
          @registry = context.fetch(:registry)
          @capability = capability
          @target = target
          @done = []
          @sub = nil
          @objects = context[:room_objects]
          @before = object_at_target
        end

        def result(state = @last)
          last = @done.last
          entered = @stopped_by == :done && last && [last.dig(:to, :row), last.dig(:to, :col)] == @target
          super.merge(capability: @capability, steps: @done.map { |step| step.slice(:skill, :stopped_by, :frames, :blocked_at).compact },
                      target: { row: @target[0], col: @target[1] }, effect: entered ? true : false,
                      **(@objects ? { object_before: @before, object_after: object_at_target } : {}))
        end

        private

        def hard_cap = @cap

        def object_at_target = @objects&.call&.dig(*@target)

        def input_for(state)
          return finish(:done) if @sub.nil? && @done.size == @steps.size

          step = @steps[@done.size]
          @sub ||= @registry.start(step[:skill], state, step[:params], @context)
          buttons = @sub.next_input(state)
          return buttons if buttons

          @done << @sub.result(state)
          @sub = nil
          return finish(:step_failed) unless step[:accept].include?(@done.last[:stopped_by].to_s)

          input_for(state)
        end
      end

      attr_reader :entry

      def initialize(entry)
        @entry = entry
      end

      def name = @entry['name']

      # A capability needs the item it was learned with.
      def usable?(held) = Array(held).include?(@entry.dig('trigger', 'item'))

      def max_frames = @entry['steps'].sum { |step| CAPS.fetch(step['skill']) }

      def params_schema
        { type: 'object', title: name,
          properties: { row: { type: 'integer', minimum: 0, maximum: Geometry::ROWS - 1 },
                        col: { type: 'integer', minimum: 0, maximum: Geometry::COLS - 1 },
                        direction: { type: 'string', enum: DIRECTIONS.map(&:to_s) } },
          required: %w[row col direction], additionalProperties: false }
      end

      def normalize(params)
        params = Skills.symbolize(params, %i[row col direction])
        raise ArgumentError, "#{name}: row must be 0..#{Geometry::ROWS - 1}" unless params[:row].is_a?(Integer) && params[:row].between?(0, Geometry::ROWS - 1)
        raise ArgumentError, "#{name}: col must be 0..#{Geometry::COLS - 1}" unless params[:col].is_a?(Integer) && params[:col].between?(0, Geometry::COLS - 1)

        direction = params[:direction].respond_to?(:to_sym) ? params[:direction].to_sym : nil
        raise ArgumentError, "#{name}: direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)

        { row: params[:row], col: params[:col], direction: }
      end

      def start(state, params, context = {})
        params = normalize(params)
        values = { '$row' => params[:row], '$col' => params[:col], '$direction' => params[:direction].to_s }
        steps = @entry['steps'].map do |step|
          { skill: step['skill'], params: step['params'].transform_values { |value| values.fetch(value, value) }, accept: step['accept'] }
        end
        target = [params[:row], params[:col]].zip(DELTAS.fetch(params[:direction])).map(&:sum)
        Run.new(skill: name, params:, state:, steps:, context:, target:, cap: max_frames, capability: { id: @entry['id'], version: @entry['version'] })
      end
    end
  end
end
