require 'koholint/vision/capabilities'

module Koholint
  module Vision
    class Beliefs
      RESULTS = %i[yes no].freeze
      DIRECTIONS = %i[up down left right].freeze

      def self.from_events(events)
        new.tap do |beliefs|
          events.each do |event|
            next unless event['type'] == 'affordance'

            %w[action result].each do |key|
              raise ArgumentError, "affordance event at frame #{event['frame'].inspect} lacks #{key}" unless event[key]
            end
            beliefs.record(
              appearance: event['appearance'],
              action: event['action'].to_sym,
              direction: event['direction']&.to_sym,
              result: event['result'].to_sym,
              method: event['method'],
              context: Capabilities.new(event['context'] || []),
              frame: event['frame'],
              source: event['source']
            )
          end
        end
      end

      def initialize
        @evidence = Hash.new { |hash, key| hash[key] = [] }
      end

      def record(appearance:, action:, direction:, result:, method:, context:, frame:, source:)
        raise ArgumentError, "result must be :yes or :no, got #{result.inspect}" unless RESULTS.include?(result)
        raise ArgumentError, "action must be a Symbol, got #{action.inspect}" unless action.is_a?(Symbol)
        raise ArgumentError, "frame must be an Integer, got #{frame.inspect}" unless frame.is_a?(Integer)
        unless direction.nil? || DIRECTIONS.include?(direction)
          raise ArgumentError, "direction must be one of #{DIRECTIONS.join('/')} or nil, got #{direction.inspect}"
        end

        @evidence[[appearance, action]] << { appearance:, action:, direction:, result:, method:, context:, frame:, source: }.freeze
        nil
      end

      def evidence_for(appearance, action) = @evidence.fetch([appearance, action], []).dup

      def query(appearance:, action:, context:, direction: nil)
        raise ArgumentError, "context must be a Capabilities, got #{context.inspect}" unless context.is_a?(Capabilities)

        all = @evidence.fetch([appearance, action], [])
        return :unknown if all.empty?

        return query_directed(all, direction, context) if direction

        query_undirected(all, context)
      end

      private

      def relevant_for(all, direction)
        specific = all.select { |entry| entry[:direction] == direction }
        specific.empty? ? all.select { |entry| entry[:direction].nil? } : specific
      end

      def query_directed(all, direction, context)
        relevant = relevant_for(all, direction)
        return :unknown if relevant.empty?

        decided = relevant.select { |entry| entry[:context] == context }
        decided.empty? ? :stale : latest(decided)[:result]
      end

      def query_undirected(all, context)
        directionless = all.select { |entry| entry[:direction].nil? }
        return :unknown if directionless.empty?

        in_context = all.select { |entry| entry[:context] == context }
        return :stale if in_context.empty?

        base = in_context.select { |entry| entry[:direction].nil? }
        return :unknown if base.empty?

        answer = latest(base)[:result]
        directional = in_context.reject { |entry| entry[:direction].nil? }.group_by { |entry| entry[:direction] }
        disagree = directional.values.any? { |entries| latest(entries)[:result] != answer }
        disagree ? :unknown : answer
      end

      def latest(entries)
        entries.each_with_index.max_by { |entry, index| [entry[:frame], index] }.first
      end
    end
  end
end
