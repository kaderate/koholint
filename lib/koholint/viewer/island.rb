require 'json'
require 'set'
require 'koholint'
require 'koholint/atlas'
require 'koholint/place_kinds'
require 'koholint/viewer/story'

module Koholint
  module Viewer
    module Island
      ITEMS = File.join(Atlas::DATA, 'items.json')
      CHECKPOINTS = File.join(Atlas::DATA, 'checkpoints.json')
      IMPORTANCE = %w[high normal low tip].freeze
      RECENT = 12
      PERSON_TEXTS = 6
      SAME_TEXT = 40

      module_function

      def build(roots, cache: {}, items: ITEMS, checkpoints: CHECKPOINTS)
        dirs, digests = Atlas.read(roots, cache:)
        of(dirs, digests, roots:, items:, checkpoints:)
      end

      def of(dirs, digests, roots:, items: ITEMS, checkpoints: CHECKPOINTS)
        digests = digests.compact
        atlas = Atlas.merge(digests, dirs:, roots:, unreadable: 0)
        places = atlas[:places]
        screen_of = screens(places)
        recent = recent_runs(digests)
        furthest = digests.max_by { |digest| [digest[:held].size, digest[:run]] }
        {
          runs: digests.size, last_run: atlas[:last_run], dollars: atlas[:totals][:dollars],
          places: places.map { |place| place_view(place, places, screen_of, recent) },
          gains: gains(places, screen_of),
          items: read_json(items).map { |item| { id: item['id'], name: item['name'], confidence: item['confidence'] } },
          held: furthest ? furthest[:held] : [],
          furthest: furthest&.dig(:run),
          next: furthest ? next_leads(furthest, digests, screen_of) : [],
          leads: atlas[:leads].map { |lead| lead_view(lead, screen_of) },
          people: people(places, screen_of),
          metro: metro(digests, places, furthest, read_json(checkpoints))
        }
      end

      def date(run) = run.to_s.match(/\A(\d{4})(\d{2})(\d{2})-/)&.captures&.join('-')

      def screens(places) = places.to_h { |place| [place[:label], place[:grid] ? place[:label] : place[:opens_from].first] }

      def read_json(path)
        JSON.parse(File.read(path))
      rescue SystemCallError, JSON::ParserError
        []
      end

      def recent_runs(digests)
        digests.sort_by { |digest| digest[:run] }.each_with_object(Hash.new { |hash, label| hash[label] = [] }) do |digest, out|
          digest[:places].each { |place, found| out[Atlas.label(place)] << digest[:run] if found[:visits].positive? }
        end
      end

      def place_view(place, places, screen_of, recent)
        deaths = places.select { |other| screen_of[other[:label]] == place[:label] }.sum { |other| other[:deaths] }
        { label: place[:label], key: place[:key], room: place[:room], map: place[:map], grid: place[:grid],
          first: place[:first].merge(date: date(place[:first][:run])), visits: place[:visits], runs: place[:runs], deaths: place[:grid] ? deaths : place[:deaths],
          exits: place[:exits].reject { |exit| exit[:way] == 'door' }.map { |exit| [exit[:to], exit[:count]] },
          opens_from: place[:opens_from], heat: place[:heat], screen: place[:screen], seen: place[:seen].transform_values(&:size),
          recent: recent[place[:label]].last(RECENT).reverse }
      end

      def gains(places, screen_of)
        places.flat_map { |place| place[:items].map { |item| item.merge(place: place[:label], screen: screen_of[place[:label]]) } }
              .sort_by { |item| [item[:run], item[:frame]] }.uniq { |item| item[:item] || item[:name] }
              .map { |item| item.merge(date: date(item[:run])) }
      end

      def lead_view(lead, screen_of)
        { quote: lead[:quote], claim: lead[:claim], status: lead[:status], importance: lead[:importance], place: lead[:place],
          screen: screen_of[lead[:place]] || lead[:place], runs: lead[:runs], tried: lead[:tried], achieved: lead[:achieved],
          run: lead.dig(:first, :run), date: date(lead.dig(:first, :run)) }
      end

      # A person without a name is the voice of the screen it was heard on; one text read in several runs, its OCR varying, counts once.
      def people(places, screen_of)
        places.flat_map { |place| place[:texts].map { |text| text.merge(place: place[:label]) } }.sort_by { |text| [text[:run], text[:frame]] }
              .group_by { |text| text[:speaker] || "@#{screen_of[text[:place]] || text[:place]}" }
              .map do |key, texts|
                read = texts.group_by { |text| text[:run] }.flat_map { |_, run| Story.merged(run) }
                talks = read.each_with_index.sort_by { |talk, index| [-talk[:text].size, index] }.uniq { |talk, _| Dialogues.compact(talk[:text])[0, SAME_TEXT] }
                            .sort_by(&:last).map(&:first)
                { name: key.start_with?('@') ? nil : key, screen: screen_of[texts.first[:place]] || texts.first[:place], count: talks.size,
                  texts: talks.last(PERSON_TEXTS).reverse.map { |talk| talk.slice(:text, :place, :frame) } }
              end
              .sort_by { |person| [-person[:count], person[:name].to_s] }
      end

      def lineage(digest, by_run)
        chain = []
        while digest && !chain.include?(digest)
          chain << digest
          digest = by_run[digest[:parent]]
        end
        chain
      end

      # The furthest run comes first, so a lead's newest verdict wins over an ancestor's.
      def next_leads(furthest, digests, screen_of)
        by_run = digests.to_h { |digest| [digest[:run], digest] }
        lineage(furthest, by_run).flat_map { |member| member[:leads].map { |lead| lead.merge(run: member[:run]) } }
                                 .uniq { |lead| lead[:key] }.select { |lead| lead[:status] == 'open' }
                                 .sort_by.with_index { |lead, index| [IMPORTANCE.index(lead[:importance].to_s) || IMPORTANCE.size, index] }
                                 .map { |lead| { quote: lead[:quote], claim: lead[:claim], importance: lead[:importance], place: lead[:place], screen: screen_of[lead[:place]] || lead[:place], run: lead[:run], date: date(lead[:run]) } }
      end

      # The lines worth drawing: the furthest lineage, and every lineage that reached a checkpoint, a first gain or a new screen;
      # the other forks of a drawn run are only counted.
      def metro(digests, places, furthest, checkpoints)
        by_run = digests.to_h { |digest| [digest[:run], digest] }
        chain = furthest ? lineage(furthest, by_run).map { |digest| digest[:run] } : []
        stations = checkpoints.select { |checkpoint| by_run.key?(checkpoint['run']) }.group_by { |checkpoint| checkpoint['run'] }
        firsts = places.flat_map { |place| place[:items] }.sort_by { |item| [item[:run], item[:frame]] }.uniq { |item| item[:item] || item[:name] }.group_by { |item| item[:run] }
        screens = places.select { |place| place[:grid] }.group_by { |place| place[:first][:run] }
        keep = (chain + stations.keys + firsts.keys + screens.keys).flat_map { |run| lineage(by_run[run], by_run).map { |digest| digest[:run] } }.to_set
        kids = digests.group_by { |digest| digest[:parent] }
        keep.sort.map do |run|
          digest = by_run[run]
          { run:, parent: by_run.key?(digest[:parent]) ? digest[:parent] : nil, fork: digest[:fork], end: digest[:fork] + digest[:frames], main: chain.include?(run),
            flow: digest[:flow], date: date(run), dollars: digest[:dollars].round(2), cum: lineage(digest, by_run).sum { |member| member[:dollars] }.round(2),
            screens: screens.fetch(run, []).size, held: digest[:held], deaths: digest[:places].sum { |_, found| found[:deaths] },
            gains: firsts.fetch(run, []).map { |item| [item[:item], item[:frame]] },
            checkpoints: stations.fetch(run, []).map { |checkpoint| { name: checkpoint['name'], frame: checkpoint['frame'] } },
            hidden: kids.fetch(run, []).count { |kid| !keep.include?(kid[:run]) } }
        end
      end
    end
  end
end
