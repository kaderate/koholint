require 'json'
require 'fileutils'
require 'koholint/config'
require 'koholint/entities'
require 'koholint/geometry'
require 'koholint/perception'
require 'koholint/probes/entity_census'
require 'koholint/probes/mode_census'
require 'koholint/vision/dialogue_shot'

module Koholint
  module Probes
    module ObjectCensus
      OUT_DIR = File.join(Config::ROOT, 'tmp', 'objects')
      STANDING = { up: [1, 0], down: [-1, 0], left: [0, 1], right: [0, -1] }.freeze
      FACE_FRAMES = 6
      PRESS_FRAMES = 2
      RESPONSE_FRAMES = 8
      CONTROL_FRAMES = 10
      PAGE_FRAMES = 120
      SAMPLES_PER_OBJECT = 6
      CROSS_FRAMES = 40
      CROSS_EXTRA_FRAMES = 20
      SETTLE_FRAMES = 120
      BORDER = { up: ->(i) { [0, i] }, down: ->(i) { [Geometry::ROWS - 1, i] }, left: ->(i) { [i, 0] }, right: ->(i) { [i, Geometry::COLS - 1] } }.freeze
      ADDR = Perception::ADDRESSES
      ROOM = Entities::ADDRESSES.fetch(:room_objects)

      module_function

      def census(run_dir, frames, crawl: 0, out: OUT_DIR)
        tested = Hash.new(0)
        frames.map do |frame|
          start = ModeCensus.copy(ModeCensus.state_at(run_dir, frame))
          settled?(start)
          rooms = crawl.positive? ? crawl(start, crawl) : [start]
          report = { run: File.basename(run_dir), frame:, rooms: rooms.map { |emulator| scan(emulator, tested:, out:) } }
          write(File.join(out, "#{File.basename(run_dir)}-#{frame}#{crawl.positive? ? "-crawl#{crawl}" : ''}.json"), report)
        end
      end

      def objects(emulator) = Array.new(Geometry::ROWS) { |row| Array.new(Geometry::COLS) { |col| emulator.read(ROOM + (row * Entities::ROOM_ROW_STRIDE) + col) } }

      def place(emulator) = [emulator.read(ADDR.fetch(:room_id)), emulator.read(ADDR.fetch(:map_id))]

      # Entities are cleared in the copy so that only background objects can answer A.
      def bare(emulator)
        copy = ModeCensus.copy(emulator)
        Entities::SLOTS.times { |slot| ModeCensus.poke(copy, ADDR.fetch(:entity_status) + slot, 0) }
        copy
      end

      def scan(emulator, tested: Hash.new(0), cells: nil, out: OUT_DIR)
        base = bare(emulator)
        grid = objects(base)
        hits = []
        (cells || Geometry::ROWS.times.to_a.product(Geometry::COLS.times.to_a)).each do |row, col|
          id = grid[row][col]
          next if tested[id] >= SAMPLES_PER_OBJECT

          STANDING.each do |side, (drow, dcol)|
            stand = [row + drow, col + dcol]
            next unless stand[0].between?(0, Geometry::ROWS - 1) && stand[1].between?(0, Geometry::COLS - 1)

            tested[id] += 1
            hit = read_at(base, stand, side) or next
            tested[id] = -Float::INFINITY unless hit[:control]
            hits << { cell: [row, col], side:, object: id, **hit, page: shot(hit.delete(:copy), place(base), [row, col], side, out) }
          end
        end
        { place: place(base), objects: grid, hits: }
      end

      def read_at(base, stand, side)
        copy = ModeCensus.copy(base)
        EntityCensus.place_link(copy, *Geometry.center_of(*stand))
        FACE_FRAMES.times { copy.step([side]) }
        control = ModeCensus.copy(copy)
        PRESS_FRAMES.times { copy.step([:a]) }
        return unless opens?(copy, RESPONSE_FRAMES)

        { control: opens?(control, CONTROL_FRAMES), copy: }
      end

      def opens?(copy, frames)
        frames.times.any? do
          copy.step([])
          EntityCensus.dialog?(copy)
        end
      end

      def shot(copy, place, cell, side, out)
        PAGE_FRAMES.times { copy.step([]) }
        path = File.join(out, 'pages', "#{place.join('-')}-#{cell.join('-')}-#{side}.png")
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, copy.frame_png)
        File.basename(path)
      end

      def crawl(start, limit)
        seen = {}
        queue = [start]
        found = []
        until queue.empty? || found.size >= limit
          emulator = queue.shift
          next if seen[place(emulator)]

          seen[place(emulator)] = true
          found << emulator
          BORDER.each_key do |side|
            nxt = cross(emulator, side)
            queue << nxt if nxt && !seen[place(nxt)]
          end
        end
        found
      end

      def cross(emulator, side)
        from = place(emulator)
        span = %i[up down].include?(side) ? Geometry::COLS : Geometry::ROWS
        (0...span).sort_by { |i| [(i - ((span - 1) / 2.0)).abs, i] }.each do |i|
          copy = bare(emulator)
          EntityCensus.place_link(copy, *Geometry.center_of(*BORDER.fetch(side).(i)))
          CROSS_FRAMES.times { copy.step([side]) }
          next if place(copy) == from || place(copy)[1] != from[1]

          CROSS_EXTRA_FRAMES.times { copy.step([side]) }
          return copy if settled?(copy) && copy.read(ADDR.fetch(:hp)).positive?
        end
        nil
      end

      def settled?(copy)
        SETTLE_FRAMES.times do
          state = Perception.read(copy)
          return true if state.game_mode == PLAY_MODE && state.game_submode == 7 && state.room_transition.to_i.zero?

          copy.step([])
        end
        false
      end

      def write(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report))
        path
      end
    end
  end
end
