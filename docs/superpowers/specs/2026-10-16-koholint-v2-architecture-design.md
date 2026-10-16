# Koholint v2 — deterministic game engine that calls agents

Status: draft for owner approval. Written from a brainstorming session on 2026-10-16.

## Intent

Koholint v1 is an agent session that plays Link's Awakening DX: the game runs inside a Claude
conversation, process rules live in prose (`AGENTS.md`, roles, MetaPlanner), and progress is
tracked in Markdown. After two months it has 27 labeled rooms, a solid perception layer (RAM,
VRAM terrain), and no game milestone. Process rules were repeatedly violated because nothing
enforces them. Real saves and throwaway savestates are mixed, so "how far are we" has no answer.

v2 inverts the dependency: **a deterministic engine owns the game loop and calls agents at defined
decision points**. The agent cannot leave its role because it only has decision contracts. A run
is a self-contained, versioned, observable unit stored in the repo.

Reference lessons from Jev×Tetris (`../terraindejeu/jev/tetris`): runner + pluggable strategies,
a deterministic baseline that beat the LLM strategies (so keep one as yardstick), per-call
latency/cost logging, seeds. Its weak spots to avoid: unstructured `runs/`, no strategy version
attached to a run, hand-built reports, video capture changing RNG timing.

## Goals

1. Deterministic game loop; agents are called only at decision points.
2. Distinct **runs** (`runs/<id>/`), versioned by `flow_version`; a V1 run cannot continue on V2.
3. Simple game state, short-term and long-term memory.
4. Deterministic where possible: perception, intra/inter-screen navigation on known terrain,
   action library, gameplay loop skeleton.
5. Agent-decided: next short-term action from a growing library ("go to X", "talk to Y",
   "destroy enemy Z") and the current long-term objective (find item, reach dungeon, find person).
6. Live observability (video + decision/action feed) and headless mode on the same engine.
7. Time/money budgets, including unbounded.
8. Workflow amendment is a separate engineering flow; a run may only emit suggestions.

## Non-goals / anti-goals

- No walkthrough knowledge. The agent knows the **game manual** (in repo, see D14 and
  `docs/GAME_MANUAL_NOTES.md`) and is assumed familiar with the genre (not a first video game).
  Where items are, who NPCs are, how puzzles resolve: discovered during the run.
- No hand-written morning report. Reports are views over the trace.
- No role ceremony (Explorer/Builder/Reviewer/MetaPlanner sessions) inside the game loop.
- Anti-goal: a design where the agent can write facts into long-term memory unchecked, or where a
  savestate silently defines "progress".
- Game progress from v1 is discarded. Runs start from a new game.

## Knowledge regimes (explicit in the repo)

1. **Manual**: static, read-only, given to the agent at start.
2. **Run knowledge**: facts observed during this run (`world.json`). Each run starts empty.
3. **Engineering knowledge**: RAM addresses, VRAM terrain signatures, movement constants. Used by
   deterministic perception; the agent sees derived values ("3 of 5 hearts"), never addresses.
   Existing `data/ram_registry.json` provenance rules (`verified_count`) apply here only.

## Architecture

Layers, bottom to top:

- **Emulator adapter** (gemboy, DMG mode per D3). Time unit is the frame. No wall clock, no
  video-capture side effects on emulation.
- **Perception** (kept from v1: RAM/HRAM reads, VRAM terrain, dialogue text): produces a typed
  `GameState` (hearts, items, position, room, dialogue, nearby entities).
- **Action library**: deterministic skills (`goto(target)` via pathfinding on known collision
  grid, `talk`, `use_item`, `attack` basics). Each skill returns a typed result.
- **Decision points**: contracts `(input schema, allowed options, output schema)`. Routing to
  an agent is configuration in the flow definition.
  - Tactical, many calls, compact state, closed choices: **Jev** (e.g. where to move on screen).
  - Strategic, rare, rich context: **Claude** (next major objective, interpreting NPC dialogue).
  - The split is provisional; moving a decision between agents must not change the loop.
- **Engine loop**: perceive → (strategic decision if objective unset/done/failed) → (tactical
  decision) → execute skill → record → check budget.
- **Observability server**: reads the trace, serves the live view.

