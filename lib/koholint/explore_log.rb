require 'koholint/geometry'
require 'koholint/ledger'
require 'koholint/navigation/planner'

module Koholint
  class ExploreLog
    TRIED_AT = 2

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
    end

    def absorb(result)
      return unless result.is_a?(Hash)

      place = Ledger.place_of(Ledger.pick(result, :from)) or return
      know(place)
      survey = Ledger.pick(result, :survey)
      @surveys[place] = parse_survey(survey) if survey.is_a?(Hash)
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
    end

    def walked(place) = @walked.fetch(place, []).dup

    def known?(place) = @known.include?(place)

    def side_left?(place, direction) = @edges.fetch(place, {}).key?(direction.to_sym)

    def door_tried?(place, cell) = tried?(place, [cell[0] + 1, cell[1]], :up)

    def untried?(place)
      survey = @surveys[place] or return true
      return survey[:pending] unless survey[:pending].nil?

      survey[:sides].any? { |side, cells| !side_left?(place, side) && cells.any? { |cell| !tried?(place, cell, side) } } ||
        survey[:doors].any? { |cell| !door_tried?(place, cell) }
    end

    def route(from)
      seen = { from => nil }
      queue = [from]
      until queue.empty?
        place = queue.shift
        return first_hop(seen, place, from) if place != from && untried?(place)

        @edges.fetch(place, {}).each do |key, to|
          next if seen.key?(to)

          seen[to] = [place, key]
          queue << to
        end
      end
      nil
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
