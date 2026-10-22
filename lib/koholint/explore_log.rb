require 'koholint/geometry'
require 'koholint/ledger'
require 'koholint/navigation/planner'

module Koholint
  class ExploreLog
    TRIED_AT = 2

    def self.from_events(events)
      log = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action' && Ledger.pick(event, :skill).to_s == 'explore'

        log.absorb(Ledger.pick(event, :result))
      end
      log
    end

    def initialize
      @exits = Hash.new(0)
      @offered = []
      @walked = Hash.new { |hash, key| hash[key] = [] }
      @walls = Hash.new { |hash, key| hash[key] = [] }
    end

    def absorb(result)
      return unless result.is_a?(Hash)

      place = Ledger.place_of(Ledger.pick(result, :from)) or return
      Array(Ledger.pick(result, :exits)).each do |exit|
        cell = [Ledger.pick(exit, :row), Ledger.pick(exit, :col)]
        direction = Ledger.pick(exit, :direction)
        next unless cell.all?(Integer) && direction.respond_to?(:to_sym)

        key = [place, cell, direction.to_sym]
        @exits[key] = Ledger.pick(exit, :outcome).to_s == 'left' ? TRIED_AT : @exits[key] + 1
      end
      Array(Ledger.pick(result, :offered)).each { |object| offer(place, cell_of(object)) }
      Array(Ledger.pick(result, :walls)).each { |wall| (@walls[place] << cell_of(wall)).uniq! }
      Array(Ledger.pick(result, :crossed)).each do |row, col, direction|
        delta = Navigation::Planner::DELTAS[direction.to_s.to_sym] or next
        walk(place, [row, col])
        walk(place, [row + delta[0], col + delta[1]])
      end
    end

    def walked(place) = @walked.fetch(place, []).dup

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

    def tried_exits(place)
      @exits.filter_map { |(where, (row, col), direction), count| { row:, col:, direction: } if where == place && count >= TRIED_AT }
            .sort_by { |exit| [exit[:row], exit[:col], exit[:direction]] }
    end
  end
end
