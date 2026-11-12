require 'json'
require 'koholint/probes/object_census'

module Koholint
  module Probes
    module DoorCensus
      OUT_DIR = File.join(Config::ROOT, 'tmp', 'doors')
      WALK_FRAMES = 60
      SAMPLES_PER_OBJECT = 2
      SETTLE_FRAMES = 120
      PLAY_SUBMODE = 7

      module_function

      def census(run_dir, frames, out: OUT_DIR)
        frames.map do |frame|
          start = ModeCensus.copy(ModeCensus.state_at(run_dir, frame))
          ObjectCensus.settled?(start)
          report = { run: File.basename(run_dir), frame:, **scan(start) }
          ObjectCensus.write(File.join(out, "#{File.basename(run_dir)}-#{frame}.json"), report)
        end
      end

      def scan(emulator, cells: nil)
        base = ObjectCensus.bare(emulator)
        grid = ObjectCensus.objects(base)
        from = ObjectCensus.place(base)
        tested = Hash.new(0)
        tries = (cells || (0...Geometry::ROWS - 1).to_a.product(Geometry::COLS.times.to_a)).filter_map do |row, col|
          id = grid[row][col]
          next if tested[id] >= SAMPLES_PER_OBJECT

          tested[id] += 1
          { cell: [row, col], object: id, entered: enter(base, [row, col], from) }.compact
        end
        { place: from, objects: grid, tries: }
      end

      def enter(base, cell, from)
        copy = ModeCensus.copy(base)
        EntityCensus.place_link(copy, *Geometry.center_of(cell[0] + 1, cell[1]))
        auto = false
        (WALK_FRAMES + SETTLE_FRAMES).times do |i|
          state = Perception.read(copy)
          if !auto && (state.door_walk_in? || state.game_submode != PLAY_SUBMODE)
            return nil unless state.cell == cell

            auto = true
          end
          return arrival(copy) if [state.room_id, state.map_id] != from && state.room_transition.to_i.zero?
          return nil if !auto && (i >= WALK_FRAMES || state.room_transition.to_i.positive? || (state.cell && state.cell[0] < cell[0]))

          copy.step(auto ? [] : [:up])
        end
        nil
      end

      def arrival(copy) = ObjectCensus.settled?(copy) ? ObjectCensus.place(copy) : nil
    end
  end
end
