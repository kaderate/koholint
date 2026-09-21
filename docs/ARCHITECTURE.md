# Koholint — architecture

An autonomous agent that plays *The Legend of Zelda: Link's Awakening DX* through gemboy, a
Game Boy emulator written in Ruby. Objectives and constraints are in `docs/OBJECTIVES.md`; this
document assumes its three decisions:

- **Objective**: finish the game. The agent decomposes it; the score is global.
- **Knowledge**: the manual is the only document in the agent's context; the model's own priors
  are allowed but tagged; nothing becomes a fact without in-game verification.
- **Rollback**: a gameplay mechanic, not a debugging tool.

---

## 1. The central idea

**The agent is a search over a tree of emulator states, guided by an LLM.** Not a player
pressing buttons through one continuous life.

The emulator is deterministic and a snapshot costs ~0.05–0.08 s, so an emulator state is a value
that can be kept, copied, returned to and searched from. Nodes are states, edges are action
sequences, and the score orders the nodes. The LLM decides what to try and reads what happened;
code does the searching, the scoring and the bookkeeping.

Three properties follow immediately, and they are why the design is shaped this way:

- **A wall becomes a search with a budget.** A passage the agent cannot cross is a subtree that
  buys no score. When its budget is spent, the runner backs up and branches. Deciding that a
  subgoal is unreachable is a graph operation, not a judgement call, so it needs no human.
- **Durable progress is a path, not a save file.** The route from the root to the best node is
  exactly the sequence of inputs that produces it — a few kilobytes of text that reproduce any
  state on any machine.
- **Expansion is parallel.** Independent branches explore in separate processes with separate
  emulators, which is the only way to buy throughput (`docs/OBJECTIVES.md` C1).

### Two levels, or it explodes

A naive search over all action sequences is combinatorially hopeless. The tree has two levels,
and keeping them separate is what makes it tractable.

**The macro graph** — nodes are *states worth keeping*: a milestone reached, a new room entered,
a subgoal completed. Edges are whole maneuvers. This graph stays small, on the order of hundreds
of nodes for a full playthrough, and it is where the LLM plans.

**A maneuver** — a bounded, code-driven search inside a single edge:

```
Maneuver
  from:       snapshot
  succeeds?:  (observation) -> bool     # e.g. x > 100 && hp >= 16
  candidates: generator of action sequences   # timing, row, approach angle, order
  budget:     frames, or attempts
```

Code runs it, in parallel, and returns a winning input sequence or `:exhausted`. The LLM never
sees individual attempts — only the verdict and a summary of the evidence.

A hostile room an unarmed Link cannot walk straight through is the worked example. Played as one
life it is a wall. As a maneuver it is: start from the snapshot at the room's entrance, succeed
on reaching the far exit above an HP floor, vary the approach row, the timing and the shield
state, and stop after 200 attempts. That is a few seconds per attempt, so roughly twenty minutes
on one emulator or three on eight. It yields a crossing, or it returns exhausted — and
exhaustion is a fact the planner can act on.

---

## 2. Invariants: what is fixed, and what the agent chooses

The loop's *structure* is fixed in code. What the agent supplies is the *content* of a few
decisions inside it. This is the boundary that keeps autonomy from becoming drift, and every
line of it is enforced mechanically rather than asked for in a prompt.

### Fixed — the agent cannot change these

| Invariant | Enforced by |
|---|---|
| The cycle is observe → score → plan → declare → execute → record → repeat | the runner; the planner cannot add, skip or reorder a step |
| The LLM never sends an input to the emulator | the planner's only return type is a `Maneuver` |
| Every emulator action happens inside a declared maneuver carrying a success predicate and a budget | the maneuver runner refuses an undeclared action |
| Budgets are counted down and terminated by the runner | frame and attempt counters, not the planner's judgement |
| The score is computed from RAM by code | `Score` is a pure function; nothing on the planner's path can write it |
| Kept states are monotone in score | the node store refuses a replacement that scores lower |
| A flat score over N expansions forces re-planning | a counter in the runner |
| Model calls are receipted, and a guard halts the run when the budget is exceeded | the guard runs before each call and writes the stop marker itself |
| Nothing enters the world model without passing the schema | the validator, in CI and at write time |

### Free — the agent's only degrees of freedom

- Which subgoal to pursue next, and whether to abandon it before its budget is spent.
- A maneuver's success predicate and candidate generator.
- The budget it requests, within the cap its configuration sets.
- Which hypotheses to form, and which to test first.

### The drift that remains, and why it is bounded

Two failure modes survive this, and neither is worth pretending away.

**The agent pursues a wrong subgoal.** It can spend a night of emulation on a branch that leads
nowhere. Three things bound the damage: the cost is capped, because every maneuver carries a
budget and the run carries a spend guard; it is visible, because `score.jsonl`, `events.jsonl`
and the dashboard show a flat score against accumulating attempts; and it is recoverable,
because the tree still holds every good node and the search resumes from one of them. Wasted
time is the worst case. Lost ground is not possible, which is what score monotonicity buys.

