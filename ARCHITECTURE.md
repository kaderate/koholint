# Architecture

High-level map of Koholint v2. Keep it in sync with the code: change this file in the same commit as a change to
a layer, a data flow or a run artifact. The detailed design and its rationale are in
`docs/superpowers/specs/`; what remains to build is in `ROADMAP.md`; conventions are in `AGENTS.md`.

## Principle

A deterministic engine plays Link's Awakening DX through the emu-gb emulator. It calls an agent only at
**decision points** and executes what the agent chose with deterministic **skills**. The agent knows the game
manual and the genre, never a walkthrough: game facts are observed and stored as typed data with provenance.
The engine owns the loop, the budgets, the files of a run and the trace; agents never touch them.

```
            ┌────────────────────────── Engine (engine.rb) ───────────────────────────┐
 emulator ─▶│ Perception ─▶ Vision (grid, beliefs) ─▶ Policy.decide(decision point) ─▶ │
 (emu-gb)   │      ▲                                        │ choice                  │
            │      │                                        ▼                         │
            │      └──────── frames ◀──── Skill execution (goto, talk_to, press…) ────┤
            └──── Run (journal, trace, keyframes, saves, summary) ◀── Budget ─────────┘
```

## Layers

**Emulator and replay** — `emulator.rb` wraps emu-gb (headless, paused between engine steps; the engine
decides when frames advance). `input_log.rb` is the append-only input journal; `replay.rb` rebuilds any
state by replaying the journal from boot; `keyframes.rb` and `canonical_save.rb` checkpoint it. The game is
deterministic, so *ROM + journal* is the whole run. Time is the frame; wall clock appears only in budgets,
pacing (`pacer.rb`) and observability.

**Perception** — `perception.rb`, `addresses.rb`, `game_state.rb`, `data/addresses.json`: a typed `GameState`
(position, room/map, HP, phase such as dialogue or locked, milestone) read from RAM. Every address carries
provenance and a `verified_count`; `verified` needs two independent checks. No RAM writes to gameplay state.

**Vision** (`vision/`) — what RAM does not give: `screen_vision` and `screen_snapshot` read the screen,
`grid_builder` probes neighbouring cells (the only place that snapshots and restores the emulator) and
builds a collision `grid`; `beliefs` and `world` accumulate per-place knowledge (observed free, blocked,
doubtful, contradicted); `capabilities` records what Link can do; `dialogue_shot` crops dialogue boxes for the
model. Unknown cells are unknown, not walls.

**Navigation and skills** — `geometry.rb` (cell grid, pixel offsets), `navigation/planner.rb` (shortest path
with the fewest turns over known cells), `skills/` (`walk`, `goto`, `step`, `talk_to`, `press`,
`advance_dialogue`, `wait`) behind `skills/registry.rb`. A skill is a bounded, deterministic action with
validated parameters; it reports how it stopped (`done`, `blocked`, `no_path`, `no_response`…). `ledger.rb`
counts blocked edges per place (doubtful edges), `triggers.rb` forbids inputs that re-fire a scripted event,
`talk_log.rb` remembers which sides of a person gave no response and, per person (the last `talk_to` target), the key (letters
and digits only, as for `new_text`) of each stitched text read and a world stamp (milestone, places visited, leads): the context says whether the last talk gave
new text, how many talks in a row gave nothing new, and `worth retrying` (the stamp changed or the last talk was new) or
`exhausted` (the last two talks repeated under the same stamp).
`dialogues.rb` groups `dialogue` events (same frame and place) into one dialogue and stitches the overlapping pages of a
scrolling text box into the full text without losing a word; the stored events stay raw.

**Decision points and policies** — `decision.rb` defines the points (`choose_objective`, `choose_skill`,
`move`, macros) with their output schema and validation. A policy answers them: `policies/delegated.rb`
(agent-driven; owns the context, plan memory, automatic dialogue pages, lock/hemmed handling),
`policies/walk_and_talk.rb` and `start_game.rb` (deterministic baselines and the intro), `with_fallback.rb`
(an invalid answer falls back deterministically, 5 consecutive fallbacks stop the run).

