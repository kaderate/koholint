require 'json'
require 'koholint/addresses'
require 'koholint/geometry'

module Koholint
  module Entities
    class Invalid < Error; end

    SLOTS = 16
    KINDS = %w[npc enemy object unknown].freeze
    DEFAULT_PATH = File.expand_path('../../data/entities.json', __dir__)
    ADDRESSES = Addresses.load.slice(:entity_x, :entity_y, :entity_status, :entity_state, :entity_type).freeze

    module_function

    def read(reader, kinds: catalogue)
      (0...SLOTS).filter_map do |slot|
        at = ->(name) { reader.read(ADDRESSES.fetch(name) + slot) }
        status = at.(:entity_status)
        next if status.zero?

        x = at.(:entity_x)
        y = at.(:entity_y)
        type = at.(:entity_type)
        known = kinds[type]
        { slot:, type:, x:, y:, status:, state: at.(:entity_state), cell: Geometry.cell_for(x, y), kind: known ? known[:kind] : :unknown,
          verified: known ? known[:verified] : false, moves: known&.dig(:moves) }
      end
    end

    def catalogue(path = DEFAULT_PATH)
      @catalogue ||= {}
      @catalogue[path] ||= load(path).freeze
    end

    def load(path = DEFAULT_PATH)
      JSON.parse(File.read(path)).to_h do |entry|
        validate!(entry)
        [Integer(entry.fetch('type')), { kind: entry.fetch('kind').to_sym, verified: entry['confidence'] == 'verified', moves: entry['moves'] }]
      end
    end

    def validate!(entry)
      %w[type kind source confidence verified_count].each do |key|
        raise Invalid, "entity #{entry['type'].inspect}: missing #{key}" unless entry.key?(key)
      end
      raise Invalid, "entity #{entry['type']}: unknown kind #{entry['kind']}" unless KINDS.include?(entry['kind'])
      raise Invalid, "entity #{entry['type']}: unknown confidence #{entry['confidence']}" unless Addresses::CONFIDENCES.include?(entry['confidence'])
      return unless entry['confidence'] == 'verified' && entry['verified_count'] < 2

      raise Invalid, "entity #{entry['type']}: verified needs verified_count >= 2"
    end

    def near(entities, cell, within: 1)
      entities.select { |entity| entity[:cell] && (entity[:cell][0] - cell[0]).abs <= within && (entity[:cell][1] - cell[1]).abs <= within }
              .min_by { |entity| [(entity[:cell][0] - cell[0]).abs + (entity[:cell][1] - cell[1]).abs, entity[:slot]] }
    end
  end
end