**The agent declares a weak success predicate.** A maneuver can "succeed" at reaching a position
that turns out not to be progress. The arbiter is the score, not the predicate: a maneuver that
succeeds without moving the score is recorded as exactly that, and a run of them is what the
flat-score trigger detects.

Both are bounded, observable and recoverable. Neither is silent, and neither needs a human to
notice it.

---

## 3. Layers

Eight, bottom up. Each is testable without the one above it.

### L0 — Emulator session

A thin wrapper over gemboy's `Motherboard`, owning the invariant everything else rests on:
**the same ROM plus the same input log produces the same state.**

```
Emulator
  step(frames)                  # frame-accurate, aligned on PPU frame boundaries
  press(buttons, frames)        # via FakeKeys, recorded into the input log
  snapshot -> bytes             # Motherboard#dump(with_rom: false)
  restore(bytes)                # Motherboard.load(bytes, rom_bytes:)
  read(addr), read_range(a, b)
  framebuffer
  input_log
```

Two notes on gemboy. `run_cycles` advances in chunks of 20 instructions and overshoots by up to
one chunk, so it is deterministic but not frame-exact — L0 aligns on the PPU's frame boundary
itself. And `dump(with_rom: false)` yields a ROM-free snapshot, which decides what may be cached
on disk.

**The first test to write, before anything else**: boot, replay a fixed input log in two fresh
processes, assert identical RAM. Determinism from boot is an assumption, not yet a fact, and
rollback, the input log as the durable unit and the snapshot cache all rest on it.

### L1 — Observation

One struct, built from RAM in a single cheap pass.

```
Observation
  x, y, room, map, direction     # 0xFF98, 0xFF99, 0xFFF6, 0xFFF7, 0xFF9E
  hp, max_hp                     # 0xDB5A
  a_slot, b_slot                 # 0xDB00 (hypothesis: 4 = shield)
  inventory_flags                # to find
  progress_flags                 # to find
  in_dialogue                    # to find
  tilemap_digest
```

Screenshots are produced on demand, upscaled 4–6×, for the owner and the rare vision call —
never for the loop's own decisions.

The unknown addresses are task zero. The method: diff the whole `0x0000–0xFFFF` space across a
controlled action, then cross-check against the community disassembly. Scanning WRAM alone is
not enough; the known position and direction addresses live in HRAM.

Dialogue text is decoded by 8×8 pixel bitmap, never by tile ID: the renderer reuses a fixed
scratch tile range (`0xD0–0xDF`, `0xE0–0xEF`) and rewrites its pixels per textbox, so tile IDs
carry no information.

### L2 — Score

```
Score.of(observation)         -> Integer      # weighted milestones reached
Score.milestones(observation) -> Set<Symbol>
Score.percent(observation)    -> Float
```

A pure function of RAM, running on any snapshot in milliseconds. The milestone list is declared
— sword, shield, first dungeon entered, Roc's Feather, first boss defeated, Full Moon Cello, on
through the eight instruments to the egg. The list is itself knowledge under the
manual-plus-tagged-priors rule: sourced, labelled, and each entry verified in-game the first
time it is observed.

Four properties:

1. It is **the only indicator**. Rooms charted, dialogues transcribed, terrain coverage and
   verified-fact counts are diagnostics. They may be logged; they never sit beside the score as
   peers. A number that does not order nodes in the tree is not an indicator.
2. Every run prints it without being asked.
3. It is **monotone over kept states** — the rule that decides which state to keep, and what
   makes rollback coherent.
4. A flat score over N expansions **triggers re-planning in code**.

### L3 — Action space

An action is an object, not a method on a navigator.

```
Action
  name
  applicable?(observation) -> bool
  inputs                   -> [(buttons, frames), ...]
  effect(before, after)    -> :ok | :no_effect | :unexpected
  frame_cost
```

Initial vocabulary: `Tap(dir)`, `Hold(dir, frames)`, `Attack`, `Push(dir)`, `Dive`,
`UseItem(slot)`, `Equip(item, slot)`, `OpenMenu`, `AdvanceDialogue`.

`Push` and `Dive` are in the first vocabulary because the manual describes both and each turns a
class of apparent wall — statues, water edges — into a passage.

**Growth rule**: a new mechanic is a new file implementing this interface, never an edit to a
navigator.

**Recording rule**: an attempt records the `Action` instance and the observation delta, never a
boolean. A directional tap commits ~14 px over ~24–28 frames or bounces; a sustained hold of
110–400 frames is a *different action* with a different outcome, as are the approach row and the
angle. A negative result that does not record how it was obtained is not a result.

