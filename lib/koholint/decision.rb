require 'koholint'
require 'json'
require 'koholint/skills/registry'
require 'koholint/objectives'

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

    def self.choose_objective = new(name: :choose_objective, options: nil, output_schema: %i[title predicate])

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
      return validate_objective(choice) if name == :choose_objective
      return validate_macro(choice) if options.nil?
      raise Invalid, "#{name}: #{choice.inspect} is not an allowed option" unless options.include?(choice)

      choice
    end

    def json_schema
      return objective_schema if name == :choose_objective
      raise Invalid, "#{name}: no skill registry" unless registry

      { type: 'object',
        properties: registry.schema.merge(justification: { type: 'string' },
                                           confidence: { type: 'number', minimum: 0, maximum: 1 },
                                           transcription: { type: 'string' }),
        required: %w[skill params justification confidence], additionalProperties: false }
    end

    private

    PLACE_SCHEMA = { type: 'array', items: { type: 'integer' }, minItems: 2, maxItems: 2 }.freeze
    FIELD_SCHEMAS = { place: PLACE_SCHEMA, row: { type: 'integer', minimum: 0, maximum: 7 },
                      col: { type: 'integer', minimum: 0, maximum: 9 } }.freeze

    def objective_schema
      predicates = Objectives::PREDICATES.map do |kind, fields|
        { type: 'object', properties: { kind: { type: 'string', enum: [kind] } }.merge(FIELD_SCHEMAS.slice(*fields)),
          required: ['kind', *fields.map(&:to_s)], additionalProperties: false }
      end
      { type: 'object',
        properties: { title: { type: 'string', minLength: 1 }, predicate: { oneOf: predicates },
                      justification: { type: 'string' }, confidence: { type: 'number', minimum: 0, maximum: 1 } },
        required: %w[title predicate justification confidence], additionalProperties: false }
    end

    def validate_objective(choice)
      raise Invalid, "#{name}: title must be a non-empty string" unless choice[:title].is_a?(String) && !choice[:title].strip.empty?
      raise Invalid, "#{name}: invalid predicate #{choice[:predicate].inspect}" unless Objectives.valid_predicate?(choice[:predicate])

      choice
    end

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
