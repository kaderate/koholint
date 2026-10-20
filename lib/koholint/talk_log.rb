require 'koholint/ledger'
require 'koholint/vision/grid'

module Koholint
  class TalkLog
    MAX_ROWS = 2
    MAX_COLS = 2
    ATTEMPT_STOPS = %w[done no_response].freeze

    def self.attempt?(result)
      return false unless result.is_a?(Hash)

      Ledger.pick(result, :talked) == true || ATTEMPT_STOPS.include?(Ledger.pick(result, :stopped_by).to_s)
    end

    def self.from_events(events)
      log = new
      events.each do |event|
        next unless Ledger.pick(event, :type).to_s == 'action' && Ledger.pick(event, :skill).to_s == 'talk_to'

        result = Ledger.pick(event, :result)
        params = Ledger.pick(event, :params)
        place = result.is_a?(Hash) ? Ledger.place_of(Ledger.pick(result, :from)) : nil
        row = Ledger.pick(params, :row)
        col = Ledger.pick(params, :col)
        log.record(place:, row:, col:, talked: Ledger.pick(result, :talked) == true, standing: standing_of(result)) if place && row && col && attempt?(result)
      end
      log
    end

    def self.standing_of(result)
      tried = Ledger.pick(result, :standing_cells_tried)
      if tried.is_a?(Array)
        return tried.filter_map do |entry|
          cell = [Ledger.pick(entry, :row), Ledger.pick(entry, :col)]
          [cell, Ledger.pick(entry, :outcome).to_s == 'no_response'] if cell.all?
        end
      end
      standing = Ledger.pick(result, :standing_cell)
      cell = standing.is_a?(Hash) ? [Ledger.pick(standing, :row), Ledger.pick(standing, :col)] : nil
      cell&.all? ? [[cell, Ledger.pick(result, :stopped_by).to_s == 'no_response']] : []
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
        split(cells.sort)
      end.flatten(1).sort
    end

    def self.split(cells)
      left = cells.dup
      blocks = []
      until left.empty?
        row, col = left.first
        block = left.select { |r, c| r.between?(row, row + MAX_ROWS - 1) && c.between?(col, col + MAX_COLS - 1) }
        left -= block
        blocks << block
      end
      blocks
    end

    def initialize
      @attempts = Hash.new(0)
      @talked = Hash.new(0)
      @silent = Hash.new { |hash, key| hash[key] = [] }
    end

    def record(place:, row:, col:, talked:, standing: [])
      @attempts[[place, [row, col]]] += 1
      @talked[[place, [row, col]]] += 1 if talked
      standing.each do |cell, silent|
        list = @silent[[place, [row, col]]]
        silent ? (list << cell unless list.include?(cell)) : list.delete(cell)
      end
    end

    def failed_sides(place, cell) = @silent.fetch([place, cell], []).dup

    def lines(grid, place, limit: nil)
      objects = self.class.objects(grid)
      stats = objects.to_h { |cells| [cells, [0, 0, []]] }
      @attempts.each do |(where, cell), tried|
        next unless where == place

        owner = owner_of(objects, cell) or next
        stats[owner][0] += tried
        stats[owner][1] += @talked[[where, cell]]
        stats[owner][2] |= @silent.fetch([where, cell], [])
      end
      shown = limit && objects.size > limit ? kept(objects, stats, limit) : objects
      out = shown.map { |cells| "- at #{label(cells)}: #{describe(*stats[cells])}" }
      out << "... #{objects.size - shown.size} more objects" if shown.size < objects.size
      out
    end

    def attempts(place, cells) = cells.sum { |cell| @attempts[[place, cell]] }

    def talked(place, cells) = cells.sum { |cell| @talked[[place, cell]] }

    private

    def owner_of(objects, cell)
      objects.find { |cells| cells.include?(cell) } ||
        objects.select { |cells| cells.any? { |r, c| (r - cell[0]).abs <= 1 && (c - cell[1]).abs <= 1 } }
               .min_by { |cells| cells.map { |r, c| (r - cell[0]).abs + (c - cell[1]).abs }.min }
    end

    def kept(objects, stats, limit)
      tried, untried = objects.partition { |cells| stats[cells][0].positive? }
      (tried + untried).first(limit).sort
    end

    def describe(tried, talked, silent = [])
      return 'never tried' if tried.zero?

      text = "talked to #{tried} #{tried == 1 ? 'time' : 'times'} (dialogue opened #{talked})"
      silent.empty? ? text : "#{text}; no response from #{silent.map { |r, c| "(#{r},#{c})" }.join(', ')}"
    end

    def label(cells)
      return "(#{cells[0][0]},#{cells[0][1]})" if cells.size == 1

      rows = cells.map(&:first)
      cols = cells.map(&:last)
      "(#{rows.min},#{cols.min})-(#{rows.max},#{cols.max})"
    end
  end
end