Navigation proposal (to validate by spike, after design): deterministic pathfinding on known
terrain; Jev supplies local intent at decision points as macros (direction + frame count), not
per-frame buttons; hybrid chosen by measured success/frames/cost/latency. Combat micro-decisions
are an open problem (see Open questions).

## Run model

```
runs/<id>/
  manifest.json   flow_version, parent (fork source), ROM hash, seed, budget, status
  trace.jsonl     append-only typed events; the single source of truth
  save/           canonical game .sav = real progress
  keyframes/      local cache of savestates every 30–60 game seconds, tied to a trace line (gitignored)
  inputs.log      compressed per-frame button journal
  world.json      run knowledge
  suggestions.md  flow gaps noticed by the run (only file the loop writes about the flow)
```

- Only the engine writes `trace.jsonl` and `save/`.
- **Progress** = the last in-game save (a `save{source: game}` trace event, detected by the engine when cartridge RAM changes) + the trace. Saves and keyframes are events on the same timeline, so any of them is a fork point. Savestates/keyframes are disposable accelerators.
- **Resume**: last keyframe + input replay, or `.sav` if missing; same `flow_version` required.
- **Fork**: new run with `parent` link from any point of the trace (nearest keyframe + replay up
  to the point). Required to test a modified flow on the same critical moment. Nothing is
  overwritten.
- **Durable progress = canonical `.sav` + `inputs.log` from boot + ROM hash.** Any machine with
  the ROM can reproduce the exact state from the repo alone. Keyframes are a local cache of the
  replay, regenerable, gitignored.
- **Snapshot size**: v1's `Motherboard#dump` is ~2.7 MB because it embeds the ROM. A keyframe must
  serialize machine state *without* the ROM (target tens of KB, unmeasured). Keyframes never
  contain the ROM.
- **Replay cost**: measured locally (Task 2, `bin/measure_speed`, 2026-10-16, Apple silicon, Ruby 4.0.1):
  **26 fps without YJIT (0.44x real time, matching the v1 remote figure) and 96 fps with `--yjit`
  (1.6x real time).** The engine and tests must run with YJIT. At 96 fps, 5 game-minutes replay in
  ~3 min and 10 game-hours in ~6 h; keyframe interval stays a candidate of 30–60 game seconds
  (~20–40 s of replay worst case).
- **Sleep and interruption tolerance**: runs must survive the machine sleeping or the process being
  suspended. Game time is frames, so suspension never affects determinism. Wall-clock budgets count
  active time only (monotonic, gaps over a threshold excluded); agent calls have timeouts and
  bounded retries and a call interrupted by sleep is retried, not traced as a failure; the engine
  checkpoints (trace flush + periodic keyframe) so a killed process resumes from the last one.
  Optional wrapper to keep the Mac awake for long runs (`caffeinate -i`); the design must not
  depend on it.
- **Hard requirement**: bit-exact replay. A test replays a run and compares state hashes at
  fixed intervals. Tetris showed video capture shifting RNG; the engine must forbid it.

## Trace

One typed, schema-versioned line per event: perception summary, delegated decision, action,
result, budget stop, notable event, stop. A delegated decision records: perceived input (plus
image if the agent saw one), options offered, choice with brief justification and confidence,
model, latency, cost, resulting state delta. "Notable event" (proposal): new item, new area,
first-seen dialogue, large heart loss, objective change. A "health" line (progressing / blocked
for N frames / dead) is derived, not authored.

## Session & budget

A session = one engine run segment with an optional budget. Budgets compose and the first
reached stops the session: game frames, steps (proposal: one step = one long-term objective
reached or abandoned), wall-clock time, dollars, or unlimited until stopped. Stopping — by budget
or by the owner — always follows one path: write the canonical save, final keyframe, trace event,
done. Per-call cost/latency feeds the budget live.

## Step definition (my call, precise version)

A step is the lifecycle of one top-level long-term objective, created by a strategic decision. It
is created with a **success predicate** (a check over `GameState`/dialogue, e.g. "item X in
inventory", "room Y entered", "NPC Z spoke to") and a **stall limit** (frames without trace-level
progress). It ends in exactly one terminal outcome, each a trace event:
- `achieved`: predicate true, checked by perception, not by the agent's claim. If an objective has
  no machine-checkable predicate, Claude judges it and the judgment is traced as such.
