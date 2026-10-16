# Koholint v2 Engine Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic engine that plays Link's Awakening DX headless through emu-gb with a trivial non-agent policy, producing a replayable, forkable, budget-bounded run directory (trace, inputs journal, keyframes, canonical save, manifest).

**Architecture:** `Engine` owns the loop (perceive → decide → execute → record → budget check) over an `Emulator` adapter; every event goes through a schema-validated `Trace`; progress is reproducible from `inputs.log` + ROM hash, with keyframes as a local cache. Agents, world model, skills, live view and navigation are later plans; this plan only builds the vertical slice they plug into.

**Tech Stack:** Ruby 4.0.1 (as Jev/Tetris), minitest, emu-gb (`Driver`) at `$EMU_GB_HOME` (default `~/Code/emu-gb`), zlib, JSON/JSONL.

**Spec:** `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`

## Global Constraints

- Time unit is the frame; no `sleep`, no wall-clock in game logic (wall clock only inside `Budget`).
- Everything in the repo is English; comments almost none (one-line hidden *why* only); commits are one imperative line, no body.
- The ROM is never committed. Path from `$KOHOLINT_ROM`, default `~/Code/emu-gb/roms/zelda_dx_rev1.gbc`. Tests needing it skip when absent.
- Keyframes, videos, `manual/` text are gitignored. Committable per run: `manifest.json`, `trace.jsonl`, `inputs.log`, `save/`, `world.json`, `suggestions.md`.
- Only the engine writes `trace.jsonl` and `save/`. A run resumes only with the same `flow_version` and ROM hash.
- DMG mode (D3). Replay must be bit-exact.
- `AGENTS.md` ≤ 1 page after Task 1; no role taxonomy, no escalation queue.

## Review Focus

- Process killed mid-write leaves a truncated last `trace.jsonl` line: resume must ignore it, not crash.
- Resume with a different ROM hash or `flow_version` must refuse with a clear error, not silently continue.
- Machine sleep (large monotonic gap) must not exhaust a wall-clock budget or fail an in-flight call.
- SIGINT / stop request during an unlimited-budget run must still run the single stop path (save, keyframe, `stop` event, manifest status).
- Missing ROM or missing emu-gb checkout must fail with a one-line actionable message.

---

### Task 1: Archive v1 and scaffold v2

**Files:**
- Delete (after tag): `lib/*.rb`, `lib/validation/`, `test/*`, `PLAN.md`, `NEXT.md`, `METAPLANNER*.md`, `data/puzzle_*.json`, `data/world_model.json`, `.claude/skills/autonomous-recovery/`
- Keep: `data/ram_registry.json` (read-only source for Task 10), `docs/`, `DECISIONS.md`
- Create: `Gemfile`, `.ruby-version` (`4.0.1`), `Rakefile`, `lib/koholint.rb`, `test/test_helper.rb`, `manual/README.md`
- Modify: `.gitignore` (add `.superpowers/`, `runs/*/keyframes/`, `runs/*/video/`, `manual/*.txt`, `Notice Zelda.pdf`), `AGENTS.md` (rewrite ≤ 1 page), `README.md`

**Interfaces:**
- Produces: `rake test`; `Koholint::VERSION`; `Koholint.rom_path -> String` (raises `Koholint::Error` with one-line message if missing); `Koholint.emu_gb_home -> String`; `test_helper` provides `skip_without_rom!`.

- [ ] **Step 1: Tag the archive.** `git tag v1-archive` (verify `git tag -l v1-archive`). Confirm with the owner before pushing the tag.
- [ ] **Step 2: Write failing test** `test/koholint_test.rb`: `Koholint.rom_path` raises `Koholint::Error` matching `/KOHOLINT_ROM/` when `ENV['KOHOLINT_ROM']='/nope'`; `emu_gb_home` raises matching `/EMU_GB_HOME/` when pointed at a nonexistent dir.
- [ ] **Step 3: Run** `rake test` → FAIL (`Koholint` undefined).
- [ ] **Step 4: Implement** `lib/koholint.rb` (module, `Error`, the two path resolvers, requires added per later task), `Gemfile` (minitest, rake), `Rakefile` (`Rake::TestTask`).
- [ ] **Step 5: Run** `rake test` → PASS. Remove the v1 files listed above, rewrite `AGENTS.md` (conventions only: language, commits, comments, frames, ROM, `flow_version` rule) and `README.md` (layout of v2, link to the spec).
- [ ] **Step 6: Commit** `git commit -m "Archive v1 behind a tag and scaffold the v2 engine"`

### Task 2: Emulator adapter

**Files:** Create `lib/koholint/emulator.rb`, `bin/measure_speed`; Test `test/emulator_test.rb`

