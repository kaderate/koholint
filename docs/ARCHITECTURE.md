# Koholint — architecture

Written September 21, 2026, from `docs/RETROSPECTIVE.md` and the objectives and constraints
settled with the owner in `docs/OBJECTIVES.md`. Those three decisions are assumed here:

- **Objective**: finish Link's Awakening DX. The agent decomposes; the score is global.
- **Knowledge**: the manual is the only document in context; the model's own priors are allowed
  but tagged; nothing becomes a fact without in-game verification.
- **Rollback**: a gameplay mechanic, not a debugging tool.

---

## 1. The central idea

**The agent is a search over a tree of emulator states, guided by an LLM.** Not a player
pressing buttons in one continuous life.

That reframing is the architecture, and it follows directly from the decisions. The emulator is
deterministic and snapshots cost ~0.05–0.08 s, so a state is a value that can be kept, copied,
returned to and searched from. Nodes are states, edges are action sequences, the score orders
the nodes. The LLM decides what to try and reads what happened; code does the searching, the
scoring and the bookkeeping.

Everything the retrospective flagged falls out of this:

| Root cause | How the tree answers it |
|---|---|
| R1 — no loop | The loop *is* tree expansion. It is small, and it is the first commit. |
| R8 — grinding on a wall | A wall is a subtree that buys no score. Budget spent → back up and branch. Abandonment is a graph operation, not a judgement call. |
| R9 — progress in `/tmp` | The path from root to the best node *is* the input log. Progress is a committed file. |
| R7 — throughput | Expansion is embarrassingly parallel across emulator processes. |
| R5 — drifting indicators | The score orders the tree. A metric that does not order nodes is not an indicator. |

### Two levels, or it explodes

A naive search over all action sequences is combinatorially hopeless. The tree has two levels,
and keeping them separate is what makes it tractable.

**The macro graph** — nodes are *states worth keeping*: a milestone reached, a new room entered,
a subgoal completed. Edges are whole maneuvers. This graph is small (hundreds of nodes for a
full playthrough) and it is where the LLM plans.

**A maneuver** — a bounded, code-driven search inside one edge. It is declared as:

```
Maneuver
  from:      snapshot
  succeeds?: (observation) -> bool     # e.g. x > 100 && hp >= 16
  candidates: generator of action sequences   # timing, row, approach angle, order
  budget:    frames, or attempts
```

Code runs it, in parallel, and returns either a winning input sequence or `:exhausted`. The LLM
never sees the individual attempts — only the verdict and a summary of the evidence.

Room `240/0` is the worked example. Under one continuous life it is a wall: six attempts, five
techniques, the same 8/24 HP floor. As a maneuver it is `from:` the snapshot at the room's
entrance, `succeeds?:` crossed the right edge with HP ≥ 16, `candidates:` variations over
approach row, timing and shield state, `budget:` 200 attempts. That is a few seconds per attempt,
so roughly twenty minutes on one emulator or three on eight. It either yields an input sequence
or it returns exhausted — and exhaustion is a *fact the planner can act on*, which is precisely
what the old system never had.

---

## 2. Layers

Eight, bottom up. Each one is testable without the one above it.

### L0 — Emulator session

A thin wrapper over gemboy's `Motherboard`. It owns the one invariant everything else rests on:
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
one chunk, so it is deterministic but not frame-exact — L0 must align on the PPU's frame
boundary itself. And `dump(with_rom: false)` gives a ROM-free snapshot, which matters for what
may be cached on disk.

**First test to write, before anything else**: boot, run a fixed input log twice in two fresh
processes, assert identical RAM. If determinism from boot does not hold, the whole design
changes, and it is cheap to find out.

### L1 — Observation

One struct, built from RAM in a single cheap pass. No prose, no derived narrative.

```
Observation
  x, y, room, map, direction     # 0xFF98, 0xFF99, 0xFFF6, 0xFFF7, 0xFF9E
  hp, max_hp                     # 0xDB5A
  a_slot, b_slot                 # 0xDB00 (hypothesis: 4 = shield)
  inventory_flags                # TO FIND
  progress_flags                 # TO FIND
  in_dialogue                    # TO FIND (currently inferred by probing movement)
  tilemap_digest
```

