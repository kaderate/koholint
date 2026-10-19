# Cheaper and more purposeful agent loop — design

Status: draft for owner approval, 2026-10-19. Follows the first live run (`docs/runs/2026-10-first-agent-run.md`). Builds on the first agent loop (`docs/superpowers/plans/2026-10-18-first-agent-loop.md`) and the architecture spec (`2026-10-16-koholint-v2-architecture-design.md`).

## Intent

The first run spent 1 USD and 78 model calls on 26 s of game time without leaving the starting house. The loop is safe (no crash, no invalid output, clean stop) but unaffordable and aimless: one call per 1 to 3 cells, one call per dialogue page, objectives that reach already-known cells, and 25 calls on a cell the grid wrongly called free. This design makes the same loop cheaper per game second and its objectives meaningful, without giving the agent any game knowledge.

Success: a rerun with the same defaults (Sonnet, 1 USD) reaches further than the first run in frames and in places discovered, with fewer than half the calls per 1000 frames, and the context shows the agent where its beliefs failed. Leaving the starting house is the first target, not a promise.

## Goals

1. **`goto`**: one skill call walks several cells along a path computed by code on the known grid.
2. **Dialogue read once**: the engine advances a dialogue by itself and the model is called once, when it closes, with every page.
3. **Meaningful objectives**: code rejects trivial objectives; a new objective kind rewards discovering places.
4. **Failure memory**: blocked walks are counted per cell and direction, shown to the agent, and make a hopeless objective end.
5. **Beliefs versus reality**: when the grid says free and the game blocks twice, the cell is shown as doubtful and the contradiction is traced.
6. **Controls** in the agent's manual digest.
7. **Room survey and alignment**: a mapped room the agent can trust, and walks that end aligned on a cell (see "Room survey and alignment").

## Non-goals and anti-goals

- No game knowledge in code or prompts (no places, no solutions). The controls below are manual-level.
- No Jev wiring here. The owner suggests Jev for the frequent calls later; `choose_skill` stays the seam, and `goto` makes it rarer. Not a per-frame model either way: latency makes it impossible, and the engine keeps executing macros and skills itself.
- No snapshot/restore outside `Calibration`; the path planner reads the grid only (no lookahead on the emulator). No RAM writes to gameplay state.
- Not a navigation system across screens, no combat, no inventory perception, no dialogue-to-leads (all in `ROADMAP.md`).
- No vision model for passability in this iteration (the spike showed it is not the bottleneck).
- A failure the agent cannot see is worse than a costly one: nothing here may hide information from the trace.

## Design

### goto (goal 1)
- New skill `goto(row, col)` in the registry (same `Execution` contract: at least one frame, 400-frame cap, typed result with `from`, `to`, `moved_cells`, `stopped_by`). Params: a cell on the 8x10 grid of the current place.
- The path is computed once at start by breadth-first search over the cells of the current grid, moving to 4-neighbours; cells believed free and cells unknown are walkable (unknown is not a wall), cells believed blocked and static objects are not. One-way ledges follow the belief's direction rule used by the grid builder. The route is walked as `walk` segments (reusing the walk execution logic).
- It stops early with `stopped_by`: `blocked` (a real blocked segment: report the cell and direction), `dialogue`, `room_change`, `damage`, `frame_cap`, `budget`, or `done`; and `no_path` when the search finds none (zero frames are not allowed: a `no_path` execution still consumes one idle frame and reports it).
- The skill result lists the path length and the segment where it stopped, so the context can show it.
- The 400-frame cap bounds it (a long path is cut and the agent calls again).

### Dialogue read once (goal 2)
- While `phase == :dialogue`, the delegated policy answers by itself, with no client call: it runs `advance_dialogue` cycles, keeping each page image (the same crop as today), up to 40 pages (owner: some dialogues are long). When the dialogue closes, or at 40 pages or 1800 frames, it makes one `choose_skill` call whose prompt carries the page images assembled into sheets of up to 8 pages (at most 5 images, oldest first) and asks for the full transcription plus the next skill. Page images are written under `prompts/` (as now), the transcription becomes the `dialogue` event(s) as now, with `page` numbers.
- Risk (owner to know): a dialogue with a choice cursor would be validated by the automatic A. The page cap and the frame guard limit the damage; detecting the cursor is deferred (ROADMAP) unless the live run shows it.
- The trace marks automatic advances as deterministic decisions (agent `delegated`, cost 0), like the hemmed-in wait.

