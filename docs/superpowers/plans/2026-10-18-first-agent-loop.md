# Koholint First Agent Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent (Claude through `claude -p`) plays the starting house of Link's Awakening DX through the engine: it picks its own objective, chooses generic actions from a typed registry, reads dialogue from an image, and is measured (frames, calls, cost) on leaving the starting house.

**Architecture:** The engine stays the loop owner. Perception gets the missing "can the player act" signals; a skill registry turns agent choices into frame-by-frame inputs with typed results; an `Objectives` object (pure code) owns objective lifecycle, predicates, stall limits and loop detection; a `ClaudeCli` client calls `claude -p` stateless and isolated; `Policies::Delegated` (the policy that delegates its decisions to an agent client) assembles the context (grid, memory, attempts, manual digest) through `Agents::Context` and asks the decision point to validate the answers; every failure degrades to a deterministic `wait` and is traced. Replays never call the agent: the journal records the inputs.

**Tech Stack:** Ruby 4.0.1, minitest, `claude -p` 2.1.x (flags used: `--output-format json`, `--json-schema`, `--tools ""`, `--no-session-persistence`, `--setting-sources ""`, `--system-prompt`, `--model`, `--max-budget-usd`), stdlib only.

**Spec:** `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md` (Decision points, Step definition, Agent context contract); earlier plans: `docs/superpowers/plans/2026-10-18-vision-and-grid.md`.

## Owner decisions for this plan (2026-10-18)

- Agents: **Claude only** first (tactical and strategic both through `claude -p`); the decision points stay routable so Jev can take `:choose_skill` later without touching the loop.
- Dialogue: the agent reads the **dialogue box as an image** (cropped, upscaled), and its transcription is written to the trace.
- Model and budget: **Sonnet, one dollar cap per run** (configurable, stops the run cleanly).
- First objective: **chosen by the agent** from the manual digest and the game state; the plan's success measure (leaving the starting house place) is computed by code, never by the agent's claim.

## Facts established (from the previous plans and live checks; re-verify, do not trust blindly)

- Boot: the state-based `Policies::StartGame` reaches gameplay (game_mode 0x0B) at frame ~230. Link is moved by the game until ~f258 (cutscene), a dialogue box opens near f778 (`dialog_state` RAM 0xC19F non-zero), and `A` taps (3 frames held, 57 idle) close the chain around f1560. `Perception#controllable?` (hp > 0 and x > 0) is already true during the cutscene and the dialogue: it is not "free to act".
- `game_submode` != 7 in mode 0x0B means loading/fade-in (grid snapshots are overlays then).
- Link: two 8x16 sprites; his cell is row (y-8)/16, col x/16 on the 8x10 grid; about 1 px per frame while a direction is held; a 2-frame tap moves ~1 px. The grid builder (`run --grid`) gives `context[:grid]` (`Vision::Grid`) and records beliefs by probes on emulator copies (~0.65 s each); real walking teaches nothing by itself.
- `claude -p --output-format json` returns `structured_output` (when `--json-schema` is given), `total_cost_usd`, `usage` (tokens), `duration_api_ms`, `num_turns`, `is_error`. A haiku call with a 3-line system prompt cost about 0.0003 USD and took about 2 s; the base prompt overhead is ~1.2k tokens. Emulation runs at ~100 frames per second with YJIT.
- The manual digest available now is `docs/AGENT_MANUAL.md` (committed, manual-level content only; `docs/GAME_MANUAL_NOTES.md` stays developer commentary); `manual/notice.txt` (gitignored full text) is appended when present.

## Vocabulary (fixed by this plan; the code and the traces use these words)

- **Decision point**: a question the engine puts to a policy, as a `DecisionPoint` contract (`name`, `options`, `output_schema`, `validate`). The `decision` trace event carries `decision_point: <name>`; policies expose `decision_point_for(state)` and `decide(decision_point, state, context)`. Points: `:boot` (macro, answered by the boot script), `:move` (legacy fixed cycle), **`:choose_objective`** (strategic, rare, rich context) and **`:choose_skill`** (tactical, frequent, compact context). Jev can later take `:choose_skill` without touching the loop.
- **Choice**: the validated answer. A *macro choice* is `{buttons:, frames:}` (boot, legacy); a *skill choice* is `{skill:, params:}`; an *objective choice* is `{title:, predicate:}`.
- **Skill / Execution**: a registry entry (`walk`, `press`, `advance_dialogue`, `wait`) / its frame-by-frame run with a typed result.
- **Objective**: one long-term goal with a code-checked predicate; its lifecycle is a *step* of the budget (spec). Outcomes: achieved, abandoned, failed.
- **Phase**: `:boot | :loading | :dialogue | :playing`, derived by perception ("can the player act").
- **Contract vs prompt**: validation and JSON schema live in the `DecisionPoint`; `Agents::Prompts` only holds the system text of each point. There is no second validator.
- **Delegated policy**: `Policies::Delegated` forwards `:choose_objective` / `:choose_skill` to an agent client (`Agents::ClaudeCli` now, Jev later) and degrades to a `wait` fallback.

