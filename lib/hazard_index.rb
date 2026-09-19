# frozen_string_literal: true

require "json"
require_relative "navigator"

module Koholint
  # Routed (not built) by MP11, resolving ESC9: a derived, read-only cross-reference over
  # data/ram_registry.json's scattered hazard/creature facts, so a session about to log a new
  # classification can query first instead of quietly duplicating or contradicting one already on
  # file. Same shape as ClueCrossReference (its own MP10-routed precedent): a query module plus a
  # runnable CLI, no writes to the registry.
  #
  # Grounding rule, exactly MP10's mechanism (b): room_labels and visual_catalog entries are
  # fully grounded (they only ever record an actually placed/observed fact). Inside
  # world_topology, the `note` field is open-discussion prose (MP11's own worked example -- the
  # "Loupe" false-grounding bug's sibling case) and is never treated as a grounded fact; every
  # other world_topology field is. Dialogue `note`/`text` are fair game ONLY for the untested-claim
  # scan below, never counted as an existing grounded fact about a tile/creature the way a
  # visual_catalog/room_labels hit would be.
  module HazardIndex
    DEFAULT_REGISTRY_PATH = "data/ram_registry.json"

    GROUNDED_TEXT_COLLECTIONS = %w[visual_catalog room_labels].freeze
    UNGROUNDED_WORLD_TOPOLOGY_FIELDS = %w[note].freeze

    # "tile=0x6c", "tile 88/90", "tile_id: 94" -- one or more hex/decimal tokens following the
    # word "tile", as this registry's own free text actually writes them.
    TILE_MENTION_RE = /tile[a-z_]*\s*(?:id)?\s*[:=]?\s*((?:0x[0-9a-f]+|\d+)(?:\s*[\/,]\s*(?:0x[0-9a-f]+|\d+))*)/i

    CLAIM_COUNTERMEASURE_TERMS = %w[bouclier protège protéger protection].freeze
    CLAIM_STOP_WORDS = %w[de des du le la les un une et avec pour dans sur sans se ne pas toi tu
                           il elle nous vous ils elles car est sont cette].freeze
    MIN_CLAIM_WORD_LENGTH = 4
    # Evidence that a claim was actually put to the test, not just repeated/discussed -- kept
    # deliberately narrow (not "confirmed"/"verified", both too common in this registry's prose
    # to mean anything specific) to avoid an ordinary re-statement reading as a test.
    TEST_EVIDENCE_TERMS = %w[test tested testé teste contact dégât dégâts damage hit knockback].freeze
    # A word can't both name the hazard AND be the signal that it was tested -- excluded from
    # candidate claim terms so a dialogue's own methodology-heavy note field (which legitimately
    # uses these words) never manufactures a false self-referential "claim".
    GENERIC_METHOD_WORDS = %w[confirmed verified].freeze

    HINT_STOP_WORDS = %w[de des du le la les un une et avec pour dans sur].freeze
    MIN_HINT_WORD_LENGTH = 4

    SNIPPET_LENGTH = 160

    TileHit = Struct.new(:collection, :key, :field, :snippet, keyword_init: true) do
      def to_h = {"collection" => collection, "key" => key, "field" => field, "snippet" => snippet}
    end

    UntestedClaim = Struct.new(:dialogue_path, :terms, :text, keyword_init: true) do
      def to_h = {"dialogue_path" => dialogue_path, "terms" => terms, "text" => text}
    end

    def self.load_registry(path = DEFAULT_REGISTRY_PATH)
      JSON.parse(File.read(path, encoding: "UTF-8"))
    end

    # HOSTILE_TILE_IDS / UNKNOWN_HAZARD_TILE_IDS membership -- AGENTS.md's own cross-reference
    # convention requires checking both, never HOSTILE_TILE_IDS alone.
    def self.hazard_membership(tile_id)
      {
        hostile: Navigator::HOSTILE_TILE_IDS.include?(tile_id),
        unknown_hazard: Navigator::UNKNOWN_HAZARD_TILE_IDS.include?(tile_id)
      }
    end

    # Every registry location that already records something about `tile_id`: visual_catalog's
    # structured tile_ids_seen, plus any grounded field (see module doc) mentioning it in prose.
    def self.tile_hits(registry, tile_id)
      hits = []

      registry.fetch("visual_catalog", {}).each do |key, entry|
        next unless entry.is_a?(Hash)

        entry.fetch("tile_ids_seen", {}).each do |room, ids|
          next unless Array(ids).any? { |i| i.to_i == tile_id }

          hits << TileHit.new(collection: "visual_catalog", key: key, field: "tile_ids_seen.#{room}",
                               snippet: "tile_ids_seen[#{room}] includes #{tile_id}")
        end
      end

      each_grounded_field(registry) do |collection, key, path, text|
        next unless tile_mentions(text).include?(tile_id)

        hits << TileHit.new(collection: collection, key: key, field: path.join("."), snippet: truncate(text))
      end

      hits.uniq { |h| [h.collection, h.key, h.field] }
    end

    def self.tile_report(registry, tile_id)
      hazard_membership(tile_id).merge(tile_id: tile_id, hits: tile_hits(registry, tile_id))
    end

    # Every grounded field whose (whitespace-stripped) text contains `signature`'s hex bytes --
    # for cross-room CHR-pattern identity checks (D9's own technique), not raw tile IDs.
    def self.chr_hits(registry, signature)
      sig = normalize_chr(signature)
      return [] if sig.empty?

      each_grounded_field(registry).filter_map do |collection, key, path, text|
        next unless normalize_chr(text).include?(sig)

        TileHit.new(collection: collection, key: key, field: path.join("."), snippet: truncate(text))
      end
    end

    # Every grounded field about `room_key` (e.g. "240/0"), optionally narrowed to fields
    # mentioning one of `hint`'s significant words (an object description).
    def self.room_hits(registry, room_key, hint: nil)
      hint_words = hint.nil? ? nil : significant_words(hint)
      hits = []

      room_entry = registry.dig("room_labels", room_key)
      if room_entry.is_a?(Hash)
        each_string_leaf(room_entry) do |path, text|
          next if hint_words && !contains_any?(text, hint_words)

          hits << TileHit.new(collection: "room_labels", key: room_key, field: path.join("."), snippet: truncate(text))
        end
      end

      registry.fetch("visual_catalog", {}).each do |key, entry|
        next unless entry.is_a?(Hash)
        next unless Array(entry["rooms_seen"]).any? { |r| r.to_s.start_with?(room_key) }

        each_string_leaf(entry) do |path, text|
          next if hint_words && !contains_any?(text, hint_words)

          hits << TileHit.new(collection: "visual_catalog", key: key, field: path.join("."), snippet: truncate(text))
        end
      end

      registry.fetch("world_topology", {}).each do |key, entry|
        next unless entry.is_a?(Hash)
        next unless world_topology_entry_for_room?(entry, room_key)

        each_string_leaf(entry, skip_keys: UNGROUNDED_WORLD_TOPOLOGY_FIELDS) do |path, text|
          next if hint_words && !contains_any?(text, hint_words)

          hits << TileHit.new(collection: "world_topology", key: key, field: path.join("."), snippet: truncate(text))
        end
      end

      hits
    end

    # Scans dialogues.*.note/text for a specific, falsifiable behavioral claim (a hazard mentioned
    # alongside a countermeasure -- MP11's worked example: riverside_flower_clearing_sign's
    # "a shield counters oursins") and surfaces it unless some OTHER registry entry already shows,
    # in a single sentence, both the same claim term and actual test evidence -- not just the same
    # word reused elsewhere, per this registry's own real near-miss (room_labels['225/0']'s
    # multi-page description mentions both "oursins" and a later, unrelated "TACTIC TESTED"
    # paragraph about a different, invisible creature in the same room; sentence-level, not
    # field-level, co-occurrence is what tells those apart).
    def self.untested_claims(registry = load_registry)
      dialogue_documents(registry).filter_map do |doc|
        terms = claim_terms(doc[:text])
        next if terms.empty?
        next if claim_tested_elsewhere?(registry, terms, doc[:key])

        UntestedClaim.new(dialogue_path: doc[:path], terms: terms, text: doc[:text].strip)
      end
    end

    # --- internals ---

    # Yields (collection, key, field_path, text) for every grounded string field across
    # visual_catalog, room_labels, and world_topology minus its ungrounded fields.
    def self.each_grounded_field(registry)
      return enum_for(:each_grounded_field, registry) unless block_given?

      GROUNDED_TEXT_COLLECTIONS.each do |collection|
        registry.fetch(collection, {}).each do |key, entry|
          next unless entry.is_a?(Hash)

          each_string_leaf(entry) { |path, text| yield collection, key, path, text }
        end
      end

      registry.fetch("world_topology", {}).each do |key, entry|
        next unless entry.is_a?(Hash)

        each_string_leaf(entry, skip_keys: UNGROUNDED_WORLD_TOPOLOGY_FIELDS) do |path, text|
          yield "world_topology", key, path, text
        end
      end
    end

    def self.each_string_leaf(value, skip_keys: [], path: [], &block)
      case value
      when Hash
        value.each do |k, v|
          next if skip_keys.include?(k)

          each_string_leaf(v, skip_keys: skip_keys, path: path + [k], &block)
        end
      when Array
        value.each_with_index { |v, i| each_string_leaf(v, skip_keys: skip_keys, path: path + [i.to_s], &block) }
      when String
        block.call(path, value)
      end
    end

    def self.tile_mentions(text)
      return [] unless text.is_a?(String)

      text.scan(TILE_MENTION_RE).flatten.flat_map do |group|
        group.split(/[\/,]/).map { |tok| parse_tile_token(tok.strip) }
      end.uniq
    end

    def self.parse_tile_token(token)
      token =~ /\A0x/i ? token[2..].to_i(16) : token.to_i
    end

    def self.normalize_chr(text) = text.to_s.downcase.gsub(/[^0-9a-fx]/, "")

    def self.world_topology_entry_for_room?(entry, room_key)
      room_id_str = room_key.split("/").first
      return true if entry["room_id"].to_s == room_id_str

      found = false
      each_string_leaf(entry, skip_keys: UNGROUNDED_WORLD_TOPOLOGY_FIELDS) do |_path, text|
        found ||= text.include?(room_key)
      end
      found
    end

    def self.significant_words(text)
      text.downcase.scan(/[a-zà-ÿ0-9]+/).uniq.reject do |w|
        w.length < MIN_HINT_WORD_LENGTH || HINT_STOP_WORDS.include?(w)
      end
    end

    def self.contains_any?(text, words)
      low = text.downcase
      words.any? { |w| low.include?(w) }
    end

    # `text` and `note` are scanned as SEPARATE documents, not concatenated -- a dialogue's own
    # methodology-heavy note (checkpoints, tap counts, transcription steps) would otherwise dilute
    # the actual in-game claim's word set with unrelated vocabulary.
    def self.dialogue_documents(registry)
      registry.fetch("dialogues", {}).flat_map do |key, entry|
        next [] unless entry.is_a?(Hash)

        %w[text note].filter_map do |field|
          value = entry[field]
          next unless value.is_a?(String) && !value.strip.empty?

          {key: key, path: "dialogues.#{key}.#{field}", text: value}
        end
      end
    end

    def self.sentences(text) = text.split(/(?<=[.!?])\s+/)

    def self.claim_terms(text)
      words = text.downcase.scan(/[a-zà-ÿ]+/)
      return [] unless words.any? { |w| CLAIM_COUNTERMEASURE_TERMS.include?(w) }

      words.uniq.reject do |w|
        w.length < MIN_CLAIM_WORD_LENGTH || CLAIM_STOP_WORDS.include?(w) || CLAIM_COUNTERMEASURE_TERMS.include?(w) ||
          TEST_EVIDENCE_TERMS.include?(w) || GENERIC_METHOD_WORDS.include?(w)
      end
    end

    # True as soon as one sentence anywhere else in the registry (any collection, any field,
    # notes included -- this is evidence-of-testing, not the tile/CHR grounding rule above)
    # contains both a claim term and a test-evidence term together.
    def self.claim_tested_elsewhere?(registry, terms, exclude_dialogue_key)
      registry.each do |collection, entries|
        next unless entries.is_a?(Hash)

        entries.each do |key, entry|
          next if collection == "dialogues" && key == exclude_dialogue_key

          each_string_leaf(entry) do |_path, text|
            sentences(text).each do |sentence|
              low = sentence.downcase
              next unless terms.any? { |t| low.include?(t) }

              return true if TEST_EVIDENCE_TERMS.any? { |ev| low.include?(ev) }
            end
          end
        end
      end
      false
    end

    def self.truncate(text)
      text.length > SNIPPET_LENGTH ? "#{text[0, SNIPPET_LENGTH]}..." : text
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  registry = Koholint::HazardIndex.load_registry
  arg = ARGV[0]

  print_hits = lambda do |hits|
    if hits.empty?
      puts "  no existing registry entries reference this."
    else
      hits.each { |h| puts format("  %-15s %-40s %-20s %s", h.collection, h.key, h.field, h.snippet) }
    end
  end

  case arg
  when nil
    claims = Koholint::HazardIndex.untested_claims(registry)
    if claims.empty?
      puts "No untested hazard/creature claims found."
    else
      claims.each do |c|
        puts format("%-45s terms=%-20s %s", c.dialogue_path, c.terms.join(","), c.text)
      end
    end
  when /\A\d+\/\d+\z/ # room+object key, e.g. "240/0"
    print_hits.call(Koholint::HazardIndex.room_hits(registry, arg, hint: ARGV[1]))
  when /\A(?:0x)?[0-9a-fA-F]{6,}\z/ # CHR signature (several bytes, not a bare tile ID)
    print_hits.call(Koholint::HazardIndex.chr_hits(registry, arg))
  else
    tile_id = arg =~ /\A0x/i ? Integer(arg, 16) : Integer(arg)
    membership = Koholint::HazardIndex.hazard_membership(tile_id)
    puts format("tile 0x%02x (%d): hostile=%s unknown_hazard=%s", tile_id, tile_id, membership[:hostile], membership[:unknown_hazard])
    print_hits.call(Koholint::HazardIndex.tile_hits(registry, tile_id))
  end
end
