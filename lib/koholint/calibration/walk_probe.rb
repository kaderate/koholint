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

        copy = Emulator.restore(emulator.dump)
        before = Perception.read(copy)
        held, idle = schedule(method, frames)
        held.times { copy.step([direction]) }
        idle.times { copy.step }
        after = Perception.read(copy)
        summarize(direction, before, after, held + idle)
      end

      def schedule(method, frames)
        return [TAP_HOLD_FRAMES, (frames || TAP_FRAMES) - TAP_HOLD_FRAMES] if method == :tap

        [frames || HOLD_FRAMES, HOLD_SETTLE_FRAMES]
      end

      def summarize(direction, before, after, frames)
        axis, sign = AXES.fetch(direction)
        room_changed = [before.room_id, before.map_id] != [after.room_id, after.map_id]
        delta = (after[axis] - before[axis]) * sign
        { moved: !room_changed && delta >= 1, from: { x: before.x, y: before.y }, to: { x: after.x, y: after.y },
          room_changed:, hp_delta: after.hp - before.hp, frames: }
      end
    end
  end
end
