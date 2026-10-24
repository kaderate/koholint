require 'koholint/dialogues'
require 'koholint/ledger'
require 'koholint/talk_log'
require 'koholint/trace'

module Koholint
  module NpcCatalogue
    UNATTRIBUTED = 'opened by itself'.freeze

    module_function

    def runs(root) = Dir[File.join(root, '*')].select { |dir| File.exist?(Trace.located(File.join(dir, 'trace.jsonl'))) }.sort

    def collect(root)
      people = {}
      runs(root).each do |dir|
        run = File.basename(dir)
        events = Trace.read(File.join(dir, 'trace.jsonl'))
        talks(events).each { |key| entry(people, key)[:talks] += 1 }
        Dialogues.from_events(events).each do |dialogue|
          person = entry(people, key_of(dialogue[:place], dialogue[:source]))
          person[:names] |= [dialogue[:speaker]] if dialogue[:speaker]
          text_key = Dialogues.key(dialogue[:text])
          next if text_key.empty?

          said = same(person[:texts], text_key, dialogue[:text]) || (person[:texts][text_key] = { text: dialogue[:text], milestone: dialogue[:stamp]&.first, runs: [], order: person[:texts].size })
          said[:runs] |= [run]
          person[:runs] |= [run]
        end
      end
      people
    end

    def same(texts, key, text)
      related = texts.select { |known, _| known.include?(key) || key.include?(known) }
      return if related.empty?

      first = related.values.min_by { |said| said[:order] }
      longest, = related.max_by { |known, _| known.size }
      merged = first.merge(runs: related.values.flat_map { |said| said[:runs] }.uniq, text: longest.size >= key.size ? related[longest][:text] : text)
      related.each_key { |known| texts.delete(known) }
      texts[[longest, key].max_by(&:size)] = merged
    end

    def talks(events)
      events.filter_map do |event|
        next unless event['type'] == 'action' && event['skill'] == 'talk_to' && event.dig('result', 'talked') == true

        place = Ledger.place_of(event.dig('result', 'from')) or next
        entity = TalkLog.entity_of(event['result'])
        key_of(place, { row: event.dig('params', 'row'), col: event.dig('params', 'col'), entity: }.compact)
      end
    end

    def key_of(place, source)
      who = if source.nil? then UNATTRIBUTED
            elsif source[:entity] then "entity type #{source[:entity]}"
            else "cell (#{source[:row]},#{source[:col]})"
            end
      [place, who]
    end

    def entry(people, key) = people[key] ||= { names: [], talks: 0, runs: [], texts: {} }

    def markdown(root)
      people = collect(root)
      lines = ['| place | person | names | talks | runs | dialogues (milestone when first read, runs) |', '|---|---|---|---|---|---|']
      people.sort_by { |(place, who), _| [place, who] }.each do |(place, who), person|
        said = person[:texts].values.sort_by { |text| text[:order] }.map { |text| "[#{text[:milestone] || '?'}, #{text[:runs].size}] #{cell(text[:text])}" }
        lines << "| #{place.join('/')} | #{who} | #{person[:names].join(', ')} | #{person[:talks]} | #{person[:runs].size} | #{said.join('<br>')} |"
      end
      "#{lines.join("\n")}\n"
    end

    def cell(text) = text.to_s.gsub('|', '\\|').gsub(/\s*\n\s*/, ' ')
  end
end