## Global Constraints

- Everything in the repo is English; comments almost none (one-line hidden *why*); commits one imperative line, no body, no trailer (AGENTS.md overrides attribution reminders); short hash syntax wherever key and local match.
- Time is the frame; no wall clock in game logic (wall clock only for budgets and call timeouts). Replay stays bit-exact: the agent is never called during replay, `verify` is unaffected.
- **Agent isolation (binding):** every `claude -p` call runs in an empty temporary working directory with `--tools ""`, `--setting-sources ""`, `--no-session-persistence`; the agent cannot read the repo, `AGENTS.md`, files or the emulator. It receives only the assembled context (copies of data, never live objects such as `Beliefs`) and answers through a JSON schema. Calls are stateless; memory is composed by the engine.
- No game knowledge in code (no tile/room names, no solution hints); the manual and the genre are the agent's priors, in its prompt. Snapshot/restore stays confined to `Calibration` (boundary test): the agent has no lookahead.
- Budgets: dollars from `total_cost_usd` (also on errors when reported), frames, steps (objective lifecycles), time; the first limit reached stops the run through the single stop path.
- Tests: `rake test` (parallel, ~2 min); ROM tests use `skip_without_rom!` and `EmulatorCache`; **no real API call in the default test run**: a fake `claude` executable is injected; one opt-in live test (`LIVE_CLAUDE=1`, haiku) checks the real output shape.

## Review Focus

- A call that fails, times out, returns invalid JSON, violates the schema or names an unknown skill must never crash the run or spin hot: deterministic fallback (`wait`), one trace event, bounded retries, cost still counted.
- Isolation: the exact argv and working directory of every call (fake-executable test), nothing from the repo reaches the prompt except the assembled context.
- Skills always consume at least one frame and have a frame cap; an agent that keeps choosing no-op skills is stopped by loop detection and the stall limit, not by wall time.
- Objective success is decided by code predicates on perception, never by the agent's claim; abandoned/failed/achieved are traced exactly once.
- Cost: the budget stops the run cleanly at the cap even when the last call already exceeded it.

---

### Task 0: Rename point to decision_point

**Files:** Modify `lib/koholint/engine.rb`, `lib/koholint/trace.rb`, `lib/koholint/policies/{start_game,walk_and_talk,with_fallback}.rb`, `lib/koholint/summary.rb` and `lib/koholint/viewer/*` where they read the key, the tests that name them (`decision`, `start_game`, `engine`, `summary`, `feed`, `screen_diff`, `grid_builder` tests), `docs/` mentions

**Interfaces:**
- Mechanical rename, no behavior change: `Policy#point_for(state)` -> `#decision_point_for(state)`; `decide(point, state, context)` -> `decide(decision_point, state, context)`; `Engine.new(point:)` -> `decision_point:`; the `decision` trace key `point` -> `decision_point` (trace schema, summary, viewer feed and page, fixtures). The class `DecisionPoint` and its factories keep their names.
- Ruling: no `flow_version` bump and no migration of old traces: only disposable demo runs exist, and `Trace` validation would reject an old `point` key (say so in the report).
- [ ] **Step 1:** `grep -rn "point" lib test bin docs` before and after; the suite is the safety net. **Step 2:** `rake test` green. **Step 3: Commit** `Rename point to decision_point`

### Task 1: Player-control perception

**Files:** Modify `lib/koholint/game_state.rb`, `lib/koholint/perception.rb`; Test `test/perception_test.rb`, `test/game_state_test.rb`

