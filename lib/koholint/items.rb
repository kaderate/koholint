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
    ARTICLES = %w[le la l les un une des du d].freeze

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
      Array(entry['forms']).each do |form|
        raise Invalid, "#{entry['name']}: a form needs a name and a when" unless form.is_a?(Hash) && form['name'].is_a?(String) && form['when'].is_a?(String)

        validate_fact!(form.merge('value' => form['name']), "#{entry['name']} form #{form['name']}")
      end
    end

    # A fact about the item with its provenance: the pickups a gain was observed at, observed from one lineage and verified from two.
    def validate_fact!(fact, label)
      %w[value confidence verified_count source].each { |key| raise Invalid, "#{label}: missing #{key}" unless fact.is_a?(Hash) && fact.key?(key) }
      raise Invalid, "#{label}: unknown confidence #{fact['confidence']}" unless CONFIDENCES.include?(fact['confidence'])
      raise Invalid, "#{label}: verified needs verified_count >= 2" if fact['confidence'] == 'verified' && fact['verified_count'].to_i < 2
    end

    # Every name an item goes by: its catalogue name and its aliases (the game's own words, plurals, short forms).
    def names(entry) = [entry, *Array(entry['forms'])].flat_map { |named| [named['name'], *Array(named['aliases'])] }.map(&:downcase)

    # The form an item id takes in a state: the first whose `when` state field is positive, as the mushroom becomes the magic powder.
    def form(id, state)
      return nil unless state

      fields = state.to_h.transform_keys(&:to_s)
      Array(catalogue.dig(id.to_i, 'forms')).find { |form| fields[form['when']].to_i.positive? }
    end

    # Item ids a state shows held: A, B, the inventory slots, and the items whose milestone it has (older traces lack the slots).
    def held_ids(state)
      state = state.to_h.transform_keys(&:to_s)
      ids = [state['item_a'], state['item_b'], *Array(state['inventory']).first(SLOTS)].map(&:to_i).reject(&:zero?)
      ids | catalogue.values.select { |item| item['milestone'] && item['milestone'] == state['milestone'].to_s }.map { |item| item['id'] }
    end

    def name(id, state = nil)
      entry = form(id, state) || catalogue[id.to_i]
      return "unknown item #{id}" unless entry

      entry['confidence'] == 'verified' ? entry['name'] : "#{entry['name']}?"
    end

    def label(id, state = nil) = id.to_i.zero? ? 'empty' : "#{name(id, state)} (id #{id})"

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

    # One letter is the hero's name in a greeting, never an item.
    def name_words(text)
      words = text.to_s.split(/(?<=[.!?])\s/).first.to_s.scan(/[\p{L}\p{N}-]+/)
      capital = ->(word) { word.match?(/\A\p{Lu}/) }
      start = (1...words.size).find { |index| ARTICLES.include?(words[index - 1].downcase) && capital.(words[index]) } or return []
      name = words.drop(start).take_while(&capital)
      name.join.length > 1 ? name : []
    end

    # Only names the quoted pickup text says: a plural alias or a gloss comes from elsewhere.
    def pickup_text_names(catalogue = self.catalogue)
      catalogue.values.filter_map do |entry|
        next unless %w[observed verified].include?(entry['confidence']) && entry['source'].to_s.match?(/pickup text/i)

        said = entry['source'].scan(/"([^"]+)"/).flatten.map { |text| Dialogues.words(text) }
        found = names(entry).map { |name| Dialogues.words(name) }.select { |words| said.any? { |text| text.each_cons(words.size).include?(words) } }
        [entry['id'], found] unless found.empty?
      end.to_h
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
          gain = pending.find { |waiting| waiting['place'] == event['place'] && waiting['frame'].to_i - event['frame'].to_i <= PICKUP_FRAMES } or next
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
      catalogue.find { |_, entry| [entry, *Array(entry['forms'])].any? { |named| named['name'] == wanted } }&.first
    end
  end

  # Emits each item id, in each of its forms, once per run, the first time it appears among the held items after the first play frame.
  class ItemWatch
    PLAY_MODE = 0x0B

    def self.from_events(events) = new(gained: events.filter_map { |event| [event['item'].to_i, event['form']] if event['type'] == 'item_gained' })

    def initialize(gained: [])
      @gained = gained.map { |id, form| [id.to_i, form] }.to_set
      @baseline = nil
    end

    def observe(state)
      return [] unless state.game_mode == PLAY_MODE

      held = Items.held(state).uniq
      keys = held.map { |id| [id, Items.form(id, state)&.fetch('name')] }
      unless @baseline
        @baseline = keys.to_set
        return []
      end

      keys.reject { |key| @baseline.include?(key) || @gained.include?(key) }.map do |id, form|
        @gained << [id, form]
        { item: id, name: Items.name(id, state), **(form ? { form: } : {}), place: state.place, held: held.sort }
      end
    end
  end
end
