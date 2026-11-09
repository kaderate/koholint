require 'delegate'
require 'koholint/items'
require 'koholint/navigation/threat'

module Koholint
  module Skills
    # Holds the guarding item's button during the inputs of a moving skill while a threat is near; never touches the direction.
    class Shielded < SimpleDelegator
      MOVING = %w[walk goto explore step].freeze
      DIRECTIONS = %i[up down left right].freeze

      def initialize(inner, entities:)
        super(inner)
        @entities = entities
        @held = 0
      end

      def next_input(state)
        buttons = super
        return buttons unless buttons && buttons.intersect?(DIRECTIONS)

        button = Items.button_of(state, Items::SHIELD)
        return buttons unless button && !buttons.include?(button) && threatened?(state)

        @held += 1
        [*buttons, button]
      end

      def result(*args) = super.then { |result| @held.positive? ? result.merge(shield_frames: @held) : result }

      private

      def threatened?(state)
        Navigation::Threat.within?(Navigation::Threat.of(Array(@entities.call)), state.x, state.y, margin: Navigation::Threat.shield_margin)
      end
    end
  end
end
