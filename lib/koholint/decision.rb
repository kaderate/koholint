require 'koholint'

module Koholint
  class DecisionPoint
    class Invalid < Error; end

    DIRECTIONS = %i[up right down left].freeze

    attr_reader :name, :options, :output_schema

    def self.move
      options = DIRECTIONS.map { |direction| { buttons: [direction], frames: 30 } } + [{ buttons: [:a], frames: 2 }]
      new(name: :move, options: options, output_schema: %i[buttons frames])
    end

    def initialize(name:, options:, output_schema:)
      @name = name
      @options = options
      @output_schema = output_schema
    end

    def validate(choice)
      missing = choice.is_a?(Hash) ? output_schema - choice.keys : output_schema
      raise Invalid, "#{name}: choice missing #{missing.join(', ')}" unless missing.empty?
      raise Invalid, "#{name}: #{choice.inspect} is not an allowed option" unless options.include?(choice)

      choice
    end
  end
end