### Meaningful objectives (goal 3)
- Code check at `choose_objective` (beside the existing "already true" checks): `reach_cell` on a cell the grid shows as free and reachable by known cells (a path exists over free cells only) is rejected with a fallback justification saying why. `reach_cell` on an unknown, stale or doubtful cell stays valid.
- New predicate `new_place` (no fields): achieved when Link is in a non-loading place not visited earlier in this run (the objectives object keeps the visited set; the starting place counts as visited at the first observation). Added to `Objectives::PREDICATES`, the decision point schema and the viewer text. `leave_place` stays; the system prompt says finding a way out is `leave_place`, and exploring is `new_place`.

### Failure memory (goal 4)
- A ledger keyed by (place, cell, direction) counts `blocked` skill results (a walk or goto segment that ended `blocked` from that cell in that direction). It resets when the place changes. The context's neighbour table adds "blocked N times" next to the belief and the last result.
- An objective is abandoned with reason `unreachable` when it accumulates 6 blocked results at the same (cell, direction) pairs toward its target, or 8 in total. The thresholds are my guess; they live as constants next to the stall and loop ones.

### Beliefs versus reality (goal 5)
- When the ledger reaches 2 blocked results in one direction from a cell whose neighbour is believed free (belief `yes`), the context draws that neighbour as `!` ("doubtful") and the trace gets a `grid_contradiction` event (the type already exists). Beliefs themselves stay probe-driven (real walking still teaches the belief store nothing).

### Controls (goal 6)
Add a controls section to `docs/AGENT_MANUAL.md` (it counts against the 3000-character manual sub-cap), from the owner:
- A talks to NPCs, reads signs, advances dialogues page by page, and interacts with the world.
- B cancels dialogues when it can.
- An item can be assigned to each of A and B. Contextual actions win over the assigned item: facing an NPC, A talks even if a sword is assigned to it.

### Half-cell navigation (owner's point, goal 7)
- The collision and survey resolution becomes the **8 px tile lattice** (16 x 20 tiles per screen). Link's position is a pixel position; a position is walkable when Link's footprint (the measured collision band, a few pixels smaller than a cell: the builder measures it with probes, not from memory) overlaps no blocked tile. Beliefs keep working per appearance, now with a **tile-level appearance** (the 8x8 tile pattern, plus the 16x16 block pattern as today) so a door drawn across two blocks is recognised as a door, not as two half-doors.
- The agent still sees the 8x10 cell view (cheap to read); each cell carries a flag when its navigability is partial (`half`) and `goto` accepts a target in tile units (`row`/`col` in tiles, or a cell plus `offset: half`), so "centre on the doorway" is expressible. Paths are planned on the tile lattice and walked in segments ending aligned.
- The probe boundary is unchanged: only `vision/grid_builder` uses `Calibration`; the lattice is built from the same snapshots and probes.
- Risk: more probes (a room has 320 tiles); the per-appearance generalisation keeps it near the cost measured for 21 appearances. The builder measures the real count before committing to the lattice.

### Room survey and alignment (goal 7)
Measured by a throwaway spike on the first run's starting house (report: `.superpowers/sdd/2026-10-18-first-agent-loop/spike-map-report.md`, scripts were in /tmp/spike-map, nothing committed). Findings that shape this block:
- The probe-based grid was mostly right: of the starting house, 30 cells agreed free, 25 agreed blocked, **0 false walls**, 2 wrong, 22 unknown (walls, unreachable cells, the two door cells). Terrain alone is constant per appearance (21 distinct appearances); the only mixed-truth classes come from NPC sprites standing on a floor appearance.
- The 25-call failure at cell (1,1) was **alignment, not belief**: the belief "free" was true (Link can stand there at y=32), but the agent stopped a `walk up 3` at y=39. `GameState#cell` calls y=39 row 1, yet the collision band of row 1 is y 26..38, so at y=39 Link overlaps row 2 (the beds), and left/right walks stop against them. The builder had correctly discarded its own probe at y=39 as `misaligned`.
- The two wrong cells, (2,4) and (2,5), are believed free but blocked by an NPC whose 8x16 sprites cover rows 2 and 3: `Grid` maps a static sprite to one cell only.
- A survey costs about 0.8 s per probe: one representative per appearance is about 17 s per room, all four directions of the 31 reachable cells about 99 s. A vision model is **not needed for passability**; I drop the vision-model labelling idea for now (it stays a possible helper for the meaning of cells: exit, chest, sign).
- Doorway (owner, 2026-10-19): the exit is exactly one cell wide but **straddles two grid cells**, (7,4) and (7,5). The 16 px grid (2x2 background tiles per cell, aligned on the screen origin) is therefore too coarse for navigation: navigability can be decided at half-cell (8 px tile) granularity. The spike saw Link stop at y=121 without a room change; the likely cause is that he was not centred on the doorway's real x-span (to be confirmed by the builder). Leaving the house depends on this.