One trap worth encoding: crossing a room boundary rebases the position, so an axis delta can
read as blocked while a real transition happened. Never infer "nothing happened" from a zero
delta alone.

### L4 — The search

```
Node
  id             # hash of the input-log prefix that reaches it
  parent, edge   # the maneuver that got here
  observation, score
  snapshot_ref   # cache path; evictable, re-derivable by replay
  status         # open | expanded | dead
```

A pool of N worker processes, each owning one emulator, pulls `(node, maneuver)` jobs from a
queue. One instance yields ~25–30 minutes of game time per real hour, so the job queue exists
from the first version even while N is 1.

Snapshots are a **cache** keyed by the input-log hash, evictable at any time and re-derivable by
replay. That is what keeps disk bounded across a search holding thousands of states.

### L5 — The planner

The only place an LLM is called, and it never presses a button. It does four things:

1. **Decompose** the objective into the current subgoal, from the world model and the score.
2. **Declare a maneuver**: success predicate, candidate generator, budget.
3. **Interpret** a result, and on `:exhausted` choose between *the approach was wrong*, *the
   subgoal was wrong* and *the budget was too small*.
4. **Form hypotheses** about the world, each tagged with its provenance.

Budget: **LLM calls per emulated game minute**, declared in configuration, receipted per call
and enforced by a guard (§5). The state a call receives is compact — the current observation,
the score, the subgoal, a summary of recent maneuver results, and the queried slice of the world
model. Never a narrative, and never a file read end to end.


### L6 — World model

A typed store with a validator, not a document.

```
rooms       id, map, exits[]         # exit: direction, action used, destination, verified_count
entities    room, kind, position, behaviour observations
facts       address, meaning, provenance, verified_count
hypotheses  claim, source, status, evidence[]
milestones  the score's definition
```

`source` is an enum: `manual`, `model_prior`, `in_game_observation`. `status` is an enum:
`open`, `verified`, `refuted`. This makes the knowledge policy mechanical — a prior is a
legitimate, labelled source, and the share of the world model that came from priors rather than
observation is a measurable quantity at the end of a run.

Queries it must answer **in code**, not in tokens:

- frontier — which known exits have never been taken
- routing — A\* over the room graph from A to B
- contradiction — two facts about the same cell that disagree
- lookup — what is known about this room, entity or address

Provenance, `verified_count >= 2` before `verified`, and both enums are checked by a validator
that fails the build. Free prose lives in one `notes` field, capped in length, that no code
reads.

### L7 — Persistence and observability

**Durable progress is the input log from boot**: a few kilobytes of text, no ROM inside it, no
format fragility, reproducing any state exactly on any machine. Snapshots are a local cache. The
game's own `.sav`, via gemboy's `BatteryRam.save/load`, remains a coarse anchor.

Acceptance test: a fresh container plus the owner's ROM replays the committed log and reaches
the same state and score. The ROM cannot be committed, so this test runs locally; CI runs the
schema validators, the unit tests and everything else that does not need it.

**Observability is an output of the loop, not a reporting convention.** Every run writes
`score.jsonl`, `events.jsonl` (goals set, maneuvers declared, exhaustions, abandonments), a
screenshot at every milestone and goal change, and an `index.html` regenerated in place carrying
the current score, the current goal, the latest screenshot and the score curve. If the loop
runs, the dashboard exists. The owner reads pictures, not `room_id/map_id` pairs.

---

## 4. What is built in advance, and what the agent builds

The boundary sits further toward "built in advance" than intuition suggests, for a simple
reason: an agent that has to build its own instrumentation spends its budget on instrumentation
rather than on the game. Perception, scoring and the means to act are infrastructure, and
infrastructure assembled at runtime is assembled badly, slowly, and again on the next run.

One asymmetry decides much of the rest. We own the emulator, so the game's own state is readable
directly — position is four RAM addresses, not a localization problem to be recovered from
pixels. An agent working against a black-box environment would have to infer all of it visually.
**That entire problem class is bought rather than solved**, and no effort goes into visual
perception.

### Bucket A — built in advance, by us

Emulator session, frame-accurate stepping, snapshot/restore, input log, determinism test (L0).
The RAM map (L1). The score and its milestone predicates (L2). The action vocabulary and each
action's input sequence (L3). Tree, node store, worker pool, budget accounting (L4). Planner
scaffolding: prompt structure, state compaction, call budget, maneuver declaration format (L5).
The world-model **schema** and its validator, and A\* as an algorithm (L6). Persistence, run
directory, dashboard (L7).

The RAM map is the one debatable entry, and it belongs here. Finding addresses is *engineering*
discovery and it is ours; discovering the island is *game* discovery and it is the agent's. An
agent hunting its own addresses at runtime is foundation work wearing the costume of play.

### Bucket B — built by the agent, and persisted

