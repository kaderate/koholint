require 'delegate'
require 'koholint/items'
require 'koholint/navigation/threat'

module Koholint
  module Skills
    # Holds the guarding item's button during the inputs of a moving skill while a threat is near; never touches the direction.
    class Shielded < SimpleDelegator
      MOVING = %w[walk goto explore step].freeze
      DIRECTIONS = %i[up down left right].freeze

      def initialize(inner, entities: nil, objects: nil)
        super(inner)
        @entities = entities
        @objects = objects
        @held = 0
      end

      def next_input(state)
        buttons = super
        return buttons unless buttons && buttons.intersect?(DIRECTIONS)

        button = Items.button_of(state, Items::SHIELD)
        return buttons unless button && !buttons.include?(button) && (threatened?(state) || pushing?(state, buttons))

        @held += 1
        [*buttons, button]
      end

      def result(*args) = super.then { |result| @held.positive? ? result.merge(shield_frames: @held) : result }

      private

      DELTAS = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }.freeze

      def pushing?(state, buttons)
        return false unless @objects && state.cell

        dr, dc = DELTAS.fetch((buttons & DIRECTIONS).first)
        ahead = [state.cell[0] + dr, state.cell[1] + dc]
        Array(@objects.call).any? { |object| object[:kind].to_s == 'pushable' && object[:cell] == ahead }
      end

      def threatened?(state)
        return false unless @entities

        Navigation::Threat.within?(Navigation::Threat.of(Array(@entities.call)), state.x, state.y, margin: Navigation::Threat.shield_margin)
      end
    end
  end
end
