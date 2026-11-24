module Koholint
  module Policies
    class Base
      def observe(_state, frame:) = nil

      def prepare(_context) = nil

      def decision_point_for(_state) = nil

      def after_action(**) = nil

      def note_card(_card) = nil

      def offered_candidates = []

      def cancel = nil
    end
  end
end
