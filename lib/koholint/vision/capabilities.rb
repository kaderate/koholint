module Koholint
  module Vision
    class Capabilities
      def initialize(items = [])
        @items = items.map(&:to_s).uniq.sort.freeze
      end

      def to_a = @items.dup

      def ==(other) = other.is_a?(Capabilities) && @items == other.items
      alias eql? ==

      def hash = [Capabilities, @items].hash

      def to_s = "Capabilities(#{@items.join(', ')})"
      alias inspect to_s

      protected

      attr_reader :items
    end
  end
end
