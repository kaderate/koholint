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
      @pockets = []
    end

    def absorb(result)
      return unless result.is_a?(Hash)

      place = Ledger.place_of(Ledger.pick(result, :from)) or return
      know(place)
      survey = Ledger.pick(result, :survey)
      keep(place, parse_survey(survey).merge(provisional: provisional?(result))) if survey.is_a?(Hash)
      note_pocket(place, result)
      Array(Ledger.pick(result, :exits)).each do |exit|
        cell = [Ledger.pick(exit, :row), Ledger.pick(exit, :col)]
        direction = Ledger.pick(exit, :direction)
        next unless cell.all?(Integer) && direction.respond_to?(:to_sym)

        key = [place, cell, direction.to_sym]
        left = Ledger.pick(exit, :outcome).to_s == 'left'
        @exits[key] = left ? TRIED_AT : @exits[key] + 1
        to = Ledger.pick(exit, :to)
        next unless left && to.is_a?(Array) && to.size == 2 && to.all?(Integer)

        @edges[place][edge_key(exit, cell, direction.to_sym)] = to
        note_arrival(to, cell, direction.to_sym) if Ledger.pick(exit, :kind).to_s != 'door'
        @edges[to][OPPOSITE.fetch(direction.to_sym)] ||= place if Ledger.pick(exit, :kind).to_s != 'door' && OPPOSITE.key?(direction.to_sym)
        know(to)
      end
      Array(Ledger.pick(result, :offered)).each { |object| offer(place, cell_of(object)) }
      Array(Ledger.pick(result, :walls)).each { |wall| (@walls[place] << cell_of(wall)).uniq! }
      Array(Ledger.pick(result, :crossed)).each do |row, col, direction|
        delta = Navigation::Planner::DELTAS[direction.to_s.to_sym] or next
        walk(place, [row, col])
        walk(place, [row + delta[0], col + delta[1]])
      end
    end

    def note(result)
      %i[from to].each { |end_| (place = Ledger.place_of(Ledger.pick(result, end_))) && know(place) }
      note_crossing(result)
    end

    # Only walk and step cross in the direction they were given; the result's from is where the skill began, not where it crossed.
    STRAIGHT = %w[walk step].freeze

    def note_crossing(result)
      from_at = Ledger.pick(result, :from)
      from = Ledger.place_of(from_at)
      to = Ledger.place_of(Ledger.pick(result, :to))
      return unless from && to && from != to && STRAIGHT.include?(Ledger.pick(result, :skill).to_s)

      direction = Ledger.pick(Ledger.pick(result, :params) || {}, :direction)&.to_s&.to_sym
      return unless OPPOSITE.key?(direction)

      @edges[from][direction] ||= to
      @edges[to][OPPOSITE.fetch(direction)] ||= from
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

    def route(from, goal: nil)
      seen = { from => nil }
      queue = [from]
      until queue.empty?
        place = queue.shift
        return first_hop(seen, place, from) if place != from && (goal ? place == goal : untried?(place))

        @edges.fetch(place, {}).each do |key, to|
          next if seen.key?(to) || pocket?(to, key)

          seen[to] = [place, key]
          queue << to
        end
      end
      nil
    end

    # The cell an exit lands on in the next place; a call that finds nothing to do there while some place still has work
    # shows the landing is a closed pocket, which routes must not enter.
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
      return unless Ledger.pick(result, :stopped_by).to_s == 'no_frontier' && Ledger.pick(result, :cells_walked).to_i.zero?

      from = Ledger.pick(result, :from)
      cell = [Ledger.pick(from, :row), Ledger.pick(from, :col)]
      return unless route(place)

      @arrivals.each { |(where, side), arrival| @pockets << [where, side] if where == place && arrival == cell && !@pockets.include?([where, side]) }
    end

    def pocket?(to, key) = key.is_a?(Symbol) && OPPOSITE.key?(key) && @pockets.include?([to, OPPOSITE.fetch(key)])

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

    def first_hop(seen, goal, from)
      place = goal
      place = seen[place][0] while seen[place][0] != from
      { goal:, next: place, via: seen[place][1] }
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
