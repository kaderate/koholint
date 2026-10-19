require 'json'
require 'koholint/game_state'
require 'koholint/geometry'
require 'koholint/perception'
require 'koholint/vision/grid'

module Koholint
  module Agents
    module Context
      LEGEND = 'Legend: . passable, # blocked, ? unknown, ! stale or doubtful, ~ one-way, o static object, @ Link'.freeze
      DIRECTIONS = %i[up right down left].freeze
      DELTAS = { up: [-1, 0], right: [0, 1], down: [1, 0], left: [0, -1] }.freeze
      RESULT_LIMIT = 6
      MANUAL_LIMIT = 3000
      KEEP_RESULTS = 3
      KEEP_FINISHED = 5
      KEEP_REFUSALS = 3

      def self.build(state:, grid:, objective:, history:, attempts:, manual:, last_results:, max_chars: 9000, ledger: nil, refusals: [], plan: nil)
        link = state.cell
        place = [state.room_id, state.map_id]
        results = last_results.last(RESULT_LIMIT).map { |r| r.transform_keys(&:to_sym) }
        fixed = [header(state, link), grid_block(grid, link, ledger, place), neighbours(grid, link, results, ledger, place), objective_block(objective, attempts, plan)]
        finished = history.map { |h| "- #{h[:id]} #{h[:outcome]}#{h[:reason] ? " (#{h[:reason]})" : ''}: #{h[:title]}" }
        refused = refusals.last(KEEP_REFUSALS).map { |r| "- #{r[:title]} #{r[:predicate].to_json}: #{r[:reason]}" }
        lines = results.map { |r| "- #{result_line(r)}" }
        notes = trim_manual(manual.to_s)
        loop do
          text = render(fixed, finished, refused, lines, notes)
          return text if text.size <= max_chars

          if !notes.empty? then notes = trim_lines(notes, text.size - max_chars)
          elsif finished.size > KEEP_FINISHED then finished.shift
          elsif lines.size > KEEP_RESULTS then lines.shift
          else return text
          end
        end
      end

      def self.trim_manual(notes) = notes.size <= MANUAL_LIMIT ? notes : trim_lines(notes, notes.size - MANUAL_LIMIT)
      private_class_method :trim_manual

      def self.trim_lines(notes, excess)
        keep = notes[0, [notes.size - excess, 0].max]
        cut = keep.rindex("\n")
        cut ? keep[0, cut] : ''
      end
      private_class_method :trim_lines

      def self.render(fixed, finished, refused, lines, notes)
        sections = fixed.dup
        sections << "Finished objectives:\n#{finished.join("\n")}" if finished.any?
        sections << "Refused objectives:\n#{refused.join("\n")}" if refused.any?
        sections << "Last skill results:\n#{lines.join("\n")}" if lines.any?
        sections << "Game manual:\n#{notes}" unless notes.empty?
        sections.join("\n\n")
      end
      private_class_method :render

      def self.header(state, link)
        where = link ? "row #{link[0]}, col #{link[1]}" : 'outside the grid (doorway or screen edge)'
        lines = ["Phase: #{state.phase}", "Place: room #{state.room_id}, map #{state.map_id}",
                 "Link: #{where} (pixel x=#{state.x}, y=#{state.y}), facing #{state.direction}"]
        if link
          dx, dy = Geometry.offset(state.x, state.y, link)
          lines << "Link offset from cell centre (positive = right of / below the centre): dx=#{dx}, dy=#{dy}"
        end
        lines << "Health: #{hearts(state.hp)} of #{hearts(state.max_hp)} hearts"
        lines.join("\n")
      end
      private_class_method :header

      def self.hearts(hp) = (hp.to_f / Perception::HP_PER_HEART).to_s.delete_suffix('.0')
      private_class_method :hearts

      def self.cells(count) = "#{count} #{count == 1 ? 'cell' : 'cells'}"
      private_class_method :cells

      def self.grid_block(grid, link, ledger, place)
        doubt = doubtful_cells(grid, ledger, place, link)
        rows = (0...Vision::Grid::ROWS).map do |row|
          cells = (0...Vision::Grid::COLS).map { |col| [row, col] == link ? '@' : symbol(grid, row, col, doubt) }
          format(' %d  %s', row, cells.join(' '))
        end
        ["Grid (rows 0-7 top to bottom, cols 0-9 left to right):", "    #{(0...Vision::Grid::COLS).to_a.join(' ')}", *rows,
         LEGEND, 'Unknown cells are not walls.'].join("\n")
      end
      private_class_method :grid_block

      def self.beliefs_of(grid, row, col) = DIRECTIONS.map { |d| grid.passable(row, col, d) }

      def self.symbol(grid, row, col, doubt = [])
        return 'o' if grid.static_sprite(row, col)
        return '!' if doubt.include?([row, col])

        found = beliefs_of(grid, row, col).uniq
        if found.include?(:yes) && found.include?(:no) then '~'
        elsif found.include?(:stale) then '!'
        elsif found.include?(:yes) then '.'
        elsif found.include?(:no) then '#'
        else '?'
        end
      end
      private_class_method :symbol

      def self.doubtful_cells(grid, ledger, place, link)
        return [] unless ledger && link

        DIRECTIONS.select { |d| ledger.doubtful?(place, link, d) && grid.passable(link[0] + DELTAS[d][0], link[1] + DELTAS[d][1], d) == :yes }.map { |d| [link[0] + DELTAS[d][0], link[1] + DELTAS[d][1]] }
      end
      private_class_method :doubtful_cells

      def self.neighbours(grid, link, results, ledger, place)
        return "Neighbours of Link:\n- Link is outside the 8x10 grid (doorway or screen edge): no neighbour cells" unless link

        rows = DIRECTIONS.map do |direction|
          row = link[0] + DELTAS[direction][0]
          col = link[1] + DELTAS[direction][1]
          unless row.between?(0, Vision::Grid::ROWS - 1) && col.between?(0, Vision::Grid::COLS - 1)
            next "- #{direction}: edge of the screen"
          end

          shown = symbol(grid, row, col, doubtful_cells(grid, ledger, place, link))
          times = ledger ? ledger.count(place, link, direction) : 0
          blocked = times.positive? ? ", blocked #{times} #{times == 1 ? 'time' : 'times'}" : ''
          "- #{direction}: cell (#{row},#{col}) '#{shown}', belief #{grid.passable(row, col, direction)}, " \
            "last walk: #{last_walk(results, direction)}#{blocked}"
        end
        "Neighbours of Link:\n#{rows.join("\n")}"
      end
      private_class_method :neighbours

      def self.last_walk(results, direction)
        found = results.reverse.find { |r| walked?(r, direction) || blocked_going?(r, direction) }
        return 'none' unless found
        return 'blocked' unless walked?(found, direction)

        "#{found[:stopped_by]} after #{cells(found[:moved_cells])}"
      end
      private_class_method :last_walk

      def self.walked?(r, direction) = r[:skill].to_s == 'walk' && r[:params].to_h.transform_keys(&:to_sym)[:direction].to_s == direction.to_s
      private_class_method :walked?

      def self.blocked_going?(r, direction) = blocked_at(r)&.dig(:direction).to_s == direction.to_s
      private_class_method :blocked_going?

      def self.blocked_at(r) = r[:blocked_at].is_a?(Hash) ? r[:blocked_at].transform_keys(&:to_sym) : nil
      private_class_method :blocked_at

      def self.objective_block(objective, attempts, plan = nil)
        lines = objective ? ["Current objective: #{objective[:title]}", "Predicate: #{objective[:predicate].to_json}"] : ['Current objective: none']
        lines << "Your plan from your last call (written by you; follow it unless the situation changed): #{plan}" if plan
        return lines.join("\n") unless objective

        lines << "Attempts on this objective:\n#{attempts.map { |a| "- #{a}" }.join("\n")}" if attempts.any?
        lines.join("\n")
      end
      private_class_method :objective_block

      def self.result_line(r)
        cause = r[:cause] ? " (cause: #{r[:cause]})" : ''
        line = "#{r[:skill]} #{r[:params].to_json}: stopped_by #{r[:stopped_by]}#{cause}, #{r[:frames]} frames, " \
               "moved #{r[:moved_px] ? "#{r[:moved_px]} px" : cells(r[:moved_cells])}, " \
               "room_changed #{r[:room_changed]}, hp_delta #{r[:hp_delta]}, dialogue open before #{r[:dialog_before]}, after #{r[:dialog_after]}"
        line += ", path #{r[:path_length]}, steps #{r[:steps_done]}, aligned #{r[:aligned]}" if r[:skill].to_s == 'goto'
        block = blocked_at(r)
        block ? "#{line}, blocked at (#{block[:row]},#{block[:col]}) #{block[:direction]}" : line
      end
      private_class_method :result_line
    end
  end
end