**Interfaces:**
- Produces: `Koholint::Emulator.boot(rom_path = Koholint.rom_path) -> Emulator`; `#step(buttons = []) -> nil` (advances exactly one frame with `buttons` ⊂ `%i[up down left right a b start select]` held); `#frame -> Integer`; `#read(addr) -> Integer`; `#state_hash -> String` (SHA256 hex of RAM regions: WRAM, HRAM, VRAM, OAM, IO, cart RAM, plus CPU registers); `#dump -> String`; `Emulator.restore(bytes) -> Emulator`; `#cartridge_ram -> String`; `#framebuffer_png(path)`.

- [ ] **Step 1: Test** `two_boots_with_same_inputs_have_equal_state_hash`: boot twice, step 600 frames with inputs `[[:start]]*10 + [[]]*590`, assert equal `state_hash` and equal `frame == 600`. `restore_then_step_matches_continuous`: dump at 300, restore, step 300 more, compare hash with a continuous 600-frame run.
- [ ] **Step 2: Run** → FAIL. 
- [ ] **Step 3: Implement** over emu-gb `Driver` (`Driver.build`, `press`/`release`/`clear_keys`, `advance_frames(1)`, `snapshot`, `Driver.restore`). Keys are set per frame from `buttons`; never use `Driver#tap`'s settle frames. Verify the exact emu-gb API names in `~/Code/emu-gb/lib/driver.rb` before coding; also locate how cart RAM is exposed (`battery_ram.rb`).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: `bin/measure_speed [frames=3600]`** prints frames/second of the bare loop locally. Run it, paste the figure into `docs/superpowers/specs/…-design.md` under "Replay cost" (replacing the "to measure" text), and note it in the commit.
- [ ] **Step 6: Commit** `git commit -m "Add the deterministic emulator adapter and measure local frame rate"`

### Task 3: Input journal

**Files:** Create `lib/koholint/input_log.rb`; Test `test/input_log_test.rb`

**Interfaces:**
- Produces: `InputLog.new(path)`; `#append(buttons) -> nil` (one entry per frame, run-length encoded in memory); `#flush`; `#frames -> Integer`; `#each_frame { |buttons| }`; `InputLog.load(path)`. Compressed with zlib; file format version byte first.

- [ ] **Step 1: Test** `round_trip_preserves_every_frame` (random 5 000 frames over 8 buttons, flush, load, compare); `rle_makes_idle_runs_small` (100 000 empty frames file < 1 KB); `rejects_unknown_format_version`.
- [ ] **Step 2–4:** run FAIL → implement → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the compressed per-frame input journal"`

### Task 4: Trace with typed events

**Files:** Create `lib/koholint/trace.rb`; Test `test/trace_test.rb`

**Interfaces:**
- Produces: `Trace.new(path, schema_version: 1)`; `#emit(type, frame:, **fields) -> Hash` appends one JSON line and returns it, raising `Trace::InvalidEvent` if `type` is unknown or required fields are missing; `Trace.read(path) -> Array<Hash>` (ignores a truncated last line); types and required fields: `perception{state}`, `decision{point, input, options, choice, justification, confidence, agent, latency_ms, cost_usd}`, `action{skill, params, result}`, `notable{kind, detail}`, `objective{id, status, predicate}` (status ∈ achieved/abandoned/failed/started), `budget_stop{kind}`, `stop{reason}`, `keyframe{path}`, `save{path, sav_sha256, source}` (source ∈ `game`/`stop`). Every line carries `v`, `type`, `frame`.

- [ ] **Step 1: Test** `emit_rejects_unknown_type`, `emit_rejects_missing_required_field`, `read_ignores_truncated_last_line` (write a valid line then half a line), `lines_are_append_only` (second `Trace.new` on same path appends).
- [ ] **Step 2–4:** FAIL → implement (flush each emit) → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the schema-validated append-only trace"`

### Task 5: Run directory and manifest

**Files:** Create `lib/koholint/run.rb`; Test `test/run_test.rb`

**Interfaces:**
- Consumes: `Trace`, `InputLog`.
- Produces: `Run.create(root: 'runs', flow_version:, budget:, parent: nil) -> Run` (id `YYYYMMDD-HHMMSS-<4hex>`, creates dir layout from the spec, writes `manifest.json` with `flow_version`, `rom_sha256`, `seed`, `budget`, `status: 'created'`, `parent`); `Run.open(path, flow_version:) -> Run` raising `Run::VersionMismatch` / `Run::RomMismatch`; readers `#trace`, `#inputs`, `#dir`, `#manifest`; `#status=(s)` rewrites the manifest atomically (temp file + rename).

- [ ] **Step 1: Test** `open_with_other_flow_version_raises`, `open_with_other_rom_hash_raises` (edit manifest hash), `create_makes_layout` (manifest, trace.jsonl, inputs.log, save/, keyframes/), `ids_do_not_collide_in_same_second`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add run directories with versioned manifests"`

