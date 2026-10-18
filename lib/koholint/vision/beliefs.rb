require 'koholint/vision/capabilities'

module Koholint
  module Vision
    class Beliefs
      RESULTS = %i[yes no].freeze

      def self.from_events(events)
        new.tap do |beliefs|
          events.each do |event|
            next unless event['type'] == 'affordance'

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

        @evidence[[appearance, action]] << { appearance:, action:, direction:, result:, method:, context:, frame:, source: }
        nil
      end

      def evidence_for(appearance, action) = @evidence.fetch([appearance, action], []).dup

      def query(appearance:, action:, context:, direction: nil)
        all = @evidence.fetch([appearance, action], [])
        return :unknown if all.empty?

        relevant = direction ? relevant_for(all, direction) : relevant_undirected(all)
        return :unknown if relevant.nil? || relevant.empty?

        decided = relevant.select { |entry| entry[:context] == context }
        return :stale if decided.empty?

        if direction.nil? && decided.map { |entry| entry[:direction] }.uniq.size > 1
          latest_by_direction = decided.group_by { |entry| entry[:direction] }.transform_values { |entries| latest(entries)[:result] }
          return :unknown if latest_by_direction.values.uniq.size > 1
        end

        latest(decided)[:result]
      end

      private

      def relevant_for(all, direction)
        specific = all.select { |entry| entry[:direction] == direction }
        specific.empty? ? all.select { |entry| entry[:direction].nil? } : specific
      end

      def relevant_undirected(all)
        all.any? { |entry| entry[:direction].nil? } ? all : nil
      end

      def latest(entries)
        entries.each_with_index.max_by { |entry, index| [entry[:frame], index] }.first
      end
    end
  end
end
