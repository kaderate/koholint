require 'koholint/exits'
require 'koholint/geometry'
require 'koholint/ledger'
require 'koholint/navigation/planner'

module Koholint
  class ExploreLog
    TRIED_AT = 2
    OPPOSITE = { up: :down, down: :up, left: :right, right: :left }.freeze

    def self.from_events(events)
      log = new
      events.each do |event|
        log.screen(event['place'], event['grid']) if event['type'] == 'screen'
        if event['type'] == 'decision'
          Array(event['puzzles_offered']).each { |place| log.restore_offer(place, Exits.context(event['input'] || {})) }
          entry = event['puzzle_entry']
          log.enter_puzzle(entry['place'], Exits.context(event['input'] || {}), entry['texts']) if entry
        end
        next unless Ledger.pick(event, :type).to_s == 'action'

        result = Ledger.pick(event, :result)
        log.note(result, frame: event['frame'])
        log.absorb(result, frame: event['frame']) if Ledger.pick(event, :skill).to_s == 'explore'
      end
      log.resumed(events.select { |event| event['type'] == 'puzzle' })
      log
    end

    def initialize
      @exits = Hash.new(0)
      @offered = []
      @walked = Hash.new { |hash, key| hash[key] = [] }
      @walls = Hash.new { |hash, key| hash[key] = [] }
      @edges = Hash.new { |hash, key| hash[key] = {} }
      @surveys = {}
      @known = []
      @arrivals = {}
      @pockets = {}
      @suspects = {}
      @assumed = []
      @doubted = {}
      @visits = Hash.new(0)
      @failed = Hash.new { |hash, key| hash[key] = [] }
      @screens = {}
      @looks = {}
      @explored_since_clear = []
      @stood = Hash.new { |hash, key| hash[key] = [] }
      @entered = {}
      @at = nil
      @through = []
      @observed = Hash.new { |hash, key| hash[key] = {} }
      @puzzles = {}
      @pending = []
      @frame = nil
      @bench = { edges: {}, status: {}, benches: {} }
      @context = nil
      @puzzle_offers = Set.new
      @puzzle_entries = Set.new
      @cut_off = Set.new
      @cut_seen = {}
    end

    # The exit bench's measured edges and benches for the current context (Exits.for_context); they fill ways this run never crossed.
    def use_bench(found)
      @bench = found
    end

    def bench_of(place) = @bench[:benches][place]

    def bench_status(place, key) = @bench[:status]&.dig([place, key])

    # A bench with a way never reached concludes nothing.
    def bench_concluded?(place) = %w[leads_on depends_on_context].include?(bench_of(place)&.dig('status'))

    # The milestone and items held now (Exits.context): a puzzle objective is offered once per place and context in a run.
    def in_context(context)
      @context = context
    end

    def offer_puzzle(place) = @puzzle_offers << [place, @context]

    def puzzle_offered?(place) = @puzzle_offers.include?([place, @context])

    def restore_offer(place, context) = @puzzle_offers << [place, context]

    # The first entry of a puzzle place in a context with a set of texts read there (a digest); nil when nothing changed since.
    def enter_puzzle(place, context, texts) = @puzzle_entries.add?([place, context, texts])

    def screen(place, grid)
      @screens[place] = grid if place.is_a?(Array) && grid.is_a?(Array)
    end

    def absorb(result, frame: nil)
      return unless result.is_a?(Hash)

      @frame = frame if frame
      place = Ledger.place_of(Ledger.pick(result, :from)) or return
      know(place)
      survey = Ledger.pick(result, :survey)
      keep(place, parse_survey(survey).merge(provisional: provisional?(result))) if survey.is_a?(Hash)
      @explored_since_clear << place if (@looks.any? { |_, record| record[:wins].positive? } || Ledger.pick(result, :clears)) && !@explored_since_clear.include?(place)
      note_pocket(place, result)
      side = @entered[place]
      Array(Ledger.pick(result, :exits)).each { |exit| take_exit(place, exit) }
      Array(Ledger.pick(result, :unreachable)).each { |via| cut_off(place, side, via.is_a?(Array) ? via : via.to_s.to_sym) } if side
      drop_unreachable(place, result) if Ledger.pick(result, :dead_end)
      Array(Ledger.pick(result, :offered)).each { |object| offer(place, cell_of(object)) }
      Array(Ledger.pick(result, :walls)).each { |wall| (@walls[place] << cell_of(wall)).uniq! }
      Array(Ledger.pick(result, :clears)).each do |use|
        cell = cell_of(Ledger.pick(use, :target) || {})
        Ledger.pick(use, :effect) ? @failed[place].delete(cell) : (@failed[place] << cell).uniq!
      end
      Array(Ledger.pick(result, :crossed)).each do |row, col, direction|
        delta = Navigation::Planner::DELTAS[direction.to_s.to_sym] or next
        walk(place, [row, col])
        walk(place, [row + delta[0], col + delta[1]])
      end
    end

    # A door is tried from the cell below it, walking up; Link stands on it or just below it when the place changes.
    def self.door_exit(cell, ahead, doors, to)
      door = [cell, ahead].find { |c| doors.include?(c) } || cell
      { row: door[0] + 1, col: door[1], direction: :up, outcome: :left, to:, kind: :door }
    end

    def take_exit(place, exit)
      cell = [Ledger.pick(exit, :row), Ledger.pick(exit, :col)]
      direction = Ledger.pick(exit, :direction)
      return unless cell.all?(Integer) && direction.respond_to?(:to_sym)

      key = [place, cell, direction.to_sym]
      left = Ledger.pick(exit, :outcome).to_s == 'left'
      @exits[key] = left ? TRIED_AT : @exits[key] + 1
      to = Ledger.pick(exit, :to)
      return unless left && to.is_a?(Array) && to.size == 2 && to.all?(Integer)

      surprised = observe_edge(place, edge_key(exit, cell, direction.to_sym), to)
      crossed(place, edge_key(exit, cell, direction.to_sym), to, door: Ledger.pick(exit, :kind).to_s == 'door' || Ledger.pick(exit, :walk_in))
      know(to)
      return if Ledger.pick(exit, :kind).to_s == 'door' || Ledger.pick(exit, :walk_in)

      note_arrival(to, cell, direction.to_sym)
      assume_edge(to, OPPOSITE.fetch(direction.to_sym), place) if OPPOSITE.key?(direction.to_sym) && !surprised
    end

    def note(result, frame: nil)
      @frame = frame if frame
      %i[from to].each { |end_| (place = Ledger.place_of(Ledger.pick(result, end_))) && know(place) }
      from = Ledger.place_of(Ledger.pick(result, :from))
      to = Ledger.place_of(Ledger.pick(result, :to))
      @entered.delete(from) if from && @at && from != @at
      @at = to || from
      @visits[to] += 1 if from && to && from != to
      note_crossing(result)
      note_looks(from, result) if from
      note_stood(from, result) if from
    end

    # Cells Link entered with any skill, which no object fills.
    def note_stood(place, result)
      Array(Ledger.pick(result, :crossed)).each do |row, col, direction|
        delta = Navigation::Planner::DELTAS[direction.to_s.to_sym] or next
        @stood[place] |= [[row, col], [row + delta[0], col + delta[1]]]
      end
    end

    # The tiles capabilities ran on, with the clears that worked and failed; a tile that clears more often than not is a hypothesis elsewhere.
    def note_looks(place, result)
      Array(Ledger.pick(result, :clears)).each do |use|
        cell = cell_of(Ledger.pick(use, :target) || {})
        look = Ledger.pick(use, :look) || (@screens.dig(place, *cell) if cell.all?(Integer))
        next unless look

        record = @looks[look] ||= { wins: 0, losses: 0, first: nil }
        if Ledger.pick(use, :effect)
          record[:wins] += 1
          record[:first] ||= { place:, cell: }
        else
          record[:losses] += 1
        end
      end
    end

    # Cells of a place last explored before any clear whose tile clears more often than not, never walked but next to a walked cell;
    # each names the first clear of its tile and the tile's record.
    def inferred_clearable(place)
      grid = @screens[place]
      return [] if grid.nil? || @explored_since_clear.include?(place)

      walked = @walked.fetch(place, []) | @stood.fetch(place, [])
      Geometry::ROWS.times.to_a.product(Geometry::COLS.times.to_a).filter_map do |cell|
        record = @looks[grid.dig(*cell)]
        next unless record && record[:wins] > record[:losses] && !walked.include?(cell) && !@failed.fetch(place, []).include?(cell)
        next unless Navigation::Planner::DELTAS.values.any? { |dr, dc| walked.include?([cell[0] + dr, cell[1] + dc]) }

        { cell:, look: grid.dig(*cell), source: record[:first], wins: record[:wins], losses: record[:losses] }
      end
    end

    # Without an exit cell, only walk and step cross in the direction they were given; the result's from is where the skill began, not where it crossed.
    STRAIGHT = %w[walk step].freeze

    def note_crossing(result)
      from = Ledger.place_of(Ledger.pick(result, :from))
      to = Ledger.place_of(Ledger.pick(result, :to))
      skill = Ledger.pick(result, :skill).to_s
      return unless from && to && from != to && skill != 'explore'

      exit = Ledger.pick(result, :exit)
      direction = (exit ? Ledger.pick(exit, :direction) : (Ledger.pick(Ledger.pick(result, :params) || {}, :direction) if STRAIGHT.include?(skill)))&.to_s&.to_sym
      return unless OPPOSITE.key?(direction)

      cell = cell_of(exit) if exit
      dr, dc = Navigation::Planner::DELTAS[direction]
      ahead = [cell[0] + dr, cell[1] + dc] if cell&.all?(Integer)
      return take_exit(from, ExploreLog.door_exit(cell, ahead, @surveys.dig(from, :doors) || [], to)) if ahead && ahead[0].between?(0, Geometry::ROWS - 1) && ahead[1].between?(0, Geometry::COLS - 1)

      surprised = observe_edge(from, direction, to)
      crossed(from, direction, to, door: exit && Ledger.pick(exit, :walk_in))
      # A door walk (a house left by its bottom edge) loads the next place instead of scrolling: it says nothing of the side Link arrives by.
      assume_edge(to, OPPOSITE.fetch(direction), from) unless (exit && Ledger.pick(exit, :walk_in)) || surprised
    end

    # A tie goes to the latest destination.
    def self.most_observed(seen) = seen.keys.each_with_index.max_by { |to, index| [seen[to][:count], index] }.first

    # The way back across an edge Link crossed once is assumed until he crosses it; explores that find no exit for it on two visits drop it (a ledge jumped down).
    # Every destination seen through a way is kept: a second one is a contradiction, and a first one other than its hypothesis is a puzzle; both return its kind.
    def observe_edge(place, key, to)
      seen = @observed[[place, key]]
      kind = if seen.empty?
               expected = hypothesis(place, key)
               (@assumed.include?([place, key]) ? 'refuted' : 'unexpected_arrival') if expected && expected[:to] != to
             elsif !seen.key?(to)
               expected = { to: ExploreLog.most_observed(seen), source: 'observed' }
               'contradiction'
             end
      record = seen[to] ||= { count: 0, frames: [] }
      record[:count] += 1
      record[:frames] << @frame if @frame
      @edges[place][key] = ExploreLog.most_observed(seen)
      @assumed.delete([place, key])
      kind ? raise_puzzle(kind, place, key, expected, to) : repeat_puzzle(place, key, to)
      kind
    end

    # A way back assumed from another map is still routed, but a door lands on its own cell, so it predicts nothing.
    def hypothesis(place, key)
      to = @edges[place][key]
      return { to:, source: 'reverse' } if @assumed.include?([place, key]) && to[1] == place[1]

      to = key.is_a?(Symbol) && Geometry.neighbour(place, key)
      { to:, source: 'neighbour' } if to
    end

    def raise_puzzle(kind, place, way, expected, to)
      id = "#{kind}-#{place.join('-')}-#{way.is_a?(Array) ? way.join('-') : way}"
      puzzle = @puzzles[id] ||= { id:, kind:, place:, way:, expected:, observed: { to: }, frames: [] }.tap { |fresh| @pending << fresh }
      puzzle[:frames] << @frame if @frame
    end

    def repeat_puzzle(place, way, to)
      @puzzles.each_value { |puzzle| puzzle[:frames] << @frame if @frame && puzzle[:place] == place && puzzle[:way] == way && puzzle[:observed][:to] == to }
    end

    # Puzzles raised since the last call, for the engine to trace; the landing is where Link stands when it is read, if he is still in the arrival place.
    def new_puzzles(place: nil, cell: nil)
      fresh = @pending.map do |puzzle|
        puzzle[:observed][:landing] ||= cell if cell && place == puzzle[:observed][:to]
        puzzle.dup
      end
      @pending = []
      fresh
    end

    # A rebuilt log keeps the landings of the puzzles already traced and emits only those a fork cut off before their event.
    def resumed(events)
      events.each { |event| (puzzle = @puzzles[event['id']]) && puzzle[:observed][:landing] ||= event.dig('observed', 'landing') }
      traced = events.map { |event| event['id'] }
      @pending.reject! { |puzzle| traced.include?(puzzle[:id]) }
    end

    def visits(place) = @visits[place]

    def puzzles(place = nil) = @puzzles.values.select { |puzzle| place.nil? || puzzle[:place] == place }

    def contradicted?(place, key) = @observed.fetch([place, key], {}).size > 1

    def assume_edge(place, key, to)
      return if @edges[place].key?(key)

      @edges[place][key] = to
      @assumed << [place, key]
    end

    def walked(place) = @walked.fetch(place, []).dup

    def known?(place) = @known.include?(place)

    def surveyed?(place) = @surveys.key?(place) && !@surveys[place][:provisional]

    def side_left?(place, direction) = ways(place).key?(direction.to_sym)

    # A way back assumed and never crossed is still a frontier.
    def side_crossed?(place, direction) = side_left?(place, direction) && !@assumed.include?([place, direction.to_sym])

    def stood(place) = @stood.fetch(place, []).dup

    def door_tried?(place, cell) = tried?(place, [cell[0] + 1, cell[1]], :up)

    # A door Link has walked through, recognised or not as a door object (98/0's way into 189/10 is not one).
    def door_edge?(place, cell) = ways(place).key?(cell)

    def untried?(place)
      surveyed_untried?(place) || inferred_clearable(place).any?
    end

    def surveyed_untried?(place)
      survey = @surveys[place] or return true
      return true if survey[:provisional]
      return survey[:pending] unless survey[:pending].nil?

      survey[:sides].any? { |side, cells| !side_crossed?(place, side) && cells.any? { |cell| !tried?(place, cell, side) } } ||
        survey[:doors].any? { |cell| !door_tried?(place, cell) }
    end

    # skip: places not to aim at (a loop's own places), still crossed on the way.
    def route(from, goal: nil, avoid: [], skip: [])
      hops = path(from, goal:, avoid:, skip:) or return nil
      { goal: hops.last[:to], next: hops.first[:to], via: hops.first[:via] }
    end

    # Where a loop goes when no place has untried work: the reachable place entered least, nearest first, outside the loop.
    def least_visited(from, avoid: [])
      far = hops(from).reject { |place, _| place == from || avoid.include?(place) }
      far.sort_by { |place, count| [@visits[place], count, place] }.each { |place, _| (found = route(from, goal: place)) and return found }
      nil
    end

    # Ways that led to one place first (a way back is assumed only across a crossing its hypothesis predicted), then ways that led to two.
    TIERS = %i[consistent contradicted].freeze

    def path(from, goal: nil, avoid: [], skip: [])
      TIERS.each do |tier|
        found = search(from, goal:, avoid:, skip:, tier:)
        return found if found
      end
      nil
    end

    # A place is searched once per side it is entered by, since a way cut off from one side may be reached from another.
    def search(from, goal:, avoid:, skip:, tier:)
      start = [from, @entered[from]]
      seen = { start => nil }
      queue = [start]
      until queue.empty?
        state = queue.shift
        place, came = state
        return hops_to(seen, state) if place != from && (goal ? place == goal : untried?(place) && !skip.include?(place))

        ways(place).each do |key, to|
          ahead = [to, OPPOSITE[key]]
          next if seen.key?(ahead) || pocket?(to, key) || (place == from && avoid.include?(key)) || beyond?(tier, place, key) ||
                  @cut_off.include?([place, came, key])

          seen[ahead] = [state, key]
          queue << ahead
        end
      end
      nil
    end

    def beyond?(tier, place, key) = tier == :consistent && contradicted?(place, key)

    # A bench edge replaces an assumed way back, never a way the run crossed.
    def ways(place)
      benched = @bench[:edges].filter_map { |(where, key), to| [key, to] if where == place && !@observed.key?([place, key]) }.to_h
      @edges.fetch(place, {}).merge(benched) { |key, own, bench| @observed.key?([place, key]) ? own : bench }
    end

    # The cell an exit lands on in the next place; a call that finds nothing to do there while some place still has work, or
    # whose route has no reachable exit on two visits (an enemy may block it once), shows the landing is a closed pocket: routes must not
    # enter it, and Link leaves a landing suspected or known as one the way he came.
    def note_arrival(to, cell, direction)
      return unless OPPOSITE.key?(direction)

      @arrivals[[to, OPPOSITE.fetch(direction)]] = case direction
                                                   when :up then [Geometry::ROWS - 1, cell[1]]
                                                   when :down then [0, cell[1]]
                                                   when :left then [cell[0], Geometry::COLS - 1]
                                                   else [cell[0], 0]
                                                   end
    end

    def note_pocket(place, result)
      from = Ledger.pick(result, :from)
      cell = [Ledger.pick(from, :row), Ledger.pick(from, :col)]
      side = landing_side(place, cell) or return
      return if @through.include?([place, side])

      idle = Ledger.pick(result, :stopped_by).to_s == 'no_frontier' && Ledger.pick(result, :cells_walked).to_i.zero?
      @pockets[[place, cell]] ||= side if ((idle && route(place)) || Ledger.pick(result, :dead_end)) && again?(@suspects, [place, cell], place)
    end

    def pocket_side(place, cell) = @pockets[[place, cell]] || (landing_side(place, cell) if @suspects.key?([place, cell]))

    def pocket?(to, key) = key.is_a?(Symbol) && OPPOSITE.key?(key) && !@through.include?([to, OPPOSITE.fetch(key)]) && @pockets.key?([to, @arrivals[[to, OPPOSITE.fetch(key)]]])

    # Leaving a place by another way than the side Link came in by proves that landing leads on: it is never a pocket.
    def crossed(place, way, to, door: false)
      came = @entered[place]
      @cut_off.delete([place, came, way])
      @through << [place, came] if came && came != way && !@through.include?([place, came])
      @entered[to] = (OPPOSITE[way] unless door)
    end

    def landing_side(place, cell) = @arrivals.find { |(where, _), arrival| where == place && arrival == cell }&.dig(0, 1)

    def drop_unreachable(place, result)
      Array(Ledger.pick(result, :unreachable)).each do |via|
        key = via.is_a?(Array) ? via : via.to_s.to_sym
        next unless @assumed.include?([place, key]) && again?(@doubted, [place, key], place)

        @assumed.delete([place, key])
        @edges[place].delete(key)
      end
    end

    # A way no path reaches from the side Link entered by, on two visits, is no longer routed through that side.
    def cut_off(place, side, via)
      key = [place, side, via]
      @cut_off << key if again?(@cut_seen, key, place)
    end

    def again?(seen, key, place)
      return true if seen.key?(key) && seen[key] != @visits[place]

      seen[key] ||= @visits[place]
      false
    end

    def hops(from)
      found = { from => 0 }
      queue = [from]
      until queue.empty?
        place = queue.shift
        ways(place).each do |key, to|
          next if found.key?(to) || pocket?(to, key)

          found[to] = found[place] + 1
          queue << to
        end
      end
      found
    end

    def walls(place) = @walls.fetch(place, []).dup

    # Object cells a capability ran on without clearing them: no longer frontiers there.
    def failed_clears(place) = @failed.fetch(place, []).dup

    def walk(place, cell)
      return unless cell.all?(Integer) && cell[0].between?(0, Geometry::ROWS - 1) && cell[1].between?(0, Geometry::COLS - 1)

      @walls[place].delete(cell)
      @walked[place] << cell unless @walked[place].include?(cell)
    end

    def offer(place, cell)
      @offered << [place, cell] if cell.all?(Integer) && !offered?(place, cell)
    end

    def offered?(place, cell) = @offered.include?([place, cell])

    def tried?(place, cell, direction) = @exits[[place, cell, direction.to_sym]] >= TRIED_AT

    def cell_of(hash) = [Ledger.pick(hash, :row), Ledger.pick(hash, :col)]

    def know(place) = (@known << place unless @known.include?(place))

    def edge_key(exit, cell, direction) = Ledger.pick(exit, :kind).to_s == 'door' ? [cell[0] - 1, cell[1]] : direction

    def hops_to(seen, goal)
      hops = []
      state = goal
      while seen[state]
        hops.unshift({ via: seen[state][1], to: state[0] })
        state = seen[state][0]
      end
      hops
    end

    # A call that left the place after a few cells saw only the strip it arrived by: its survey stands until a longer one replaces it.
    PROVISIONAL_CELLS = 3

    def provisional?(result)
      %w[known_place new_place].include?(Ledger.pick(result, :stopped_by).to_s) && Ledger.pick(result, :cells_walked).to_i < PROVISIONAL_CELLS
    end

    def keep(place, survey)
      @surveys[place] = survey unless survey[:provisional] == true && @surveys[place] && !@surveys[place][:provisional]
    end

    def parse_survey(survey)
      sides = (Ledger.pick(survey, :sides) || {}).to_h do |side, cells|
        [side.to_sym, Array(cells).filter_map { |cell| cell_of(cell) if cell.is_a?(Hash) }]
      end
      { sides:, doors: Array(Ledger.pick(survey, :doors)).filter_map { |cell| cell_of(cell) if cell.is_a?(Hash) }, pending: Ledger.pick(survey, :pending) }
    end

    def tried_exits(place)
      @exits.filter_map { |(where, (row, col), direction), count| { row:, col:, direction: } if where == place && count >= TRIED_AT }
            .sort_by { |exit| [exit[:row], exit[:col], exit[:direction]] }
    end
  end
end
