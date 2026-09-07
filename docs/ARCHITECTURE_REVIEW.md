# Architecture and concept review of the spike

Review done on September 7, 2026 on gemboy's `lib/game_agents/` spike, then at 50 commits over 3
days; updated the same day after the exploration branch verified the HRAM hypothesis and mapped
three more screens. Scope: concept and architecture, not a code review. The reviewed code is in
`legacy/`, the concept in `docs/CONCEPT.md`, the log in `docs/archive/EXPLORATION_LOG.md`.

## Verdict

The concept is sound: deterministic execution between decisions, facts read in RAM, LLM only at
decision points, traceable provenance of facts. The spike's code does not implement it. It builds
a blind mapping robot that:

1. reads the game through the wrong layer (PPU: OAM and VRAM) instead of game state (RAM/HRAM);
2. ignores a deterministic emulator's main lever (instant snapshot/restore) and explores like a
   physical robot;
3. pursues a goal the concept does not ask for (exhaustively mapping every cell of every screen) at
   a structural cost of 1.5 to 5h per screen.

After 4 days: 7 screens mapped, 4 NPCs, no sword, no decision loop. The project's value (an LLM
that plays) has not started.

## What holds up and was kept

- **The design document** (`docs/CONCEPT.md`): decoupling execution/decision, code-detected
  triggers, pause-capture, planner/executor split, confidence via `verified_count`.
- **`Zelda::Checkpoint`** (Marshal of the whole emulator state, 0.03s dump / 0.05s load) and
  `Zelda::Scenarios`' chaining. The spike's best technical idea, the foundation for everything
  else. The scenarios' input sequences encode hours of exploration.
- **Validation discipline**: cross-validation between two tools, suspicious data discarded rather
  than committed, fixes revalidated live. Discovering the tile catalog's contamination by
  starting_house's `[3,3]` corner is a real result.
- **Three lasting findings**: the tile scratch-buffer for dialogue text (`0xD0-0xEF`, decode by
  bitmap, never by ID); the tile-locked movement model (a one-frame tap commits ~14px or a bounce,
  over ~24-28 frames); and, after the review, position and room in HRAM.
- **`TilemapReader`**: correct BG reads, mirroring the PPU's own addressing, with the DMG/CGB trap
  identified. Useful for "looking at the screen" as a cross-check.

## Root problem 1 — the observation layer

The concept says "RAM, not vision". The implementation drifted toward "PPU, not RAM":

| Fact | Read by the spike via | Fragility observed |
|---|---|---|
| Link's position | OAM (`find_link`, tile 0/2, exclusion of positions) | slot reassigned, idle pose not recognized, Tarin mistaken for Link, wandering villager |
| Screen change | SCX/SCY, before that a pixel distance | camera panning on screen3, false `:exit` on starting_house |
| Terrain | VRAM tilemap, 8x8 hash + palette | same floor pattern shared between cells with different behavior |
| HUD | window layer | dynamically reconfigured during a dialogue |

OAM and VRAM are the game's *view*, not its *model*. All of `TileClassifier`'s machinery
(cell_for, corner drift, `:lost`, `clear_entry_lock!`, retry budgets) compensates for the absence
of three facts present in memory: Link's real coordinates, room ID, collision.

**Position and room: confirmed.** The spike's two memory-diff hunts had never scanned HRAM. A diff
over the whole `0x0000-0xFFFF` space found, in one pass, `0xFF98` (X), `0xFF99` (Y), `0xFF9E`
(direction), `0xFFF6` (room), and `0xFFF7` (map), matching the community LADX disassembly. Detail
in `data/ram_registry.json`, decision D1.

**Collision: next hypothesis, same method.** The game decodes each room into a 16x16 object grid
(10x8 per screen) in WRAM, and reads each object type's physics from a ROM table. The
empirically-rebuilt tile catalog reconstructs, at 8x8 and by pixel hash, information the game
already stores explicitly at the right level of granularity. That `TileCatalog` needs all 4 tiles
of a cell to agree is already an approximation of the game's own 16x16 object. This is `NEXT.md`'s
next question.

## Root problem 2 — determinism is not exploited

