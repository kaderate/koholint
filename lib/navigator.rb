# frozen_string_literal: true

module Koholint
  # Snapshot-based navigation (D7): every direction test starts from a known in-memory state
  # (Motherboard#dump) and restores after, so collision tests never drift or chain partial
  # slides into each other -- the bug that made legacy/'s move_tiles undercount real movement
  # (see data/ram_registry.json's wram_unmapped.intro_door_gate root_cause_2026_09_07_night:
  # each move_tiles call compares against its own fresh "before" reading, so a real but
  # sub-tile-threshold slide never accumulates into a registered step across repeated calls).
  class Navigator
    TILE_SIZE = 16 # native px per walkable tile grid cell, matches legacy/.../primitives.rb
    COMMIT_THRESHOLD = TILE_SIZE / 2 # a real step resolves to ~14px, not a full 16 -- same
                                      # threshold legacy/.../primitives.rb's move_tiles uses to
                                      # tell a committed step from a collision-bounce
    TRIGGER_FRAMES = 2
    SETTLE_FRAMES = 28
    FRAME_CYCLES = 70_224
    MAX_TAPS = 8 # bound on taps toward one tile before calling it blocked (real tile is ~14px,
                 # smallest observed slide is ~2px, so 8 taps comfortably covers a real step)

    AXIS = { up: :y, down: :y, left: :x, right: :x }.freeze
    SIGN = { up: -1, down: 1, left: -1, right: 1 }.freeze

    def self.position(mmu) = { x: mmu.read(0xFF98), y: mmu.read(0xFF99) }

    # Checkpoints saved right after dialogue/interact() (no run_steps settle -- e.g. legacy/'s
    # after_shield_interior) carry a one-off transitional artifact: the FIRST tap in ANY
    # direction produces the same fixed position shift regardless of which key was pressed
    # (confirmed empirically: up/down/left/right all showed an identical x:56->70 jump on tap 1
    # from the same checkpoint). A pure idle wait does NOT clear it -- only an actual keypress
    # does. Call this once before real probing on a freshly-loaded, unsettled checkpoint.
    def self.settle!(motherboard)
      tap(motherboard, :down)
      motherboard
    end

    # gemboy's run_steps(cpu, ppu, apu, count) takes an *instruction count*, not raw T-cycles --
    # calling it with TRIGGER_FRAMES*FRAME_CYCLES like a cycle target (an earlier version of this
    # method did) asks for that many INSTRUCTIONS, roughly 5.7x more simulated game time than
    # intended (measured: 2,106,720 instructions ~= 171 real frames, not 30). legacy/'s
    # primitives.rb already solved this with its own run_cycles (small instruction chunks,
    # accumulating real cycles until the target is reached) -- same technique, reimplemented here
    # rather than depending on legacy/ code that D5 says gets replaced, not extended.
    def self.run_cycles(cpu, ppu, apu, target_cycles)
      total = 0
      total += run_steps(cpu, ppu, apu, 20) while total < target_cycles
      total
    end

    def self.tap(motherboard, direction)
      keys = motherboard.mmu.joypad.key_state
      cpu, ppu, apu = motherboard.cpu, motherboard.ppu, motherboard.apu
      keys.press(direction)
      run_cycles(cpu, ppu, apu, TRIGGER_FRAMES * FRAME_CYCLES)
      keys.clear
      run_cycles(cpu, ppu, apu, SETTLE_FRAMES * FRAME_CYCLES)
    end

    # Presses `direction` from `motherboard`'s current state, tracking cumulative displacement
    # from the position at entry (not per-tap) -- fixes the creeping-collision undercount.
    # Mutates `motherboard` forward for real; use #probe instead to test without side effects.
    # Returns :ok once TILE_SIZE worth of real progress lands, :blocked after MAX_TAPS with no
    # such progress.
    def self.move!(motherboard, direction)
      axis = AXIS.fetch(direction)
      sign = SIGN.fetch(direction)
      start = position(motherboard.mmu)[axis]

      MAX_TAPS.times do
        tap(motherboard, direction)
        delta = (position(motherboard.mmu)[axis] - start) * sign
        return :ok if delta >= COMMIT_THRESHOLD
      end
      :blocked
    end

    # Same direction test, but from a snapshot: no side effect on `motherboard` regardless of
    # outcome. Returns [:ok | :blocked, restored_motherboard] -- callers must swap to the
    # restored object, since Motherboard.load always builds fresh cpu/ppu/apu/mmu instances.
    def self.probe(motherboard, direction)
      snapshot = motherboard.dump
      result = move!(motherboard, direction)
      [result, Motherboard.load(snapshot)]
    end

    # Probes all 4 directions from `motherboard`'s current state (each independently, from the
    # same starting snapshot -- no order effects, unlike legacy/'s DIRECTIONS-order sensitivity).
    # Returns { up: :ok|:blocked, down: ..., left: ..., right: ... } plus the restored motherboard
    # to continue from (identical state to the one passed in).
    def self.probe_all(motherboard)
      snapshot = motherboard.dump
      edges = {}
      %i[up down left right].each do |dir|
        edges[dir], = probe(Motherboard.load(snapshot), dir)
      end
      [edges, Motherboard.load(snapshot)]
    end
  end
end
