require 'koholint/place_card'
require 'koholint/place_kinds'

module Koholint
  module Candidates
    PER_KIND = 4
    HERE_WORTH = %i[never new changed repeat].freeze
    AWAY_WORTH = %i[never new].freeze

    module_function

    def build(place:, grid:, explore_log:, talk_log:, leads:, cards: {}, entities: [], signs: [], stamp: nil, link: nil, low_health: false)
      hops = explore_log.hops(place)
      named = ->(where) { leads.name_of(where) }
      people = people_here(place, entities, talk_log, stamp)
      leaving = exits(place, grid, explore_log) + doors(place, signs, explore_log, link) + places(place, hops, explore_log, named) +
                people_away(place, hops, cards, talk_log, named) + signs_away(place, hops, cards, talk_log, named) + lead_places(place, hops, leads, named)
      [(shelter(place, hops, named) if low_health)].compact + people + signs_here(place, signs, talk_log) + warn(leaving, people)
    end

    def warn(leaving, people)
      return leaving if people.empty?

      who = people.map { |person| person[:who] }.join(', ')
      leaving.map { |candidate| candidate.merge(label: "#{candidate[:label]} (leaves unexhausted people here: #{who})") }
    end

    def shelter(place, hops, named)
      return if PlaceKinds.kind(place) == 'interior'

      where = away(place, hops).find { |known| PlaceKinds.kind(known) == 'interior' } or return
      { id: "shelter-#{where.join('-')}", label: "LOW HEALTH: take shelter in #{describe(where, named)}, #{moves(hops[where])} (an interior; the tip that it restores hearts is not confirmed)",
        title: "Take shelter in #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'shelter', place: where } }
    end

    def lines(candidates) = candidates.map { |candidate| "- #{candidate[:id]}: #{candidate[:label]}" }

    def find(candidates, id) = candidates.find { |candidate| candidate[:id] == id.to_s.strip }

    def exits(place, grid, explore_log)
      PlaceCard.exits(grid).filter_map do |side, cells|
        next if explore_log.side_left?(place, side) || cells.all? { |cell| explore_log.tried?(place, cell, side) }

        { id: "exit-#{side}", label: "leave by the #{side} side (open border cells #{cells.map { |r, c| "(#{r},#{c})" }.join(' ')})",
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

    def places(place, hops, explore_log, named)
      away(place, hops).select { |where| explore_log.untried?(where) }.first(PER_KIND).map do |where|
        { id: "place-#{where.join('-')}", label: "go to #{describe(where, named)}, #{moves(hops[where])}: it has untried exits or doors",
          title: "Go to #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'place', place: where } }
      end
    end

    def people_away(place, hops, cards, talk_log, named)
      away(place, hops).flat_map do |where|
        Array(cards.dig(where, :people)).uniq { |person| person[:type] }.filter_map do |person|
          next unless AWAY_WORTH.include?(talk_log.last_status(place: where, entity: person[:type]))

          who = talk_log.name_of(where, person[:type]) || "person (type #{person[:type]})"
          { id: "person-#{where.join('-')}-t#{person[:type]}", label: "talk to #{who} in #{describe(where, named)}, #{moves(hops[where])}, not exhausted",
            title: "Go talk to #{who}"[0, 80], predicate: { kind: 'reach_place', place: where },
            target: { kind: 'person', place: where, type: person[:type], cell: person[:cell] } }
        end
      end.first(PER_KIND)
    end

    def signs_away(place, hops, cards, talk_log, named)
      away(place, hops).flat_map do |where|
        Array(cards.dig(where, :signs)).filter_map do |sign|
          cell = sign[:cell]
          next unless cell.is_a?(Array) && talk_log.sign_status(place: where, cell:) != :read

          { id: "sign-#{where.join('-')}-#{cell.join('-')}", label: "read the sign at (#{cell.join(',')}) in #{describe(where, named)}, #{moves(hops[where])}, not read yet",
            title: "Go read the sign in #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'sign', place: where, cell: } }
        end
      end.first(PER_KIND)
    end

    def lead_places(place, hops, leads, named)
      leads.all.reverse.filter_map do |lead|
        where = leads.place_for(lead)
        next unless where && where != place

        route = hops[where] ? moves(hops[where]) : 'no known route'
        { id: lead[:id], label: "go to #{describe(where, named)} (#{lead[:importance]} lead: #{lead[:claim]}), #{route}",
          title: "Go to #{describe(where, named)}"[0, 80], predicate: { kind: 'reach_place', place: where }, target: { kind: 'lead', place: where, lead: lead[:id] } }
      end.first(PER_KIND)
    end

    def away(place, hops) = hops.reject { |where, _| where == place }.sort_by { |where, count| [count, where] }.map(&:first)

    def describe(where, named) = (name = named.(where)) ? "#{name} (#{where.join('-')})" : "place #{where.join('-')}"

    def moves(count) = "#{count} #{count == 1 ? 'move' : 'moves'} away"

    def status_text(status)
      { never: 'never talked to', new: 'last talk gave new text', changed: 'something changed since the last talk',
        repeat: 'last talk repeated an older text, not exhausted yet' }.fetch(status)
    end
  end
end
