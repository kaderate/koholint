require 'koholint/calibration/walk_probe'
require 'koholint/vision/beliefs'
require 'koholint/vision/capabilities'
require 'koholint/vision/grid'
require 'koholint/vision/screen_diff'
require 'koholint/vision/screen_vision'

module Koholint
  module Vision
    class GridBuilder
      # Link is drawn as two 8x16 sprites at his HRAM position and 8 px to the right, measured within 1 px.
      LINK_SPRITE_OFFSETS = [0, 8].freeze
      LINK_SPRITE_TOLERANCE = 2
      # Link walks about 1 px per frame: 32 frames cross the 16 px to the next cell with a 2x margin.
      PROBE_HOLD_FRAMES = 32
      STEPS = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }.freeze

      def self.link_sprite?(sprite, state)
        (sprite[:y] - state.y).abs <= LINK_SPRITE_TOLERANCE &&
          LINK_SPRITE_OFFSETS.any? { |offset| (sprite[:x] - state.x - offset).abs <= LINK_SPRITE_TOLERANCE }
      end

      # Link's sprites cover x - 8...x + 8 and y - 16...y on screen; walls stop his center out of their cell.
      def self.link_cell(x, y)
        row = (y - 8) / 16
        col = x / 16
        [row, col] if row.between?(0, Grid::ROWS - 1) && col.between?(0, Grid::COLS - 1)
      end

      def initialize(trace:, capabilities: Capabilities.new, beliefs: Beliefs.new, prober: Calibration::WalkProbe)
        @trace = trace
        @capabilities = capabilities
        @beliefs = beliefs
        @prober = prober
        @last = nil
        @stuck = nil
        @previous = nil
        @emitted = nil
        @statics = {}
        @statics_place = nil
      end

      def observe(emulator, state)
        place = [state.room_id, state.map_id]
        snapshot = ScreenVision.snapshot(emulator, place:)
        if snapshot.overlay
          @previous = nil
          @last = nil
          return nil
        end

        settled = @previous && @previous[:place] == place
        current = snapshot.sprites.reject { |sprite| self.class.link_sprite?(sprite, state) }.group_by { |s| [s[:x], s[:y]] }
        track(place, current)
        statics = @statics.map { |(x, y), pattern| { x:, y:, pattern: } }.sort_by { |s| [s[:y], s[:x]] }
        emit(state.frame, snapshot, statics) if changed?(snapshot, statics)
        grid = Grid.new(cells: grid_of(snapshot), static_sprites: statics.map { |s| s.transform_keys(&:to_s) }, beliefs: @beliefs,
                        capabilities: @capabilities)
        cell = self.class.link_cell(state.x, state.y)
        check_contradiction(state.frame, place, cell)
        spot = [place, state.x, state.y]
        @stuck = probe_neighbours(emulator, state.frame, grid, cell) && spot if settled && cell && @prober && @stuck != spot
        @last = cell && { place:, cell:, grid: }
        grid
      end

      private

      # Static identity is the position; after an overlay the last statics stand until two observations are consecutive again.
      def track(place, current)
        if @previous && @previous[:place] == place
          @statics = current.filter_map do |position, sprites|
            [position, [@statics[position], *sprites.map { |s| s[:pattern] }].compact.min] if @previous[:positions].include?(position)
          end.to_h
        elsif @statics_place != place
          @statics = {}
        end
        @statics_place = place
        @previous = { place:, positions: current.keys }
      end

      def changed?(snapshot, statics)
        @emitted.nil? || @emitted[:snapshot].place != snapshot.place ||
          @emitted[:snapshot].terrain_hash != snapshot.terrain_hash || @emitted[:statics] != statics
      end

      def emit(frame, snapshot, statics)
        before = @emitted&.fetch(:snapshot)
        @trace.emit(:screen, frame:, place: snapshot.place, terrain_hash: snapshot.terrain_hash, objects_hash: snapshot.objects_hash,
                             grid: grid_of(snapshot), static_sprites: statics)
        cells = before && ScreenDiff.between(before, snapshot)
        @trace.emit(:screen_changed, frame:, place: snapshot.place, cells:) if cells && !cells.empty?
        @emitted = { snapshot:, statics: }
      end

      def check_contradiction(frame, place, cell)
        return unless @last && cell && @last[:place] == place

        delta = [cell[0] - @last[:cell][0], cell[1] - @last[:cell][1]]
        direction = STEPS.key(delta) or return
        believed = @last[:grid].passable(*cell, direction)
        return unless believed == :no

        @trace.emit(:grid_contradiction, frame:, place:, row: cell[0], col: cell[1], direction: direction.to_s, believed: believed.to_s,
                                         observed: 'entered')
      end

      # All probes share one no-input control: one inconclusive voids all. Link is free only if some direction moves him;
      # returns whether he was shown not free, so the same spot is not reprobed until he moves.
      def probe_neighbours(emulator, frame, grid, cell)
        neighbours = STEPS.to_h { |direction, (drow, dcol)| [direction, [cell[0] + drow, cell[1] + dcol]] }
                          .select { |_, (row, col)| row.between?(0, Grid::ROWS - 1) && col.between?(0, Grid::COLS - 1) }
        unknown = neighbours.select { |direction, target| %i[unknown stale].include?(grid.passable(*target, direction)) }
        return if unknown.empty?

        probes = {}
        (unknown.keys + (neighbours.keys - unknown.keys)).each do |direction|
          break if !unknown.key?(direction) && probes.values.any? { |probe| moved?(probe) }

          probes[direction] = @prober.run(emulator, direction:, method: :hold, frames: PROBE_HOLD_FRAMES)
          return if probes[direction][:inconclusive]
        end
        return true unless probes.values.any? { |probe| moved?(probe) }

        unknown.each do |direction, (row, col)|
          result = walk_result(probes.fetch(direction), cell, direction) or next
          record(grid.static_sprite(row, col) || grid.appearance(row, col), direction, result, frame)
        end
        false
      end

      def moved?(probe) = probe[:room_changed] || probe[:to] != probe[:from]

      def walk_result(probe, cell, direction)
        return if probe[:room_changed] || probe[:hp_delta].negative?

        after = self.class.link_cell(probe[:to][:x], probe[:to][:y]) or return
        return :no if after == cell

        drow, dcol = STEPS.fetch(direction)
        delta = [after[0] - cell[0], after[1] - cell[1]]
        cells = drow.zero? ? delta[1] * dcol : delta[0] * drow
        :yes if cells >= 1 && delta == [drow * cells, dcol * cells]
      end

      def record(appearance, direction, result, frame)
        @beliefs.record(appearance:, action: :walk, direction:, result:, method: 'hold', context: @capabilities, frame:, source: 'probe')
        @trace.emit(:affordance, frame:, appearance:, action: 'walk', direction: direction.to_s, result: result.to_s, method: 'hold',
                                 context: @capabilities.to_a, source: 'probe')
      end

      def grid_of(snapshot) = snapshot.cells.map { |row| row.map(&:appearance) }
    end
  end
end