### Task 6: Keyframes, replay, fork

**Files:** Create `lib/koholint/keyframes.rb`, `lib/koholint/replay.rb`; Test `test/replay_test.rb`

**Interfaces:**
- Consumes: `Emulator`, `InputLog`, `Run`.
- Produces: `Keyframes.new(dir)`; `#save(emulator) -> String` (zlib dump named by frame); `#nearest_at_or_before(frame) -> [Integer, String]|nil`; `Replay.to(run, frame) -> Emulator` (nearest keyframe else fresh boot, then steps journal entries up to `frame`); `Replay.verify(run, every: 600) -> Array<[Integer, Boolean]>` comparing recorded `perception.state_hash` events to a replay; `Run#fork(at_frame:, flow_version:) -> Run` (new run, `parent: {id, frame}`, journal truncated to `at_frame`, nothing in the parent touched).

- [ ] **Step 1: Test** `replay_to_frame_equals_live_state_hash` (live run 1 200 frames with scripted inputs, keyframe at 600; replay to 1 000 from keyframe and from boot give same hash as a live run stopped at 1 000), `fork_is_independent` (parent files unchanged byte-for-byte), `keyframes_are_gitignored_dir_only`.
- [ ] **Step 2–4:** FAIL → implement → PASS. At the end, print compressed dump size and whether emu-gb's `dump` embeds the ROM; if separable, strip it; if not, keep full dumps (gitignored) and record the figure in the spec (deviation from "no ROM in keyframes", acceptable only because keyframes never leave the machine).
- [ ] **Step 5: Commit** `git commit -m "Add keyframes, bit-exact replay and fork"`

### Task 7: Budget

**Files:** Create `lib/koholint/budget.rb`; Test `test/budget_test.rb`

**Interfaces:**
- Produces: `Budget.new(frames: nil, steps: nil, active_seconds: nil, dollars: nil, clock: Process.method(:clock_gettime), sleep_gap: 120)`; `#tick(frames: 0, cost: 0.0)`; `#step_done`; `#exhausted -> Symbol|nil` (first reached of `:frames,:steps,:time,:dollars`); `#stop!` makes `exhausted` return `:stopped`; `#unlimited? -> true` when all nil. Active time sums wall deltas between ticks, ignoring any single delta > `sleep_gap`.

- [ ] **Step 1: Test** with a fake clock: `first_limit_reached_wins`, `unlimited_never_exhausted_until_stop`, `sleep_gap_is_excluded` (clock jumps 3 600 s between ticks, `exhausted` stays nil with `active_seconds: 60`), `dollars_accumulate`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add composable budgets with sleep-tolerant active time"`

### Task 8: Game state perception (hearts, room, position)

**Files:** Create `data/addresses.json`, `lib/koholint/game_state.rb`, `lib/koholint/perception.rb`; Test `test/perception_test.rb`

**Interfaces:**
- Produces: `GameState = Struct(:frame, :room_id, :map_id, :x, :y, :direction, :hp, :max_hp, :milestone)`; `Perception.read(emulator) -> GameState`; `data/addresses.json` entries `{name, addr, source, verified_count}` extracted from v1's `ram_registry.json` (X `0xFF98`, Y `0xFF99`, direction `0xFF9E`, room `0xFFF6`, map `0xFFF7`, HP `0xDB5A`); `max_hp` and milestone addresses start as `hypothesis`; `milestone` is `:none` until a later plan.

- [ ] **Step 1: Test** `reads_known_room_after_boot_sequence`: boot, apply the recorded input script `test/fixtures/start_game.inputs` (generated in Step 3), assert room/map equal the pair recorded in the fixture's `.expected.json` and `hp` is a positive Integer; `schema_rejects_entry_without_verified_count`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Generate `start_game.inputs` once by pressing Start through the intro until Link controls (frame condition: HP > 0 and position nonzero), write expected values as a fixture. Entries are `hypothesis` with `verified_count: 1` unless the fixture check is a second independent method.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add typed game state perception from verified addresses"`

### Task 9: Decision contracts and the trivial policy

**Files:** Create `lib/koholint/decision.rb`, `lib/koholint/policies/walk_and_talk.rb`; Test `test/decision_test.rb`

**Interfaces:**
- Produces: `DecisionPoint.new(name:, options:, output_schema:)`; `#validate(choice) -> choice` raising `DecisionPoint::Invalid`; `Policy` protocol `#decide(point, state, context) -> {choice:, justification:, confidence:, agent:}`; `Policies::WalkAndTalk` deterministic: cycles `up,right,down,left` for 30 frames each and presses `a` for 2 frames every 10th cycle; `Policies::WithFallback.new(primary, fallback)` retries once on `Invalid`, then returns the fallback's choice flagged `fallback: true`.

