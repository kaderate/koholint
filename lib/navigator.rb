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

    # Press-then-settle for any single button (direction or otherwise), frame-timed like every
    # other Navigator primitive (AGENTS.md: time is frames, never an instruction count). Distinct
    # hold_frames/settle_frames from a direction tap's defaults are for menu/dialogue advancement
    # (large text-box "typing" settle windows), not movement -- movement keeps TRIGGER_FRAMES/
    # SETTLE_FRAMES via #tap below.
    def self.tap_button(motherboard, button, hold_frames: TRIGGER_FRAMES, settle_frames: SETTLE_FRAMES)
      keys = motherboard.mmu.joypad.key_state
      cpu, ppu, apu = motherboard.cpu, motherboard.ppu, motherboard.apu
      keys.press(button)
      run_cycles(cpu, ppu, apu, hold_frames * FRAME_CYCLES)
      keys.clear
      run_cycles(cpu, ppu, apu, settle_frames * FRAME_CYCLES)
    end

    def self.tap(motherboard, direction) = tap_button(motherboard, direction)

    # Presses `direction` from `motherboard`'s current state, tracking cumulative displacement
    # from the position at entry (not per-tap) -- fixes the creeping-collision undercount.
    # Mutates `motherboard` forward for real; use #probe instead to test without side effects.
    # Returns :ok once TILE_SIZE worth of real progress lands, :blocked after MAX_TAPS with no
    # such progress.
    # Known caveat (found 2026-09-08, reaching room 177 from front_yard): on a step that crosses a
    # room boundary, position() rebases onto the new screen, so the old-axis delta can read as
    # under COMMIT_THRESHOLD even though a real transition just happened -- move! returns :blocked
    # while room_id/map_id have actually changed. Check room identity after every call near a
    # screen edge; never infer "nothing happened" from :blocked alone.
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

    # D13: hostile-avoidance primitive. Formalizes the tactic 4 independent Explorer sessions
    # hand-rolled across the Plage Coco cluster (224/0, 225/0, 226/0, 209/0 -- see
    # data/ram_registry.json's room_labels): hold B continuously via mmu.joypad.key_state (not
    # #tap_button, which clears every key between taps and would drop the shield mid-sequence),
    # tap toward a target while biasing away from the nearest hostile/unknown OAM sprite, watch HP.

    OAM_BASE = 0xFE00
    OAM_SPRITE_COUNT = 40
    OAM_HIDDEN_Y_THRESHOLD = 160 # sentinel for "not drawn this frame" -- room_labels['224/0']'s
                                  # post-scroll SCY investigation found y=244 on a hidden Link;
                                  # nothing legitimately on-screen exceeds the 144px LCD height.

    # D11-confirmed hostile family: riverside_south_tan_creature, riverside_south_river_room_sprite,
    # riverside_east_room_creatures. One OAM entry's tile byte per 8x16-mode composite half (tile
    # id is always even -- the odd partner is the auto-paired bottom half, never a raw OAM value).
    # The family cycles through all 6 ids frame to frame (visual_catalog's 4-sample idle log) --
    # one species' animation/facing frames, not 6 distinct creatures.
    HOSTILE_TILE_IDS = [0x60, 0x62, 0x64, 0x66, 0x68, 0x6a].freeze
    # riverside_south_pale_creature: hazard_status "unknown, suggestive of hostile" (D11 contact
    # test inconclusive -- the creature read absent from OAM at both jump instants). Deliberately
    # NOT pulling in every other visual_catalog entry marked "unknown" (e.g.
    # building_screen_flutter_object) -- those have no established contact/damage signature and
    # are outside D13's motivating scope (Plage Coco).
    UNKNOWN_HAZARD_TILE_IDS = [0x6c].freeze
    HAZARD_TILE_IDS = (HOSTILE_TILE_IDS + UNKNOWN_HAZARD_TILE_IDS).freeze

    LINK_HP_ADDRESS = 0xDB5A # wram_unmapped.link_health, verified (D12)

    # Hypothesis, found this session (data/ram_registry.json's wram_unmapped.equipped_b_item):
    # 0xDB00 read 4 on every post-shield checkpoint sampled (8, spanning 6+ rooms and several past
    # sessions) and 0 on a fresh pre-shield boot; 0xDB01 stayed 0 throughout every sample, which is
    # only consistent with "the A slot" since no non-empty A-slot state exists yet to contrast
    # against -- not independently confirmed as the A-slot address.
    EQUIPPED_B_ITEM_ADDRESS = 0xDB00
    SHIELD_ITEM_ID = 4

    HAZARD_PROXIMITY_PX = 40 # ~2.5 tiles -- starts biasing before contact range, not just after it
    AVOIDANCE_WEIGHT = 1.5 # outweighs straight-line progress once a hazard is inside the radius

    UNIT_VECTOR = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }.freeze

    def self.shield_equipped?(mmu) = mmu.read(EQUIPPED_B_ITEM_ADDRESS) == SHIELD_ITEM_ID

    # Raw OAM census, bypassing the PPU bus gate -- plain mmu.read returns 0xFF here outside
    # vblank/HBlank (world_topology.riverside_south_room_adaptive_chase_experiment hit this first).
    # Skips hidden/inactive slots.
    def self.oam_sprites(motherboard)
      mmu = motherboard.mmu
      (0...OAM_SPRITE_COUNT).filter_map do |i|
        base = OAM_BASE + (i * 4)
        y = mmu.debug_read(base)
        next if y.zero? || y >= OAM_HIDDEN_Y_THRESHOLD

        { y:, x: mmu.debug_read(base + 1), tile: mmu.debug_read(base + 2), attrs: mmu.debug_read(base + 3) }
      end
    end

    # D11/visual_catalog-classified hostile-or-unknown OAM sprites within `radius` px of `from`
    # (world/screen pixel units, same frame as #position -- D9 confirmed Link's own OAM position
    # matches his HRAM position exactly in every room checked so far, no +8/+16 offset to correct).
    def self.nearby_hazards(motherboard, from:, radius: HAZARD_PROXIMITY_PX)
      oam_sprites(motherboard).select do |s|
        HAZARD_TILE_IDS.include?(s[:tile]) && Math.hypot(s[:x] - from[:x], s[:y] - from[:y]) <= radius
      end
    end

    # Picks whichever cardinal direction's unit vector best matches `target_direction`'s pull
    # biased away from the single nearest hazard -- a 4-way dot-product choice, not a path search.
    # Pure function of positions (no motherboard access), so it's cheap to exercise standalone.
    def self.biased_direction(link_pos, hazards, target_direction)
      vx, vy = UNIT_VECTOR.fetch(target_direction)
      nearest = hazards.min_by { |h| Math.hypot(h[:x] - link_pos[:x], h[:y] - link_pos[:y]) }
      if nearest
        dx = link_pos[:x] - nearest[:x]
        dy = link_pos[:y] - nearest[:y]
        dist = Math.hypot(dx, dy)
        if dist.positive?
          vx += AVOIDANCE_WEIGHT * dx / dist
          vy += AVOIDANCE_WEIGHT * dy / dist
        end
      end
      UNIT_VECTOR.max_by { |_, (ux, uy)| (ux * vx) + (uy * vy) }.first
    end

    # Same tap loop as #move!, but holds `hold` pressed across every internal tap instead of
    # #tap_button's per-tap clear -- releasing the shield mid-sequence is exactly what left every
    # ad-hoc Plage Coco script's shield mitigating only "most of the time", not reliably
    # (room_labels['225/0']: "a later shield-held attempt... still took a full heart of damage").
    # Not folded into #move! itself, to avoid changing that method's behavior for existing callers.
    def self.move_holding!(motherboard, direction, hold)
      axis = AXIS.fetch(direction)
      sign = SIGN.fetch(direction)
      start = position(motherboard.mmu)[axis]
      keys = motherboard.mmu.joypad.key_state
      cpu, ppu, apu = motherboard.cpu, motherboard.ppu, motherboard.apu
      Array(hold).each { |k| keys.press(k) }
      result = :blocked
      MAX_TAPS.times do
        keys.press(direction)
        run_cycles(cpu, ppu, apu, TRIGGER_FRAMES * FRAME_CYCLES)
        keys.send(:"#{direction}=", false)
        run_cycles(cpu, ppu, apu, SETTLE_FRAMES * FRAME_CYCLES)
        delta = (position(motherboard.mmu)[axis] - start) * sign
        if delta >= COMMIT_THRESHOLD
          result = :ok
          break
        end
      end
      Array(hold).each { |k| keys.send(:"#{k}=", false) }
      result
    end

    def self.shielded_move!(motherboard, direction) = move_holding!(motherboard, direction, :b)

    # The D13 primitive: one avoidance-biased step toward `target_direction`, holding the shield
    # automatically if #shield_equipped?. Hazards are sampled once, before the step -- a wandering
    # creature can still land the family's invisible mid-tap knockback (D11) inside #move!'s/
    # #shielded_move!'s own internal tap loop, same as every ad-hoc script hit; this reports what
    # happened afterward (hp_before/hp_after/damage) rather than assuming the biased direction was
    # ever really safe.
    def self.avoid_hostiles_and_move!(motherboard, target_direction, radius: HAZARD_PROXIMITY_PX)
      mmu = motherboard.mmu
      link_pos = position(mmu)
      hazards = nearby_hazards(motherboard, from: link_pos, radius:)
      chosen = hazards.empty? ? target_direction : biased_direction(link_pos, hazards, target_direction)
      shield = shield_equipped?(mmu)
      hp_before = mmu.read(LINK_HP_ADDRESS)
      result = shield ? shielded_move!(motherboard, chosen) : move!(motherboard, chosen)
      hp_after = motherboard.mmu.read(LINK_HP_ADDRESS)
      { direction: chosen, target_direction:, result:, hazards_seen: hazards.size,
        shield_held: shield, hp_before:, hp_after:, damage: hp_before - hp_after }
    end

    # Repeats #avoid_hostiles_and_move! toward one target direction, stopping before HP would drop
    # to/through `min_hp` -- callers decide whether/how to top HP back up between pushes (D12's
    # scoped Plage Coco permission); this only refuses to walk into a KO by itself. Returns one
    # result hash per step actually taken (see #avoid_hostiles_and_move!).
    def self.avoid_hostiles_and_push!(motherboard, target_direction, max_steps:, min_hp: 4, radius: HAZARD_PROXIMITY_PX)
      results = []
      max_steps.times do
        break if motherboard.mmu.read(LINK_HP_ADDRESS) <= min_hp

        step = avoid_hostiles_and_move!(motherboard, target_direction, radius:)
        results << step
        break if step[:hp_after] <= min_hp
      end
      results
    end
  end
end
