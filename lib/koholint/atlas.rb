require 'json'
require 'zlib'
require 'koholint'
require 'koholint/archive'
require 'koholint/dialogues'
require 'koholint/leads'
require 'koholint/place_card'
require 'koholint/place_kinds'
require 'koholint/summary'
require 'koholint/trace'

module Koholint
  # What every run under some roots observed, merged per place; a fork counts only its own events, from its fork frame on.
  module Atlas
    TRACE = 'trace.jsonl'.freeze
    OUT = 'tmp/atlas.json'.freeze
    COLUMNS = 'ABCDEFGHIJKLMNOP'.freeze
    WAYS = { 1 => 'right', -1 => 'left', 16 => 'down', -16 => 'up' }.freeze
    ENTITIES = %w[people enemies unknown creatures].freeze
    NAME_WORD = 4
    STATUSES = %w[open refuted tested].freeze

    module_function

    def label(place)
      room, map = place
      PlaceKinds.grid?(place) ? "#{COLUMNS[room % 16]}#{(room / 16) + 1}" : "#{room}/#{map}"
    end

    def key(place) = place.join('-')

    def build(roots, cache: {})
      dirs = roots.flat_map { |root| Archive.runs(root) }.uniq { |dir| File.basename(dir) }
      ids = dirs.to_h { |dir| [File.basename(dir), dir] }
      digests = dirs.map { |dir| cached(dir, ids, cache) }
      merge(digests.compact, dirs:, roots:, unreadable: digests.count(&:nil?))
    end

    def cached(dir, ids, cache)
      trace = Trace.located(File.join(dir, TRACE))
      parent = Summary.read_json(File.join(dir, 'manifest.json'))['parent']
      fork = parent.is_a?(Hash) ? parent['frame'].to_i : 0
      since = parent.is_a?(Hash) && ids.key?(parent['id']) ? fork : 0
      stamp = [since, fork, File.mtime(trace).to_f, File.size(trace)]
      found = cache[dir]
      return found[:digest] if found && found[:stamp] == stamp

      cache[dir] = { stamp:, digest: digest(dir, since:, fork:) }
      cache[dir][:digest]
    rescue Error, SystemCallError, Zlib::Error, JSON::ParserError
      nil
    end

    def blank = { visits: 0, deaths: 0, texts: {}, names: [], seen: {}, signs: 0, doors: 0, tried: {}, exits: {}, opens_from: [], items: [], puzzles: [] }

    # Places count from `since` (the fork frame when the parent is read, else 0); cost, calls and frames always from the fork frame.
    def digest(dir, since: 0, fork: since)
      events = Trace.read(File.join(dir, TRACE))
      run = File.basename(dir)
      places = {}
      at = ->(place) { places[place] ||= blank }
      dialogues = Dialogues.from_events(events).select { |talk| talk[:place].is_a?(Array) }
      dialogues.each do |talk|
        next if talk[:frame].to_i < since

        texts = at.(talk[:place])[:texts]
        texts[Dialogues.key(talk[:text])] ||= { text: talk[:text], speaker: talk[:speaker], run:, frame: talk[:frame] }.compact
      end
      PlaceCard.tries(events.select { |event| event['frame'].to_i >= since }).each do |(place, type), tried|
        at.(place)[:tried][type] = tried.slice(:tries, :answered)
      end
      current = nil
      respawn = false
      run_frames = 0
      dollars = 0.0
      calls = 0
      events.each do |event|
        frame = event['frame'].to_i
        own = frame >= since
        case event['type']
        when 'perception'
          place = Summary.perceived_place(event)
          next if place.nil? || place == current

          if own
            entry = at.(place)
            entry[:visits] += 1
            entry[:first] ||= frame
            way = current && !respawn && way(current, place)
            if way
              exits = at.(current)[:exits]
              exits[[way, label(place)]] = exits.fetch([way, label(place)], 0) + 1
            end
            entry[:opens_from] |= [label(current)] if way == 'door' && PlaceKinds.grid?(current)
          end
          respawn = false
          current = place
        when 'decision'
          next if frame < fork

          dollars += event['cost_usd'].to_f
          calls += 1 if event['agent'] == 'claude'
        when 'place_card'
          next unless own && event['place'].is_a?(Array)

          entry = at.(event['place'])
          ENTITIES.each { |kind| entry[:seen][kind] = Array(entry[:seen][kind]) | Array(event[kind]).filter_map { |thing| thing['type'] if thing.is_a?(Hash) } }
          entry[:signs] = [entry[:signs], Array(event['signs']).size].max
          entry[:doors] = [entry[:doors], Array(event['doors']).size].max
        when 'notable'
          next unless event['kind'] == 'death'

          respawn = true
          at.(current)[:deaths] += 1 if own && current
        when 'place_name'
          next unless own && event['place'].is_a?(Array)

          source = source_text(event['name'], dialogues.select { |talk| talk[:place] == event['place'] && talk[:frame].to_i <= frame })
          at.(event['place'])[:names] << { name: event['name'], run:, frame:, source: source && { text: source[:text], frame: source[:frame] } }
        when 'item_gained'
          at.(event['place'])[:items] << { name: event['name'], run:, frame: } if own && event['place'].is_a?(Array)
        when 'puzzle'
          next unless own && event['place'].is_a?(Array)

          at.(event['place'])[:puzzles] << { id: event['id'], kind: event['kind'], way: event['way'], expected: event.dig('expected', 'to')&.then { |to| label(to) },
                                             observed: event.dig('observed', 'to')&.then { |to| label(to) }, run:, frame: }
        end
        run_frames = [run_frames, frame - fork].max if frame >= fork
      end
      { run:, flow: Summary.read_json(File.join(dir, 'manifest.json'))['flow_version'], frames: run_frames, dollars:, calls:, places:, leads: leads(events, since:, run:) }
    end

    # Each lead the run holds, keyed by its quote: read here when its event is from `since` on; status and attempts from the whole run.
    def leads(events, since:, run:)
      read = events.select { |event| event['type'] == 'lead' }.to_h { |event| [event['id'], event['frame'].to_i] }
      Leads.from_events(events).with_status.filter_map do |lead|
        quote = lead[:quote].to_s
        next if quote.strip.empty?

        frame = read[lead[:id]]
        attempts = lead[:evidence].select { |attempt| attempt[:frame].to_i >= since }
        { key: Dialogues.key(quote), quote:, claim: lead[:claim], importance: lead[:importance], place: lead[:place].is_a?(Array) ? label(lead[:place]) : nil,
          status: lead[:status], read: frame && frame >= since ? { run:, frame: } : nil,
          tried: attempts.size, achieved: attempts.count { |attempt| attempt[:outcome] == 'achieved' } }
      end
    end

    # Overworld screens that are not neighbours (a warp, or a row wrap from P to A) are not a way.
    def way(from, to)
      return 'door' unless PlaceKinds.grid?(from) && PlaceKinds.grid?(to)

      delta = to[0] - from[0]
      WAYS[delta] unless delta.abs == 1 && to[0] / 16 != from[0] / 16
    end

    def order(types) = types.sort_by { |type| type.is_a?(Integer) ? [0, type, ''] : [1, 0, type.to_s] }

    def source_text(name, talks)
      words = fold(name).scan(/\p{L}+/).select { |word| word.length >= NAME_WORD }
      talks.find { |talk| words.any? { |word| fold(talk[:text]).include?(word) } } unless words.empty?
    end

    def fold(text) = text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase

    def merge(digests, dirs:, roots:, unreadable:)
      places = {}
      digests.sort_by { |digest| digest[:run] }.each do |digest|
        digest[:places].each do |place, found|
          entry = places[place] ||= blank.merge(key: key(place), room: place[0], map: place[1], label: label(place), kind: PlaceKinds.kind(place),
                                                grid: PlaceKinds.grid?(place), first: nil, runs: 0)
          entry[:first] ||= { run: digest[:run], frame: found[:first] } if found[:first]
          entry[:visits] += found[:visits]
          entry[:runs] += 1 if found[:visits].positive?
          entry[:deaths] += found[:deaths]
          found[:texts].each { |text_key, text| entry[:texts][text_key] ||= text }
          entry[:names].concat(found[:names])
          found[:seen].each { |kind, types| entry[:seen][kind] = Array(entry[:seen][kind]) | types }
          entry[:signs] = [entry[:signs], found[:signs]].max
          entry[:doors] = [entry[:doors], found[:doors]].max
          found[:tried].each do |type, tried|
            sum = entry[:tried][type] ||= { tries: 0, answered: 0 }
            sum[:tries] += tried[:tries]
            sum[:answered] += tried[:answered]
          end
          found[:exits].each { |exit, count| entry[:exits][exit] = entry[:exits].fetch(exit, 0) + count }
          entry[:opens_from] |= found[:opens_from]
          entry[:items].concat(found[:items])
          entry[:puzzles].concat(found[:puzzles])
        end
      end
      shots = dirs.reverse
      list = places.values.select { |entry| entry[:first] }.sort_by { |entry| [entry[:map], entry[:room]] }.map do |entry|
        named = entry[:names].select { |name| name[:source] }.uniq { |name| name[:name] }
        seen = entry[:seen].transform_values { |types| order(types) }
        hostile = seen.fetch('enemies', []) | seen.fetch('creatures', [])
        entry.merge(texts: entry[:texts].values, names: named, names_withheld: entry[:names].map { |name| name[:name] }.uniq.size - named.size, seen:,
                    tried: order(entry[:tried].keys).map { |type| { type:, **entry[:tried][type] } },
                    untried: order(seen.fetch('people', []) - entry[:tried].keys),
                    unknown_untried: order(seen.fetch('unknown', []) - hostile - entry[:tried].keys),
                    exits: entry[:exits].map { |(way, to), count| { way:, to:, count: } }.sort_by { |exit| [exit[:way], -exit[:count], exit[:to]] },
                    puzzles: entry[:puzzles].uniq { |puzzle| puzzle[:id] },
                    screen: shots.find { |dir| File.file?(File.join(dir, 'screens', "#{entry[:key]}.png")) }&.then { |dir| File.basename(dir) })
      end
      texts = list.flat_map { |entry| entry[:texts].map { |text| Dialogues.key(text[:text]) } }.uniq
      leads = merge_leads(digests)
      items = list.flat_map { |entry| entry[:items] }
      {
        roots:, runs: digests.size, unreadable:, last_run: digests.map { |digest| digest[:run] }.max,
        totals: { frames: digests.sum { |digest| digest[:frames] }, dollars: digests.sum { |digest| digest[:dollars] }.round(2),
                  calls: digests.sum { |digest| digest[:calls] }, runs_with_calls: digests.count { |digest| digest[:calls].positive? },
                  overworld: list.count { |entry| entry[:grid] }, interiors: list.count { |entry| !entry[:grid] }, texts: texts.size,
                  deaths: list.sum { |entry| entry[:deaths] }, items: items.group_by { |item| item[:name] }.transform_values(&:size),
                  puzzles: list.sum { |entry| entry[:puzzles].size }, names_withheld: list.sum { |entry| entry[:names_withheld] } },
        places: list,
        leads:,
        flows: flows(digests, list, leads)
      }
    end

    def merge_leads(digests)
      found = {}
      digests.sort_by { |digest| digest[:run] }.each do |digest|
        digest[:leads].each do |lead|
          entry = found[lead[:key]] ||= lead.except(:key, :read, :tried, :achieved).merge(first: nil, runs: 0, tried: 0, achieved: 0)
          entry[:first] ||= lead[:read]
          entry[:runs] += 1 if lead[:read]
          entry[:tried] += lead[:tried]
          entry[:achieved] += lead[:achieved]
          entry[:status] = lead[:status] if STATUSES.index(lead[:status]).to_i > STATUSES.index(entry[:status]).to_i
        end
      end
      found.values.select { |lead| lead[:first] }
    end

    # Per flow version: the runs, their own frames, cost and calls, and what they reached first in the runs read.
    def flows(digests, places, leads)
      flow_of = digests.to_h { |digest| [digest[:run], digest[:flow].to_s] }
      rows = digests.group_by { |digest| digest[:flow].to_s }.to_h do |flow, group|
        [flow, { flow:, runs: group.size, frames: group.sum { |digest| digest[:frames] }, dollars: group.sum { |digest| digest[:dollars] }.round(2),
                 calls: group.sum { |digest| digest[:calls] }, screens: [], interiors: [], texts: 0, items: [], leads: 0 }]
      end
      places.each do |place|
        rows[flow_of[place[:first][:run]]][place[:grid] ? :screens : :interiors] << place[:label]
        place[:texts].each { |text| rows[flow_of[text[:run]]][:texts] += 1 if flow_of[text[:run]] }
      end
      places.flat_map { |place| place[:items] }.sort_by { |item| [item[:run], item[:frame]] }.uniq { |item| item[:name] }.each do |item|
        rows[flow_of[item[:run]]][:items] << item[:name]
      end
      leads.each { |lead| rows[flow_of[lead[:first][:run]]][:leads] += 1 }
      rows.values.sort_by { |row| [row[:flow][/\d+/].to_i, row[:flow]] }
    end
  end
end
