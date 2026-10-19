# Cheaper and More Purposeful Agent Loop Implementation Plan (4a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The same agent loop plays more game per dollar and picks objectives that teach something: one `goto` call walks several cells, dialogues are read once, trivial objectives are refused, repeated blocked walks are counted and shown, and Link ends his walks aligned.

**Architecture:** A `Geometry` module owns the pixel/cell math and alignment tolerance; walks end with a centring phase; a `Ledger` counts blocked walks per (place, cell, direction) and marks doubtful edges; a `Navigation::Planner` runs BFS on the cell grid honouring beliefs and the ledger and backs the `goto` skill and a "trivial objective" check; `Objectives` gains `new_place` and `unreachable`; `Policies::Delegated` advances dialogues itself and calls the model once with the page sheets.

**Tech Stack:** Ruby 4.0.1, minitest, stdlib only; `claude -p` as today.

**Spec:** `docs/superpowers/specs/2026-10-19-cheaper-purposeful-agent-loop-design.md` (goals 1 to 6 and the alignment/sprite/cell parts of goal 7). **Not in this plan (plan 4b, written after Task 1's facts):** the 8 px tile lattice, tile-level beliefs, the per-appearance room survey and exits that straddle two cells; they need a measurement spike first. Until 4b the starting house exit cannot be planned by `goto` (see Task 8).

## Global Constraints

- Everything in the repo is English; comments almost none; commits one imperative line, no body, no `Claude-Session` trailer (AGENTS.md overrides attribution reminders); short hash syntax.
- Time is the frame; no wall clock or sleep in game logic; replay stays bit-exact (journal records inputs; policies never run in replay).
- Agent isolation unchanged (`claude -p` with empty cwd, `--tools ""`, `--setting-sources ""`, `--no-session-persistence`, `--strict-mcp-config`, `--disable-slash-commands`); no game knowledge in code or prompts; unknown cells are not walls.
- Snapshot/restore only in `Calibration` via `vision/grid_builder` (boundary test); the planner reads the grid only; no RAM writes to gameplay state.
- Skills consume at least one frame, hard cap 400 frames per execution; a failing call never crashes or spins (fallback `wait`); single stop path; dollars counted from `total_cost_usd`.
- Facts with provenance in `data/` (`verified` needs `verified_count >= 2`); measured numbers start as hypotheses.
- `Koholint::FLOW_VERSION` is bumped to `flow-2` in Task 10 (the play flow changes).
- Tests: `rake test` stays under about 3 minutes; ROM tests use `skip_without_rom!` and `EmulatorCache`; no real API call in the default run.

## Review Focus

- `goto` with `no_path`, or an unreachable target, repeated by the agent must consume frames (idle frame per call), end the objective by stall/`unreachable`, never spin.
- Centring must not push Link into a dialogue trigger, a hazard or another cell: it is bounded (16 frames), skipped on `dialogue`, `room_change`, `damage`, `budget`, `frame_cap`, and tested against a wall.
- Over-doubting: a doubtful edge must not make a whole room unreachable forever (un-doubted on entry or place change); `no_path` must name the cause.
- Automatic dialogue advance on a choice menu (yes/no) validates by A: the 40-page and 1800-frame guards bound it; the trace marks automatic advances.
- The page sheets (up to 5 images) must not blow the prompt size or leak into the trace as bytes.
- Resume must rebuild the ledger and the visited places from the trace; ids and counters never repeat.

---

## Wave plan

Wave 1 (parallel, disjoint files): Tasks 1, 2, 4, 5. Wave 2: Task 3 (needs Task 1). Wave 3: Task 6 (needs 3 and 5). Wave 4: Task 7 (needs 4, 5, 6). Wave 5 (parallel): Tasks 8 and 9 (9 follows 7 in `delegated.rb`, 8 touches the registry and context only). Wave 6: Task 10 (controller, live run). Each parallel task works in its own worktree and is merged `--no-ff`.

### Task 1: Geometry module and measured Link footprint

**Files:** Create `lib/koholint/geometry.rb`, `data/geometry.json`, `test/geometry_test.rb`; Modify `lib/koholint/game_state.rb`, `lib/koholint/vision/grid_builder.rb` (use `Geometry`, remove its private alignment math and `ALIGNMENT_TOLERANCE`)

**Interfaces:**
- Produces: `Geometry.cell_for(x, y) -> [row, col] | nil` (the existing `(y-8)/16, x/16` nearest-cell rule, nil outside the 8x10 grid), `Geometry.center_of(row, col) -> [x, y]` (`[col*16+8, row*16+16]`), `Geometry.offset(x, y, cell) -> [dx, dy]`, `Geometry.aligned?(x, y, cell, axis: :both) -> Boolean` with `Geometry::ALIGN_TOLERANCE = 4`; `GameState#cell` delegates to `Geometry.cell_for`. `data/geometry.json`: `{ "link_footprint": { "value": {...}, "verified_count": 1, "provenance": "..." } }` loaded by `Geometry.fact(name)`.
- [ ] **Step 1: Tests** (`test/geometry_test.rb`): `cell_for(72, 32) == [1, 4]`; `cell_for(44, 39) == [1, 2]` and `offset(44, 39, [1, 2]) == [4, 7]`, `aligned?(44, 39, [1, 2]) == false`; `aligned?(44, 32, [1, 2], axis: :y)`; `cell_for(10, 2) == nil`; existing grid/vision/skills tests still pass untouched (they use `GameState#cell`).
- [ ] **Step 2: Implement** `Geometry` and make `GameState.cell_at`/`GridBuilder.link_cell`/`aligned?` call it; run the vision and skills tests.
- [ ] **Step 3: ROM measurement (hypothesis count 1):** with `EmulatorCache.interactive`, drive Link by inputs only to find the collision extent: the y range where `walk left` along the starting house row 1 is free versus blocked by the beds (spike says band y 26..38 for row 1; y=39 blocked) and the x extent against the side walls; record `link_footprint` (width, height in px) and the band formula in `data/geometry.json` with `verified_count: 1` and the method in `provenance`. Add one ROM test asserting Link at y=32 walks left past x=36 and at y=39 does not.
- [ ] **Step 4: Commit** `Centralise the cell geometry and record Link's measured footprint`

### Task 2: Static sprites cover every cell they overlap

**Files:** Modify `lib/koholint/vision/grid.rb`, `lib/koholint/vision/grid_builder.rb` (only if it builds sprite boxes), `test/grid_test.rb` (or the vision grid test file)

**Interfaces:**
- Produces: `Grid#static_sprite(row, col)` returns the sprite pattern for every cell the sprite's box overlaps (an 8x16 NPC covers two rows); `Grid#new` input unchanged (`static_sprites:` hashes with `'x'`, `'y'`, `'pattern'` and the sprite height available as `'height'` when the snapshot provides it, else 16 for the 8x16 mode and 8 otherwise: read `ScreenVision.sprites` for what is carried).
- [ ] **Step 1: Tests:** two vertically stacked 8x16 sprite halves at x=64,y=48 and x=72,y=48 make `static_sprite(2, 4)` and `static_sprite(3, 4)` non-nil; a sprite inside one cell still marks one cell; a sprite partly off-grid does not raise; `passable(2, 4, :down)` is not answered from the floor appearance when a sprite covers the cell.
- [ ] **Step 2: Implement** the overlap mapping (box `[x-8, y-16, w, h]` overlap with each 16x16 cell box); keep the first-sprite-wins rule per cell.
- [ ] **Step 3: Run** the grid, grid_builder and context tests. **Step 4: Commit** `Map static sprites to every cell they overlap`

### Task 3: Aligned stops and blocked_at in skill results

**Files:** Modify `lib/koholint/skills/execution.rb`, `lib/koholint/skills/walk.rb`, `test/skills_test.rb`, `test/engine_test.rb`

**Interfaces:**
- Consumes: `Geometry` (Task 1).
- Produces: `Execution#result` gains `aligned: Boolean`, `offset: {dx:, dy:}` (Link's offset from the centre of his nearest cell at the end) and `blocked_at: {row:, col:, direction:} | nil` (set whenever the walk was blocked, even if centring was then cut short and `stopped_by` became `dialogue`, `damage` or `room_change`: the cell Link stood on and the direction tried). A centring phase runs after a normal stop (`done`, `blocked`): up to 16 frames pressing toward the centre of the nearest cell on each axis where `|offset| > Geometry::ALIGN_TOLERANCE`, one axis at a time, stopping early on room change, dialogue, damage; skipped when `stopped_by` is `dialogue`, `room_change`, `damage`, `budget`, `frame_cap`. Centring frames count in `frames` and in the 400-frame cap.
- [ ] **Step 1: Tests (unit, scripted states):** a walk that stops at y=39 in row 1 emits up to 7 more frames pressing `:up` and ends `aligned: true`; `walk` blocked at a wall ends with `blocked_at` equal to the start cell and direction; centring is skipped on `dialogue`; a state stream that never gets aligned stops at 16 centring frames with `aligned: false`; result keys of existing tests unchanged otherwise. ROM test from `EmulatorCache.interactive`: `walk(:up, 3)` then the result `aligned` is true and a following `walk(:left, 4)` is not blocked by the beds (spike scenario).
- [ ] **Step 2: Run to see FAIL; Step 3: Implement** the settle phase inside `Execution` (state-based, no sleeps) and set `blocked_at` in `finish(:blocked)`; **Step 4: PASS** (skills, engine, delegated and context tests). **Step 5: Commit** `End walks aligned and report where a walk was blocked`

### Task 4: Objectives: new_place and unreachable

**Files:** Modify `lib/koholint/objectives.rb`, `lib/koholint/decision.rb` (objective schema), `test/objectives_test.rb`, `test/decision_test.rb`

**Interfaces:**
- Produces: `Objectives::PREDICATES` gains `'new_place' => []`; `Objectives#update` achieves `new_place` when Link is in a non-loading place not in `visited` (the set holds the place of the first non-loading observation and every place observed since; `Objectives#visited -> Array<[room, map]>`, seeded by `Objectives.new(visited: [])`); `Objectives#note_blocked(blocked_at:, target:)` called by the policy after each skill; abandons with `reason: 'unreachable'` after `UNREACHABLE_PAIRS = 6` blocked results at the same (cell, direction) pair toward a `reach_cell` target or `UNREACHABLE_TOTAL = 8` blocked results in total for any objective (counters reset when an objective starts); the `choose_objective` json_schema and validator accept `new_place` with no fields.
- [ ] **Step 1: Tests:** `new_place` not achieved in the starting place, achieved at the first non-loading state in another place, never achieved by a loading state; resume seeding via `visited:`; 6 same-pair blocked notes abandon a `reach_cell` objective with reason `unreachable`, 7 mixed blocked notes do not, the 8th abandons any kind; counters reset on a new objective; exactly one terminal event; `valid_predicate?` accepts `{kind: 'new_place'}` and rejects extra keys.
- [ ] **Step 2: FAIL; Step 3: Implement; Step 4: PASS. Step 5: Commit** `Add the new_place predicate and unreachable abandon`

### Task 5: Ledger of blocked walks and doubtful edges

**Files:** Create `lib/koholint/ledger.rb`, `test/ledger_test.rb`; Modify `lib/koholint/agents/context.rb`, `test/agents_context_test.rb`

**Interfaces:**
- Consumes: `blocked_at` from skill results (Task 3).
- Produces: `Ledger.new`, `#record(place:, blocked_at:)` (increments), `#entered(place:, cell:, direction:)` (clears doubt and count for that edge), `#count(place, cell, direction) -> Integer`, `#doubtful?(place, cell, direction) -> Boolean` (true at `DOUBT_AT = 2` blocked results), `#reset_unless(place)` (drops other places), `Ledger.from_events(events)` (rebuilds from `action` events with `result.blocked_at`). `Agents::Context.build(..., ledger: nil)`: the neighbour table adds `blocked N times` to a neighbour's line when N > 0; a doubtful neighbour is drawn `!` in the grid and the legend reads `! stale or doubtful`; with `ledger: nil` output is unchanged.
- [ ] **Step 1: Tests:** doubtful at 2, not at 1; `entered` un-doubts; changing place resets; `from_events` rebuild equals the incremental ledger; context snapshot test with one doubtful neighbour shows `!` and `blocked 2 times`; context with `ledger: nil` equals today's snapshots.
- [ ] **Step 2: FAIL; Step 3: Implement; Step 4: PASS. Step 5: Commit** `Count blocked walks and show doubtful edges to the agent`

### Task 6: Planner and the goto skill

**Files:** Create `lib/koholint/navigation/planner.rb`, `lib/koholint/skills/goto.rb`, `test/planner_test.rb`; Modify `lib/koholint/skills/registry.rb`, `lib/koholint/engine.rb` (pass the tour context to `registry.start`), `test/skills_test.rb`, `test/engine_test.rb`

**Interfaces:**
- Consumes: `Vision::Grid#passable/static_sprite`, `Ledger#doubtful?` (Task 5), `Execution` (Task 3).
- Produces: `Navigation::Planner.new(grid:, ledger:, place:)`, `#path(from:, to:, mode: :explore) -> Array<[row, col]> | nil` (BFS, 4-neighbours; `mode: :explore` walks cells believed `:yes`, `:unknown`, `:stale`; `mode: :free_only` only `:yes`; never a static-sprite cell or a cell believed `:no`; an edge is skipped when `ledger.doubtful?`; the shortest path with fewest turns). `Skills::Goto` (`name 'goto'`, params `{row: Integer 0..7, col: Integer 0..9}`), `#start(state, params, context)` where `context` carries `:grid` and `:ledger`; the run walks the path as segments, centring before each turn and at the end, honours the 400-frame cap, and ends with `stopped_by` in `done|blocked|no_path|dialogue|room_change|damage|frame_cap|budget`; `no_path` consumes one idle frame and its result carries `path_length: 0`; results carry `path_length`, `steps_done`, `blocked_at`, plus Task 3's `aligned/offset`. `Registry#start(name, state, params, context = {})`; the engine passes the policy `context` hash it already built for `decide`.
- [ ] **Step 1: Tests (planner, pure):** straight path; detours around a `:no` cell; unknown cells are walkable in `:explore` and not in `:free_only`; a doubtful edge is avoided; a static-sprite cell is avoided; `nil` when no path. **Skill tests (scripted states):** a 3-cell goto ends `done` with `aligned`; a blocked segment ends `blocked` with `blocked_at`; unreachable target gives `no_path` after 1 frame; unknown params raise `ArgumentError` (the decision point converts to `Invalid`); missing context gives `no_path`. ROM test: from `EmulatorCache.interactive` `goto(row: 2, col: 5)`-style move across free starting-house cells ends within one cell of the target aligned (use cells the grid shows free; report them).
- [ ] **Step 2: FAIL; Step 3: Implement planner, then `Goto`, register it in `Skills::Registry.default`, extend `schema`; Step 4: PASS (skills, decision_test schema naming `goto`, engine). Step 5: Commit** `Add the grid planner and the goto skill`

### Task 7: Delegated policy: ledger, trivial-objective rejection, doubt feedback

**Files:** Modify `lib/koholint/policies/delegated.rb`, `lib/koholint/agents/prompts.rb`, `test/delegated_policy_test.rb`

**Interfaces:**
- Consumes: Tasks 4 to 6.
- Produces: `Delegated` owns a `Ledger` (rebuilt through `Delegated.new(ledger:)`), records `blocked_at` after every skill, calls `ledger.entered` when a walk or goto enters a cell, resets it on place change, passes `ledger:` to `Agents::Context.build` and calls `Objectives#note_blocked`; `satisfied?` is extended: a `reach_cell` objective whose target is reachable over `:free_only` cells (Planner, doubtful edges excluded) is rejected with a fallback and a justification naming why; `Prompts.system_for` states that `leave_place` means finding a way out, `new_place` means discovering, that `goto` walks several cells, that `!` may be doubtful.
- [ ] **Step 1: Tests (scripted client):** a `reach_cell` on a known-free reachable cell is rejected and traced, on an unknown cell is accepted; a blocked walk updates the ledger and the next context shows `blocked 1 time` (singular) on that neighbour; after 2 blocks the neighbour is drawn `!`; `unreachable` abandons the objective and the next tour asks `choose_objective`; place change clears the ledger; `new_place` objective starts and is achieved on a place change (scripted states).
- [ ] **Step 2: FAIL; Step 3: Implement; Step 4: PASS. Step 5: Commit** `Feed blocked walks back to the agent and refuse trivial objectives`

### Task 8: Step skill for half-cell positioning (proposed bridge)

**Files:** Create `lib/koholint/skills/step.rb`; Modify `lib/koholint/skills/registry.rb`, `lib/koholint/agents/context.rb` (print Link's pixel offset from his cell centre), `test/skills_test.rb`, `test/agents_context_test.rb`

**Interfaces:**
- Produces: `Skills::Step` (`name 'step'`, params `{direction, pixels: Integer 1..16}`), holds the direction until Link has moved `pixels` px along that axis (state-based on `x`/`y`), stops on blocked (8 still frames), dialogue, room change, damage, 80-frame cap; result has `moved_px`; no centring afterwards (the point is an offset). The context line `Link offset from cell centre: dx, dy` so the agent can line up on a doorway that straddles two cells.
- Note to the owner: this is a small generic skill added as a bridge so the starting-house exit is reachable before plan 4b; drop it if you prefer to wait for the tile lattice.
- [ ] **Step 1: Tests:** `step(right, 8)` from a scripted stream ends `done` after 8 px; blocked stops with `blocked`; params range errors; ROM test: from `EmulatorCache.interactive`, `step(up, 5)` moves y by 5 within one frame of tolerance.
- [ ] **Step 2: FAIL; Step 3: Implement; Step 4: PASS. Step 5: Commit** `Add a step skill for half-cell positioning`

### Task 9: Dialogue sheets and automatic advance

**Files:** Modify `lib/koholint/vision/dialogue_shot.rb`, `lib/koholint/agents/claude_cli.rb`, `lib/koholint/policies/delegated.rb`, `lib/koholint/agents/prompts.rb`, `test/dialogue_shot_test.rb`, `test/claude_cli_test.rb`, `test/delegated_policy_test.rb`

**Interfaces:**
- Produces: `Vision::DialogueShot.rgb(emulator) -> String` (the stacked bands, RGB), `DialogueShot.sheets(pages, per_sheet: 8) -> Array<String>` (PNG bytes, each sheet tiles up to 8 pages vertically at the existing x4 scale, oldest first); `Agents::ClaudeCli#call(..., images: [])` (multi-image stream-json content blocks; `image:` keeps working as a one-element list; whole-argv assertions unchanged). `Delegated`: while `phase == :dialogue` and the automatic mode is on, `decide` returns `{skill: 'advance_dialogue', params: {}}` with agent `delegated`, fallback false, cost 0, justification `automatic dialogue advance`, keeps each page's `rgb`, counts pages; the model is called once on the first non-dialogue tour (or at `DIALOGUE_PAGE_LIMIT = 40` pages or `DIALOGUE_FRAME_LIMIT = 1800` frames) with the sheets in `images:`, the `:choose_skill` schema asks for the full transcription; the transcription is emitted as `dialogue` events with sequential `page` numbers; after the cap hit the next dialogue tour is agent-driven until the dialogue closes, then automatic mode re-arms.
- [ ] **Step 1: Tests:** `sheets` of 9 pages gives 2 PNGs (8 and 1 page) with decoded dimensions; 40 pages give 5; the claude client test asserts the stdin message has N image blocks then the text; Delegated with a scripted client: a 3-page dialogue makes zero client calls during the dialogue, one call after it with a sheet, three `dialogue` events (pages 1 to 3), no PNG bytes in the trace; the 40-page guard stops the automatic mode and asks the model once; a dialogue that reopens inside the sequence counts to the same sequence; a failing client call after the dialogue falls back to `wait`.
- [ ] **Step 2: FAIL; Step 3: Implement; Step 4: PASS (including the live-opt-in tests staying skipped). Step 5: Commit** `Advance dialogues automatically and read them once from page sheets`

### Task 10: Flow version, resume seeding, viewer, docs, live rerun

**Files:** Modify `lib/koholint.rb` (`FLOW_VERSION = 'flow-2'`), `lib/koholint/cli.rb` (seed visited places and the ledger from the trace on resume), `lib/koholint/viewer/page.html`, `lib/koholint/viewer/feed.rb`, `docs/AGENT_MANUAL.md` (controls section), `test/agent_manual_test.rb`, `test/page_test.rb`, `test/feed_test.rb`, `test/cli_test.rb`, `README.md`, `ROADMAP.md`; Create `docs/runs/2026-10-second-agent-run.md` (measurements)

**Interfaces:**
- Produces: viewer wording `goto (r, c) · walked 3 cells, stopped: done`, `blocked at (r,c) up`, `automatic dialogue advance`, `objective: new_place … started/achieved/abandoned (unreachable)`, `step up 8 px`; feed status adds `ledger_doubtful` count if cheap; `docs/AGENT_MANUAL.md` gains a Controls section from the owner (A talks to NPCs, reads signs, advances dialogues page by page and interacts with the world; B cancels dialogues when it can; an item can be assigned to each of A and B; contextual actions win over the assigned item, so facing an NPC A talks even with a sword assigned), within the 3000-char sub-cap and the existing no-game-facts validator; resume rebuilds `Objectives(visited:)` and `Ledger.from_events` from the trace.
- [ ] **Step 1: Tests:** each new viewer format through node; manual validator passes with the controls section; a resume test where a trace with blocked results and visited places gives the same ledger and visited set; `FLOW_VERSION` mismatch refuses to resume a `flow-1` run.
- [ ] **Step 2: Implement; run the full suite once. Step 3: Commit** `Bump the flow version, rebuild agent memory on resume and show the new events`
- [ ] **Step 4 (controller, manual):** live rerun `bin/koholint run --agent --realtime --max-dollars 1 --minutes 25` with `watch --host 0.0.0.0` open for the owner's phone; record in `docs/runs/2026-10-second-agent-run.md`: frames, calls, dollars, calls per 1000 frames against the first run (78 calls / 2601 frames), places discovered, `unreachable` abandons, doubtful cells, dialogue calls, whether the house was left, and what is still missing; update `ROADMAP.md` (remove what landed, add plan 4b: tile lattice, tile-level beliefs, room survey, straddling exits, Jev routing for `choose_skill`). **Commit** `Record the second agent run and update the roadmap`

---

## Self-review against the spec

- Goal 1 `goto`: Task 6 (+7 prompt). Goal 2 dialogue once: Task 9. Goal 3 objectives: Tasks 4 (new_place), 7 (trivial refusal). Goal 4 ledger and unreachable: Tasks 3, 4, 5, 7. Goal 5 doubtful cells: Tasks 5, 6, 7. Goal 6 controls: Task 10. Goal 7: alignment Tasks 1 and 3, sprite coverage Task 2, half-cell bridge Task 8; tile lattice and room survey deferred to plan 4b by decision (needs the footprint facts of Task 1).
- Flow version bump and resume seeding: Task 10. Calls made after the builder check are reflected in Tasks 4 to 7 and 9.
- Interfaces carried between tasks: `blocked_at` (3 -> 5, 7), `Ledger` (5 -> 6, 7), `Planner`/`goto` (6 -> 7), `Objectives(visited:)` (4 -> 10), `images:` (9). Names match across tasks.