- `abandoned`: the agent changes objective at a strategic decision, or the stall limit is hit.
- `failed`: Link dies during it.

"N steps" budget = N objectives with any terminal outcome. Sub-goals and tactical actions are not
steps. Steps vary a lot in size, so a step budget is a coarse pacing tool; use frames, time or
dollars when comparing flow versions.

## Live view

Local web page served from the trace (single source). Layout chosen by the owner: **A + C** —
central game video with a decision/action feed on the right and a top bar (run id, flow version,
status/health, budget, pause/stop); below, a session timeline of notable events, Claude calls
and blockages, clickable to review a moment or fork from it. State panel: hearts, objective with
elapsed frames, last notable event. Headless mode = same engine without the viewer.

## Enforcement

- Agents only get decision contracts with validated output schemas; no file or emulator tools.
- Two separate flows. **Play**: loop writes only under `runs/`. **Evolve the flow**: ordinary
  engineering (tests, PRs) producing a new `flow_version`. The MetaPlanner as a session type
  disappears into this second flow; `suggestions.md` is its input.

## Reuse / discard

Keep: perception (RAM/HRAM, VRAM terrain, dialogue decoding), movement constants as facts (≈8 px
steps, tap vs hold), the manual notes, D3/D12/D14 intent. Discard: v1 `Navigator`, checkpoint
scripts, `ram_registry` room labels and world model, autonomous-recovery/ResearchTask machinery,
`NEXT.md`/MetaPlanner process.

## Audit against v1 failure modes (docs/RETROSPECTIVE.md R1–R10)

| v1 failure | Does this design prevent it? | Added below |
|---|---|---|
| R1 loop never built; humans were the loop | Partly: inversion is in the design, but nothing forced build order | Build-order rule |
| R2 world model was prose | No: `world.json` had no schema | World model schema |
| R3 rules enforced by documentation | Partly: engine-only writes | Validators on every write |
| R4 meta-process before the product | Partly: roles removed, but "evolve the flow" was unbounded | Process cap |
| R5 indicators drifted from the goal | No: no primary score | Primary score |
| R6 action vocabulary too small | No: skills listed, no extension mechanism | Skill registry |
| R7 throughput never budgeted | No (and the replay claim above was wrong) | Corrected; measure first |
| R8 no way to abandon a subgoal | Mostly: step stall/abandon exists | Loop detection, attempt memory |
| R9 progress in /tmp on one machine | Yes with `.sav` + `inputs.log` | Entry point, manifest |
| R10 narrative memory re-read each time | No: agent context undefined | Agent context contract |

### Build-order rule (R1, R4)
The first deliverable is a vertical slice: engine loop + trace + canonical save + budget stop,
driven by a trivial deterministic policy (no agent) that walks and talks. Perception, skills and
agents are added to a loop that already runs. Nothing may be built that the slice does not call.
Process artifacts are capped: `AGENTS.md` ≤ 1 page, no role taxonomy, no escalation queue.
`suggestions.md` entries are structured (`decision_point`, `symptom`, `evidence_trace_lines`),
not free prose, and are read only by the flow-evolution flow.

### Primary score (R5)
The score is a **milestone ladder computed by code from game state**, never narrated: ordered
list of milestones (sword, each dungeon entered / instrument obtained, …) detected by perception.
The run summary shows: highest milestone, frames and dollars since the last milestone change. A
streak of N steps without milestone change raises a `stalled` health state that forces a
strategic re-decision. Milestone detection addresses are hypotheses to verify like any other
engineering fact; the list of milestones is derived from the manual's structure, not a walkthrough.
**Initial ladder (owner, 2026-10-16): shield obtained, then sword obtained.** Extended later by the
owner, as a flow_version change.

### World model schema (R2, R3)
`world.json` is typed, versioned, and validated on every write; free text is limited to a short
bounded `note` field that no code reads.
- `rooms[id]`: visited, entry/exit **edges** `{from, to, direction, kind, observed_by}` forming a
  queryable graph, collision grid (from VRAM terrain read), static objects.