Screenshots are produced on demand, upscaled 4–6×, and are for the owner and the rare vision
call — never for the loop's own decisions.

The unknown addresses are **task zero**, using the method that already worked: diff the whole
`0x0000–0xFFFF` space across a controlled action, cross-check against the community
disassembly. The ~15 KB of already-clean addresses in the old `data/ram_registry.json` migrate
as they are.

### L2 — Score

```
Score.of(observation)         -> Integer      # weighted milestones reached
Score.milestones(observation) -> Set<Symbol>
Score.percent(observation)    -> Float
```

A pure function of RAM. Runs on any snapshot in milliseconds. The milestone list is declared —
sword, shield, Tail Cave entered, Roc's Feather, Moldorm defeated, Full Moon Cello, and on
through the eight instruments to the egg — and it is itself knowledge under decision B: sourced
from the manual and model priors, tagged as such, each entry verified in-game the first time it
is observed.

Four properties, and they are the whole point of R5:

1. It is **the only indicator**. Rooms charted, dialogues transcribed, terrain coverage and
   verified-fact counts are diagnostics. They may be logged. They may never sit in a table next
   to the score as peers.
2. Every run prints it without being asked.
3. It is **monotone over kept states**: a node is never replaced by one that scores lower. This
   is what makes rollback coherent — it is the rule that says which state to keep.
4. A flat score over N expansions **triggers re-planning in code**. Fourteen of twenty sessions
   reported "game indicator unchanged" and nothing noticed; this is the mechanism that notices.

### L3 — Action space

An action is an object, not a method on a navigator.

```
Action
  name
  applicable?(observation) -> bool
  inputs               -> [(buttons, frames), ...]
  effect(before, after) -> :ok | :no_effect | :unexpected
  frame_cost
```

Initial vocabulary: `Tap(dir)`, `Hold(dir, frames)`, `Attack`, `Push(dir)`, `Dive`,
`UseItem(slot)`, `Equip(item, slot)`, `OpenMenu`, `AdvanceDialogue`.

`Push` and `Dive` are in the first vocabulary deliberately: the manual describes both, the old
project never attempted either, and it recorded statue-shaped objects and water edges as
impassable walls while doing so.

**Growth rule**: a new mechanic is a new file implementing this interface. It never edits a
navigator. That is the answer to R6, where the action space accreted from whatever the next
script happened to need.

**Recording rule**: an attempt records the `Action` instance and the observation delta, never a
boolean. "I tried X and it did not work" is meaningless without tap-versus-hold, the approach
row and the angle — at least four "confirmed hard walls" in the old project were tap-timing
false negatives.

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
queue. This is where C1 is absorbed: one instance yields ~25–30 minutes of game time per real
hour, so parallelism is not an optimisation to add later — the job queue exists in the first
version even when N is 1.

Snapshots are a **cache**, keyed by the input-log hash, evictable at any time and re-derivable
by replaying the log. That is what keeps disk bounded on a search that keeps thousands of states.

### L5 — The planner

This is the only place an LLM is called, and it never presses a button.

It does four things:

1. **Decompose** the objective into the current subgoal, from the world model and the score.
2. **Declare a maneuver**: the success predicate, the candidate generator, the budget.
3. **Interpret** a result — and on `:exhausted`, decide between *the approach was wrong*, *the
   subgoal was wrong*, or *the budget was too small*. This is the mechanism R8 never had.
4. **Form hypotheses** about the world, each tagged with its provenance.

Budget: **LLM calls per emulated game minute**, declared, measured and enforced in code. The
state a call receives is compact — the current observation, the score, the subgoal, a summary of
the last few maneuver results, and the queried slice of the world model. Never a narrative, and
never a file read from end to end.

This is `docs/CONCEPT.md`'s three-tier design, which was scheduled as sessions 5 to 7 and never
started. It is still right. The PokéAgent Challenge reaches the same shape independently —
an orchestrator holding the route plan, dispatching specialised sub-agents — and reports that
without such a harness, frontier models achieve *"effectively 0% task completion"*, which it
calls *"not a marginal optimization but a prerequisite"*.

