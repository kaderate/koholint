require 'koholint'
require 'koholint/dialogues'
require 'koholint/game_state'
require 'koholint/items'
require 'koholint/modes'
require 'koholint/perception'
require 'koholint/place_card'
require 'koholint/place_kinds'
require 'koholint/summary'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/vision/grid_builder'
require 'koholint/vision/world'

module Koholint
  module Viewer
    module Insights
      ROWS = Vision::Grid::ROWS
      COLS = Vision::Grid::COLS
      MAX_PLACES = 200
      LEADS_PER_PLACE = 5
      MARKERS = 300
      BUCKETS = 150
      LABEL = 160
      SERIES = 200
      FPS = 60
      HEALTH_POINTS = 400
      DIALOGUE_GROUPS = 60
      TALKS_PER_PERSON = 20
      TEXT = 500
      ALERT_STOPS = %w[stuck_boot unknown_mode_stuck].freeze

      module_function

      def visits(trace)
        current = nil
        seen = {}
        moves = []
        observe = lambda do |place, frame|
          next if place == current

          seen[place] ||= { place:, order: seen.size + 1, first_frame: frame, arrivals: 0 }
          seen[place][:arrivals] += 1
          seen[place][:last_frame] = frame
          moves << { from: current, to: place, frame: } if current
          current = place
        end
        trace.each do |event|
          if event['type'] == 'perception'
            place = Summary.perceived_place(event)
            observe.call(place, event['frame']) if place
          elsif event['type'] == 'action' && event['result'].is_a?(Hash)
            from = spot(event['result']['from'])
            to = spot(event['result']['to'])
            next unless from && to && from[:place] != to[:place]

            observe.call(from[:place], event['frame'])
            observe.call(to[:place], event['frame'])
          end
        end
        { places: seen, moves:, current: }
      end

      def spot(value)
        return nil unless value.is_a?(Hash) && value['room'].is_a?(Integer) && value['map'].is_a?(Integer)

        { place: [value['room'], value['map']] }
      end

      def layout(order, moves, kinds = PlaceKinds.catalogue)
        grid = ->(place) { PlaceKinds.grid?(place, kinds) }
        cells = order.select(&grid).to_h { |place| [place, PlaceKinds.cell(place)] }
        min_x, max_x = cells.values.map(&:first).minmax
        min_y, max_y = cells.values.map(&:last).minmax
        spots = cells.transform_values { |(x, y)| [x - min_x, y - min_y] }
        lane = cells.empty? ? 0 : max_y - min_y + 2
        parents = parents(order, moves, grid)
        taken = {}
        order.each do |place|
          next if spots[place]

          x = spots[parents[place]]&.first || 0
          y = lane
          y += 1 while taken[[x, y]]
          taken[[x, y]] = true
          spots[place] = [x, y]
        end
        { spots:, parents:, lane: cells.empty? ? nil : lane, width: cells.empty? ? 0 : max_x - min_x + 1 }
      end

      def parents(order, moves, grid)
        last = nil
        found = {}
        moves.each do |move|
          last = move[:from] if grid.call(move[:from])
          found[move[:to]] ||= last unless grid.call(move[:to])
        end
        order.each do |place|
          next if grid.call(place) || found[place]

          out = moves.find { |move| move[:from] == place && grid.call(move[:to]) }
          found[place] = out[:to] if out
        end
        found.compact
      end

      def map(trace, screens:, affordances:, frame:, shots: {})
        found = visits(trace)
        places = found[:places].values.first(MAX_PLACES)
        keep = places.to_h { |entry| [entry[:place], true] }
        moves = found[:moves].select { |m| keep[m[:from]] && keep[m[:to]] }
        placed = layout(places.map { |entry| entry[:place] }, moves)
        spots = placed[:spots]
        world = Vision::World.from_events(screens + affordances, at_frame: frame)
        capabilities = Vision::Capabilities.new
        people = people(trace)
        leads = trace.select { |e| e['type'] == 'lead' && e['place'].is_a?(Array) }.group_by { |e| e['place'] }
        names = trace.select { |e| e['type'] == 'place_name' && e['place'].is_a?(Array) }.to_h { |e| [e['place'], e['name']] }
        nodes = places.map do |entry|
          cells = cells(world.grid_for(entry[:place], capabilities))
          known = cells&.flatten&.count { |state| state != 'unknown' }
          entry.merge(x: spots[entry[:place]][0], y: spots[entry[:place]][1], kind: PlaceKinds.kind(entry[:place]),
                      cell: PlaceKinds.grid?(entry[:place]) ? PlaceKinds.cell(entry[:place]) : nil, parent: placed[:parents][entry[:place]],
                      current: entry[:place] == found[:current], screenshot: shots.key?(entry[:place]),
                      coverage: known && (known * 100.0 / (ROWS * COLS)).round, cells:,
                      people: people.fetch(entry[:place], []), name: names[entry[:place]],
                      leads: leads.fetch(entry[:place], []).last(LEADS_PER_PLACE).map { |e| { id: e['id'], importance: e['importance'], claim: clip(e['claim']) } })
        end
        links = moves.group_by { |m| [m[:from], m[:to]].sort }.map do |(a, b), group|
          { a:, b:, count: group.size, first_frame: group.first[:frame] }
        end
        { frame:, current: found[:current], places: nodes, links:, lane: placed[:lane], truncated: found[:places].size > MAX_PLACES }
      end

      def cells(grid)
        return nil unless grid

        (0...ROWS).map { |row| (0...COLS).map { |col| Feed.cell_state(grid, row, col) } }
      end

      def people(trace)
        attempts = Hash.new(0)
        trace.each do |event|
          next unless event['type'] == 'action' && event['skill'] == 'talk_to' && event['result'].is_a?(Hash) && event['params'].is_a?(Hash)

          from = spot(event['result']['from']) or next
          result = event['result']
          attempts[[from[:place], [event['params']['row'], event['params']['col']]]] += 1 if result['talked'] == true || %w[done no_response].include?(result['stopped_by'].to_s)
        end
        npcs(trace).group_by { |(place, _), _| place }.transform_values do |list|
          list.map do |(place, cell), talks|
            { row: cell[0], col: cell[1], attempts: attempts[[place, cell]], texts: talks.size, state: talks.last[:state], last_frame: talks.last[:frame] }
          end
        end
      end

      def npcs(trace)
        dialogues = Dialogues.from_events(trace)
        now = stamp(trace)
        dialogues.select { |d| d[:source].is_a?(Hash) && d[:source][:row].is_a?(Integer) && d[:source][:col].is_a?(Integer) && d[:place].is_a?(Array) }
                 .group_by { |d| [d[:place], [d[:source][:row], d[:source][:col]]] }
                 .transform_values { |talks| judge(talks, now) }
      end

      def judge(talks, now)
        keys = talks.map { |talk| Dialogues.key(talk[:text]) }
        talks.each_with_index.map do |talk, index|
          fresh = !Dialogues.known?(keys[index], keys.first(index))
          { frame: talk[:frame], talk: index + 1, new_text: fresh, state: index == talks.size - 1 ? verdict(talks, keys, now) : nil }
        end
      end

      def verdict(talks, keys, now)
        fresh = !Dialogues.known?(keys[-1], keys[0...-1])
        return 'worth retrying: something changed since' if now != talks.last[:stamp]
        return 'worth retrying' if fresh
        return 'exhausted' if talks.size >= 2 && Dialogues.known?(keys[-1], [keys[-2]]) && talks[-1][:stamp] == talks[-2][:stamp]

        'nothing new'
      end

      def stamp(trace)
        state = trace.reverse_each.find { |e| e['type'] == 'perception' && e['state'].is_a?(Hash) }&.dig('state') || {}
        Dialogues.stamp_of(state, trace.select { |e| e['type'] == 'lead' })
      end

      def dialogue_states(trace)
        npcs(trace).flat_map { |(place, _), talks| talks.map { |talk| [[talk[:frame], place], talk] } }.to_h
      end

      def timeline(trace, frames:)
        markers = []
        visits(trace)[:moves].each { |m| markers << { frame: m[:frame], kind: 'place', label: "entered [#{m[:to].join(',')}]" } }
        Dialogues.from_events(trace).each { |d| markers << { frame: d[:frame], kind: 'dialogue', label: "dialogue: #{d[:text]}" } }
        trace.each do |event|
          marker = marker(event)
          markers << marker.merge(frame: event['frame']) if marker && event['frame'].is_a?(Integer)
        end
        markers.select! { |m| m[:frame].is_a?(Integer) }
        markers.sort_by!.with_index { |m, i| [m[:frame], i] }
        { frames: [frames.to_i, markers.last&.dig(:frame) || 0].max, markers: thin(markers, frames), total: markers.size }
      end

      def marker(event)
        case event['type']
        when 'objective'
          { kind: 'objective', status: event['status'], label: "objective #{event['status']}: #{event['title'] || event['id']}#{" (#{event['reason']})" if event['reason']}" }
        when 'decision'
          return nil unless Summary.model_call?(event)

          { kind: 'call', skill: Summary.skill_of(event), label: "#{Summary.skill_of(event)} $#{format('%.4f', event['cost_usd'].to_f)}: #{event['justification']}" }
        when 'lead' then { kind: 'lead', label: "lead [#{event['importance']}] #{event['claim']}" }
        when 'notable' then { kind: 'notable', label: "#{event['kind']}: #{event['detail']}" }
        when 'stop' then { kind: 'stop', label: "stop: #{event['reason']}" }
        when 'action'
          stop = event['result'].is_a?(Hash) ? event['result']['stopped_by'] : nil
          { kind: 'explore', label: "explore stopped: #{stop}" } if event['skill'] == 'explore' && stop
        end
      end

      def thin(markers, frames)
        clipped = markers.map { |m| m.merge(label: clip(m[:label])) }
        return clipped.map { |m| m.merge(count: 1) } if clipped.size <= MARKERS

        span = [frames.to_i, clipped.last[:frame]].max + 1
        width = [(span / BUCKETS.to_f).ceil, 1].max
        width *= 2 while clipped.map { |m| [m[:frame] / width, m[:kind]] }.uniq.size > MARKERS
        clipped.group_by { |m| [m[:frame] / width, m[:kind]] }.values.map do |group|
          first = group.first
          next first.merge(count: 1) if group.size == 1

          skill = group.filter_map { |m| m[:skill] }.tally.max_by { |_, n| [n, 0] }&.first
          first.merge(count: group.size, skill:, last_frame: group.last[:frame], label: clip("#{group.size} × #{first[:kind]}, first: #{first[:label]}")).compact
        end.sort_by { |m| m[:frame] }
      end

      def clip(text)
        text = text.to_s.gsub(/\s+/, ' ').strip
        text.length > LABEL ? "#{text[0, LABEL - 1]}…" : text
      end

      def cost(trace)
        calls = trace.select { |e| Summary.model_call?(e) }
        total = 0.0
        points = [[0, 0.0]] + calls.map { |e| [e['frame'].to_i, (total += e['cost_usd'].to_f).round(6)] }
        decisions = trace.select { |e| e['type'] == 'decision' }
        { series: sample(points), by_skill: Summary.cost_by_skill(calls), total: total.round(6),
          decisions: { paid: calls.size, free: decisions.size - calls.size } }
      end

      def sample(points)
        return points if points.size <= SERIES

        step = (points.size - 1) / (SERIES - 1).to_f
        (0...SERIES).map { |i| points[(i * step).round] }
      end

      def stats(trace) = cost(trace).merge(usage: Summary.usage(trace))

      def mode(trace)
        perception = trace.reverse_each.find { |e| e['type'] == 'perception' && e['state'].is_a?(Hash) } or return { phase: 'unknown', name: nil }
        fields = GameState.members.map(&:to_s)
        state = GameState.new(**perception['state'].slice(*fields).transform_keys(&:to_sym))
        { phase: state.phase(booted: GameState.played?(trace)).to_s, name: Modes.for(state)&.name, frame: perception['frame'] }
      rescue StandardError
        { phase: 'unknown', name: nil }
      end

      def cockpit(trace, manifest: {}, frame: 0)
        state = last_state(trace)
        found = visits(trace)
        names = trace.select { |e| e['type'] == 'place_name' && e['place'].is_a?(Array) }.to_h { |e| [e['place'], e['name']] }
        world = PlaceCard.world(trace, names:)
        shown = [frame.to_i, trace.last&.dig('frame').to_i].max
        interiors = interiors(trace, found, world, names)
        leads = trace.select { |e| e['type'] == 'lead' }
        { frame: shown, kpis: kpis(trace, manifest, shown, found[:places].size), health: health(trace), hud: hud(state, trace),
          now: now(trace, leads), reasoning: reasoning(trace), symptoms: symptoms(trace),
          place: place_view(found[:current], world, names, interiors), interiors:, leads: leads_view(leads),
          dialogues: dialogue_groups(trace, world, names, leads) }
      end

      def last_state(trace) = trace.reverse_each.find { |e| e['type'] == 'perception' && e['state'].is_a?(Hash) }&.dig('state') || {}

      def kpis(trace, manifest, frame, places)
        decisions = trace.select { |e| e['type'] == 'decision' }
        calls = decisions.count { |e| Summary.model_call?(e) }
        spent = decisions.sum { |e| e['cost_usd'].to_f }
        budget = manifest['budget'].is_a?(Hash) ? manifest['budget'] : {}
        per = ->(value) { frame.positive? ? (value * 1000.0 / frame).round(4) : nil }
        { frame:, spent: spent.round(6), cap: budget['dollars'].is_a?(Numeric) ? budget['dollars'] : nil, calls:, free: decisions.size - calls,
          calls_per_1000f: per.call(calls), usd_per_1000f: per.call(spent), minutes: (frame / FPS / 60.0).round(1),
          cap_minutes: budget['active_seconds'].is_a?(Numeric) ? (budget['active_seconds'] / 60.0).round(1) : nil, places: }
      end

      def health(trace)
        points = trace.filter_map do |event|
          state = event['state']
          next unless event['type'] == 'perception' && state.is_a?(Hash) && state['max_hp'].to_i.positive?

          [event['frame'], state['hp'].to_i, state['max_hp'].to_i]
        end
        points = points.chunk_while { |a, b| a[1] == b[1] && a[2] == b[2] }.map(&:first)
        points = points.each_slice((points.size / HEALTH_POINTS.to_f).ceil).map(&:first) if points.size > HEALTH_POINTS
        hits = trace.select { |e| e['type'] == 'notable' && %w[damage death].include?(e['kind']) }.map { |e| { frame: e['frame'], kind: e['kind'] } }.last(MARKERS)
        { points: points.map { |frame, hp, max| { frame:, hp:, max_hp: max } }, hits: }
      end

      def hud(state, trace)
        item = ->(id) { id.to_i.zero? ? nil : { id: id.to_i, name: Items.name(id) } }
        gained = trace.reverse_each.find { |e| e['type'] == 'item_gained' }
        reached = Perception::MILESTONES.index(state['milestone'].to_s.to_sym) || 0
        { hp: state['hp'], max_hp: state['max_hp'], item_a: item.call(state['item_a']), item_b: item.call(state['item_b']),
          inventory: Array(state['inventory']).first(Items::SLOTS).map { |id| item.call(id) }, milestone: state['milestone'],
          ladder: Perception::MILESTONES.each_with_index.reject { |_, index| index.zero? }.map { |name, index| { name: name.to_s, reached: index <= reached } },
          last_item: gained && { frame: gained['frame'], id: gained['item'], name: gained['name'] } }
      end

      def now(trace, leads)
        started = trace.reverse_each.find { |e| e['type'] == 'objective' && e['status'] == 'started' }
        ended = started && trace.any? { |e| e['type'] == 'objective' && e['id'] == started['id'] && e['status'] != 'started' }
        offered = started && trace.reverse_each.find { |e| e['type'] == 'decision' && e['decision_point'] == 'choose_objective' && e['frame'] <= started['frame'] }
        because = started && leads.find { |lead| lead['id'] == started['because'] }
        options = offered && offered['options'].is_a?(Array) ? offered['options'].select { |o| o.is_a?(Hash) } : []
        { objective: started && { id: started['id'], title: started['title'], predicate: started['predicate'], frame: started['frame'], ended: ended },
          why: { lead: because && { id: because['id'], importance: because['importance'], claim: clip(because['claim']) }, text: offered && clip(offered['justification']) },
          candidates: options.map { |o| { id: o['id'], label: clip(o['label']), leaves_unexhausted: o['leaves_unexhausted'] == true, picked: o['picked'] == true } } }
      end

      def reasoning(trace)
        decisions = trace.select { |e| e['type'] == 'decision' }
        view = lambda do |event|
          event && { frame: event['frame'], point: event['decision_point'], skill: Summary.skill_of(event), justification: event['justification'].to_s[0, TEXT],
                     confidence: event['confidence'], agent: event['agent'], paid: Summary.model_call?(event), cost: event['cost_usd'].to_f }
        end
        { last: view.call(decisions.last), paid: view.call(decisions.reverse_each.find { |e| Summary.model_call?(e) }) }
      end

      def symptoms(trace)
        usage = Summary.usage(trace)
        { left_with_unexhausted_people: Summary.unexhausted_departures(trace).size, damage_events: usage[:damage_events], deaths: usage[:deaths],
          talks: usage[:talks], talks_to_known: usage[:talks_to_known] }
      end

      def leads_view(leads)
        leads.reject { |e| e['importance'] == 'low' }.last(40).reverse.map { |e| { id: e['id'], importance: e['importance'], claim: clip(e['claim']), place: e['place'], tip: e['importance'] == 'tip' } }
      end

      def place_view(current, world, names, interiors)
        return nil unless current

        card = world[current.join('-')] || {}
        crossed = interiors.select { |i| i[:parent] == current && i[:door] }.map { |i| i[:door][:cell] }
        { place: current, name: names[current], kind: PlaceKinds.kind(current), visits: card['visits'],
          people: Array(card['people']).map { |p| { type: p['type'], cell: p['cell'], name: p['name'], verdict: p['status'] == 'exhausted' ? 'exhausted' : 'revisit' } },
          signs: Array(card['signs']).map { |sign| { cell: sign['cell'], read: sign['status'] == 'read' } },
          doors: Array(card['doors']).map { |door| { cell: door['cell'], object: door['object'], crossed: crossed.include?(door['cell']) } },
          creatures: (Array(card['creatures']) + Array(card['enemies']) + Array(card['unknown'])).map { |c| { type: c['type'], cell: c['cell'] } } }
      end

      def interiors(trace, found, world, names)
        grid = ->(place) { PlaceKinds.grid?(place) }
        order = found[:places].keys
        parents = parents(order, found[:moves], grid)
        order.reject(&grid).map do |place|
          parent = parents[place]
          card = world[place.join('-')] || {}
          people = Array(card['people'])
          { place:, name: names[place], kind: PlaceKinds.kind(place), parent:, parent_name: parent && names[parent], frame: found[:places][place][:first_frame],
            door: parent && door_between(trace, world, parent, place),
            people: people.size, exhausted: people.count { |p| p['status'] == 'exhausted' } }
        end
      end

      def door_between(trace, world, parent, place)
        crossing = trace.find do |e|
          e['type'] == 'action' && e['result'].is_a?(Hash) && spot(e['result']['from'])&.dig(:place) == parent && spot(e['result']['to'])&.dig(:place) == place
        end
        from = crossing && crossing['result']['from']
        return nil unless from && from['x'].is_a?(Integer) && from['y'].is_a?(Integer)

        row, col = Vision::GridBuilder.link_cell(from['x'], from['y'])
        doors = Array(world.dig(parent.join('-'), 'doors'))
        return nil unless row && !doors.empty?

        door = doors.min_by { |d| (d['cell'][0] - row).abs + (d['cell'][1] - col).abs }
        { cell: door['cell'], object: door['object'], frame: crossing['frame'] }
      end

      def dialogue_groups(trace, world, names, leads)
        tips = leads.select { |e| e['importance'] == 'tip' }.map { |e| Dialogues.compact(e['quote']) }.reject(&:empty?)
        states = dialogue_states(trace)
        groups = Dialogues.from_events(trace.select { |e| %w[dialogue action].include?(e['type']) }).group_by do |d|
          source = d[:source]
          [d[:place], source ? [source[:row], source[:col]] : nil, source ? nil : d[:speaker]]
        end
        groups.map do |(place, cell, _), talks|
          npc_states = talks.map { |d| states[[d[:frame], d[:place]]] }
          type = talks.filter_map { |d| d.dig(:source, :entity) }.last
          name = talks.filter_map { |d| d[:speaker] }.last || (type ? "personne type #{type}" : 'personne inconnue')
          verdict = npc_states.compact.last&.dig(:state)
          { place:, place_name: place && names[place], cell:, name:, type:, last_frame: talks.last[:frame],
            verdict: verdict.nil? ? 'unknown' : (verdict == 'exhausted' ? 'exhausted' : 'revisit'),
            talks: talks.each_with_index.map do |d, index|
              npc = npc_states[index]
              { frame: d[:frame], talk: npc ? npc[:talk] : index + 1, new_text: npc ? npc[:new_text] : true, text: d[:text].to_s[0, TEXT],
                tip: tips.any? { |quote| Dialogues.compact(d[:text]).include?(quote) } }
            end.last(TALKS_PER_PERSON) }
        end.sort_by { |g| -g[:last_frame].to_i }.first(DIALOGUE_GROUPS)
      end

      def alerts(trace)
        notables = trace.select { |e| e['type'] == 'notable' && e['kind'] == 'unknown_mode' }.last(3)
        stops = trace.select { |e| e['type'] == 'stop' && ALERT_STOPS.include?(e['reason'].to_s) }
        notables.map { |e| { kind: 'unknown_mode', frame: e['frame'], detail: clip(e['detail']) } } +
          stops.map { |e| { kind: e['reason'], frame: e['frame'], detail: "run stopped: #{e['reason']}" } }
      end
    end
  end
end