The emulator is deterministic and restoring costs 0.046s. Yet `ScreenMap.build` explores like a
physical robot: walking to the cell, testing a direction, *walking back*
(`walk_back_to_cell!`), a recovery budget per direction, re-navigating from spawn after every
`reset`. Documented consequences in the log: drift, "creep", contamination by direction order
(`up` first changes `down`'s result), the `live_probed` guard, `MAX_RECOVERIES_PER_CELL`, `SKIPPED`
cells, RSS at 1.4GB after 1.75h of file reloads.

With an **in-memory** snapshot per cell (Marshal to a String, not to a file):

- each direction is tested from a strictly identical state, then restored;
- no more walk-back, no more drift, no more order effect: `DIRECTIONS` stops being a parameter;
- the `[3,3]` corner quirk becomes a deterministic, testable, reproducible property of the state,
  rather than a historical accident;
- `live_probed`, recovery budgets, and half of `screen_map.rb` disappear;
- the cost of one direction drops to ~30 emulated frames plus a restore.

This is decision D7.

## Root problem 3 — exhaustive mapping or on-demand navigation

The concept says Explore is "fully scripted, no judgment", not "exhaustive". The spike chose
exhaustive without deciding it explicitly. The cost:

| Measure | Value |
|---|---|
| Screens mapped in 4 days | 7 |
| Cost of one screen (`ScreenMap.build`) | 1.5 to 5h (house2_interior: 2h05 for 27 cells) |
| Skip-rate ceiling imposed by `live_probed` | 75% (one live probe per cell minimum) |
| Best rate observed | 71% (starting_house) |
| Overworld screens in the game | around 256, excluding dungeons and interiors |

The `live_probed` guard contradicts the catalog's promise ("trend toward zero live tests"). A
human player doesn't probe 40 cells, they look at the screen and walk. If collision reads from
WRAM (next question), the probe becomes a cross-check, not the source. Decision D4, owner's call.

## Architecture

**No boundary between emulator and agent.** The primitives are global functions defined on `main`
(`find_link`, `move_tiles`, `tap_key`), the agent boots via gemboy's `profiling/utils.rb`,
`Checkpoint` reaches into private ivars of the APU and CPU. The `[cpu, ppu, apu, mmu, keys]` tuple
threads through every signature and gets reassigned on every reset. What's missing is a **headless
session object on gemboy's side**: advance N frames, press/release, read an address, in-memory
snapshot/restore. `Motherboard` and `debug/headless_emulator.rb` are already two-thirds of it. It
would also serve `test_roms/` and `profiling/`. Decision D6.

**Placement.** A ROM-specific subtree lived in the emulator's `lib/`, outside its own
`ARCHITECTURE.md`, with zero specs while the emulator has 1237, tolerated rubocop offenses, and
essay-comments contrary to its own conventions. Hence this repo, which depends on gemboy like a
gem.

**Time is counted in instructions.** `run_steps(60_000_000)` to wait for boot, `hold: 100_000` for
a keypress, mixed with `TRIGGER_FRAMES * FRAME_CYCLES`. The game samples per frame; the agent
should speak only in frames. Better: wait for a state **condition** (what the concept calls a
trigger) instead of a counter. The scenarios are open-loop timers, fragile to any change in the
emulator's timing. The `villager_screen` checkpoint saved mid-scroll is a symptom of this.

**Three generations of mappers, four coordinate frames.** `Navigator` (static grid + greedy pixel),
`RoomMap::Recorder` (snapped pixel nodes), `ScreenGrid` (16px cells from OAM feet), plus
`world_model.json.map_graph` written by hand. No canonical frame: screens are named "screen2" by
discovery order, `:exit` edges connect nothing. `0xFFF6` gives the key and the world graph for
free.

**The data model only exists in docs.** The RAM registry has just received its first real
entries; `world_model.json` is hand-edited with prose in it, while the concept calls for a
mechanical update from RAM reads; there is no action log.

**DMG or CGB, an implicit decision.** Decision D3, owner's call.

**Policy on pre-trained knowledge.** The anti-cheat check (`puzzle_validator.rb`) rightly targets
*game* knowledge. It was implicitly applied to *engineering* knowledge too, which cost days: the
disassembly's memory map was the right source of hypotheses all along. Rule in `AGENTS.md`.

## Plan, in order

1. ~~Full memory diff, HRAM included, for position and room.~~ Done, D1.
2. **Does collision read from WRAM?** `NEXT.md`'s question. Settles D4 in practice.
3. **Headless session API in gemboy** (D6): frames, keys, memory reads, in-memory
   snapshot/restore, specs. Save state as a feature of the emulator.
4. **New snapshot-based navigation tool** (D7) in `lib/`, validated once against `legacy/`'s
   oracle grids, then regeneration of the 7 checkpoints without `legacy/`. Removal of `legacy/`.
5. **Decide D3 and D4** before accumulating new data.
6. **Only then**, the concept's decision loop: triggers on RAM state, planner, executor, JSONL
   action log. That's where the project's value is supposed to be.

## Spike's open items, reread

- `[6,7]` of overworld_screen3 (suspected wandering villager): disappears with D1 and D7.
- house2_interior: entered and mapped by the spike after the review. Pépé le Ramollo talks about a
  phone "outside": first in-game clue read, to be followed up by the planner.
- `ScreenMap.build`'s memory growth: stops being a topic without file reloads.
- Dialogue OCR: after the decision loop, not before.
- Sword and `cut_grass`: a game objective, for the planner to handle, not a script.
