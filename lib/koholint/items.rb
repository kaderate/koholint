require 'json'
require 'set'
require 'koholint'
require 'koholint/dialogues'

module Koholint
  module Items
    class Invalid < Error; end

    DEFAULT_PATH = File.expand_path('../../data/items.json', __dir__)
    CONFIDENCES = %w[hypothesis observed verified].freeze
    REQUIRED = %w[id name source confidence verified_count].freeze
    SLOTS = 10
    SHIELD = 4
    SWORD = 1
    PICKUP_FRAMES = 600

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
      raise Invalid, "#{entry['name']}: aliases must be a list of names" if entry.key?('aliases') && !(entry['aliases'].is_a?(Array) && entry['aliases'].all? { |name| name.is_a?(String) && !name.strip.empty? })

      validate_fact!(entry['pickups'], "#{entry['name']} pickups") if entry.key?('pickups')
    end

    # A fact about the item with its provenance: the pickups a gain was observed at, observed from one lineage and verified from two.
    def validate_fact!(fact, label)
      %w[value confidence verified_count source].each { |key| raise Invalid, "#{label}: missing #{key}" unless fact.is_a?(Hash) && fact.key?(key) }
      raise Invalid, "#{label}: unknown confidence #{fact['confidence']}" unless CONFIDENCES.include?(fact['confidence'])
      raise Invalid, "#{label}: verified needs verified_count >= 2" if fact['confidence'] == 'verified' && fact['verified_count'].to_i < 2
    end

    # Every name an item goes by: its catalogue name and its aliases (the game's own words, plurals, short forms).
    def names(entry) = [entry['name'], *Array(entry['aliases'])].map(&:downcase)

    # Item ids a state shows held: A, B, the inventory slots, and the items whose milestone it has (older traces lack the slots).
    def held_ids(state)
      state = state.to_h.transform_keys(&:to_s)
      ids = [state['item_a'], state['item_b'], *Array(state['inventory']).first(SLOTS)].map(&:to_i).reject(&:zero?)
      ids | catalogue.values.select { |item| item['milestone'] && item['milestone'] == state['milestone'].to_s }.map { |item| item['id'] }
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

    # The name a pickup sentence gives: the first run of capitalised words in the text's first sentence, past its first word.
    def name_words(text)
      sentence = text.to_s.split(/(?<=[.!?])\s/).first.to_s
      sentence.scan(/[\p{L}\p{N}-]+/).drop(1).slice_when { |a, b| a.match?(/\A\p{Lu}/) != b.match?(/\A\p{Lu}/) }.find { |run| run.first.match?(/\A\p{Lu}/) }.to_a
    end

    # Each gained item's name words, from its pickup text: the first text transcribed at its place after the gain shows as held, within
    # PICKUP_FRAMES. A sheet is transcribed once it closes, so its dialogue events follow the gain in the trace though they carry the
    # frame the sheet opened.
    def pickup_names(events)
      names = {}
      pending = []
      now = 0
      events.each_with_index do |event, index|
        if event['type'] == 'dialogue'
          gain = pending.find { |waiting| waiting['place'] == event['place'] } or next
          pending.delete(gain)
          pages = events.drop(index).take_while { |page| page['type'] == 'dialogue' && page.values_at('frame', 'place') == event.values_at('frame', 'place') }
          words = name_words(Dialogues.text(pages.map { |page| page['text'].to_s }))
          names[gain['item'].to_i] ||= words if words.any?
          next
        end
        now = [now, event['frame'].to_i].max
        pending.reject! { |waiting| now - waiting['frame'].to_i > PICKUP_FRAMES }
        pending << event if event['type'] == 'item_gained'
      end
      names
    end

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
        { item: id, name: Items.name(id), place: state.place, held: held.uniq.sort }
      end
    end
  end
end