**Objectives** — `objectives.rb`: a short goal with a predicate the harness checks from memory
(`leave_place`, `reach_place`, `reach_cell`, `dialogue_closed`, `new_place`, `new_text`: a text not read before in
the run, compared whitespace-insensitively on the stitched text, the read texts rebuilt from `dialogue` events on resume); the engine emits started and
achieved/abandoned/failed events; a `started` event may carry `because`, the id of the lead that motivated it. The
long-term direction is the agent's own `goal` (a short text it restates or revises at every objective; the context shows
when it was set). `leads.rb` holds the leads: claims the
agent extracts from texts it read (dialogue, signs, objects), each with a verbatim `quote`, a `claim` and an importance
(`high`, `normal`, `low`). A lead whose quote is not in the transcription of the same call is dropped (`notable`
`lead_rejected`), duplicates are dropped by quote. Goal and leads are rebuilt from the `goal` and `lead` trace events on
resume.

**Agents** (`agents/`) — `context.rb` renders state for the model (grid map, neighbours, objects on screen,
goal, leads — every `high` one, `normal` ones of the current place, never `low` ones —, recent results, plan), `prompts.rb` holds the system prompts, `claude_cli.rb` calls `claude -p` with a JSON
schema and reports cost and latency. Jev (tactical choices) is planned, not wired.

**Run storage** — `run.rb`: `runs/<id>/` with `manifest.json` (flow version, ROM hash, tag, harness/prompts
sha, model), `inputs.log`, `trace.jsonl` (events validated by `trace.rb`), `keyframes/`, `save/`, `prompts/`,
`world.json` (`{ goal, leads }`, rewritten from the trace at every stop), `summary.json` (written at every stop by
`summary.rb` from the trace only, versioned by `Summary::VERSION`: totals, cost by skill, decisions by agent and
feature usage; `archive` rewrites an outdated one), `star.json`. Trace events: `perception`, `decision`, `action`, `objective`, `dialogue`, `lead`, `goal`,
`notable`, `screen`, `screen_changed`, `affordance`, `grid_contradiction`, `keyframe`, `save`, `budget_stop`, `stop`. `budget.rb` enforces frames,
minutes, dollars and objective steps. `archive.rb` keeps a light bundle per run in git (trace gzipped);
heavy artifacts stay local. A run resumes only with the same `flow_version` and ROM hash; a change to the
play flow means a new `flow_version`.

**Viewer** (`viewer.rb`, `viewer/`) — a small HTTP server. A `Follower` replays the journal of the watched
run; `Feed` derives status, feed, reasoning, objectives, goal, leads and the stitched dialogue history (newest first,
with the person talked to) from the trace up to the shown frame. `Explorer` and `Registry` serve
past runs (list, read-only replays with pacing, comparison via `run_compare.rb`, star). It never writes game
state.

**CLI** — `cli.rb`, `bin/koholint`: `run`, `resume`, `fork`, `verify`, `summary`, `watch`, `archive`, `star`,
`prune-heavy`.

## Data flow of one decision

1. The engine reads `GameState` and emits a `perception` event; vision updates the grid and beliefs.
2. The policy gets a decision point and a context. For an agent policy: render context, call the model, validate
   the answer against the schema; invalid twice means deterministic fallback.
3. The engine emits a `decision` event (choice, justification, confidence, cost, latency, prompt sha) and runs
   the chosen skill frame by frame, appending every input to the journal.
4. The skill result becomes an `action` event and feeds the next context; objectives are re-evaluated.
5. The budget is checked after every frame; at stop the engine saves, checkpoints, emits `stop` and writes
   `summary.json`.

## Invariants

- Only the engine writes `trace.jsonl`, `inputs.log` and `save/`; `verify` replays the journal and compares hashes.
- Determinism: the same journal on the same ROM gives the same states. Agents are never called in replay.
- No walkthrough or game knowledge in code or prompts; facts live in `data/addresses.json` and a run's
  `world.json`, with provenance.
- A rule a script can check is a validator, not a paragraph.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`.

## Where things are

| Need | Look at |
|---|---|
| Design rationale | `docs/superpowers/specs/` |
| Plans of past work | `docs/superpowers/plans/` |
| Measurements of agent runs | `docs/runs/` (`index.md` lists every archived run) |
| What remains | `ROADMAP.md` |
| Conventions | `AGENTS.md` |
| Run storage and viewer usage | `README.md` |
| Game manual digest given to the agent | `docs/AGENT_MANUAL.md` |
