require 'json'
require 'koholint'
require 'koholint/items'
require 'koholint/place_kinds'
require 'koholint/summary'
require 'koholint/trace'

module Scoreboard
  # What a run achieved and what it cost, read from its trace and manifest only: no emulator, no model.
  module Measure
    PLAY_MODE = 11
    ONE_HEART = 8
    STALL_FRAMES = 4000
    # First match wins. A 'base' family is a plain engine mechanic; a 'rule' family is a harness rule added by a flow.
    FAMILIES = [
      ['base', 'dialogue advance', '\\Aautomatic dialogue advance'], ['base', 'locked wait', '\\Alocked:'], ['base', 'boot script', '\\Aboot script'],
      ['base', 'game over continue', '\\Agame over: save and continue'], ['base', 'revisit npc', '\\Arevisit npc'], ['base', 'engage sign', '\\Aengage sign'],
      ['rule', 'heal give-back (109)', '\\Athe heal is over'], ['rule', 'heal detour (101/105)', 'crosses enemies: heal in|largest hit measured|heal in \\d+-\\d+ first'],
      ['rule', 'loop break (100/101)', '\\Aloop in'], ['rule', 'loop re-offer (101)', '\\Athe loop is cut'], ['rule', 'souvenir (102)', 'souvenir-'],
      ['rule', 'offspring fight (110)', 'not identified, taken for an enemy'], ['rule', 'probe strike (110)', 'strike the unidentified'],
      ['rule', 'retreat (100)', '\\(retreat by the'], ['rule', 'guarded place (101)', 'is guarded \\('], ['rule', 'hostile no standing (100)', 'no standing next to a hostile'],
      ['rule', 'zero cap (zero_watch)', 'in at most one frame|walking no cell'], ['rule', 'heart pickup / disengage (94)', 'pick up the heart|disengage at'],
      ['rule', 'fight on sight (90/100)', 'autopilot: fight type|keep fighting'], ['rule', 'try never-tried / still entity', 'never-tried (entity|object)|walk onto the still entity'],
      ['rule', 'danger / held back (106/108)', 'dangerous|would take|held back|held_back'],
      ['base', 'autopilot explore chain', '\\Aautopilot: (explore again|follow the objective target|the last explore chain|step up through)'],
      ['rule', 'harness override of model', "replaces the model's"]
    ].map { |kind, name, pattern| [kind, name, Regexp.new(pattern)] }.freeze

    module_function

    def family(justification, agent)
      return ['model', 'model'] if agent == 'claude' && !justification.include?("replaces the model's")

      FAMILIES.each { |kind, name, pattern| return [kind, name] if pattern.match?(justification) }
      ['rule', 'other harness text']
    end

    def rule_names = FAMILIES.select { |kind, _, _| kind == 'rule' }.map { |_, name, _| name } << 'other harness text'

    def place_of(event)
      state = event['state']
      return event['place'] if event['type'] == 'place_card' && event['place'].is_a?(Array)

      [state['room_id'], state['map_id']] if event['type'] == 'perception' && state.is_a?(Hash) && state['game_mode'] == PLAY_MODE
    end

    def read_json(path)
      JSON.parse(File.read(path))
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def fork_frame(manifest) = manifest['parent'].is_a?(Hash) ? manifest['parent']['frame'].to_i : 0

    def death?(event) = event['type'] == 'notable' && event['kind'] == 'death'

    # The progress vector counts the whole run, inherited prefix included; cost, deaths, stalls and rules count the run's own segment.
    def run(dir)
      manifest = read_json(File.join(dir, 'manifest.json'))
      parent = manifest['parent'].is_a?(Hash) ? manifest['parent'] : {}
      start = fork_frame(manifest)
      events = Koholint::Trace.read(File.join(dir, 'trace.jsonl'))
      own = events.select { |event| event['frame'].to_i >= start }
      frames = [(events.map { |event| event['frame'].to_i }.max || 0) - start, 0].max
      decisions = own.select { |event| event['type'] == 'decision' }
      calls = decisions.select { |event| event['agent'] == 'claude' }
      usd = decisions.sum { |event| event['cost_usd'].to_f }
      deaths = own.count { |event| death?(event) }
      per = ->(count) { frames.positive? ? (1000.0 * count / frames).round(3) : nil }
      new_frames = new_place_frames(events, start)
      progress = progress(events, read_json(File.join(dir, 'summary.json')))
      {
        run: File.basename(dir), tag: manifest['tag'], flow: manifest['flow_version'], harness_sha: manifest['harness_sha'].to_s[0, 8],
        harness_dirty: manifest['harness_dirty'] || false, parent: parent.slice('id', 'frame'), frames:, progress:,
        items_gained: own.select { |event| event['type'] == 'item_gained' }.map { |event| event['name'] },
        cost: { usd: usd.round(4), calls: calls.size, calls_per_1000f: per.(calls.size),
                calls_at_one_heart: calls.count { |event| event.dig('input', 'hp').to_i <= ONE_HEART } },
        deaths:, deaths_per_1000f: per.(deaths), new_places: new_frames.size, new_places_per_usd: usd.positive? ? (new_frames.size / usd).round(3) : nil,
        stalls: stalls(start, new_frames, start + frames), rules: rules(decisions)
      }
    end

    def new_place_frames(events, start)
      before = events.filter_map { |event| place_of(event) if event['frame'].to_i < start }.to_set
      seen = before.dup
      events.each_with_object([]) do |event, frames|
        place = place_of(event)
        frames << event['frame'].to_i if place && event['frame'].to_i >= start && seen.add?(place)
      end
    end

    def progress(events, summary)
      places = events.filter_map { |event| place_of(event) }.uniq
      state = events.reverse_each.find { |event| event['type'] == 'perception' && event['state'].is_a?(Hash) }&.fetch('state')
      dungeons = Koholint::PlaceKinds.catalogue.select { |_, entry| entry['kind'] == 'dungeon' }.keys
      { instruments: summary['instruments'],
        dungeons: dungeons.empty? ? nil : places.map(&:last).uniq.count { |map| dungeons.include?(map) },
        dungeon_keys: dungeon_keys(events, places, dungeons),
        key_items: state ? Koholint::Items.held_ids(state).sort.map { |id| { id:, name: Koholint::Items.name(id, state) } } : [],
        places_seen: places.size, highest_milestone: Koholint::Summary.highest_milestone(events) }
    end

    # Per dungeon entered, whether a key item (a data/items.json entry named like a key) was gained while there. Optional: nil while no dungeon
    # map is catalogued, and a dungeon without a key reads false, never required.
    def dungeon_keys(events, places, dungeons)
      return nil if dungeons.empty?

      keys = Koholint::Items.catalogue.select { |_, item| Koholint::Items.names(item).any? { |name| name.match?(/\b(key|clé|cle)\b/) } }.keys
      gained = events.select { |event| event['type'] == 'item_gained' && keys.include?(event['item'].to_i) && event['place'].is_a?(Array) }.map { |event| event['place'].last }
      places.map(&:last).uniq.select { |map| dungeons.include?(map) }.sort.to_h { |map| [map.to_s, gained.include?(map)] }
    end

    def stalls(start, new_frames, last)
      spans = [start, *new_frames, last].each_cons(2).map { |from, to| to - from }
      { count: spans.count { |span| span >= STALL_FRAMES }, longest_frames: spans.max || 0 }
    end

    def rules(decisions)
      decisions.each_with_object(Hash.new(0)) do |event, count|
        kind, name = family(event['justification'].to_s, event['agent'])
        count[name] += 1 if kind == 'rule'
      end.sort_by { |name, n| [-n, name] }.to_h
    end

    def table(results)
      cols = %w[run flow frames usd calls calls/1000f deaths/1000f new_places new/usd places stalls milestone key_items]
      rows = results.map do |r|
        [r[:run], r[:flow], r[:frames], r[:cost][:usd], r[:cost][:calls], r[:cost][:calls_per_1000f], r[:deaths_per_1000f], r[:new_places], r[:new_places_per_usd],
         r[:progress][:places_seen], r[:stalls][:count], r[:progress][:highest_milestone], r[:progress][:key_items].map { |item| item[:name] }.join(', ')]
      end
      ["| #{cols.join(' | ')} |", "|#{'---|' * cols.size}", *rows.map { |row| "| #{row.join(' | ')} |" }].join("\n")
    end
  end
end
