require 'koholint/decision'

module Koholint
  module Policies
    class WithFallback
      ATTEMPTS = 2

      def initialize(primary, fallback)
        @primary = primary
        @fallback = fallback
      end

      def decide(point, state, context)
        ATTEMPTS.times do
          result = @primary.decide(point, state, context)
          point.validate(result[:choice])
          return result.merge(fallback: false)
        rescue DecisionPoint::Invalid
          next
        end
        @fallback.decide(point, state, context).merge(fallback: true)
      end
    end
  end
end
