require 'json'
require 'set'
require 'koholint'

module Koholint
  module Items
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/items.json', __dir__)
    CONFIDENCES = %w[hypothesis verified].freeze
    REQUIRED = %w[id name source confidence verified_count].freeze
    SLOTS = 10
    SHIELD = 4
    SWORD = 1

    module_function

    def catalogue(path = DEFAULT_PATH)
      return @catalogue if @catalogue && path == DEFAULT_PATH

      entries = JSON.parse(File.read(path)).each { |entry| validate!(entry) }.to_h { |entry| [entry['id'], entry.freeze] }.freeze
      path == DEFAULT_PATH ? @catalogue = entries : entries
    end

    def validate!(entry)
      missing = REQUIRED - entry.keys
      raise Invalid, "#{entry['name'] || entry.inspect}: missing #{missing.join(', ')}" unless missing.empty?
      raise Invalid, "#{entry['name']}: unknown confidence #{entry['confidence']}" unless CONFIDENCES.include?(entry['confidence'])
      raise Invalid, "#{entry['name']}: verified needs verified_count >= 2" if entry['confidence'] == 'verified' && entry['verified_count'] < 2
    end

    def name(id)
      entry = catalogue[id.to_i]
      return "unknown item #{id}" unless entry

      entry['confidence'] == 'verified' ? entry['name'] : "#{entry['name']}?"
    end

    def label(id) = id.to_i.zero? ? 'empty' : "#{name(id)} (id #{id})"

    def milestone(id) = catalogue.dig(id.to_i, 'milestone')&.to_sym

    def slots(state) = Array(state.inventory).first(SLOTS)

    # Every item Link holds, wherever it sits: the A and B buttons and the 10 inventory slots.
    def held(state) = [state.item_a, state.item_b, *slots(state)].map(&:to_i).reject(&:zero?)

    def button_of(state, id)
      return :a if state.item_a.to_i == id
      return :b if state.item_b.to_i == id

      nil
    end

    def slot_of(state, id) = slots(state).index { |item| item.to_i == id }

    def find(query)
      return Integer(query) if query.is_a?(Integer) || query.to_s.match?(/\A\d+\z/)

      wanted = query.to_s.downcase.delete('?').strip
      catalogue.find { |_, entry| entry['name'] == wanted }&.first
    end
  end

  # Emits each item id once per run, the first time it appears among the held items after the first play frame.
  class ItemWatch
    PLAY_MODE = 0x0B

    def self.from_events(events) = new(gained: events.filter_map { |event| event['item'] if event['type'] == 'item_gained' })

    def initialize(gained: [])
      @gained = gained.map(&:to_i).to_set
      @baseline = nil
    end

    def observe(state)
      return [] unless state.game_mode == PLAY_MODE

      held = Items.held(state)
      unless @baseline
        @baseline = held.to_set
        return []
      end

      held.uniq.reject { |id| @baseline.include?(id) || @gained.include?(id) }.map do |id|
        @gained << id
        { item: id, name: Items.name(id), place: [state.room_id, state.map_id], held: held.uniq.sort }
      end
    end
  end
end
