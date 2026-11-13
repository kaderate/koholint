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
        next unless Ledger.pick(event, :type).to_s == 'action'

        result = Ledger.pick(event, :result)
        log.note(result)
        log.absorb(result) if Ledger.pick(event, :skill).to_s == 'explore'
      end
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
    end

    def absorb(result)
      return unless result.is_a?(Hash)

      place = Ledger.place_of(Ledger.pick(result, :from)) or return
      know(place)
      survey = Ledger.pick(result, :survey)
      keep(place, parse_survey(survey).merge(provisional: provisional?(result))) if survey.is_a?(Hash)
      note_pocket(place, result)
      Array(Ledger.pick(result, :exits)).each { |exit| take_exit(place, exit) }
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

      observe_edge(place, edge_key(exit, cell, direction.to_sym), to)
      know(to)
      return if Ledger.pick(exit, :kind).to_s == 'door' || Ledger.pick(exit, :walk_in)

      note_arrival(to, cell, direction.to_sym)
      assume_edge(to, OPPOSITE.fetch(direction.to_sym), place) if OPPOSITE.key?(direction.to_sym)
    end

    def note(result)
      %i[from to].each { |end_| (place = Ledger.place_of(Ledger.pick(result, end_))) && know(place) }
      from = Ledger.place_of(Ledger.pick(result, :from))
      to = Ledger.place_of(Ledger.pick(result, :to))
      @visits[to] += 1 if from && to && from != to
      note_crossing(result)
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

      observe_edge(from, direction, @edges[from].fetch(direction, to))
      # A door walk (a house left by its bottom edge) loads the next place instead of scrolling: it says nothing of the side Link arrives by.
      assume_edge(to, OPPOSITE.fetch(direction), from) unless exit && Ledger.pick(exit, :walk_in)
    end

    # The way back across an edge Link crossed once is assumed until he crosses it; explores that find no exit for it on two visits drop it (a ledge jumped down).
    def observe_edge(place, key, to)
      @edges[place][key] = to
      @assumed.delete([place, key])
    end

    def assume_edge(place, key, to)
      return if @edges[place].key?(key)

      @edges[place][key] = to
      @assumed << [place, key]
    end

    def walked(place) = @walked.fetch(place, []).dup

    def known?(place) = @known.include?(place)

    def surveyed?(place) = @surveys.key?(place) && !@surveys[place][:provisional]

    def side_left?(place, direction) = @edges.fetch(place, {}).key?(direction.to_sym)

    def door_tried?(place, cell) = tried?(place, [cell[0] + 1, cell[1]], :up)

    def untried?(place)
      survey = @surveys[place] or return true
      return true if survey[:provisional]
      return survey[:pending] unless survey[:pending].nil?

      survey[:sides].any? { |side, cells| !side_left?(place, side) && cells.any? { |cell| !tried?(place, cell, side) } } ||
        survey[:doors].any? { |cell| !door_tried?(place, cell) }
    end

    def route(from, goal: nil, avoid: [])
      hops = path(from, goal:, avoid:) or return nil
      { goal: hops.last[:to], next: hops.first[:to], via: hops.first[:via] }
    end

    def path(from, goal: nil, avoid: [])
      seen = { from => nil }
      queue = [from]
      until queue.empty?
        place = queue.shift
        return hops_to(seen, place) if place != from && (goal ? place == goal : untried?(place))

        @edges.fetch(place, {}).each do |key, to|
          next if seen.key?(to) || pocket?(to, key) || (place == from && avoid.include?(key))

          seen[to] = [place, key]
          queue << to
        end
      end
      nil
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
      idle = Ledger.pick(result, :stopped_by).to_s == 'no_frontier' && Ledger.pick(result, :cells_walked).to_i.zero?
      return @pockets[[place, cell]] ||= side if idle && route(place)

      @pockets[[place, cell]] ||= side if Ledger.pick(result, :dead_end) && again?(@suspects, [place, cell], place)
    end

    def pocket_side(place, cell) = @pockets[[place, cell]] || (landing_side(place, cell) if @suspects.key?([place, cell]))

    def pocket?(to, key) = key.is_a?(Symbol) && OPPOSITE.key?(key) && @pockets.key?([to, @arrivals[[to, OPPOSITE.fetch(key)]]])

    def landing_side(place, cell) = @arrivals.find { |(where, _), arrival| where == place && arrival == cell }&.dig(0, 1)

    def drop_unreachable(place, result)
      Array(Ledger.pick(result, :unreachable)).each do |via|
        key = via.is_a?(Array) ? via : via.to_s.to_sym
        next unless @assumed.include?([place, key]) && again?(@doubted, [place, key], place)

        @assumed.delete([place, key])
        @edges[place].delete(key)
      end
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
        @edges.fetch(place, {}).each_value do |to|
          next if found.key?(to)

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
      place = goal
      while seen[place]
        hops.unshift({ via: seen[place][1], to: place })
        place = seen[place][0]
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
