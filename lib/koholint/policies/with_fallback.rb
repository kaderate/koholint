require 'koholint/decision'

module Koholint
  module Policies
    class WithFallback
      ATTEMPTS = 2

      def initialize(primary, fallback)
        @primary = primary
        @fallback = fallback
      end

      def decide(decision_point, state, context)
        ATTEMPTS.times do
          result = @primary.decide(decision_point, state, context)
          decision_point.validate(result[:choice])
          return result.merge(fallback: false)
        rescue DecisionPoint::Invalid
          next
        end
        @fallback.decide(decision_point, state, context).merge(fallback: true)
      end
    end
  end
end