### L6 — World model

A typed store with a validator in CI. Not a document.

```
rooms       id, map, exits[]         # exit: direction, action used, destination, verified_count
entities    room, kind, position, behaviour observations
facts       address, meaning, provenance, verified_count
hypotheses  claim, source, status, evidence[]
milestones  the score's definition
```

`source` is an enum: `manual`, `model_prior`, `in_game_observation`. `status` is an enum:
`open`, `verified`, `refuted`. This is decision B made mechanical — the model's priors are a
legitimate, *labelled* source, and at the end of a run you can measure what fraction of the
world model came from priors versus observation. That is a result, not a compliance problem.

Queries it must answer **in code**, not in tokens:

- frontier — which known exits have never been taken
- routing — A\* over the room graph from A to B
- contradiction — two facts about the same cell that disagree
- lookup — what is known about this room, entity or address

Enforcement, answering R3 and C7: provenance, `verified_count ≥ 2` before `verified`, and the
`status` enum are checked by a validator that fails the build. The old project wrote that rule
three times in prose and shipped 63 violations of it. Free prose lives in one `notes` field,
capped in length, that no code reads.

The old registry's room facts, 25 dialogues and 20-entry visual catalog are migrated into this
schema — roughly 65 000 words of prose becoming typed rows. The facts are an asset; their
container was the problem.

### L7 — Persistence and observability

**Durable progress is the input log from boot.** A few kilobytes of text, no ROM in it, no
format fragility, and it reproduces any state exactly on any machine. Snapshots are a local
cache. The `.sav` remains a coarse anchor for convenience.

Acceptance test: a fresh container, plus the owner's ROM, replays the committed log and reaches
the same state and the same score. (The ROM cannot be committed, so this test runs locally
rather than in CI; CI runs the schema validators, the unit tests and everything else that does
not need the ROM.)

**Observability is an output of the loop, not a reporting convention.** Every run writes to one
directory: `score.jsonl`, `events.jsonl` (goals set, maneuvers declared, exhaustions,
abandonments), a screenshot at every milestone and every goal change, and a single `index.html`
regenerated in place with the current score, the current goal, the latest screenshot and the
score curve. If the loop runs, the dashboard exists. Kader reads pictures, not `room_id/map_id`
pairs.

---

## 3. What survives of the process

**Survives**: the score, a decision log of one line per decision with its invalidation
condition, and CI.

**Does not**: the three roles, the escalation queue, MetaPlanner, `PROCESS_EVIDENCE.md`, and
`AGENTS.md`'s 3 700 words. They are replaced by a schema and tests. Process work was tractable
when game work was not, and a system with an escalation path cheaper than the real work will
spend itself there.

**Cold start**: one `START_HERE.md`, at most 2 000 words, enforced by a test that fails the
build. Everything else is *queried* from the world model, not read. The old path cost ~27 300
words before the first action, paid again on every context rotation.

---

## 4. Build order

The order is the design. Getting it wrong is how R1 happened.

**Commit 1 — the walking skeleton.** L0 + a minimal L1 (position and HP) + a trivial L2 (rooms
visited) + two actions + a single-worker search with a random policy + the run directory. It
plays badly. It plays *autonomously*, end to end, from boot. Everything after this is
improvement, never foundation.

Then, in order, each step keeping the loop running:

2. Determinism test and the input log as the durable unit (L0, L7).
3. The real score from RAM — find the inventory and progress flags (L1, L2).
4. The world model with its validator in CI, and the migration of the old facts (L6).
5. The LLM planner, replacing the random policy (L5).
6. The action space beyond movement: attack, push, dive, items (L3).
7. Parallel workers (L4).

**The standing rule, and it is the important one: nothing is merged that is not reachable from
the loop.** If no code path the loop executes calls it, it does not merge. That single rule
would have stopped three of the old project's seven files, which were wired to nothing, and the
four foundation sessions that grew until the loop was never reached.

**Acceptance criterion for the architecture itself**: by the end of week one, a loop is running
whose score has moved at least once with no human touching the controls. If that is not true,
the architecture is wrong rather than merely behind — which is the check that was missing when
the same verdict was written twice, two weeks apart.
