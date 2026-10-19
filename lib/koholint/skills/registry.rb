require 'koholint'
require 'koholint/skills/advance_dialogue'
require 'koholint/skills/goto'
require 'koholint/skills/press'
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
      def self.default = new([Walk.new, Press.new, AdvanceDialogue.new, Wait.new, Goto.new])

      def initialize(skills)
        @skills = skills.to_h { |skill| [skill.name, skill] }
      end

      def names = @skills.keys

      def fetch(name)
        @skills.fetch(name.to_s) { raise ArgumentError, "unknown skill #{name.inspect}; known: #{names.join(', ')}" }
      end

      def validate(name, params) = fetch(name).normalize(params)

      def start(name, state, params, context = {}) = fetch(name).start(state, params, context)

      def schema
        { skill: { type: 'string', enum: names }, params: { anyOf: @skills.values.map(&:params_schema) } }
      end
    end
  end
end
