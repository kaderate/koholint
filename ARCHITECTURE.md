# Architecture

A map of Koholint v2: what each layer is, which files hold it, and how data moves. Change it in the same commit as a change
to a layer, a data flow or a run artifact. Keep it a map: how a skill or a harness rule behaves, flow by flow, belongs in
`docs/AGENT_SKILLS.md`; measured facts belong in `data/` with their provenance; history belongs in git (the long form of this file
is at 32d43b3). Design rationale: `docs/superpowers/specs/`. What remains: `ROADMAP.md`. Conventions: `AGENTS.md`.

## Principle

A deterministic engine plays Link's Awakening DX through the emu-gb emulator. It calls an agent only at **decision points**
and executes what the agent chose with deterministic **skills**. The agent knows the manual, the genre and how the game is
played, never a walkthrough: where to go is observed or read from in-game texts, and game facts are typed data with provenance.
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

**Emulator and replay** — `emulator.rb` wraps emu-gb, headless and paused between engine steps. `input_log.rb` is the
append-only input journal; `replay.rb` rebuilds any state from boot; `keyframes.rb` and `canonical_save.rb` checkpoint it
(every 1800 frames, at the stop, on each `item_gained` and on each first ready frame in a new place; a fork that has to replay
keyframes the parent locally on the way and the frame before the fork, where the child resumes). Keyframes never feed
perception or decisions. `checkpoints.rb` and `data/checkpoints.json` name points of runs to branch from. The game is
deterministic, so *ROM + journal* is the whole run; time is the frame, and wall clock appears only in budgets, `pacer.rb` and
observability.

**Perception** — `perception.rb`, `addresses.rb`, `game_state.rb` and `data/addresses.json` read a typed `GameState` from RAM
(position, place, hp and pending damage, rupees, phase, items, readiness signals). Every address carries provenance and a
`verified_count`. `entities.rb` reads the 16 entity slots and the room object table and gives each a kind from
`data/entities.json` (`npc`, `enemy`, `creature`, `object`, `unknown`; objects: `sign`, `door`, `chest`, `stone`, …).
`items.rb` and `data/items.json` name item ids; the engine's `ItemWatch` emits `item_gained`. The engine also watches the room
objects every frame and emits `floor_gave_way` when a crumbling floor object turns into a hole; the skills see that object as
crumbling only in places where this was seen. `footing.rb` reads the game's crumble timer for the cell under Link's foot point,
and `Skills::Execution` steps every skill off that cell before it gives way. The probes under `probes/`
(`bin/koholint census …`) measure these files on throwaway copies; they are the only code that writes RAM.

**Game modes** — `modes.rb` and `data/modes.json` catalogue the game's screens by their mode tuple, each with the engine
phase it routes to (`boot`, `loading`, `playing`, `locked`, `dialogue`, `cutscene`, `menu`, `map`, `save`, `game_over` or
`unknown`), its inputs, options and provenance. `GameState#phase` resolves it; an unknown tuple emits one `notable`.

**Readiness gate** — `readiness.rb`: in `playing` and `loading` Link is ready when the `ready` signals of the play mode hold
for 2 frames. Before each iteration the engine steps journalled empty frames until ready (recorded as `not_ready_frames`) and
stops with `not_ready_stuck` after 600. Skills are never interrupted mid-scroll; the next iteration waits.

**Place cards** — `place_card.rb`: on the first ready frame of each visit of a place, the engine emits a `place_card` (people,
enemies, creatures, unknown entities, signs, objects, doors, chests, exits). `world.json` `places` is built from these cards and
the talk log.

**Vision** (`vision/`) — what RAM does not give. `screen_vision` and `screen_snapshot` read the screen; `grid_builder` probes
neighbouring cells (the only place that snapshots and restores the emulator) and builds the collision `grid`, where a cell whose
room object is catalogued as a hole is a hole whatever its look; `beliefs` and
`world` accumulate per-place knowledge; `capabilities` records what Link can do; `dialogue_shot` crops dialogue boxes for the
model. Unknown cells are unknown, not walls.

