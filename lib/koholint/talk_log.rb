require 'koholint/ledger'
require 'koholint/vision/grid'

module Koholint
  class TalkLog
    def self.from_events(events)
      log = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action' && Ledger.pick(event, :skill).to_s == 'talk_to'

        result = Ledger.pick(event, :result)
        params = Ledger.pick(event, :params)
        place = result.is_a?(Hash) ? Ledger.place_of(Ledger.pick(result, :from)) : nil
        row = Ledger.pick(params, :row)
        col = Ledger.pick(params, :col)
        log.record(place:, row:, col:, talked: Ledger.pick(result, :talked) == true) if place && row && col
      end
      log
    end

    def self.objects(grid)
      sprites = (0...Vision::Grid::ROWS).to_a.product((0...Vision::Grid::COLS).to_a).select { |row, col| grid.static_sprite(row, col) }
      seen = {}
      sprites.filter_map do |start|
        next if seen[start]

        cells = []
        queue = [start]
        seen[start] = true
        until queue.empty?
          cell = queue.shift
          cells << cell
          [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dr, dc|
            near = [cell[0] + dr, cell[1] + dc]
            next if seen[near] || !sprites.include?(near)

            seen[near] = true
            queue << near
          end
        end
        cells.sort
      end.sort
    end

    def initialize
      @attempts = Hash.new(0)
      @talked = Hash.new(0)
    end

    def record(place:, row:, col:, talked:)
      @attempts[[place, [row, col]]] += 1
      @talked[[place, [row, col]]] += 1 if talked
    end

    def attempts(place, cells) = cells.sum { |cell| @attempts[[place, cell]] }

    def talked(place, cells) = cells.sum { |cell| @talked[[place, cell]] }

    def lines(grid, place)
      self.class.objects(grid).map do |cells|
        tried = attempts(place, cells)
        what = tried.zero? ? 'never tried' : "talked to #{tried} #{tried == 1 ? 'time' : 'times'} (dialogue opened #{talked(place, cells)})"
        "- at #{label(cells)}: #{what}"
      end
    end

    private

    def label(cells)
      return "(#{cells[0][0]},#{cells[0][1]})" if cells.size == 1

      rows = cells.map(&:first)
      cols = cells.map(&:last)
      "(#{rows.min},#{cols.min})-(#{rows.max},#{cols.max})"
    end
  end
end
