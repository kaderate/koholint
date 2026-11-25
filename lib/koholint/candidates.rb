require 'koholint/entities'
require 'koholint/geometry'
require 'koholint/items'
require 'koholint/leads'
require 'koholint/place_card'
require 'koholint/place_kinds'
require 'koholint/talk_log'

module Koholint
  module Candidates
    PER_KIND = 4
    HERE_WORTH = %i[never new changed repeat].freeze
    AWAY_WORTH = %i[never new].freeze

    module_function

    def build(place:, grid:, explore_log:, talk_log:, leads:, cards: {}, entities: [], signs: [], stamp: nil, link: nil, souvenirs: [], item_names: {})
      hops = explore_log.hops(place)
      named = ->(where) { leads.name_of(where) }
      needs = needs(place, hops, leads, talk_log, named, stamp)
      asked = needs.map { |need| need[:target].values_at(:place, :type) }
      people = needs.select { |need| need[:target][:place] == place } + people_here(place, entities, talk_log, stamp).reject { |person| asked.include?([place, person[:target][:type]]) }
      back, fresh = exits(place, grid, explore_log, named).partition { |exit| explore_log.side_left?(place, exit.dig(:target, :direction)) }
      leaving = puzzles(place, hops, explore_log, leads, named) + fresh + doors(place, signs, explore_log, link) + back + places(place, hops, explore_log, named) +
                needs.reject { |need| need[:target][:place] == place } +
                people_away(place, hops, cards, talk_log, named, stamp, explore_log).reject { |person| asked.include?(person[:target].values_at(:place, :type)) } +
                signs_away(place, hops, cards, talk_log, named) + chests_away(place, hops, cards, named) +
                lead_places(place, hops, leads, named)
      things = unidentified(place, grid, entities, talk_log, link)
      remembered = souvenirs(place, hops, souvenirs, item_names, talk_log, named, stamp)
      people, things, leaving = remember(remembered, people, things, leaving, place)
      people + signs_here(place, signs, talk_log) + chests_here(place, signs) + things + warn(leaving, people)
    end

    def remember(remembered, people, things, leaving, place)
      same = ->(candidate, souvenir) { candidate[:target][:type] && candidate[:target].values_at(:place, :type) == souvenir[:target].values_at(:place, :type) }
      swap = ->(list) { list.map { |candidate| remembered.find { |souvenir| same.(candidate, souvenir) } || candidate }.uniq { |candidate| candidate[:id] } }
      people, things, leaving = [people, things, leaving].map(&swap)
      things -= people
      here, away = (remembered - people - things - leaving).partition { |souvenir| souvenir[:target][:place] == place }
      [people + here, things, leaving + away]
    end

    def souvenirs(place, hops, souvenirs, item_names, talk_log, named, stamp)
      held = Array(Array(stamp)[1])
      souvenirs.filter_map do |entry|
        where = entry['place']
        type = entry['entity']
        next unless where == place || hops.key?(where)

        key = Dialogues.key(entry['text'])
        next if talk_log.talks_with(where, type).any? { |talk| talk[:key] == key }

        words = Dialogues.words(entry['text'])
        item, name = held.lazy.flat_map { |id| [item_names[id], *Items.pickup_text_names[id]].compact.map { |item_words| [id, item_words] } }.find do |id, item_words|
          TalkLog.names?(words, item_words) && !talk_log.talked_holding?(where, type, id) && entry['seen'].any? { |sighting| !sighting['held'].include?(id) }
        end
        next unless item

        who = talk_log.name_of(where, type) || "person (type #{type})"
        thing = name.join(' ')
        at = where == place ? "at (#{Array(entry['cell']).join(',')})" : "in #{describe(where, named)}, #{moves(hops[where])}"
        { id: "souvenir-#{where.join('-')}-t#{type}", who:,
          label: "talk to #{who} #{at}, holding the #{thing}: a souvenir of another playthrough, never heard in this one: « #{Dialogues.clean(entry['text'], 200)} »",
          title: "Bring the #{thing} to #{who}"[0, 80], predicate: { kind: 'reach_place', place: where },
          target: { kind: 'person', place: where, type:, cell: entry['cell'], try: true, item:, name: thing } }
      end.uniq { |candidate| candidate[:id] }
    end

    def warn(leaving, people)
      return leaving if people.empty?

      who = people.map { |person| person[:who] }.join(', ')
      leaving.map { |candidate| candidate.merge(label: "#{candidate[:label]} (leaves unexhausted people here: #{who})", leaves_unexhausted: true) }
    end

    def lines(candidates) = candidates.map { |candidate| "- #{candidate[:id]}: #{candidate[:label]}" }

    def offered(candidates, picked = nil)
      candidates.map { |c| { id: c[:id], label: c[:label], leaves_unexhausted: c[:leaves_unexhausted] == true, picked: c[:id] == picked&.dig(:id) } }
    end

    def find(candidates, id) = candidates.find { |candidate| candidate[:id] == id.to_s.strip }

    # A side known only as the way back, assumed and never crossed, says so: explore takes it after the place's other work.
    def exits(place, grid, explore_log, named = ->(_) {})
      PlaceCard.exits(grid).filter_map do |side, cells|
        next if explore_log.side_crossed?(place, side) || cells.all? { |cell| explore_log.tried?(place, cell, side) }

        to = explore_log.ways(place)[side.to_sym] if explore_log.side_left?(place, side)
        back = to ? ", the way back to #{describe(to, named)} you came in by (assumed, never crossed)" : ''
        { id: "exit-#{side}", label: "leave by the #{side} side (open border cells #{cells.map { |r, c| "(#{r},#{c})" }.join(' ')})#{back}",
          title: "Leave by the #{side} side", predicate: { kind: 'leave_place', place: }, target: { kind: 'exit', place:, direction: side.to_s } }
      end
    end

    def doors(place, signs, explore_log, link = nil)
      came_out = ->(cell) { link && [cell, [cell[0] + 1, cell[1]]].include?(link) }
      signs.select { |object| object[:kind].to_s == 'door' && !explore_log.door_tried?(place, object[:cell]) && !came_out.(object[:cell]) }.map do |door|
        row, col = door[:cell]
        { id: "door-#{row}-#{col}", label: "enter the door at (#{row},#{col}), never entered", title: "Enter the door at (#{row},#{col})",
          predicate: { kind: 'leave_place', place: }, target: { kind: 'door', place:, cell: [row, col] } }
      end
    end

    def people_here(place, entities, talk_log, stamp)
      entities.select { |entity| entity[:kind].to_s == 'npc' && entity[:cell] }.uniq { |entity| entity[:type] }.filter_map do |entity|
        status = talk_log.status(place:, entity: entity[:type], stamp:)
        next unless HERE_WORTH.include?(status)

        row, col = entity[:cell]
        who = talk_log.name_of(place, entity[:type]) || "person (type #{entity[:type]})"
        { id: "person-t#{entity[:type]}", who:, label: "talk to #{who} at (#{row},#{col}), #{status_text(status)}", title: "Talk to #{who}"[0, 80],
          predicate: { kind: 'new_text' }, target: { kind: 'person', place:, type: entity[:type], cell: [row, col] } }
      end
    end

    def signs_here(place, signs, talk_log)
      signs.select { |object| object[:kind].to_s == 'sign' && talk_log.sign_status(place:, cell: object[:cell]) != :read }.map do |sign|
        row, col = sign[:cell]
        { id: "sign-#{row}-#{col}", label: "read the sign at (#{row},#{col}), not read yet", title: "Read the sign at (#{row},#{col})",
          predicate: { kind: 'new_text' }, target: { kind: 'sign', place:, cell: [row, col] } }
      end
    end

    # A closed chest is offered only while a route reaches the cell below it (reachable, set by the policy from the current grid).
    def chests_here(place, objects)
      objects.select { |object| object[:kind].to_s == 'chest' && !object[:open] && object[:reachable] == true }.map do |chest|
        row, col = chest[:cell]
        { id: "chest-#{row}-#{col}", label: "open the chest at (#{row},#{col}): walk up into it from (#{row + 1},#{col}) and press A, never opened",
          title: "Open the chest at (#{row},#{col})", predicate: { kind: 'new_text' }, target: { kind: 'chest', place:, cell: [row, col] } }
      end
    end

    # Uncatalogued entities and sprites holding no entity may answer A like a person (the sword of 242/0 before its census).
    def unidentified(place, grid, entities, talk_log, link)
      things = entities.select { |entity| entity[:kind].to_s == 'unknown' && entity[:cell] }.uniq { |entity| entity[:type] }
                       .reject { |entity| talk_log.attempts(place, [[:entity, entity[:type]]]).positive? }
                       .map { |entity| [entity[:cell], "the unidentified thing (type #{entity[:type]}, not known whether it is a person or hostile)", { kind: 'person', type: entity[:type] }] }
      sprites = grid ? TalkLog.objects(grid) : []
      things += sprites.reject { |cells| entities.any? { |entity| entity[:cell] && cells.include?(entity[:cell]) } || talk_log.tried?(sprites, place, cells) }
                       .map { |cells| [cells.first, 'the unidentified object', { kind: 'examine' }] }
      near = ->((cell, _, _)) { link ? (cell[0] - link[0]).abs + (cell[1] - link[1]).abs : 0 }
      things.sort_by { |thing| [near.(thing), thing[0]] }.first(PER_KIND).map do |(row, col), what, target|
        { id: "examine-#{row}-#{col}", label: "examine #{what} at (#{row},#{col}): stand next to it, face it and press A, never tried",
          title: "Examine #{what} at (#{row},#{col})"[0, 80], predicate: { kind: 'new_text' }, target: { **target, place:, cell: [row, col] } }
      end
    end

    def places(place, hops, explore_log, named)
      away(place, hops).select { |where| explore_log.work?(where) }.first(PER_KIND).map do |where|
        work = explore_log.untried?(where) ? 'untried exits or doors' : "a thing never tried (type #{explore_log.unmet(where).join(', type ')})"
        { id: "place-#{where.join('-')}", label: "go to #{describe(where, named)}, #{moves(hops[where])}: it has #{work}",
          title: "Go to #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'place', place: where } }
      end
    end

    # After a gain, people and things this lineage never read pass the cap, and places no known route reaches yet: those come after the
    # reachable ones, nearest first on the map.
    def people_away(place, hops, cards, talk_log, named, stamp = nil, explore_log = nil)
      capped = 0
      unrouted = cards.keys.reject { |where| where == place || hops.key?(where) }
      unrouted = unrouted.sort_by { |where| [map_distance(place, where, explore_log) || Float::INFINITY, where] }
      found = (away(place, hops) + unrouted).flat_map do |where|
        gained = stamp && cards.dig(where, :held) && cards.dig(where, :held) != Array(stamp)[1]
        next [] unless hops.key?(where) || gained

        Array(cards.dig(where, :people)).uniq { |person| person[:type] }.filter_map do |person|
          stale = talk_log.stale?(place: where, entity: person[:type], stamp:)
          next unless stale || AWAY_WORTH.include?(talk_log.last_status(place: where, entity: person[:type]))
          next unless hops.key?(where) || talk_log.talks_with(where, person[:type]).empty?

          who = talk_log.name_of(where, person[:type]) || "person (type #{person[:type]})"
          why = stale ? 'Link holds other items than at the last talk' : 'not exhausted'
          [{ id: "person-#{where.join('-')}-t#{person[:type]}", label: "talk to #{who} in #{describe(where, named)}, #{moves(hops[where])}, #{why}",
             title: "Go talk to #{who}"[0, 80], predicate: { kind: 'reach_place', place: where },
             target: { kind: 'person', place: where, type: person[:type], cell: person[:cell] } },
           gained && talk_log.talks_with(where, person[:type]).empty?]
        end + things_away(where, hops, cards, talk_log, named, stamp).map { |thing| [thing, gained] }
      end
      found.filter_map { |candidate, unread| candidate if unread || (capped += 1) <= PER_KIND }
    end

    # An uncatalogued thing never tried, seen still in its cell while Link held other items than now, may answer what he holds now: offered like a stale person.
    def things_away(where, hops, cards, talk_log, named, stamp)
      held = cards.dig(where, :held)
      return [] unless stamp && held && held != Array(stamp)[1]

      Array(cards.dig(where, :unknown)).select { |thing| thing[:still] }.uniq { |thing| thing[:type] }.filter_map do |thing|
        next if Entities.catalogue.key?(thing[:type]) || talk_log.attempts(where, [[:entity, thing[:type]]]).positive?

        what = "the unidentified thing (type #{thing[:type]})"
        { id: "examine-#{where.join('-')}-t#{thing[:type]}", label: "examine #{what} in #{describe(where, named)}, #{moves(hops[where])}, never tried; Link holds other items than when it was seen",
          title: "Go examine #{what}"[0, 80], predicate: { kind: 'reach_place', place: where },
          target: { kind: 'person', place: where, type: thing[:type], cell: thing[:cell], try: true } }
      end
    end

    # Every person who asked for something and has not answered with a new text since, once Link holds other items than at the last talk;
    # nothing matches what they asked for with what Link holds.
    def needs(place, hops, leads, talk_log, named, stamp)
      leads.open_needs(talk_log).filter_map do |lead|
        where = lead[:place]
        type = lead.dig(:source, :entity)
        next unless (where == place || hops[where]) && talk_log.stale?(place: where, entity: type, stamp:)

        who = talk_log.name_of(where, type) || "person (type #{type})"
        cell = lead[:source].values_at(:row, :col)
        asked = "who asked for something (#{lead[:id]}: « #{lead[:quote]} »), Link holds other items than at the last talk"
        if where == place
          { id: "need-t#{type}", who:, label: "talk again to #{who} at (#{cell.join(',')}), #{asked}", title: "Talk again to #{who}"[0, 80],
            predicate: { kind: 'new_text' }, target: { kind: 'person', place:, type:, cell: } }
        else
          { id: "need-#{where.join('-')}-t#{type}", label: "talk again to #{who} in #{describe(where, named)}, #{moves(hops[where])}, #{asked}",
            title: "Go talk again to #{who}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'person', place: where, type:, cell: } }
        end
      end.uniq { |need| need[:id] }
    end

    def signs_away(place, hops, cards, talk_log, named)
      away(place, hops).flat_map do |where|
        Array(cards.dig(where, :signs)).filter_map do |sign|
          cell = sign[:cell]
          next unless cell.is_a?(Array) && talk_log.sign_status(place: where, cell:) != :read

          { id: "sign-#{where.join('-')}-#{cell.join('-')}", label: "read the sign at (#{cell.join(',')}) in #{describe(where, named)}, #{moves(hops[where])}, not read yet",
            title: "Go read the sign in #{describe(where, named)}"[0, 80], predicate: { kind: 'new_text' }, target: { kind: 'sign', place: where, cell:, remote: true } }
        end
      end.first(PER_KIND)
    end

    def chests_away(place, hops, cards, named)
      away(place, hops).flat_map do |where|
        Array(cards.dig(where, :chests)).map do |cell|
          { id: "chest-#{where.join('-')}-#{cell.join('-')}", label: "open the chest at (#{cell.join(',')}) in #{describe(where, named)}, #{moves(hops[where])}, never opened",
            title: "Go open the chest in #{describe(where, named)}"[0, 80], predicate: { kind: 'new_text' }, target: { kind: 'chest', place: where, cell:, remote: true } }
        end
      end.first(PER_KIND)
    end

    def lead_places(place, hops, leads, named)
      leads.all.reverse.filter_map do |lead|
        where = leads.place_for(lead)
        next unless where && where != place && !leads.settled?(lead)

        route = hops[where] ? moves(hops[where]) : 'no known route'
        { id: lead[:id], label: "go to #{describe(where, named)} (#{lead[:importance]} lead: #{Leads.shown_claim(lead)}), #{route}",
          title: "Go to #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'lead', place: where, lead: lead[:id] } }
      end.first(PER_KIND)
    end

    # A place with a world-model puzzle that an open lead's words point to, offered first once per run and context, and not at all once
    # a conclusive bench measured it in this context.
    def puzzles(place, hops, explore_log, leads, named)
      open = leads.all.reject { |lead| leads.settled?(lead) }
      hops.keys.sort_by { |where| [hops[where], where] }.filter_map do |where|
        next if explore_log.puzzles(where).empty? || explore_log.bench_concluded?(where) || explore_log.puzzle_offered?(where)

        lead = open.find { |candidate| leads.region(candidate).include?(where) } or next
        here = where == place
        { id: "puzzle-#{where.join('-')}", label: "investigate #{here ? 'this place' : describe(where, named)}#{here ? '' : ", #{moves(hops[where])}"}: a way out of it led where the map " \
                                                      "does not predict, and #{lead[:id]} « #{lead[:quote]} » points there; try its ways no crossing has measured",
          title: "Investigate #{describe(where, named)}"[0, 80], predicate: { kind: 'new_place' }, target: { kind: 'place', place: where } }
      end.first(1)
    end

    def away(place, hops) = hops.reject { |where, _| where == place }.sort_by { |where, count| [count, where] }.map(&:first)

    def describe(where, named) = (name = named.(where)) ? "#{name} (#{where.join('-')})" : "place #{where.join('-')}"

    def moves(count) = count ? "#{count} #{count == 1 ? 'move' : 'moves'} away" : 'no known route'

    # Screens apart on the overworld map; an interior stands where a way out of it leads.
    def map_distance(from, to, explore_log)
      a = overworld(from, explore_log)
      b = overworld(to, explore_log)
      return unless a && b

      width = Geometry.fact(:overworld_neighbour)['width']
      ((a[0] / width) - (b[0] / width)).abs + ((a[0] % width) - (b[0] % width)).abs
    end

    def overworld(place, explore_log)
      maps = Geometry.fact(:overworld_neighbour)['maps']
      return place if maps.include?(place[1])

      explore_log&.ways(place)&.values&.find { |to| maps.include?(to[1]) }
    end

    def status_text(status)
      { never: 'never talked to', new: 'last talk gave new text', changed: 'something changed since the last talk',
        repeat: 'last talk repeated an older text, not exhausted yet' }.fetch(status)
    end
  end
end