**Navigation and skills** — `geometry.rb` holds the cell grid, pixel offsets and the one direction vocabulary
(`DIRECTIONS`/`DELTAS`/`OPPOSITE`, `VERTICAL_FIRST` for the order some probes keep, `in_grid?`, `step`).
`navigation/planner.rb` plans shortest paths over known cells around danger, holes and doubtful edges; `navigation/threat.rb`
is the threat interface; `navigation/stones.rb` searches the pushes that open a cell in a room of sliding stones. `skills/` holds the deterministic skills behind `skills/registry.rb`: `walk`, `goto`, `step`,
`talk_to`, `attack`, `explore`, `touch` (harness only), `press`, `advance_dialogue`, `wait`, the screen skills of `screens.rb`,
`use_item` and `guard`, the `shielded` wrapper, `clearing` (operational capabilities used by the moving skills) and
`composite` (learned capabilities). Every skill reports how it stopped (`done`, `blocked`, `no_path`, …).
`explore_log.rb` keeps per place what explore walked, the exits and doors tried and their destinations, surveys and the exit
graph, and cuts a way found unreachable from the landing Link entered by (dropped when Link leaves a room where a stone was pushed); `ledger.rb` counts blocked edges, `triggers.rb` forbids inputs that re-fire a scripted event, `talk_log.rb` remembers
what each person and sign said, `revisit.rb` drives the harness's own talks to people, signs and chests, and `dialogues.rb`
stitches dialogue pages into texts. Their behaviour per flow is in `docs/AGENT_SKILLS.md`.

**Exit graph and puzzles** (`explore_log.rb`) — every crossing is an observation `(place, way) -> place`. A first crossing that
contradicts its hypothesis (the assumed way back, or the neighbouring screen from `data/geometry.json`) raises a `puzzle`
event; a second destination through the same way is a contradiction.

**Exit bench** (offline, `bench.rb`, `exits.rb`, `data/exits.json`) — `koholint bench exits` forks a run at each visit of a
puzzle place and measures each way with a `Bench::ExitTrial` policy and no model call. Trials keep their context and lineage;
`verified` needs agreeing trials from 2 root lineages. Measured edges fill only ways a run never crossed and join the exits
digest.

**Capability learning** (offline, `learn.rb`, `capabilities.rb`, `skills/composite.rb`, `data/capabilities.json`) —
`koholint learn` proposes uncatalogued room objects that blocked Link, tries each held item on them in forks with a
`Learn::Trial` policy, and records hypotheses that become `validated` after successes in 2 places. `koholint capability
publish|retire` moves an entry to or from `operational`, which changes the capabilities digest; operational entries become
`Composite` skills offered while their object is on screen and their item held.

**Decision points and policies** — `decision.rb` defines the points (`choose_objective`, `choose_skill`, `move`, macros) with
their output schema and validation; `DecisionPoint.harness_choice` builds every answer the harness gives in place of the model.
Every policy inherits the no-op hooks of `policies/base.rb` (`observe`, `prepare`, `decision_point_for`, `after_action`,
`note_card`, `offered_candidates`, `cancel`), so the engine calls them without probing.
- `policies/delegated.rb` is the agent policy. Its memory is rebuilt from the trace in one object,
  `Policies::Memory.from_events` (ledger, triggers, talk log, explore log, leads, place cards, loop and zero watches, and each gained item's name words
  read from its pickup text, `Items.pickup_names`, the item objectives started and the candidates whose objective stalled). Its
  concerns are mixed in from `policies/delegated/`: `dialogue.rb` (pages, sheets, cached readings), `waits.rb` (screens,
  locks, hemmed), `outcomes.rb` (what each result teaches the memory) and `guidance.rb` (loop breaks, zero caps, objective
  follow-up, alerts). Before asking the model it lets the harness answer: screen waits, game over, dialogue advance, lock and
  settle waits, revisits, hemmed probes, loop breaks, zero caps, item objectives (a person whose recorded text names a held item, by
  those name words, is talked to with it held, then given it with `use_item`), the explore autopilot (`autopilot.rb`, which also takes a
  visible heart below full health and fights one-strike enemies on sight through a `fight` hook in the skill context that explore checks every frame) and automatic
  objectives. An invalid answer falls back to a wait; 5 fallbacks in a row stop the run.
- `policies/start_game.rb` runs the intro and wraps the policy of every CLI run, forwarding the hooks to it.
- `policies/walk_and_talk.rb` is the deterministic baseline.
- `loop_watch.rb` and `zero_watch.rb` detect loops across places and skills that keep ending at once.

**Candidates** — `candidates.rb` builds the `choose_objective` menu: people, signs and unidentified things here, exits and
doors, chests, known places with untried work, people and signs of other places from their last card, unidentified things
seen still in one place, people who asked Link for something (`need` leads), and places that leads point to. Each candidate has an id, a label, a predicate and a `target`; an unknown id is a refusal.

**Objectives and leads** — `objectives.rb`: a short goal with a predicate the harness checks from memory (`leave_place`,
`reach_place`, `reach_cell`, `dialogue_closed`, `new_place`, `new_text`, …); the engine traces started, achieved, abandoned and
failed. The agent's long-term `goal` is its own text. `leads.rb` holds claims the agent quotes from texts it read, with a status
derived from the objectives that followed them, and the place names; `lead_check.rb` drops a lead that names an item the text
does not (the walkthrough rule), withholds the claim of one naming a person, role or thing of `data/vocabulary.json` that no
text read names, and `koholint check-leads` audits traces for it.

