require 'json'
require 'koholint'
require 'koholint/atlas'
require 'koholint/place_kinds'

module Koholint
  module Viewer
    module Island
      ITEMS = File.join(Atlas::DATA, 'items.json')
      IMPORTANCE = %w[high normal low tip].freeze

      module_function

      def build(roots, cache: {}, items: ITEMS)
        dirs, digests = Atlas.read(roots, cache:)
        of(dirs, digests, roots:, items:)
      end

      def of(dirs, digests, roots:, items: ITEMS)
        digests = digests.compact
        atlas = Atlas.merge(digests, dirs:, roots:, unreadable: 0)
        places = atlas[:places]
        screen_of = screens(places)
        furthest = digests.max_by { |digest| [digest[:held].size, digest[:run]] }
        {
          runs: digests.size, last_run: atlas[:last_run], dollars: atlas[:totals][:dollars],
          places: places.map { |place| place_view(place, places, screen_of) },
          gains: gains(places, screen_of),
          items: catalogue(items),
          held: furthest ? furthest[:held] : [],
          furthest: furthest&.dig(:run),
          next: furthest ? next_leads(furthest, digests, screen_of) : []
        }
      end

      def date(run) = run.to_s.match(/\A(\d{4})(\d{2})(\d{2})-/)&.captures&.join('-')

      def screens(places) = places.to_h { |place| [place[:label], place[:grid] ? place[:label] : place[:opens_from].first] }

      def place_view(place, places, screen_of)
        deaths = places.select { |other| screen_of[other[:label]] == place[:label] }.sum { |other| other[:deaths] }
        { label: place[:label], key: place[:key], room: place[:room], map: place[:map], grid: place[:grid],
          first: place[:first].merge(date: date(place[:first][:run])), visits: place[:visits], runs: place[:runs], deaths: place[:grid] ? deaths : place[:deaths],
          exits: place[:exits].reject { |exit| exit[:way] == 'door' }.map { |exit| [exit[:to], exit[:count]] },
          opens_from: place[:opens_from], heat: place[:heat], screen: place[:screen], seen: place[:seen].transform_values(&:size) }
      end

      def gains(places, screen_of)
        places.flat_map { |place| place[:items].map { |item| item.merge(place: place[:label], screen: screen_of[place[:label]]) } }
              .sort_by { |item| [item[:run], item[:frame]] }.uniq { |item| item[:item] || item[:name] }
              .map { |item| item.merge(date: date(item[:run])) }
      end

      def catalogue(path)
        JSON.parse(File.read(path)).map { |item| { id: item['id'], name: item['name'], confidence: item['confidence'] } }
      rescue SystemCallError, JSON::ParserError
        []
      end

      # The furthest run comes first, so a lead's newest verdict wins over an ancestor's.
      def next_leads(furthest, digests, screen_of)
        by_run = digests.to_h { |digest| [digest[:run], digest] }
        chain = []
        digest = furthest
        while digest && !chain.include?(digest)
          chain << digest
          digest = by_run[digest[:parent]]
        end
        chain.flat_map { |member| member[:leads].map { |lead| lead.merge(run: member[:run]) } }
             .uniq { |lead| lead[:key] }.select { |lead| lead[:status] == 'open' }
             .sort_by.with_index { |lead, index| [IMPORTANCE.index(lead[:importance].to_s) || IMPORTANCE.size, index] }
             .map { |lead| { quote: lead[:quote], claim: lead[:claim], importance: lead[:importance], place: lead[:place], screen: screen_of[lead[:place]] || lead[:place], run: lead[:run], date: date(lead[:run]) } }
      end
    end
  end
end