- Every probe-based fact records **how** it was obtained (`tap`/`hold n frames`/`push`/`dive`/
  item used, approach angle). "Wall" with only `tap` is stored as `unconfirmed`.
- `entities`: NPCs, enemies, items seen, with room, first/last seen, interaction results.
- `dialogues`: `{speaker, room, pages[], triggered_by}` with raw decoded text.
- `objectives` and `attempts`: each objective, its predicate, outcome, and every attempted
  approach with result (the memory that stops v1's 240/0 grind).
- Code queries it must answer without an LLM: unexplored frontier, shortest known route A→B,
  where an entity/item was last seen, attempts already tried for an objective.
- Perception rules survive from v1: text decoded by tile bitmap, terrain signatures rebased on
  SCX/SCY and keyed per room, 4–6x upscale before any image goes to a model.

### Skill registry (R6)
A skill is `{name, params, preconditions, result schema, cost in frames}`. New mechanics (push,
dive, attack, use item, pull, ram) enter by adding a skill; the loop and the decision contracts
do not change. Skill results always report what was actually done (tap vs hold, frames). The
manual's mechanics list seeds candidate skills (those v1 never attempted: push, dive).

### Agent context contract (R10, and the agent-role question)
Every agent call is **stateless**; the engine assembles the whole context from fixed templates
with a size cap per decision type:
- Role and contract: one paragraph, allowed options, output schema.
- Manual: a fixed digest (Claude only; builder measures whether the full text fits).
- Objective: current objective, predicate, steps so far, stall counter.
- Perceived state: typed `GameState` rendered compactly; for Jev, only the fields that decision
  needs (target ≤ ~1–2k tokens).
- Memory view: code-selected facts relevant to the decision (queried from `world.json`), last N
  notable events, **attempts already tried** for this objective.
There is no conversation to rotate and no reading order for a cold agent. `claude -p` runs in an
empty working directory with tools disabled and project settings not loaded, so it cannot read
`AGENTS.md`, the repo or the emulator, and outputs are validated against the schema (invalid →
logged, retried once, then the engine falls back to a deterministic default and traces it).

### Loop detection (R8)
The engine hashes the (room, position, objective, recent action) state. N repeats without
progress, or the stall limit, forces a strategic decision whose input includes the attempt
history and which may abandon the objective. The tactical layer can never grind unbounded.

## Owner answers (2026-10-16)

- **Claude is invoked via `claude -p`** (headless CLI, much cheaper than the API). Each strategic
  decision is one `claude -p` call with a JSON output schema; the engine records the reported
  usage/cost fields when present. Dollar budgets are therefore best-effort for Claude calls
  (verify what `claude -p --output-format json` actually reports) and exact for Jev.
- **Manual**: `Notice Zelda.pdf` at the repo root (2.1 MB). It is converted once to text for
  the agent (poppler is not installed here; the builder picks the tool). My call: per D14 the
  original booklet is copyrighted and not committed, so the PDF and its text are gitignored and
  `manual/README.md` says how to regenerate them. `docs/GAME_MANUAL_NOTES.md` (paraphrase) stays.
- **Jev access** uses the same setup as the Tetris project (`.env.1password` via `op run`).

## Open questions

- Combat: many micro-decisions; neither Jev-per-tick (cost, latency) nor pure deterministic is
  validated. Park for the navigation/combat spike.
- Which decisions go to Jev vs Claude; contract granularity.
- Navigation: hybrid design to be settled by spike (A* vs Jev macros vs hybrid).
- Ladder beyond shield and sword (owner will extend later).
- Optional later: inherit a map from a previous run to speed up development.

## My calls (not owner-approved yet)

- Replay-from-boot as durable progress; keyframes are a gitignored cache; the manual PDF/text is
  gitignored (D14).
- Milestone ladder as primary score; stateless agent calls with code-assembled context.
- Sleep tolerance as a design requirement (see Run model).
- Keep Ruby and gemboy (perception already written there).
- Live view as a local web page (video + feed fits better than a terminal).
- Archive v1 via a git tag and build v2 in this repo rather than a new repo.
- Input journal + sparse keyframes rather than dense snapshots.
- "Step" = one long-term objective reaching a terminal outcome (see Step definition).
