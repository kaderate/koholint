require 'json'
require 'koholint'

module Koholint
  module Geometry
    ROWS = 8
    COLS = 10
    CELL = 16
    ALIGN_TOLERANCE = 4
    DEFAULT_PATH = File.expand_path('../../data/geometry.json', __dir__)

    module_function

    def cell_for(x, y)
      return nil unless x && y

      row = (y - 8) / CELL
      col = x / CELL
      [row, col] if row.between?(0, ROWS - 1) && col.between?(0, COLS - 1)
    end

    def center_of(row, col) = [(col * CELL) + 8, (row * CELL) + 16]

    def offset(x, y, cell)
      cx, cy = center_of(*cell)
      [x - cx, y - cy]
    end

    def aligned?(x, y, cell, axis: :both)
      dx, dy = offset(x, y, cell)
      case axis
      when :x then dx.abs <= ALIGN_TOLERANCE
      when :y then dy.abs <= ALIGN_TOLERANCE
      when :both then dx.abs <= ALIGN_TOLERANCE && dy.abs <= ALIGN_TOLERANCE
      else raise ArgumentError, "unknown axis #{axis.inspect}"
      end
    end

    def fact(name, path = DEFAULT_PATH)
      JSON.parse(File.read(path)).fetch(name.to_s).fetch('value')
    end
  end
end
