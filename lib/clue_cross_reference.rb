# frozen_string_literal: true

require "json"

module Koholint
  # Promoted from the Explorer-role prototype validated twice (ESC8/MP10): a place mentioned as
  # an ordinary lowercase common noun in dialogue ("la plage") can match a place name the SELECT
  # map already records ("Plage Coco") via plain case-insensitive word matching. Only mechanism
  # (b) of that prototype -- mid-sentence-capitalization term extraction was shown blind to this
  # exact case and is deliberately not ported (see AGENTS.md's "Promoting validated Explorer
  # prototypes").
  #
  # Grounding vocabulary comes ONLY from fields recording an actually placed/observed fact --
  # select_map_screen.note and room_labels -- never world_topology or other free-text notes,
  # which are open investigation discussion, not observed fact (the exact conflation ESC8
  # flagged: a term merely discussed there would falsely read as "grounded").
  module ClueCrossReference
    DEFAULT_REGISTRY_PATH = "data/ram_registry.json"
    STOP_WORDS = %w[de des du le la les un une et chez].freeze
    MIN_WORD_LENGTH = 4
    MIN_QUOTED_NAME_LENGTH = 3
    MAX_QUOTED_NAME_LENGTH = 30

    Match = Struct.new(:dialogue_path, :place_names, keyword_init: true) do
      def to_h = {"dialogue_path" => dialogue_path, "place_names" => place_names}
    end

    def self.load_registry(path = DEFAULT_REGISTRY_PATH)
      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    def self.dialogue_texts(registry)
      dialogues = registry.fetch("dialogues", {})
      dialogues.filter_map do |key, entry|
        next unless entry.is_a?(Hash)

        text = entry["text"]
        {path: "dialogues.#{key}.text", text: text} if text.is_a?(String)
      end
    end

    # Place names as double-quoted phrases inside select_map_screen.note, plus room_labels'
    # own label text -- both are facts about something actually placed/observed, per the
    # grounding constraint above.
    def self.place_names(registry)
      names = registry.dig("select_map_screen", "note").to_s
                       .scan(/"([^"]{#{MIN_QUOTED_NAME_LENGTH},#{MAX_QUOTED_NAME_LENGTH}})"/)
                       .flatten
      names += registry.fetch("room_labels", {}).values.filter_map do |entry|
        entry["label"] if entry.is_a?(Hash) && entry["label"].is_a?(String)
      end
      names.select { |n| n =~ /[A-ZÀ-Ö]/ && n.length > MIN_QUOTED_NAME_LENGTH }.uniq
    end

    # word (downcased, stripped of punctuation) -> the place name(s) it belongs to.
    def self.place_word_index(place_names)
      index = Hash.new { |h, k| h[k] = [] }
      place_names.each do |name|
        name.split(/\s+/).each do |word|
          clean = word.downcase.gsub(/[^a-zà-ÿ]/, "")
          next if clean.length < MIN_WORD_LENGTH || STOP_WORDS.include?(clean)

          index[clean] << name unless index[clean].include?(name)
        end
      end
      index
    end

    # Cross-references every dialogue text's own words (case-insensitive) against the place-name
    # vocabulary. Returns one Match per dialogue with at least one hit.
    def self.matches(registry = load_registry)
      index = place_word_index(place_names(registry))
      dialogue_texts(registry).filter_map do |doc|
        words = doc[:text].downcase.scan(/[a-zà-ÿ]+/)
        hit = words.filter_map { |w| index[w] if index.key?(w) }.flatten.uniq
        Match.new(dialogue_path: doc[:path], place_names: hit) unless hit.empty?
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  registry_path = ARGV.fetch(0, Koholint::ClueCrossReference::DEFAULT_REGISTRY_PATH)
  results = Koholint::ClueCrossReference.matches(Koholint::ClueCrossReference.load_registry(registry_path))
  if results.empty?
    puts "No cross-references found."
  else
    results.each do |match|
      puts format("%-55s -> %s", match.dialogue_path, match.place_names.join(", "))
    end
  end
end
