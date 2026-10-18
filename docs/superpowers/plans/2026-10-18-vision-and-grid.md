# Koholint Screen Vision and Collision Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A dedicated vision mechanism that turns the game screen into a per-screen snapshot, builds a collision grid from it that stays correct as screens change and as Link gains abilities, and shows that grid in the live view.

**Architecture:** Three layers kept apart. (1) `ScreenVision` reads VRAM/OAM into a deterministic `ScreenSnapshot` of cells with *appearances* (pixel-pattern signatures), no meaning attached. (2) `Beliefs` store evidence about what each appearance affords (walk, push, swim, hurt…), conditioned on Link's capabilities at test time and on direction; passability is *derived* from beliefs plus current capabilities, `unknown` is never `blocked`, and a belief gathered under other capabilities becomes `stale`. (3) The engine records `screen`, `screen_changed` and `affordance` events in the trace; the `Grid`/`World` views are derived from the trace at any frame. The `Calibration` module may use emulator snapshot/restore probes to measure the game's own collision (owner decision), and only there.

**Tech Stack:** Ruby 4.0.1, minitest, emu-gb via the existing `Emulator` adapter, stdlib only.

**Spec:** `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md` (World model schema, Skill registry); v1 facts: `git show v1-archive:DECISIONS.md` D7, D8, D9, D10 and `git show v1-archive:lib/terrain.rb`.

## Global Constraints

- Everything in the repo is English; comments almost none (one-line hidden *why*); commits one imperative line, no body; short hash syntax (`{ buttons:, frames: }`) wherever key and local match.
- Time is the frame; no wall clock in game logic. Replay stays bit-exact.
- **Boundary (owner decision, 2026-10-18): emulator snapshot/restore may be used only to build the collision grid (`Koholint::Calibration`), never in anything an agent decides with.** No code under `lib/koholint/policies/`, `decision.rb` or the agent-facing context may require `calibration/`. A probe must leave the real emulator bit-exact (state hash equal before and after). No RAM write to gameplay state anywhere (D12), probes move Link with inputs only.
- No game knowledge in code: no tile-ID table, no appearance names ("water", "wall"); appearances are opaque ids. What the manual says goes in agent prompts, never in the model. Knowledge is per run (no persisted global tables).
- Facts about the screen (v1, to be re-verified by tests, not trusted): BG tilemap base `0x9800`/`0x9C00` chosen by LCDC (`0xFF40`) bit 3; scroll `SCX 0xFF43`, `SCY 0xFF42` in pixels (>>3 for tiles), tilemap is a 32x32 wraparound canvas; tile numbering/data addressing mode from LCDC bit 4; the visible play area is 10 columns x 8 rows of 16x16 px cells (2x2 tiles each), the bottom rows are the HUD; tile IDs are reused with different meaning between rooms, tile *pixel patterns* are what compare across rooms; static OAM sprites can block movement on walkable background (D10), mobile sprites are not obstacles.
- Tests: `rake test` (parallel, one process per file, ~45 s); ROM tests use `skip_without_rom!` and `EmulatorCache` (`playable`, `at`); no new runtime dependency; `rake test` takes no `TEST=` (run one file with `ruby --yjit -Ilib -Itest test/x_test.rb`).

## Review Focus

- Scrolled screens: reading the tilemap without the scroll offset silently returns another screen's content (v1 bug). A scrolled screen must give the same snapshot as the equivalent unscrolled content.
- A dialogue box or other overlay over the screen must not be recorded as the world changing.
- `unknown` never behaves as `blocked`, and `blocked` under capabilities A is `stale`, not final, under capabilities B.
- One-way cells (ledges) and 8 px doorway granularity (v1 caveats): passability is per direction, a cell can be passable one way only.
- A probe leaves the real run untouched: state hash identical before/after, journal and trace not affected, no Link position write.

---

### Task 1: ScreenVision: tilemap to appearance grid

**Files:** Create `lib/koholint/vision/screen_snapshot.rb`, `lib/koholint/vision/screen_vision.rb`; Test `test/screen_vision_test.rb`

