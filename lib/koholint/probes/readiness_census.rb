require 'json'
require 'koholint/config'
require 'koholint/emulator'
require 'koholint/input_log'
require 'koholint/perception'
require 'koholint/probes/mode_census'
require 'koholint/vision/screen_vision'

module Koholint
  module Probes
    module ReadinessCensus
      OUT_DIR = ModeCensus::OUT_DIR
      CANDIDATES = [0xC100..0xC1FF, 0xFF80..0xFFBF].freeze
      SIGNALS = %i[room_transition link_airborne link_z link_knockback].freeze
      FORCED_MOTION = [2, 3, 4].freeze
      WINDOW = 30
      SETTLE_FRAMES = 12
      SCREEN = Vision::ScreenVision

      module_function

      def census(run_dir, out: OUT_DIR)
        ModeCensus.write(File.join(out, "readiness-#{File.basename(run_dir)}.json"), report(run_dir))
      end

      def report(run_dir)
        frames = scan(run_dir)
        episodes = episodes(frames)
        { run: File.basename(run_dir), frames: frames.size, episodes:, durations: durations(episodes),
          settle_after_ready: episodes.filter_map { |e| e[:stable_after] }.tally.sort.to_h,
          candidates: candidates(frames) }
      end

      # One row per frame after it was played: the known signals, the candidate bytes and, after a not-ready span, the BG tile indices.
      def scan(run_dir)
        emulator = Emulator.boot
        rows = []
        settle = 0
        InputLog.new(File.join(run_dir, 'inputs.log')).each_frame do |buttons|
          emulator.step(buttons)
          state = Perception.read(emulator)
          row = { frame: emulator.frame, state:, signals: signals(state), bytes: CANDIDATES.flat_map { |r| r.map { |a| emulator.read(a) } }.pack('C*') }
          settle = SETTLE_FRAMES if rows.last && !rows.last[:signals][:ready] && row[:signals][:ready]
          if settle.positive?
            row[:tiles] = tiles(emulator)
            settle -= 1
          end
          rows << row
        end
        rows
      end

      def signals(state)
        values = SIGNALS.to_h { |name| [name, state[name].to_i] }
        forced = FORCED_MOTION.include?(state.link_motion_state.to_i)
        loading = state.loading?
        { **values, forced:, loading:, ready: state.game_mode == PLAY_MODE && !loading && !forced && values.values.all?(&:zero?) }
      end

      def tiles(emulator)
        snapshot = SCREEN.snapshot(emulator, place: nil)
        snapshot.overlay ? :overlay : snapshot.cells.flatten.map(&:tiles)
      end

      def episodes(frames)
        frames.each_index.slice_when { |a, b| frames[a][:signals][:ready] != frames[b][:signals][:ready] }
              .reject { |span| frames[span.first][:signals][:ready] || frames[span.first][:state].game_mode != PLAY_MODE }
              .map { |span| episode(frames, span.first, span.last) }
      end

      def episode(frames, first, last)
        rows = frames[first..last]
        before = frames[[first - 1, 0].max][:state]
        after = frames[[last + 1, frames.size - 1].min][:state]
        { from: rows.first[:frame], to: rows.last[:frame], length: rows.size, kind: kind(rows),
          place: [[before.room_id, before.map_id], [after.room_id, after.map_id]].uniq,
          link_z_max: rows.map { |r| r[:signals][:link_z] }.max, stable_after: stable_after(frames, last) }
      end

      def kind(rows)
        seen = ->(key) { rows.any? { |r| r[:signals][key].is_a?(Integer) ? r[:signals][key].positive? : r[:signals][key] } }
        return 'door' if seen.(:loading)
        return seen.(:link_airborne) ? 'jump_scroll' : 'scroll' if seen.(:room_transition)
        return 'jump' if seen.(:link_airborne)
        return 'knockback' if seen.(:link_knockback)

        seen.(:forced) ? 'forced_walk' : 'other'
      end

      # Frames after the last not-ready frame until the BG tile indices equal those SETTLE_FRAMES frames later.
      def stable_after(frames, last)
        settled = frames[last + 1, SETTLE_FRAMES]
        return nil unless settled && settled.size == SETTLE_FRAMES && settled.all? { |r| r[:tiles] }

        final = settled.last[:tiles]
        (1..SETTLE_FRAMES).find { |k| settled[(k - 1)..].all? { |r| r[:tiles] == final } }
      end

      def durations(episodes)
        episodes.group_by { |e| e[:kind] }.sort.to_h do |kind, group|
          lengths = group.map { |e| e[:length] }.sort
          [kind, { count: group.size, min: lengths.first, median: lengths[lengths.size / 2], max: lengths.last }]
        end
      end

      # Bytes at rest in still free play that move in every room-change window: the transition-state candidates.
      def candidates(frames)
        addrs = CANDIDATES.flat_map(&:to_a)
        changes = (1...frames.size).select { |i| frames[i][:state].room_id != frames[i - 1][:state].room_id && !frames[i][:state].loading? }
        still = frames.each_index.select { |i| i.positive? && frames[i][:signals][:ready] && frames[i][:state].to_h.values_at(:x, :y) == frames[i - 1][:state].to_h.values_at(:x, :y) }
        addrs.each_index.filter_map do |k|
          resting = still.map { |i| frames[i][:bytes].getbyte(k) }.tally.max_by(&:last)&.first
          hits = changes.count { |i| frames[[i - 2, 0].max, WINDOW].any? { |r| r[:bytes].getbyte(k) != resting } }
          rest = still.count { |i| frames[i][:bytes].getbyte(k) == resting }
          next unless changes.any? && hits == changes.size && rest >= still.size * 0.99

          { addr: format('0x%04X', addrs[k]), resting:, room_changes: changes.size, at_rest: "#{rest}/#{still.size}" }
        end
      end
    end
  end
end
