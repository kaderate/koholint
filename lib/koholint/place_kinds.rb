require 'json'
require 'koholint'

module Koholint
  module PlaceKinds
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/place_kinds.json', __dir__)
    KINDS = %w[world interior cave dungeon].freeze
    LAYOUTS = %w[grid16 attached].freeze
    CONFIDENCES = %w[hypothesis verified].freeze
    REQUIRED = %w[kind map_ids layout source confidence verified_count].freeze
    KEYS = (REQUIRED + %w[note]).freeze
    OTHER = 'other'.freeze

    module_function

    def catalogue = @catalogue ||= load

    def load(path = DEFAULT_PATH)
      entries = JSON.parse(File.read(path))
      raise Invalid, 'place kinds must be a list' unless entries.is_a?(Array)

      entries.each { |entry| validate!(entry) }
      maps = entries.flat_map { |entry| entry['map_ids'] }
      raise Invalid, "map_id #{maps.find { |m| maps.count(m) > 1 }} has two kinds" unless maps.uniq.size == maps.size

      entries.flat_map { |entry| entry['map_ids'].map { |map| [map, entry.slice('kind', 'layout').freeze] } }.to_h.freeze
    end

    def validate!(entry)
      raise Invalid, 'a place kind must be an object' unless entry.is_a?(Hash)

      name = entry['kind'].inspect
      raise Invalid, "#{name}: missing #{(REQUIRED - entry.keys).join(', ')}" unless (REQUIRED - entry.keys).empty?
      raise Invalid, "#{name}: unknown key #{(entry.keys - KEYS).first}" unless (entry.keys - KEYS).empty?
      raise Invalid, "#{name}: unknown kind" unless KINDS.include?(entry['kind'])
      raise Invalid, "#{name}: unknown layout" unless LAYOUTS.include?(entry['layout'])
      raise Invalid, "#{name}: only world uses the grid16 layout" if (entry['layout'] == 'grid16') != (entry['kind'] == 'world')
      raise Invalid, "#{name}: map_ids must be bytes" unless entry['map_ids'].is_a?(Array) && !entry['map_ids'].empty? &&
                                                               entry['map_ids'].all? { |m| m.is_a?(Integer) && m.between?(0, 255) }
      raise Invalid, "#{name}: unknown confidence" unless CONFIDENCES.include?(entry['confidence'])
      raise Invalid, "#{name}: verified needs verified_count >= 2" if entry['confidence'] == 'verified' && entry['verified_count'].to_i < 2
    end

    def kind(place, kinds = catalogue) = kinds.dig(place[1], 'kind') || OTHER

    def grid?(place, kinds = catalogue) = kinds.dig(place[1], 'layout') == 'grid16'

    def cell(place) = [place[0] & 0xF, place[0] >> 4]
  end
end