**Agents** (`agents/`) — `context.rb` renders state for the model (grid map, neighbours, things on screen, goal, leads,
results, plan), `prompts.rb` holds the system prompts, `claude_cli.rb` calls `claude -p` with a JSON schema and reports cost
and latency.

**Run storage** — `run.rb`: `runs/<id>/` holds `manifest.json` (flow version, ROM hash, harness sha and dirty flag, model,
autopilot, capabilities and exits digests), `inputs.log`, `trace.jsonl` (events validated by `trace.rb`), `keyframes/`,
`save/`, `screens/` (one capture per place, observability only), `world.json` (`goal`, `leads`, `places`, `pickups`), `summary.json`
(written by `summary.rb` from the trace at every stop), `activity.json`, `suggestions.md`, `star.json` and `notes.md`.
`budget.rb` enforces frames, minutes, dollars and steps. `archive.rb` keeps a light bundle per run in git. A run resumes only
with the same `flow_version`, ROM hash, capabilities digest and exits digest.

**Atlas** (`atlas.rb`) — what every run under one or more roots observed, merged per place, lead and flow, read only from what
the engine wrote; each fork counts from its fork frame. `Atlas.facts` lists every entry of the typed `data/` files with its status
and provenance. `koholint atlas` writes `tmp/atlas.json`; the viewer serves `/atlas`.

**Viewer** (`viewer.rb`, `viewer/`) — a small HTTP server. A `Follower` replays the watched run's journal and seeks by keyframe;
`Feed` and `Insights` derive status, feed, reasoning, objectives, leads, dialogues, recent skill calls, the world map and the cockpit from the trace
up to the shown frame; `page.html` draws them. `app.html` is the cockpit at `/`: `Island` merges the atlas of the runs root per screen
(captures, ways, deaths, heat, first gains, the open leads of the lineage holding the most items, the metro lines of the
lineages that reached something, every lead, the texts by voice) and `Story` reads one run as
frame-stamped thoughts, objectives, places, body, items, skills and merged dialogues; both are cached by trace mtime and size. It never writes game state; it writes only `star.json`, `summary.json`'s
`starred` and `notes.md`.

**CLI** — `cli.rb`, `bin/koholint`: `run`, `resume`, `fork`, `branch`, `verify`, `summary`, `watch`, `archive`, `star`,
`prune-heavy`, `atlas`, `census`, `ab-plan` and `ab-report` (`ab.rb`), `check-leads`, `check-pickups`, `learn`, `capability` and
`bench exits`. `docs/OPERATING.md` documents each.

## Data flow of one decision

1. The engine waits for readiness, reads `GameState` and emits a `perception` event; vision updates the grid and beliefs; on a
   new place the engine emits its `place_card`.
2. The policy gets a decision point and a context. The harness may answer itself (`harness_choice`); otherwise the agent policy
   renders the context, calls the model and validates the answer, falling back deterministically when it is invalid.
3. The engine emits a `decision` event and runs the chosen skill frame by frame, appending every input to the journal.
4. The skill result becomes an `action` event, feeds the policy's memory (`after_action`) and the next context; objectives are
   re-evaluated. An explore result carrying `too_heavy` (a push the game answered with a dialogue, nothing else on screen able to
   speak) also goes to `grid_builder`, which records that cell's appearance as no way in that direction (an `affordance` of source
   `push`).
5. The budget is checked after every frame; at stop the engine saves, checkpoints, emits `stop` and writes `summary.json` and
   `world.json`.

## Invariants

- Only the engine writes `trace.jsonl`, `inputs.log` and `save/`; `verify` replays the journal and compares hashes. `Engine.new`
  reads the trace once, for the grid beliefs and its own resume state.
- Determinism: the same journal on the same ROM gives the same states. Agents are never called in replay.
- No walkthrough in code or prompts (how-to-play knowledge is allowed, see `AGENTS.md`); facts live in `data/` and a run's
  `world.json`, with provenance.
- A rule a script can check is a validator, not a paragraph.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`.

## Where things are

| Need | Look at |
|---|---|
| Skill and harness behaviour, flow by flow | `docs/AGENT_SKILLS.md` |
| Commands, censuses, viewer and run storage | `docs/OPERATING.md` |
| Measured facts and their provenance | `data/*.json`, `koholint atlas` facts |
| Design rationale | `docs/superpowers/specs/` |
| Measurements of agent runs | `docs/runs/` (`index.md` lists every archived run) |
| What all runs observed, per place, lead and flow | `koholint atlas`, the viewer's `/atlas` |
| What remains | `ROADMAP.md` |
| Conventions | `AGENTS.md` |
| Game manual digest given to the agent | `docs/AGENT_MANUAL.md` |
