require 'digest'
require 'fileutils'
require 'json'
require 'zlib'
require 'koholint/boot_script'
require 'koholint/config'
require 'koholint/emulator'
require 'koholint/input_log'
require 'koholint/keyframes'
require 'koholint/modes'
require 'koholint/perception'

module Koholint
  module Probes
    module ModeCensus
      TUPLE = Modes::TUPLE_FIELDS
      WATCH = %i[inventory_cursor menu_option inventory_slot_a inventory_slot_b hp].freeze
      RAM_RANGES = [0xC000..0xDFFF, 0xFF80..0xFFFE].freeze
      OUT_DIR = File.join(Config::ROOT, 'tmp', 'census')
      # Probe-only: the game's pending-damage counter, written in a throwaway copy to reach the game-over screen.
      DAMAGE_BUFFER = 0xDB94
      HOLD = 8
      TAP = 3
      SETTLE = 60
      ALL = %i[a b start select].freeze

      SCENARIOS = {
        start_menu: [[:start, HOLD], [nil, 90], [:right, TAP], [nil, 20], [:down, TAP], [nil, 20], [:start, HOLD], [nil, 90]],
        start_menu_buttons: [[:start, HOLD], [nil, 90], [:b, HOLD], [nil, 30], [:a, HOLD], [nil, 30], [:b, HOLD], [nil, 30],
                             [:select, HOLD], [nil, SETTLE], [:start, HOLD], [nil, 90]],
        select_map: [[:select, HOLD], [nil, 150], [:right, HOLD], [nil, 30], [:up, HOLD], [nil, 30], [:a, HOLD], [nil, SETTLE],
                     [:b, HOLD], [nil, SETTLE], [:b, HOLD], [nil, 120]],
        select_map_select: [[:select, HOLD], [nil, 150], [:start, HOLD], [nil, 30], [:select, HOLD], [nil, 120]],
        select_tap: [[:select, TAP], [nil, 150]],
        save_screen: [[ALL, 10], [nil, 100], [:down, HOLD], [nil, 30], [:up, HOLD], [nil, 30], [:a, HOLD], [nil, 120]],
        save_screen_b: [[ALL, 10], [nil, 100], [:b, HOLD], [nil, 120]],
        save_and_quit: [[ALL, 10], [nil, 100], [:down, HOLD], [nil, 30], [:a, HOLD], [nil, 200]],
        game_over: [[:damage, 1], [nil, 420], [:down, HOLD], [nil, 30], [:down, HOLD], [nil, 30], [:a, HOLD], [nil, 300]],
        game_over_first: [[:damage, 1], [nil, 420], [:a, HOLD], [nil, 300]],
        game_over_quit: [[:damage, 1], [nil, 420], [:down, HOLD], [nil, 30], [:a, HOLD], [nil, 200]]
      }.freeze

      CURSORS = {
        inventory: { open: [[:start, HOLD], [nil, 90]], moves: %i[right right down left up up], press: TAP },
        map: { open: [[:select, HOLD], [nil, 150]], moves: %i[left right up down down], press: HOLD },
        save: { open: [[ALL, 10], [nil, 100]], moves: %i[down up down down up], press: HOLD },
        game_over: { open: [[:damage, 1], [nil, 420]], moves: %i[down down up up up], press: HOLD }
      }.freeze

      module_function

      def state_at(run_dir, frame, cache: File.join(OUT_DIR, 'states'))
        path = File.join(cache, "#{File.basename(run_dir)}-#{frame}.zlib")
        return Keyframes.load(path) if File.file?(path)

        emulator = replay(run_dir, frame)
        FileUtils.mkdir_p(cache)
        File.binwrite(path, Zlib::Deflate.deflate(emulator.dump))
        emulator
      end

      def replay(run_dir, frame)
        keyframes = File.join(run_dir, 'keyframes')
        nearest = Keyframes.new(keyframes).nearest_at_or_before(frame) if File.directory?(keyframes)
        emulator = nearest ? Keyframes.load(nearest.last) : Emulator.boot
        InputLog.new(File.join(run_dir, 'inputs.log')).each_frame.with_index do |buttons, index|
          next if index < emulator.frame
          break if emulator.frame >= frame

          emulator.step(buttons)
        end
        emulator
      end

      def copy(emulator) = Emulator.restore(emulator.dump)

      def tuple(emulator) = Perception.read(emulator).to_h.slice(*TUPLE)

      def watched(emulator) = WATCH.to_h { |name| [name, emulator.read(Perception::ADDRESSES.fetch(name))] }

      def screen(emulator) = Digest::SHA256.hexdigest(emulator.frame_rgb)[0, 12]

      def ram(emulator) = RAM_RANGES.flat_map { |range| range.map { |addr| emulator.read(addr) } }

      def addresses = RAM_RANGES.flat_map(&:to_a)

      def poke(emulator, addr, value) = emulator.instance_variable_get(:@driver).motherboard.mmu.write(addr, value)

      def step(emulator, button)
        return poke(emulator, DAMAGE_BUFFER, 0xFF) if button == :damage

        emulator.step(Array(button))
      end

      def run_steps(emulator, steps)
        steps.each { |button, frames| frames.times { step(emulator, button) } }
      end

      def label(state) = Modes.for(state)&.name || 'unknown'

      def record(emulator, steps)
        probe = copy(emulator)
        start = probe.frame
        rows = []
        last = nil
        steps.each do |button, frames|
          frames.times do
            step(probe, button)
            state = Perception.read(probe)
            row = { **state.to_h.slice(*TUPLE), mode: label(state), **watched(probe) }
            next if row == last

            rows << { at: probe.frame - start, input: Array(button).map(&:to_s), **row, screen: screen(probe) }
            last = row
          end
        end
        { start: tuple(emulator), rows:, end: tuple(probe) }
      end

      def cursor(emulator, open:, moves:, press:, settle: 30)
        probe = copy(emulator)
        run_steps(probe, open)
        snapshots = [ram(probe)]
        moves.each do |button|
          run_steps(probe, [[button, press], [nil, settle]])
          snapshots << ram(probe)
        end
        { moves:, mode: label(Perception.read(probe)), candidates: candidates(snapshots, moves.size) }
      end

      def candidates(snapshots, moves)
        addrs = addresses
        (0...addrs.size).filter_map do |i|
          values = snapshots.map { |snapshot| snapshot[i] }
          next if values.each_cons(2).count { |a, b| a != b } < moves

          { addr: format('0x%04X', addrs[i]), values: }
        end
      end

      def boot(frames: 2400, idle: 300)
        idle_run = Emulator.boot
        scripted = Emulator.boot
        { idle: transitions(idle_run, frames) { [] },
          late_start: transitions(scripted, frames) { |state| scripted.frame < idle ? [] : BootScript.macro_for(state)[:buttons] } }
      end

      def transitions(emulator, frames)
        rows = []
        frames.times do
          emulator.step(yield(Perception.read(emulator)))
          state = Perception.read(emulator)
          row = { **state.to_h.slice(*TUPLE), mode: label(state) }
          rows << { frame: emulator.frame, **row } unless rows.last&.except(:frame) == row
        end
        rows
      end

      def census(run_dir, frames, out: OUT_DIR)
        FileUtils.mkdir_p(out)
        frames.map do |frame|
          emulator = state_at(run_dir, frame)
          report = { run: File.basename(run_dir), frame:, start: tuple(emulator), mode: label(Perception.read(emulator)),
                     scenarios: SCENARIOS.transform_values { |steps| record(emulator, steps) },
                     cursors: CURSORS.transform_values { |spec| cursor(emulator, **spec) } }
          write(File.join(out, "#{File.basename(run_dir)}-#{frame}.json"), report)
        end
      end

      def census_boot(out: OUT_DIR) = write(File.join(out, 'boot.json'), boot)

      def write(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report))
        path
      end
    end
  end
end
