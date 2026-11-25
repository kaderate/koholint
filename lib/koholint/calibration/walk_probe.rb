require 'koholint/emulator'
require 'koholint/perception'

module Koholint
  module Calibration
    module WalkProbe
      AXES = { up: [:y, -1], down: [:y, 1], left: [:x, -1], right: [:x, 1] }.freeze
      METHODS = %i[tap hold].freeze
      TAP_HOLD_FRAMES = 2
      TAP_FRAMES = 30
      HOLD_FRAMES = 120
      HOLD_SETTLE_FRAMES = 10

      module_function

      def run(emulator, direction:, method: :tap, frames: nil)
        raise ArgumentError, "unknown direction #{direction.inspect}" unless AXES.key?(direction)
        raise ArgumentError, "unknown method #{method.inspect}" unless METHODS.include?(method)

        held, idle = schedule(method, frames)
        bytes = emulator.dump
        probe = Emulator.restore(bytes)
        before = Perception.read(probe)
        held.times { probe.step([direction]) }
        idle.times { probe.step }
        summarize(direction, before, Perception.read(probe), control(bytes, held + idle), held + idle)
      end

      # The idle control run from one state is the same for every direction probed from it, so the last one is kept.
      def control(bytes, frames)
        return @control[:after] if @control && @control[:frames] == frames && @control[:bytes] == bytes

        emulator = Emulator.restore(bytes)
        frames.times { emulator.step }
        (@control = { bytes:, frames:, after: Perception.read(emulator) })[:after]
      end

      def schedule(method, frames)
        return [TAP_HOLD_FRAMES, (frames || TAP_FRAMES) - TAP_HOLD_FRAMES] if method == :tap

        [frames || HOLD_FRAMES, HOLD_SETTLE_FRAMES]
      end

      def summarize(direction, before, after, control, frames)
        axis, sign = AXES.fetch(direction)
        room_changed = before.place != after.place
        delta = (after[axis] - before[axis]) * sign
        inconclusive = [control.x, control.y, control.room_id, control.map_id] != [before.x, before.y, before.room_id, before.map_id]
        { moved: !inconclusive && !room_changed && delta >= 1, from: { x: before.x, y: before.y }, to: { x: after.x, y: after.y },
          room_changed:, inconclusive:, hp_delta: after.hp - before.hp, frames: }
      end
    end
  end
end