- [ ] **Step 1: Test** `invalid_choice_raises`, `walk_and_talk_is_deterministic_for_same_frame`, `fallback_used_after_one_retry` (primary stub raising `Invalid` twice → result has `fallback: true`, primary called exactly twice).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add decision contracts and the deterministic walk-and-talk policy"`

### Task 10: Engine loop and single stop path

**Files:** Create `lib/koholint/engine.rb`, `lib/koholint/canonical_save.rb`; Test `test/engine_test.rb`

**Interfaces:**
- Consumes: everything above.
- Produces: `Engine.new(run:, policy:, budget:, keyframe_every: 1800)`; `#run -> Symbol` (the stop reason) and `#request_stop`; each iteration: `Perception.read` → emit `perception` (with `state_hash`) → policy decides one tactical `DecisionPoint(:move)` → emit `decision` → execute for the chosen macro's frames, appending each frame to `InputLog` and ticking the budget → emit `action`; keyframe + `keyframe` event every `keyframe_every` frames. Every 60 frames the engine hashes `Emulator#cartridge_ram`; when it changed (the game itself saved), it writes `save/<frame>.sav` and emits `save{source: 'game'}`, so real saves are timeline events, forkable like any other point. Stop path (the only one): flush `InputLog`, `CanonicalSave.write(emulator, run) -> path` (cart RAM to `save/<frame>.sav` plus `save{source: 'stop'}`), final keyframe, emit `stop{reason}`, set manifest `status`. `Engine.resume(run_path, policy:, budget:)` rebuilds the emulator via `Replay.to(run, journal_frames)`.

- [ ] **Step 1: Test** `stops_at_frame_budget_with_single_stop_event` (budget `frames: 900`: exactly one `stop` event, manifest status `stopped`, `inputs.frames == 900`, a `save` event with `source: 'stop'` and its file exist); `game_save_becomes_trace_event` (script the in-game save menu input sequence, assert a `save{source: 'game'}` event appears at that frame and the `.sav` hash matches `cartridge_ram`); `request_stop_in_unlimited_run_takes_stop_path` (unlimited budget, thread calls `request_stop` after 200 frames); `resume_continues_bit_exact` (run 600, resume to 1 200, state hash equals an uninterrupted 1 200 run); `resume_survives_truncated_trace_line`; `every_decision_has_matching_perception_before_it`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Trap `INT`/`TERM` in the CLI only (Task 11), not in `Engine`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the engine loop with a single stop path and bit-exact resume"`

### Task 11: CLI and run summary

**Files:** Create `bin/koholint`, `lib/koholint/summary.rb`; Test `test/summary_test.rb`, `test/cli_test.rb`

**Interfaces:**
- Produces: `bin/koholint run [--frames N] [--steps N] [--minutes N] [--dollars X] [--flow-version V]`, `bin/koholint resume <run_dir>`, `bin/koholint fork <run_dir> --at-frame N`, `bin/koholint verify <run_dir>` (replay hash check, exit 1 on divergence), `bin/koholint summary <run_dir>`; `Summary.for(run) -> {health:, hearts:, objective:, last_notable:, highest_milestone:, frames:, cost_usd:}` derived only from the trace (`health` ∈ `progressing|stalled|dead|stopped`); INT/TERM trigger `Engine#request_stop`.

- [ ] **Step 1: Test** `summary_is_derived_from_trace_only` (hand-built trace fixture → expected hash), `cli_run_then_verify_exits_zero` (900-frame run, then `verify`), `cli_missing_rom_prints_one_line_error_and_exits_nonzero`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Run a real 3-minute-of-game headless run** (`bin/koholint run --frames 10800`), then `bin/koholint verify` and `summary`; record frames/second and the outcome in the commit.
- [ ] **Step 6: Commit** `git commit -m "Add the CLI and trace-derived run summary"`

---

## Self-review against the spec

- Covered here: run model, trace, replay/fork, keyframes, budgets with sleep tolerance, stop path, single-source summary, build-order slice, process cap (Task 1).
- Deliberately deferred to later plans (each depends on this foundation): world model schema + validators, skill registry, Jev/Claude contract clients (`claude -p` isolation), step/objective lifecycle and loop detection, milestone ladder detection (shield, sword), live web view (A + C), navigation/combat spike, manual digest.
- Real saves and keyframes are trace events (`save`, `keyframe`): "how far are we" = the last `save{source: 'game'}` event; the journal gives exact position.
- Known spec deviation to confirm in Task 6: keyframes may embed the ROM if emu-gb's dump cannot strip it (local, gitignored only).
- Open dependency: the repo README says `gemboy`; the local checkout is `~/Code/emu-gb` (the Tetris project uses the same). Task 1 documents `$EMU_GB_HOME`.
