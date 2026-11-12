require 'koholint'
require 'koholint/skills/advance_dialogue'
require 'koholint/skills/attack'
require 'koholint/skills/composite'
require 'koholint/skills/explore'
require 'koholint/skills/goto'
require 'koholint/skills/press'
require 'koholint/skills/screens'
require 'koholint/skills/shielded'
require 'koholint/skills/step'
require 'koholint/skills/talk_to'
require 'koholint/skills/use_item'
require 'koholint/skills/wait'
require 'koholint/skills/walk'

module Koholint
  module Skills
    def self.symbolize(params, allowed)
      raise ArgumentError, 'params must be a Hash' unless params.is_a?(Hash)

      symbols = params.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      extra = symbols.keys - allowed
      raise ArgumentError, "unknown params #{extra.join(', ')}" unless extra.empty?

      symbols
    end

    class Registry
      def self.default(extra: [])
        new([Walk.new, Press.new, AdvanceDialogue.new, Wait.new, Goto.new, Step.new, TalkTo.new, Explore.new, Screens.open_menu, Screens.close_menu,
             Screens.open_map, Screens.close_map, Screens::MenuMove.new, Screens::MenuAssign.new, Screens::ChooseOption.new,
             UseItem.new, Guard.new, Attack.new, *extra])
      end

      def initialize(skills)
        @skills = skills.to_h { |skill| [skill.name, skill] }
      end

      def names = @skills.keys

      def composites = @skills.values.grep(Composite)

      def fetch(name)
        @skills.fetch(name.to_s) { raise ArgumentError, "unknown skill #{name.inspect}; known: #{names.join(', ')}" }
      end

      def validate(name, params) = fetch(name).normalize(params)

      def start(name, state, params, context = {})
        execution = fetch(name).start(state, params, context.merge(registry: self))
        execution.triggers = context[:triggers] if execution.respond_to?(:triggers=)
        execution = Shielded.new(execution, entities: context[:entities]) if Shielded::MOVING.include?(name.to_s) && context[:entities]
        execution
      end

      def schema
        { skill: { type: 'string', enum: names }, params: { anyOf: @skills.values.map(&:params_schema) } }
      end
    end
  end
end