**Interfaces:**
- Produces: `Vision::ScreenSnapshot = Struct(:frame, :place, :scroll, :cells, :sprites, :overlay)`; `cells` is an Array of 8 rows x 10 columns of `Vision::Cell = Struct(:appearance, :tiles)` where `appearance` is a short opaque String (hex digest, 8 chars) of the four tiles' 16-byte pixel patterns in reading order and `tiles` the four tile numbers; `sprites` is an Array of `{x:, y:, tile:, attr:, pattern:}` from OAM (`pattern` = appearance of the sprite's tile bytes), `place` is `[room_id, map_id]`, `scroll` `[scx, scy]`, `overlay` a Boolean (true when a window/dialogue layer covers part of the playfield). `Vision::ScreenVision.snapshot(reader, place:) -> ScreenSnapshot` where `reader` responds to `read(addr) -> Integer` (the `Emulator` does). `ScreenSnapshot#terrain_hash` (SHA256 hex of the cells' appearances and the overlay flag, excluding sprites), `#objects_hash` (sprites only).

- [ ] **Step 1: Tests (no ROM, fake reader).** Build a hash-backed fake reader with a controlled tilemap, tile data and OAM: (a) 8x10 grid dimensions; (b) two tiles with different numbers but identical pixel bytes give the same `appearance`, same number with different bytes give different appearances; (c) scroll rebasing: the same content placed at scroll (0,0) and at scroll (96,128) with the tilemap shifted accordingly yields equal `appearance` grids and equal `terrain_hash`; (d) wraparound at 32 tiles; (e) tile data addressing modes (LCDC bit 4 both ways) select the right bytes; (f) `terrain_hash` ignores sprites, `objects_hash` ignores cells. **ROM test:** on `EmulatorCache.playable` the starting house snapshot has dimensions 8x10, `place == [163, 16]`, a small number of distinct appearances (assert `<= 12`), and is identical when computed twice.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Commit** `Add ScreenVision: screen snapshots with pixel-pattern appearances`

### Task 2: Overlays and change detection

**Files:** Create `lib/koholint/vision/screen_diff.rb`; Modify `lib/koholint/vision/screen_vision.rb`; Test `test/screen_diff_test.rb`

**Interfaces:**
- Consumes: Task 1. Produces: `Vision::ScreenDiff.between(before, after) -> Array<{row:, col:, from:, to:}>` (changed appearances; empty when `terrain_hash` equal); overlay detection (`snapshot.overlay`) from the window layer registers (LCDC bit 5, WX/WY), with snapshots whose `overlay` is true never diffed (`ScreenDiff.between` returns `nil` meaning "not comparable"). `ScreenVision.snapshot` flags overlay.

- [ ] **Step 1: Tests.** Fake reader: one changed cell is reported with its row/col and both appearances; identical screens give `[]`; a snapshot with the window layer enabled has `overlay == true` and `between` returns `nil`. **ROM test (empirical):** boot with `BootScript` to the playable state, then keep running the existing `Policies::StartGame` + `WalkAndTalk` for ~900 frames; at every 10th frame take a snapshot; record in the test which frames have `overlay == true`. The test asserts that for every pair of consecutive non-overlay snapshots in the same place with no scroll change the diff is empty (no phantom changes from the HUD, sprites or Link) and that if a dialogue appeared at all (the start sequence has one in the house) at least one overlay frame was observed. If the empirical result contradicts the window-register assumption, say so in the report and adapt the detection to what the registers/tilemap actually show; do not weaken the test.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5: Commit** `Detect overlays and diff screen snapshots`

### Task 3: Beliefs: affordances conditioned on capabilities and direction

**Files:** Create `lib/koholint/vision/capabilities.rb`, `lib/koholint/vision/beliefs.rb`; Test `test/beliefs_test.rb`

**Interfaces:**
- Produces: `Vision::Capabilities.new(items = [])` (value object, `==`/`hash`/`to_a`, order-insensitive; later plans fill it from perception); `Vision::Beliefs.new`; `#record(appearance:, action:, direction:, result:, method:, context:, frame:, source:)` where `result` ∈ `:yes | :no`, `action` ∈ `:walk | :push | :swim | …` (free symbol), `direction` ∈ `:up|:down|:left|:right|nil`, `context` a `Capabilities`; `#query(appearance:, action:, direction:, context:) -> :yes | :no | :unknown | :stale` (rules: evidence under the same context decides, `yes` wins over `no` only if more recent and same method class, a direction-specific record beats a direction-less one; evidence only under other contexts gives `:stale`; none gives `:unknown`); `#evidence_for(appearance, action) -> Array`; `Beliefs.from_events(events)` rebuilds from `affordance` trace events (Task 4).

- [ ] **Step 1: Tests.** `unknown_is_not_blocked`; `blocked_without_swim_is_stale_with_swim` (water-like opaque appearance `"a1"`: `walk :no` under `Capabilities.new([])` queries `:no` under `[]` and `:stale` under `['swim']`; after a `walk :yes` record under `['swim']` the query under `['swim']` is `:yes` and under `[]` is still `:no`); `one_way_ledge` (`walk :yes` going `:down`, `:no` going `:up` queried per direction; direction-less query on a direction-split appearance returns `:unknown`); `latest_evidence_wins_within_a_context`; `evidence_keeps_provenance`; capabilities equality ignores order.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5: Commit** `Add affordance beliefs conditioned on capabilities and direction`

### Task 4: Trace events and the derived world view

**Files:** Modify `lib/koholint/trace.rb`; Create `lib/koholint/vision/world.rb`; Test `test/world_test.rb`, `test/trace_test.rb`

**Interfaces:**
- Consumes: Tasks 1-3. Produces: new trace types with required fields: `screen{place, terrain_hash, objects_hash, grid, static_sprites}` (`grid` = the 8x10 appearance matrix as nested arrays; `static_sprites` = Array of `{x:, y:, pattern:}` in OAM coordinates, only sprites the grid builder judged static), `screen_changed{place, cells}` (`cells` as in `ScreenDiff`), `affordance{appearance, action, direction, result, method, context, source}`, `grid_contradiction{place, row, col, direction, believed, observed}`. `Vision::World.from_events(events, at_frame: nil) -> World` (only events with `frame <= at_frame`): `#places -> Hash[[room,map] => {visits:, grid:, terrain_hash:, first_frame:, last_frame:}]`, `#beliefs -> Beliefs`, `#grid_for(place, capabilities) -> Vision::Grid`; `Vision::Grid` (8 rows x 10 columns) with `#appearance(row, col) -> String`, `#static_sprite(row, col) -> String | nil` and `#passable(row, col, direction) -> :yes | :no | :unknown | :stale` combining the background appearance and a static sprite on that cell (`static_sprites` of the latest `screen` event map to cells with row = (y - 16) / 16 and col = (x - 8) / 16, integer division, OAM offsets 16 and 8, ignoring those off the 8x10 grid; a cell with a static sprite is `:no` only if beliefs say so for the sprite pattern under the `walk` action, otherwise `:unknown`, never blocked by default: D10 third state).

- [ ] **Step 1: Tests.** Hand-built event lists: `at_frame` truncates both places and beliefs (a belief recorded at frame 500 is absent at `at_frame: 400`: this is the fork property); two visits to one place count visits and keep the latest grid; stale propagation through `grid_for` with different capabilities; sprite cells default to `:unknown`; every new trace type rejects a missing required field.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5: Commit** `Record screens and affordances in the trace and derive the world from it`

### Task 5: Calibration probes (snapshot/restore, collision measurement only)

**Files:** Create `lib/koholint/calibration/walk_probe.rb`; Test `test/walk_probe_test.rb`, `test/calibration_boundary_test.rb`

**Interfaces:**
- Consumes: `Emulator#dump`/`Emulator.restore`, `Perception`. Produces: `Calibration::WalkProbe.run(emulator, direction:, method: :tap | :hold, frames:) -> {moved:, from:, to:, room_changed:, hp_delta:, frames:}` which dumps the emulator, applies the direction input for `frames` (tap: press then settle; hold: sustained), reads Link's position/room/hp before and after, restores the emulator it was given (or works on a restored copy and leaves the original untouched; choose one, state it) so the caller's emulator state hash is unchanged. `moved` means the position changed along the axis by at least 1 px without a room change; a room change reports `room_changed: true`.

- [ ] **Step 1: Tests.** (ROM) from `EmulatorCache.playable`: `state_hash` identical before and after every probe, journal-independent (the probe never touches a `Run`); probing each of the four directions from the starting position yields `moved` true for at least one and false for at least one (the room has walls); a `:hold` probe against a wall agrees with a `:tap` probe (both not moved); probe results are deterministic (run twice, equal). **Boundary test (no ROM):** a static check that no file under `lib/koholint/policies/` nor `lib/koholint/decision.rb` mentions `Calibration`, and that `lib/koholint/calibration/` does not call any emulator memory *write*.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5: Commit** `Add snapshot-restore walk probes for collision calibration`

### Task 6: Grid builder: observation (screens, static sprites, grid in the context)

**Files:** Create `lib/koholint/vision/grid_builder.rb`; Modify `lib/koholint/engine.rb`, `lib/koholint/cli.rb`; Test `test/grid_builder_test.rb`, `test/engine_test.rb`

**Interfaces:**
- Consumes: Tasks 1-4. Produces: `Vision::GridBuilder.new(trace:, capabilities: Vision::Capabilities.new)`; `#observe(emulator, state) -> Vision::Grid | nil` called by the Engine once per iteration right after perception when the engine option `grid: true` (default false; CLI `run --grid`): takes `ScreenVision.snapshot(emulator, place: [state.room_id, state.map_id])`; when the snapshot is an overlay returns nil, emits nothing and forgets its sprite tracking; otherwise tracks sprites across consecutive observations (a sprite with the same x, y and pattern seen in two consecutive non-overlay observations of the same place is static) and, when the place, the `terrain_hash` or the set of static sprites changed since the last `screen` event it emitted, emits `screen` (and `screen_changed` with `ScreenDiff.between(previous_emitted, current)` when comparable); returns the `Grid` built from the builder's latest snapshot, its in-memory `Beliefs` (empty in this task) and the capabilities; the engine passes it to policies as `context[:grid]` (nil when none). Hard rule: the builder only OBSERVES: it never steps or writes the emulator, so a run with `grid: true` and the same run with `grid: false` have identical journals and state hashes.

- [ ] **Step 1: Tests.** Unit (fake emulator/trace): overlay snapshots emit nothing and return nil; a first observation emits `screen` with `static_sprites: []`; a second observation of the same screen emits nothing; a sprite seen at the same x/y/pattern twice becomes static and triggers a new `screen`; a terrain change emits `screen` then `screen_changed` with the changed cells. (ROM) engine run of ~400 frames starting from `EmulatorCache.interactive` (pass `emulator:` to `Engine`) with `StartGame`+`WalkAndTalk` and `grid: true`: journal bytes and final `state_hash` equal to the same run with `grid: false`; the trace has `screen` events for place `[163, 16]` and no `screen` event whose grid was taken during a dialogue (use the overlay frames); `Replay.verify` reports no divergence; `context[:grid]` reaches the policy (a recording policy sees a `Grid`).
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Observe screens and static sprites in the engine`

### Task 7: Grid builder: probing and contradictions

**Files:** Modify `lib/koholint/vision/grid_builder.rb`, `test/calibration_boundary_test.rb`; Test `test/grid_builder_probe_test.rb`

**Interfaces:**
- Consumes: Tasks 5-6. Produces: in `#observe`, for each of Link's four neighbouring cells (the cell reached by going one cell in a direction from the cell containing Link) whose background appearance, or static sprite pattern, has an `:unknown` or `:stale` `:walk` belief under the current capabilities, run `Calibration::WalkProbe` with `method: :hold` long enough to cross one cell (about 16 px; measure Link's speed, it was about 0.5 px per frame in the starting house, and decide the frame count by experiment) and record: `:yes` when Link's cell index changed toward that direction (he entered the neighbour cell), `:no` when he stopped without entering it, nothing (and no belief) when the probe is `inconclusive` or the result is ambiguous; emit an `affordance` event (`source: 'probe'`, `method: 'hold'`) and feed the in-memory beliefs; known appearances are never re-probed for the same direction and context. Link-to-cell mapping must be determined by experiment (compare Link's OAM sprite position with the HRAM x, y used by `Perception`, and the room's visible layout), written down in the report and covered by a test. Contradictions: when between two iterations Link's cell changed to a cell the grid believed `:no` for that direction, emit `grid_contradiction`. The boundary test is updated: `engine.rb` still must not mention Calibration (the grid builder, under `lib/koholint/vision/`, may), policies and `decision.rb` still must not, and the policies receive only the `Grid` data object.

- [ ] **Step 1: Tests.** (ROM, `EmulatorCache.interactive`) the builder probes only unknown/stale neighbour appearances, each at most once per direction and context; probe results match direct movement (from the interactive start: up and down and left are open, right is a wall; the matching beliefs are `:yes`, `:yes`, `:yes`, `:no` for the corresponding neighbour appearances); after the capabilities change (a different `Capabilities`) a previously `:no` belief is re-probed; the engine run with probing on and off yields identical journals and state hashes; a stub-belief contradiction emits `grid_contradiction`; `Replay.verify` still clean. **Unit:** cell mapping function at known positions.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Probe unknown neighbour cells and flag grid contradictions`

### Task 8: Grid overlay in the live view

**Files:** Modify `lib/koholint/viewer/feed.rb`, `lib/koholint/viewer/page.html`; Test `test/feed_test.rb`, `test/page_test.rb`

**Interfaces:**
- Consumes: Task 4 `World`, existing `Feed`/`Follower`. Produces: `/state.json` gains `grid` = `{place:, cells: [[:yes|:no|:unknown|:stale ...] x10] x8, appearances: [[id...]], frame:}` derived with `World.from_events(trace_events, at_frame: follower.frame).grid_for(...)` for the follower's current frame (empty/null before any `screen` event); the page gets a toggle "Grid" that draws the grid over the frame (canvas or CSS grid over the 480x432 image: passable green, blocked red, unknown grey, stale orange, semi-transparent, appearance id on hover/title) and a legend; default off, choice remembered like the format toggle.

- [ ] **Step 1: Tests.** Feed with a hand-built trace containing `screen` and `affordance` events returns the expected `grid` for the follower frame and an older grid for an earlier frame; no `screen` event gives `grid: nil`; page: pure formatting/color-mapping functions tested through `node` like the existing page tests, `id="grid"` toggle present with `localStorage`. **Manual check (report it):** run `bin/koholint run --realtime --grid --frames 3000 --root <tmp>` and `watch`, fetch `/state.json`, confirm a plausible grid for room 163/16, view `/frame.png` with the Read tool and check that blocked cells match walls and furniture you can see.
- [ ] **Step 2–4:** FAIL → implement → PASS. **Step 5: Commit** `Show the collision grid over the live view`

---

## Self-review against the discussion
- Dedicated vision mechanism per screen: Tasks 1-2. Screens evolve over time: `screen`/`screen_changed` events, diff, overlay exclusion, latest-snapshot-wins and `World.at(frame)` (Tasks 2, 4, 6). Impassable can become passable: capability-conditioned, direction-aware beliefs with `:stale` (Task 3, tested with the swim scenario). Calibration boundary enforced by a static test (Task 5).
- Explicitly not in this plan: actions beyond probing, the agent loop and Jev/Claude contracts, entities/dialogue/leads, milestones and inventory-based capabilities (capabilities stay an empty set until a later plan reads them from perception), push/swim real tests.
- Next plan: generic actions and the first agent loop (exit the starting house, measured in frames, calls and cost) using `context[:grid]`.
