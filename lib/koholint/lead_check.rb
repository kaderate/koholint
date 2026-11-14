require 'set'
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

    def check(dirs, out:)
      found = dirs.flat_map { |dir| leaks(Trace.read(File.join(dir, 'trace.jsonl'))).map { |leak| leak.merge(run: File.basename(dir)) } }
      found.each { |leak| out.puts "#{leak[:run]} #{leak[:id]} (#{Array(leak[:place]).join('-')}, frame #{leak[:frame]}): names #{leak[:items].join(', ')}: #{leak[:claim]}" }
      out.puts "#{found.size} lead(s) name an item absent from the text read and not held, in #{dirs.size} run(s)"
      found.empty? ? 0 : 1
    end
  end
end