**Interfaces:**
- Produces: `GameState` gains `dialog_state` (Integer, RAM `dialog_state` address already in `data/addresses.json`) and the derived predicates `dialog_open?` (`dialog_state` non-zero), `loading?` (mode 0x0B and submode != 7, using the same constants as `ScreenVision`: share them, do not duplicate), `phase -> :boot | :loading | :dialogue | :playing` (`:boot` while `game_mode` != 0x0B, `:loading`, `:dialogue`, else `:playing`). `controllable?` keeps its meaning (the boot policy hands over on it).
- [ ] **Step 1: Tests.** Fake-state tests of each predicate and `phase`; ROM test on `EmulatorCache.at(700)` (`:playing` or `:boot` per the real values: report them), a state inside the dialogue chain (step ~120 frames after f778 with idle inputs) is `:dialogue`, `EmulatorCache.interactive` is `:playing` and `dialog_open?` false.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Perceive dialogue and loading phases`

### Task 2: Skill registry and executions

**Files:** Modify `lib/koholint/decision.rb`; Create `lib/koholint/skills/registry.rb`, `lib/koholint/skills/execution.rb`, `lib/koholint/skills/walk.rb`, `press.rb`, `advance_dialogue.rb`, `wait.rb`; Modify `lib/koholint/engine.rb`; Test `test/skills_test.rb`, `test/engine_test.rb`, `test/decision_test.rb`

**Interfaces:**
- Produces: `Skills::Registry.default -> Registry` with `#names`, `#fetch(name)`, `#schema -> Hash` (JSON-schema fragment describing every skill and its params, used by `DecisionPoint.choose_skill`); each skill responds to `#start(state, params) -> Execution` and `#params_schema`. `Execution#next_input(state) -> Array<Symbol> | nil` (buttons to hold for the next frame; nil = finished) and `#result(state) -> Hash` with keys `skill, params, frames, from: {room, map, x, y, row, col}, to: {…}, moved_cells, room_changed, hp_delta, dialog_before, dialog_after, stopped_by` (`stopped_by` ∈ `done|blocked|frame_cap|dialogue|room_change|damage|budget`). Skills: `walk(direction, cells)` (1-5 cells, holds the direction until Link has moved `cells` cells net from the start cell or he stops moving for 8 frames or 90 frames per cell elapsed, stops early on dialogue opening, room change or damage), `press(button, frames)` (button in a, b, start, select; 1-60 frames; then 10 idle frames), `advance_dialogue` (one cycle: A for 3 frames then 27 idle = 30 frames, stops earlier when the dialogue closes; `dialog_state` is an animation counter (130-135) and is never compared), `wait(frames)` (1-120). Every skill consumes at least one frame; hard cap 400 frames per execution.
- `DecisionPoint.choose_skill(registry)`: name `:choose_skill`, `options: nil`, `output_schema: %i[skill params]`; `validate` accepts only a known skill with params in range (the registry's `ArgumentError` becomes `DecisionPoint::Invalid`); `#json_schema` returns the answer schema for the agent call (`skill`+`params` fragment from the registry, `justification` String, `confidence` 0-1, optional `transcription` String). Existing points are unchanged (`:move`, `macro`).
- Engine: a validated skill choice (`:skill` and `:params`) runs through the registry (a macro choice with `:buttons`/`:frames` keeps working as today): the engine steps frame by frame, appending to the journal as before, checks the budget every frame, emits the existing `decision` event and an `action` event whose `result` is the `Execution#result`. Journal flushing stays per execution.
- [ ] **Step 1: Tests.** Unit tests per skill against a scripted fake state stream; ROM tests from `EmulatorCache.interactive`: `walk(:up, 1)` moves Link one cell (record from/to), `walk(:right, 1)` reports `blocked` (the starting-house wall), `wait(30)` consumes 30 frames, `press(:a, 3)` journals 3+10 frames; a ROM test from `EmulatorCache.at(700)`: `advance_dialogue` in the dialogue chain eventually returns `dialog_after` false or progresses `dialog_state`; unknown skill / out-of-range params raise `ArgumentError` from the registry and `DecisionPoint::Invalid` from `choose_skill#validate` (the policy layer converts them to fallback); `choose_skill#json_schema` is a valid schema naming every registry skill; engine equality: the same choices give identical journals and state hashes on two runs.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Add the skill registry and skill executions`

### Task 3: Objectives (lifecycle, predicates, stall, loop detection)

**Files:** Create `lib/koholint/objectives.rb`; Test `test/objectives_test.rb`

**Interfaces:**
- Produces: `Objectives.new(trace:, stall_frames: 1800, loop_window: 12)`; `#current -> Hash | nil` (`{id:, title:, predicate:, started_frame:, attempts: []}`); `#start(frame:, title:, predicate:) -> id` emits `objective{id, status: 'started', predicate}`; `#record_attempt(skill:, params:, result_summary:)`; `#update(state, frame:) -> :achieved | :abandoned | :failed | nil` evaluated by code: predicates `{kind: 'leave_place', place: [room, map]}` (achieved when a non-loading state has another place), `{kind: 'reach_place', place:}`, `{kind: 'reach_cell', place:, row:, col:}`, `{kind: 'dialogue_closed'}` (a dialogue was open since the objective started and is now closed); `abandon(frame:, reason:)`; stall: no change of (place, Link cell, dialog_state, hp) for `stall_frames` -> `abandoned` with reason `stall`; loop detection: the same (place, cell, dialog_state, skill, params) repeated `loop_window` times with no state change -> `abandoned` with reason `loop`; Link dying (hp 0 after having positive hp) -> `failed`. `Objectives::PREDICATES` (kind => required fields) and `Objectives.valid_predicate?(hash)` are the single description of the four kinds, reused by the objective decision point. Each terminal outcome emits exactly one `objective` event (`status` achieved/abandoned/failed) and clears `current`; `#attempts_for_prompt -> Array<String>` (last 10 compact lines) and `#history -> Array` (finished objectives with outcome) for the agent context.
- [ ] **Step 1: Tests.** Pure tests with hand-built `GameState`s: each predicate, exactly-once terminal events, stall and loop thresholds, failed on death, attempts bounded to 10, `dialogue_closed` needs open-then-closed, a loading state never satisfies `leave_place`.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Add objectives with code-checked predicates, stall and loop detection`

### Task 4: ClaudeCli client

**Files:** Create `lib/koholint/agents/claude_cli.rb`; Test `test/claude_cli_test.rb`, `test/fixtures/fake_claude` (executable script)

**Interfaces:**
- Produces: `Agents::ClaudeCli.new(model: 'sonnet', command: 'claude', timeout: 90, max_call_usd: 0.25, retries: 1)`; `#call(system:, prompt:, schema:, image: nil) -> Agents::Reply` where `Reply = Struct(:output, :cost_usd, :latency_ms, :tokens, :error)` (`output` = parsed `structured_output` Hash or nil; `error` nil or a short String). The call runs `command -p --model M --tools "" --no-session-persistence --setting-sources "" --output-format json --json-schema SCHEMA --system-prompt SYS --max-budget-usd N` in a fresh empty temporary directory (removed afterwards) with the prompt on stdin or as the last argument; with an `image` (PNG bytes) it uses `--input-format stream-json` with a base64 image content block (see Task 7 spike; if the CLI cannot take images this way the reply carries `error: 'image_unsupported'`). Timeouts kill the child process group; JSON parse failures, `is_error`, a missing `structured_output` or a schema-invalid output give `output: nil` and an `error`; cost is read from `total_cost_usd` whenever present (also on errors); `retries` applies only to timeouts and transport errors, not to schema violations.
- [ ] **Step 1: Tests with `test/fixtures/fake_claude`** (a script that records its argv, cwd and stdin to a file named by an env var and prints a canned JSON chosen by another env var): argv contains exactly the isolation flags above and `--model`; cwd is empty and differs from the repo; success returns output, cost, latency, tokens; invalid JSON, `is_error: true`, missing `structured_output`, nonzero exit and timeout (script sleeps) each give an `error` and never raise; the temp dir is removed; the process is killed on timeout; cost counted on an error reply. **Opt-in live test** (`LIVE_CLAUDE=1`, model haiku): one real call with a tiny schema returns an output and a positive cost (skipped otherwise).
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Add an isolated claude -p client with a fake-executable test harness`

### Task 5: Agent context, objective decision point and prompts

**Files:** Create `lib/koholint/agents/context.rb`, `lib/koholint/agents/prompts.rb`; Modify `lib/koholint/decision.rb`; Test `test/agents_context_test.rb`, `test/prompts_test.rb`, `test/decision_test.rb`

**Interfaces:**
- Consumes: Tasks 1-3, `Skills::Registry`, `Vision::Grid`. Produces: `Agents::Context.build(state:, grid:, objective:, history:, attempts:, manual:, last_results:, max_chars: 6000) -> String` rendering: phase, place, Link cell and pixel position, hearts, an 8x10 ASCII grid (one symbol per cell: `.` passable, `#` blocked, `?` unknown, `!` stale, `~` one-way, `o` static object, `@` Link, rows and columns numbered) with a legend, a per-direction neighbour table (belief and last skill result towards it), the current objective with its predicate and attempts, finished objectives, the last 6 skill results, and the manual digest; cut to `max_chars` by dropping the oldest history first (never the grid, the objective or the legend). `DecisionPoint.choose_objective`: name `:choose_objective`, `options: nil`, `output_schema: %i[title predicate]`; `validate` requires a non-empty title and `Objectives.valid_predicate?`; `#json_schema` gives the answer schema (title, a predicate from the four kinds with its fields, `justification`, `confidence`). `Agents::Prompts.system_for(decision_point) -> String` returns the system text of `:choose_objective` / `:choose_skill`: the role (a player who knows the manual and the genre, no walkthrough), the output rules and that unknown cells are not walls. Validation stays in the decision points: no `Contracts` module.
- [ ] **Step 1: Tests.** A hand-built state/grid renders the exact ASCII lines and legend (snapshot of the string); the char cap drops history but never the grid/objective; both decision points' `json_schema` are valid JSON Schema objects, `choose_objective` accepts good outputs and rejects an empty title, an unknown predicate kind and a predicate missing fields; `Prompts.system_for` is non-empty for both points and mentions no game fact; no live object leaks (the context is a String; a test asserts `Agents::Context.build` does not call methods that mutate the grid or beliefs by passing frozen copies).
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Assemble the agent context and add the objective decision point and prompts`

### Task 6: Delegated policy, engine integration, CLI

**Files:** Create `lib/koholint/policies/delegated.rb`; Modify `lib/koholint/engine.rb`, `lib/koholint/cli.rb`, `lib/koholint/budget.rb`; Test `test/delegated_policy_test.rb`, `test/cli_test.rb`

**Interfaces:**
- Consumes: Tasks 2-5. Produces: `Policies::Delegated.new(client:, registry:, objectives:, manual:, clock:)`; `#decision_point_for(state)` returns `DecisionPoint.choose_objective` when no objective is current, else `DecisionPoint.choose_skill(registry)`. Boot stays with the existing `StartGame` wrapper (`StartGame(Delegated)`): `StartGame` gains an optional `ready:` predicate (default `controllable?`, so `WalkAndTalk` is unchanged) and the agent wiring passes `ready: ->(s) { %i[playing dialogue].include?(s.phase) }`, so the boot script runs until the phase is `:playing` or `:dialogue`. `#decide(decision_point, state, context)` dispatches on `decision_point.name`, builds the context, calls the client with `Prompts.system_for(decision_point)` and `decision_point.json_schema`, and returns `{choice:, justification:, confidence:, agent: 'claude', latency_ms:, cost_usd:}`; invalid output, an `error` reply or an exception falls back to `{choice: {skill: 'wait', params: {frames: 30}}, fallback: true}` (also for a failed `:choose_objective`: the next tour asks again, bounded by the stall and loop rules and the budget) with the error as the justification (trace `decision` fields already carry `latency_ms`/`cost_usd`/`fallback`); a validated objective choice starts the objective through `Objectives#start`; after each execution the engine records the attempt and calls `Objectives#update` (terminal outcomes emit through it); the engine adds `cost_usd` of each decision to the `Budget`. `Budget` gains `max_dollars` enforcement already present (`dollars:`): ensure the run stops cleanly when the cap is exceeded by the last call. CLI: `run --agent [--model M] [--max-dollars X]` (defaults sonnet, 1.0; implies `--grid`), accepted by `resume`; a missing `claude` executable is a one-line error. Wall-clock timeouts are the client's; the loop never sleeps.
- [ ] **Step 1: Tests.** With a scripted fake client: first decision is `:choose_objective`, then `:choose_skill`; invalid output -> fallback `wait` and a traced error; client errors never raise; cost accumulates and stops the run at the cap (cap smaller than one reply); an achieved predicate emits one `objective` event and the next iteration asks `:choose_objective` again; loop detection after repeated no-op choices abandons the objective; `--agent` plumbing in the CLI test with the fake executable via `--claude-command`; engine equality is not applicable (the agent decides) but a recorded run replays bit-exact through `Replay.verify`.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Add the delegated policy and wire it into the engine and CLI`

### Task 7: Dialogue image and transcription

**Files:** Create `lib/koholint/vision/dialogue_shot.rb`; Modify `lib/koholint/policies/delegated.rb`, `lib/koholint/trace.rb`, `lib/koholint/agents/claude_cli.rb`; Test `test/dialogue_shot_test.rb`, `test/delegated_policy_test.rb`

**Interfaces:**
- Produces: spike first: determine, with one real haiku call (opt-in), whether `claude -p --input-format stream-json` accepts a base64 PNG content block and answers with `--json-schema`; record the working invocation in the report; if impossible, report it and stop this task (the agent then only knows a dialogue is open). `Vision::DialogueShot.crop(emulator) -> String` (PNG bytes): the dialogue box region (screen rows covering grid rows 5-7: find the exact pixel box empirically from a frame with `dialog_state` non-zero), upscaled x4 with the existing `Png`; `Trace` gains `dialogue{place, text, source, page}` (`source: 'agent'`); when `phase == :dialogue` the delegated policy sends the crop with the `:choose_skill` prompt (the schema already carries the optional `transcription` String); a non-empty transcription is emitted as a `dialogue` event (page = number of `advance_dialogue` results since the dialogue opened).
- [ ] **Step 1: Tests.** `crop` on the real dialogue state (from `EmulatorCache.at(700)` plus idle until `dialog_open?`) returns a PNG with the expected dimensions and non-uniform pixels (pixel-compare against a crop of the driver PNG); fake-client test that an image is passed only in `:dialogue`; a transcription becomes a `dialogue` event, an empty one does not; `Trace` accepts the new type and rejects a missing field.
- [ ] **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Read dialogue boxes as images and record the transcription`

### Task 8: Live view of agent decisions

**Files:** Modify `lib/koholint/viewer/page.html`, `lib/koholint/viewer/feed.rb`; Test `test/page_test.rb`, `test/feed_test.rb`

**Interfaces:**
- Produces: the event list shows agent decisions readably (`f1234 · claude decides walk up 2` with the justification as a hover title and a `fallback` marker), `action` results (`walked 1 cell, stopped: blocked`), `objective` events (`objective: leave_place … started/achieved/abandoned (stall)`) and `dialogue` transcriptions; the status bar shows the current objective, the run's dollars spent and the number of agent calls (from the trace); the JSON toggle keeps the raw events. Pure formatting functions stay in the `// pure:begin` block and are tested through node.
- [ ] **Step 1: Tests** for each new format (node) and for the feed fields (objective, calls, dollars) on a hand-built trace. **Step 2-4:** FAIL -> implement -> PASS. **Step 5: Commit** `Show agent decisions, objectives and dialogue in the live view`

### Task 9: First live run and measurement

**Files:** Modify `ROADMAP.md`, `README.md`; Create `docs/runs/2026-10-first-agent-run.md` (measurements only)

- [ ] **Step 1 (manual, report it):** run `bin/koholint run --agent --realtime --max-dollars 1 --root <tmp>` with `watch` open; let it run until the objective is achieved, the budget is reached, or the stall limit stops it. Record: frames played, agent calls, dollars, objectives with outcomes, whether it left the starting house place, how it handled the intro dialogue chain, the worst-looking decisions with their justifications, and every point where the context or the skills were insufficient.
- [ ] **Step 2:** write the measurements (a table plus a short "what was missing" list) into `docs/runs/2026-10-first-agent-run.md`; update `ROADMAP.md`: remove what landed, add what the run showed missing (do not invent). **Step 3: Commit** `Record the first agent run and update the roadmap`

---

## Execution notes
Order: Task 0 (cheap model), then Task 1, then Tasks 2 / 3 / 4 in parallel (disjoint files), then Task 5 (needs 2), then Task 6 (needs 2-5), then Tasks 7 and 8, then Task 9 by the controller with the owner watching. Tasks 4 and 7 touch the client: run them sequentially.

## Self-review against the discussion
- Agent plays, code decides success: Objectives predicates and the exit-the-house measure are code. Skills are generic (walk, press, advance_dialogue, wait): no route, no game fact. Isolation and no-lookahead are enforced by argv/cwd tests and the existing calibration boundary test. Claude-only, image dialogue, Sonnet with a 1 dollar cap, self-chosen first objective: as decided.
- Not in this plan: Jev wiring, deterministic dialogue text decoding, leads extracted from dialogues, item/inventory perception and milestones (shield, sword), push/swim/combat skills, objective hierarchies; they stay in `ROADMAP.md`.
