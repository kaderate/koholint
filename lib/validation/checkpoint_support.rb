# frozen_string_literal: true
# Shared scaffolding for the Session 4 checkpoint scripts (checkpoint_*.rb): boot a fresh
# emulator, save/load a lib/-only Motherboard#dump per checkpoint, and the small room-crossing
# helpers every transition script needs. Not itself a checkpoint script -- require_relative'd by
# each one, same spirit as gemboy's own profiling/utils.rb, just local to koholint.
#
# Needs a gemboy checkout -- path from $GEMBOY_HOME, defaulting to a sibling directory
# (../gemboy relative to this repo's root), per README.md's "Dependency on gemboy".

gemboy_home = ENV.fetch('GEMBOY_HOME', File.expand_path('../../../gemboy', __dir__))
$LOAD_PATH.unshift(File.join(gemboy_home, 'lib'))
$LOAD_PATH.unshift(File.join(gemboy_home, 'profiling'))
require 'pathname'
require 'fileutils'
require 'cartridge_loader'
require 'fake_keys'
require 'motherboard'
require 'utils' # global run_steps -- Navigator.run_cycles calls it bare, see lib/navigator.rb

require_relative '../navigator'
require_relative '../terrain'

module Koholint
  module CheckpointSupport
    CHECKPOINT_DIR = '/tmp/zelda_checkpoints'
    ROM_PATH = File.expand_path('../../roms/zelda_la_dx.gbc', __dir__)

    # Upper bound on frames behind one Navigator.move! call -- it internally taps up to MAX_TAPS
    # times (Navigator.tap's fixed TRIGGER_FRAMES+SETTLE_FRAMES cost each) before giving up.
    MOVE_FRAMES_UPPER_BOUND = Navigator::MAX_TAPS * (Navigator::TRIGGER_FRAMES + Navigator::SETTLE_FRAMES)

    # module_function (not plain `def self.x`) so a checkpoint script can either call these
    # qualified (Koholint::CheckpointSupport.foo) or `include Koholint::CheckpointSupport` and
    # call them bare -- every checkpoint_*.rb script does the latter.
    module_function

    def checkpoint_path(name) = File.join(CHECKPOINT_DIR, "lib_#{name}.dump")

    def room_of(motherboard) = [motherboard.mmu.read(0xFFF6), motherboard.mmu.read(0xFFF7)]

    def boot_fresh
      cartridge = CartridgeLoader.new(ROM_PATH).cartridge
      motherboard = Motherboard.build(cartridge)
      motherboard.mmu.joypad.key_state = FakeKeys.new
      motherboard
    end

    def load_checkpoint(name)
      Motherboard.load(File.binread(checkpoint_path(name)))
    end

    def save_checkpoint(name, motherboard)
      FileUtils.mkdir_p(CHECKPOINT_DIR)
      File.binwrite(checkpoint_path(name), motherboard.dump)
    end

    # Wait N frames with no input, e.g. letting a boot/title/scroll sequence idle-progress.
    def wait_frames(motherboard, frames)
      Navigator.run_cycles(motherboard.cpu, motherboard.ppu, motherboard.apu, frames * Navigator::FRAME_CYCLES)
    end

    # Repeatedly Navigator.move!s `direction`, checking real room identity after every call (never
    # trusting :blocked alone near an edge -- see Navigator.move!'s documented caveat). Mutates
    # `motherboard`. Returns [new_room_or_nil, move_calls_issued] -- room is nil if `max_taps` real
    # move! calls never crossed (caller decides whether that's a genuine wall or needs rerouting);
    # move_calls_issued * MOVE_FRAMES_UPPER_BOUND upper-bounds the frames this call cost, for the
    # trip A->B indicator (PLAN.md) -- move! doesn't report its own exact internal tap count.
    def cross_until_room_change!(motherboard, direction, max_taps: 20)
      start_room = room_of(motherboard)
      max_taps.times do |i|
        Navigator.move!(motherboard, direction)
        room = room_of(motherboard)
        return [room, i + 1] if room != start_room
      end
      [nil, max_taps]
    end

    # Greedy single-axis approach toward `target` (a world pixel coordinate), used to line Link up
    # with a specific exit column/row before crossing it -- same idea as legacy/'s reach_pixel, but
    # lib/-only (Navigator.move! + HRAM position reads, no OAM exclusion list needed since D1).
    # Stops within `tolerance` px, or after `max_steps` move! calls regardless of outcome (a real
    # obstacle short of the target is reported, not retried forever). Returns [final_axis_pos, move_calls_issued].
    def nudge_axis!(motherboard, axis, target, tolerance: 6, max_steps: 20)
      pos_dir, neg_dir = axis == :y ? %i[down up] : %i[right left]
      calls = 0
      max_steps.times do
        current = Navigator.position(motherboard.mmu)[axis]
        delta = target - current
        break if delta.abs <= tolerance

        Navigator.move!(motherboard, delta.positive? ? pos_dir : neg_dir)
        calls += 1
      end
      [Navigator.position(motherboard.mmu)[axis], calls]
    end

    # Advances a dialogue by tapping A once, then probing whether movement is free again --
    # AGENTS.md's "wait for a state condition, not a duration" applied to dialogue, since there's
    # no known memory flag for it (NEXT.md) and a fixed tap count is fragile: a scripted greeting
    # like Marin's doesn't even open until several hundred idle frames pass (measured live this
    # session -- no amount of early A-tapping closes a box that hasn't opened yet), and a fixed
    # count generous enough to cover that risks the opposite failure, re-triggering the SAME
    # dialogue by pressing A again while still facing the NPC after it closes (the crate_room book
    # trap, data/ram_registry.json's crate_room_and_riverside_content). Probing via a real
    # Navigator.move! (not a snapshot probe) is deliberate: once free, that step is genuine
    # progress, not wasted -- the caller doesn't need to separately re-approach afterward.
    # `probe_direction` should be a direction with open floor near the NPC (untested directions
    # risk a false "still blocked" read against real furniture, not dialogue). Mutates
    # `motherboard`; stops as soon as movement succeeds or `max_rounds` A-taps are spent.
    def clear_dialogue!(motherboard, probe_direction: :down, max_rounds: 40)
      max_rounds.times do |i|
        Navigator.tap_button(motherboard, :a)
        return i + 1 if Navigator.move!(motherboard, probe_direction) == :ok
      end
      nil
    end
  end
end
