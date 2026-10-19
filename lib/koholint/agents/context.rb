require 'json'
require 'koholint/vision/grid'

module Koholint
  module Agents
    module Context
      LEGEND = 'Legend: . passable, # blocked, ? unknown, ! stale, ~ one-way, o static object, @ Link'.freeze
      DIRECTIONS = %i[up right down left].freeze
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
      RESULT_LIMIT = 6

      def self.build(state:, grid:, objective:, history:, attempts:, manual:, last_results:, max_chars: 6000)
        link = [(state.y - 8) / 16, state.x / 16]
        results = last_results.last(RESULT_LIMIT).map { |r| r.transform_keys(&:to_sym) }
        head = header(state, link)
        fixed = [head, grid_block(grid, link), neighbours(grid, link, results), objective_block(objective, attempts)]
        finished = history.map { |h| "- #{h[:id]} #{h[:outcome]}#{h[:reason] ? " (#{h[:reason]})" : ''}: #{h[:title]}" }
        lines = results.map { |r| "- #{result_line(r)}" }
        notes = manual.to_s
        loop do
          text = render(fixed, finished, lines, notes)
          return text if text.size <= max_chars

          if finished.any? then finished.shift
          elsif lines.any? then lines.shift
          elsif !notes.empty? then notes = notes[0, [notes.size - (text.size - max_chars), 0].max]
          else return text
          end
        end
      end

      def self.render(fixed, finished, lines, notes)
        sections = fixed.dup
        sections << "Finished objectives:\n#{finished.join("\n")}" if finished.any?
        sections << "Last skill results:\n#{lines.join("\n")}" if lines.any?
        sections << "Manual notes:\n#{notes}" unless notes.empty?
        sections.join("\n\n")
      end
      private_class_method :render

      def self.header(state, link)
        ["Phase: #{state.phase}", "Place: room #{state.room_id}, map #{state.map_id}",
         "Link: row #{link[0]}, col #{link[1]} (pixel x=#{state.x}, y=#{state.y}), facing #{state.direction}",
         "Health: #{state.hp} of #{state.max_hp}"].join("\n")
      end
      private_class_method :header

      def self.grid_block(grid, link)
        rows = (0...Vision::Grid::ROWS).map do |row|
          cells = (0...Vision::Grid::COLS).map { |col| [row, col] == link ? '@' : symbol(grid, row, col) }
          format(' %d  %s', row, cells.join(' '))
        end
        ["Grid (rows 0-7 top to bottom, cols 0-9 left to right):", "    #{(0...Vision::Grid::COLS).to_a.join(' ')}", *rows,
         LEGEND, 'Unknown cells are not walls.'].join("\n")
      end
      private_class_method :grid_block

      def self.beliefs_of(grid, row, col) = DIRECTIONS.map { |d| grid.passable(row, col, d) }

      def self.symbol(grid, row, col)
        return 'o' if grid.static_sprite(row, col)

        found = beliefs_of(grid, row, col).uniq
        if found.include?(:yes) && found.include?(:no) then '~'
        elsif found.include?(:stale) then '!'
        elsif found.include?(:yes) then '.'
        elsif found.include?(:no) then '#'
        else '?'
        end
      end
      private_class_method :symbol

      def self.neighbours(grid, link, results)
        rows = DIRECTIONS.map do |direction|
          row = link[0] + DELTAS[direction][0]
          col = link[1] + DELTAS[direction][1]
          unless row.between?(0, Vision::Grid::ROWS - 1) && col.between?(0, Vision::Grid::COLS - 1)
            next "- #{direction}: edge of the screen"
          end

          "- #{direction}: cell (#{row},#{col}) '#{symbol(grid, row, col)}', belief #{grid.passable(row, col, direction)}, " \
            "last walk: #{last_walk(results, direction)}"
        end
        "Neighbours of Link:\n#{rows.join("\n")}"
      end
      private_class_method :neighbours

      def self.last_walk(results, direction)
        found = results.reverse.find { |r| r[:skill].to_s == 'walk' && r[:params].to_h.transform_keys(&:to_sym)[:direction].to_s == direction.to_s }
        return 'none' unless found

        "#{found[:stopped_by]} after #{found[:moved_cells]} #{found[:moved_cells] == 1 ? 'cell' : 'cells'}"
      end
      private_class_method :last_walk

      def self.objective_block(objective, attempts)
        return 'Current objective: none' unless objective

        lines = ["Current objective: #{objective[:title]}", "Predicate: #{objective[:predicate].to_json}"]
        lines << "Attempts on this objective:\n#{attempts.map { |a| "- #{a}" }.join("\n")}" if attempts.any?
        lines.join("\n")
      end
      private_class_method :objective_block

      def self.result_line(r)
        "#{r[:skill]} #{r[:params].to_json}: stopped_by #{r[:stopped_by]}, #{r[:frames]} frames, moved #{r[:moved_cells]} cells, " \
          "room_changed #{r[:room_changed]}, hp_delta #{r[:hp_delta]}, dialogue open before #{r[:dialog_before]}, after #{r[:dialog_after]}"
      end
      private_class_method :result_line
    end
  end
end