The room graph, nodes and typed exits — A\* is ours, the graph it runs on is the agent's.
Entities, hazards and their behaviour per room. The hypothesis ledger with provenance,
verification status and refutations. **Maneuver solutions** — the winning input sequence for a
hard crossing, stored as a reusable edge. And the decomposition of "finish the game" into
subgoals, which is the route plan.

Maneuver solutions are the most valuable of these and the least obvious. Once a crossing is
solved, the sequence that solves it is a permanent asset replayable at zero search cost: the
search is paid once and the result is reusable for the rest of the run. Determinism and rollback
are what make a solved crossing storable at all.

### Bucket C — never persisted

The LLM's reasoning traces, and narrative session logs. Outcomes and evidence are recorded;
deliberation is not. A store that accepts free text will fill with free text.

### The reconciliation with "the loop is commit 1"

"Build a lot in advance" reads close to building a foundation that never reaches a loop. The
distinction is precise: **the harness is built in advance, but thin and end-to-end first, never
deep and layer-by-layer.** All of bucket A exists from day one at low quality with the loop
running through it, and improves under a running loop. Perfecting one layer before the next
exists is how the top layer never arrives.

---

## 5. Framework and run

A reusable **framework** — the library: orchestration, scoring, search, CLI — is separated from a
**run directory** holding one concrete execution: its config, its state, its ledgers, its
artifacts. Every command takes `--root DIR`. Nothing is implicitly global. (The pattern is
borrowed from `github.com/vd1/pathfinder`.)

```
runs/main/
  run.json            # config: models, budgets, knowledge policy, workers, action set
  inputs.log          # the durable unit: inputs from boot
  nodes.jsonl         # the macro graph, append-only
  world/              # the typed world model (rooms, entities, facts, hypotheses)
  maneuvers/<id>/
    declaration.json  # from, succeeds?, candidates, budget
    attempts.jsonl    # append-only evidence
    solution.log      # the winning input sequence, if any
    status.json       # open | solved | exhausted
    lock
  receipts.jsonl      # one line per model call, failures included
  events.jsonl        # goals set, maneuvers declared, abandonments
  score.jsonl
  screenshots/
  cache/snapshots/    # derived, gitignored, re-derivable by replay
  stop.json           # present = halt
  index.html
```

`koholint run --root runs/main`, and likewise `reconcile`, `serve`, `export`.

**Receipts and a spend guard.** One receipt line per *attempted* model call, failures included,
carrying model, seconds, outcome, tokens, cache reads and cost. Before admitting a call, a guard
checks that known cost plus an estimate for each in-flight call stays under the configured
budget, and if it does not, **the guard writes the stop marker itself**. A budget enforced by a
guard is a budget; a budget written in a document is a hope.

**`reconcile` instead of a cold-start read.** `stop` writes `stop.json`; a later call resumes
each thread at its recorded stage, and `reconcile` computes the safe next action and applies it
with `--apply`. A process with no memory of what came before does not *read* its way back into
the work — it asks the state what to do next. Durable memory is a queryable state, not a
document written for a reader. The human-facing orientation file stays capped at 2 000 words,
enforced by a test, because it serves a different purpose.

**`experiments/` for variants.** `experiments/no-knowledge/` is the same framework and the same
code with one configuration key changed, which is how the knowledge ablation in
`docs/OBJECTIVES.md` §3 gets run — likewise for comparing planner models, worker counts and
action sets. An experiment that costs a directory gets run; one that costs a refactor does not.

Two things this design deliberately does not have. **No role taxonomy** — no peers, reviewers or
consolidators. A system whose output is a document produced by deliberation gains from
independent viewpoints; ours is a path through a state space, checked by a score function, and
roles would buy nothing but coordination. **No linear pipeline** — a run is a loop over a tree,
not a sequence of stages, and forcing it into phases is how a plan spends itself on groundwork
before ever reaching the loop.

---

## 6. Build order

**Commit 1 — the walking skeleton.** L0, a minimal L1 (position and HP), a trivial L2 (rooms
visited), two actions, a single-worker search with a random policy, and the run directory. It
plays badly. It plays *autonomously*, end to end, from boot. Everything after is improvement,
never foundation.

Then, each step keeping the loop running:

2. Determinism test and the input log as the durable unit (L0, L7).
3. The real score from RAM — find the inventory and progress flags (L1, L2).
4. The world model with its validator in CI (L6).
5. The LLM planner, replacing the random policy (L5).
6. The action space beyond movement: attack, push, dive, items (L3).
7. Parallel workers (L4).

**The standing rule: nothing is merged that is not reachable from the loop.** If no code path
the loop executes calls it, it does not merge.

**Acceptance criterion for the architecture itself**: by the end of week one, a loop is running
whose score has moved at least once with no human touching the controls. If that is not true,
the architecture is wrong rather than merely behind.
