require 'koholint'
require 'koholint/skills/registry'

module Koholint
  class DecisionPoint
    class Invalid < Error; end

    DIRECTIONS = %i[up right down left].freeze
    BUTTONS = %i[up down left right a b start select].freeze
    MAX_MACRO_FRAMES = 300

    attr_reader :name, :options, :output_schema, :registry

    def self.move
      options = DIRECTIONS.map { |direction| { buttons: [direction], frames: 30 } } + [{ buttons: [:a], frames: 2 }]
      new(name: :move, options: options, output_schema: %i[buttons frames])
    end

    def self.choose_skill(registry) = new(name: :choose_skill, options: nil, output_schema: %i[skill params], registry:)

    def self.macro(name) = new(name: name, options: nil, output_schema: %i[buttons frames])

    def initialize(name:, options:, output_schema:, registry: nil)
      @registry = registry
      @name = name
      @options = options
      @output_schema = output_schema
    end

    def validate(choice)
      missing = choice.is_a?(Hash) ? output_schema - choice.keys : output_schema
      raise Invalid, "#{name}: choice missing #{missing.join(', ')}" unless missing.empty?
      return validate_skill(choice) if registry
      return validate_macro(choice) if options.nil?
      raise Invalid, "#{name}: #{choice.inspect} is not an allowed option" unless options.include?(choice)

      choice
    end

    def json_schema
      raise Invalid, "#{name}: no skill registry" unless registry

      { type: 'object',
        properties: registry.schema.merge(justification: { type: 'string' },
                                           confidence: { type: 'number', minimum: 0, maximum: 1 },
                                           transcription: { type: 'string' }),
        required: %w[skill params justification confidence], additionalProperties: false }
    end

    private

    def validate_skill(choice)
      registry.validate(choice[:skill], choice[:params])
      choice
    rescue ArgumentError => e
      raise Invalid, "#{name}: #{e.message}"
    end

    def validate_macro(choice)
      unless choice[:buttons].is_a?(Array) && (choice[:buttons] - BUTTONS).empty?
        raise Invalid, "#{name}: unknown buttons #{choice[:buttons].inspect}"
      end
      raise Invalid, "#{name}: frames must be 1..#{MAX_MACRO_FRAMES}" unless choice[:frames].is_a?(Integer) && choice[:frames].between?(1, MAX_MACRO_FRAMES)

      choice
    end
  end
end
