require 'json'
require 'set'
require 'koholint/dialogues'
require 'koholint/items'
require 'koholint/trace'

module Koholint
  # A lead's claim may name an item only when the text read names it (under any of its names) or Link held it by then; any other
  # item comes from general knowledge of the game, a walkthrough leak. `absorb` drops such leads, `check-leads` reports them in traces.
  module LeadCheck
    module_function

    def named(claim:, where:, texts:, held:)
      said = [claim, where].compact.join(' ').downcase
      read = Array(texts).join("\n").downcase
      Items.catalogue.values.reject { |item| held.include?(item['id']) }.select do |item|
        names = Items.names(item)
        names.any? { |name| mentions?(said, name) } && names.none? { |name| mentions?(read, name) }
      end.map { |item| item['name'] }
    end

    def mentions?(text, name) = text.match?(/(?<![[:alnum:]])#{Regexp.escape(name)}(?![[:alnum:]])/)

    VOCABULARY = File.expand_path('../../data/vocabulary.json', __dir__)
    KINDS = %w[person role thing].freeze

    def vocabulary
      @vocabulary ||= JSON.parse(File.read(VOCABULARY)).each do |entry|
        raise Error, "vocabulary entry #{entry.inspect} needs a name, a kind (#{KINDS.join('|')}), aliases and a source" unless
          entry['name'].is_a?(String) && KINDS.include?(entry['kind']) && entry['aliases'].is_a?(Array) && entry['source'].is_a?(String)
      end.freeze
    end

    # A person, a role or a thing the claim names while no text read names it under any of its names: the claim is the model's
    # knowledge of the game, so it is withheld and the quote shown in its place.
    def unread(claim:, where:, texts:)
      said = [claim, where].compact.join(' ').downcase
      read = Array(texts).join("\n").downcase
      vocabulary.select do |entry|
        names = [entry['name'], *entry['aliases']].map(&:downcase)
        names.any? { |name| mentions?(said, name) } && names.none? { |name| mentions?(read, name) }
      end.map { |entry| entry['name'] }
    end

    # Offline, the text read is the lead's quote and every dialogue text of the run up to it.
    def leaks(events)
      held = Set.new
      read = []
      events.each_with_object([]) do |event, found|
        case event['type']
        when 'perception' then held.merge(Items.held_ids(event['state'] || {}))
        when 'dialogue' then read << event['text'].to_s
        when 'lead'
          named = named(claim: event['claim'], where: event['where'], texts: read + [event['quote'].to_s], held:)
          found << { id: event['id'], frame: event['frame'], place: event['place'], items: named, claim: event['claim'] } if named.any?
        end
      end
    end

    SENTENCE_WORDS = 3

    # Every sentence of a text read (of 3 words or more) is quoted by a lead, dismissed by a low lead quoting it, or dropped; a quote
    # cut inside a sentence does not cover it. Each sentence counts once per run.
    def sentences(events)
      quotes = events.select { |event| event['type'] == 'lead' }.map { |event| [Dialogues.key(event['quote']), event['importance'].to_s] }
      texts = events.select { |event| event['type'] == 'dialogue' }.chunk_while { |a, b| a.values_at('frame', 'place') == b.values_at('frame', 'place') }
      seen = Set.new
      texts.each_with_object({ covered: 0, dismissed: 0, dropped: [] }) do |pages, found|
        Dialogues.text(pages.map { |page| page['text'] }).gsub(/\s+/, ' ').split(/(?<=[.!?…])\s+/).each do |sentence|
          key = Dialogues.key(sentence)
          next if sentence.split.size < SENTENCE_WORDS || !seen.add?(key)

          kinds = quotes.select { |quote, _| quote.include?(key) }.map(&:last)
          next found[:covered] += 1 if kinds.any? { |kind| kind != 'low' }
          next found[:dismissed] += 1 if kinds.any?

          found[:dropped] << { frame: pages.first['frame'], place: pages.first['place'], sentence: sentence.strip }
        end
      end
    end

    def check(dirs, out:)
      found = dirs.flat_map { |dir| leaks(Trace.read(File.join(dir, 'trace.jsonl'))).map { |leak| leak.merge(run: File.basename(dir)) } }
      found.each { |leak| out.puts "#{leak[:run]} #{leak[:id]} (#{Array(leak[:place]).join('-')}, frame #{leak[:frame]}): names #{leak[:items].join(', ')}: #{leak[:claim]}" }
      out.puts "#{found.size} lead(s) name an item absent from the text read and not held, in #{dirs.size} run(s)"
      counts = dirs.map { |dir| sentences(Trace.read(File.join(dir, 'trace.jsonl'))).merge(run: File.basename(dir)) }
      counts.each { |count| count[:dropped].each { |drop| out.puts "#{count[:run]} dropped (#{Array(drop[:place]).join('-')}, frame #{drop[:frame]}): #{drop[:sentence]}" } }
      out.puts "sentences read: #{counts.sum { |count| count[:covered] }} quoted by a lead, #{counts.sum { |count| count[:dismissed] }} dismissed by a low lead, " \
               "#{counts.sum { |count| count[:dropped].size }} dropped"
      found.empty? ? 0 : 1
    end
  end
end