Changes:
- **Aligned stops.** `walk` and `goto` end each segment with a deterministic centring step: after the movement stops, nudge Link along the other axis until his position is within the cell's collision band centre (a few frames, state-based, no sleeps), and report `aligned: true/false` plus the pixel offset in the result. The context shows when Link is not aligned.
- **One cell function.** Fix `GameState#cell` (and its users) so a pixel position maps to the cell whose collision band contains it, with the band and the tolerance expressed once as named constants next to it; the builder's alignment tolerance uses the same constants.
- **Sprites on every cell they cover.** `Grid` maps a static sprite to all the cells its box overlaps (8x16 sprites cover two rows).
- **Room survey.** On first entry to a place (and after a long idle), a survey probes one representative cell per appearance not yet decided, starting from an aligned Link, on emulator copies, through the existing grid builder and `Calibration` (the only module allowed to snapshot). It adds evidence to the same `Beliefs`; nothing else changes. Survey time is wall time only (no game frames), traced as `notable survey` with probe count and seconds. Doorway cells: the builder investigates the exit behaviour (see the unresolved point) and records the facts in the trace and in `data/addresses.json` only if they are verified twice.
- The agent's context shows, for every neighbour, belief, ledger count and an `aligned` hint, so "blocked because misaligned" is distinguishable from "blocked by a wall".

## Constraints that carry over

Agent isolation, single stop path, bit-exact replay (the journal records inputs; policies never run in replay), one-line commits without trailers, the AGENTS.md rules, hypothesis versus verified facts. The suite stays under about 3 minutes.

## Left to the builder

File layout, the BFS tie-breaks, exact result shapes of `goto`, trace field names for the automatic dialogue advance, tests, and the viewer wording. Measure the cost per 1000 frames before and after with a live run (fake-claude tests cannot show it).

## Open for the first rerun

Cost per 1000 frames, calls per place discovered, share of calls spent in dialogues, number of `unreachable` abandons and of doubtful cells. If `goto` alone does not bring the cost down enough, the next lever is routing `choose_skill` to a cheaper tactical agent (Jev).

## Calls made after the builder check (my calls, to be checked by the owner)

- **Doubtful cells and planning.** A doubtful cell (ledger: 2 blocked results in one direction toward a believed-free neighbour) is NOT walkable for `goto` in that entry direction; other directions into the same cell stay allowed. It is un-doubted when a walk enters it from that direction, or when the place changes (the ledger resets). After a `blocked` stop, the next `goto` replans with the ledger applied, so it routes around the blocked edge or answers `no_path`.
- **Attribution of blocked.** A blocked result is counted once per skill execution, for the (cell, direction) of the last step that failed (the cell Link stood on and the direction he tried). A result counts when it carries `blocked_at` (the walk was blocked); stops by dialogue, damage, room change, budget or cap without a block never count. A block followed by a centring cut short by a dialogue still counts (ruling after Task 3). `goto` and `walk` results carry `blocked_at: {row, col, direction}`.
- **`unreachable`.** The counters are per objective, reset when a new objective starts, and read from the ledger entries created during that objective. The 6-pairs-toward-the-target rule applies to `reach_cell` only (pairs = blocked entries whose cell is on the straight line or path toward the target; the builder may simplify to "6 blocked results in the same direction from the same cell"). The 8-in-total rule applies to every objective kind.
- **Trivial `reach_cell` check.** The target is rejected when a path of cells believed free exists from Link's current cell, with ledger-doubtful edges excluded. The check and `goto` share one planner module with one walkability rule set; the "free only" mode is a parameter of the same search.
- **Dialogue closed.** The signal is `phase` leaving `:dialogue`. If a dialogue reopens within the same automatic sequence, it counts as the same sequence until the page cap. At the cap, the model is called once; if the dialogue is still open, the next `choose_skill` may continue with `advance_dialogue` (agent-driven) and the automatic mode resumes at the next new dialogue. The call with the page sheets counts as one agent call for the steps and cost accounting (the real `total_cost_usd` is added as today); the image count is bounded by the 8-page sheets.
- **`new_place`.** A place is the `[room_id, map_id]` pair used by `leave_place` and the grid. The starting place counts as visited at the first non-loading observation of the objective. The visited set is rebuilt from the trace's perception events on resume (like the beliefs and objective ids). Loading states never count.
- **Flow version and trace.** The play flow changes (a new skill, automatic dialogue advance), so `FLOW_VERSION` is bumped and v1 runs of the first agent loop cannot resume. Automatic advances and automatic `goto` stops are ordinary `decision`/`action` events (agent `delegated`, cost 0) using existing trace types; `Trace` is extended only for the new `blocked_at` field in action results, if the schema validates them (the builder checks), and the viewer is updated for `goto` and `new_place` wording.
