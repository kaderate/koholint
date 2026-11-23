require 'json'
require 'koholint'

module Koholint
  module Geometry
    ROWS = 8
    COLS = 10
    CELL = 16
    ALIGN_TOLERANCE = 4
    DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
    DIRECTIONS = DELTAS.keys.freeze
    # The grid builder's probes and fall records and the exit bench iterate in this order; DIRECTIONS would reorder their trace events.
    VERTICAL_FIRST = %i[up down left right].freeze
    OPPOSITE = { up: :down, down: :up, left: :right, right: :left }.freeze
    DEFAULT_PATH = File.expand_path('../../data/geometry.json', __dir__)

    module_function

    def cell_for(x, y)
      return nil unless x && y

      row = (y - 8) / CELL
      col = x / CELL
      [row, col] if in_grid?([row, col])
    end

    def in_grid?(cell) = cell[0].between?(0, ROWS - 1) && cell[1].between?(0, COLS - 1)

    def step(cell, direction)
      dr, dc = DELTAS[direction]
      to = [cell[0] + dr, cell[1] + dc] if dr
      to if to && in_grid?(to)
    end

    def center_of(row, col) = [(col * CELL) + 8, (row * CELL) + 16]

    def x_aligned?(dx) = gap_entry.cover?(dx)

    def gap_entry = @gap_entry ||= fact(:gap_entry).then { |gap| gap['min_offset']..gap['max_offset'] }

    def offset(x, y, cell)
      cx, cy = center_of(*cell)
      [x - cx, y - cy]
    end

    def aligned?(x, y, cell, axis: :both)
      dx, dy = offset(x, y, cell)
      case axis
      when :x then x_aligned?(dx)
      when :y then dy.abs <= ALIGN_TOLERANCE
      when :both then x_aligned?(dx) && dy.abs <= ALIGN_TOLERANCE
      else raise ArgumentError, "unknown axis #{axis.inspect}"
      end
    end

    # The screen next to a place across a side, where the measured map layout applies; a hypothesis to compare a first crossing with, never a route.
    def neighbour(place, side)
      layout = @neighbour ||= fact(:overworld_neighbour)
      room, map = place
      delta = DELTAS[side.to_s.to_sym]
      return nil unless delta && layout['maps'].include?(map)

      dr, dc = delta

      width = layout['width']
      row = (room / width) + dr
      col = (room % width) + dc
      [(row * width) + col, map] if row.between?(0, width - 1) && col.between?(0, width - 1)
    end

    def fact(name, path = DEFAULT_PATH)
      JSON.parse(File.read(path)).fetch(name.to_s).fetch('value')
    end
  end
end
