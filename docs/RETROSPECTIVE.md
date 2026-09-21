# Koholint — retrospective, and input for the architecture brainstorm

Written September 21, 2026, at the owner's request, after the project stalled. Scope: the whole
koholint experiment (September 7–19, 2026), its predecessor spike in gemboy, the code in `lib/`,
the data in `data/`, and the process machinery in `AGENTS.md` / `PLAN.md` / `DECISIONS.md` /
`METAPLANNER*.md`.

**This document does not propose a new architecture.** That is the next step, a separate
brainstorm. What follows is: where the project actually is, what was built, what worked, what
stalled and why, what is worth carrying over, and the questions the brainstorm has to answer.

Every number below is reproducible from this repository; Appendix A says how.

This is the *second* review of this kind. The first, `docs/ARCHITECTURE_REVIEW.md` (September 7,
2026), reviewed the gemboy spike and concluded: *"After 4 days: 7 screens mapped, 4 NPCs, no
sword, no decision loop. The project's value (an LLM that plays) has not started."* That review
was right, the rewrite it triggered was well executed — and two weeks later the same sentence is
still true, with bigger numbers. That repetition is the single most important thing in this
document, and section 4 is about why it happened.

---

## 1. Where the project stands

| | |
|---|---|
| Repository history | 256 commits, September 7 → 19, 2026 (13 days, 3 of them idle) |
| Last progress in the game | **September 7, 2026**: shield obtained, starting house left |
| Commits since that milestone | **242** |
| Rooms labelled | 28 (`room_labels`), 17 "charted", 11 "glimpsed" |
| Items owned | 1 (Level-1 Shield). No weapon. `inventory` registry entry: `"status": "not found"` |
| Ruby in `lib/` | 1 734 lines (2 603 with `test/`) |
| English prose in `*.md` | ~58 600 words |
| English prose inside `data/ram_registry.json` | ~65 400 words |
| Decision records | 14 game decisions (D1–D14), 11 workflow decisions (MP1–MP11), 9 escalations (ESC1–ESC9) |
| Sessions logged with an indicator line | 20, of which **14 report "game indicator unchanged"** |

The commit-rate curve tells the story on its own: 21 / 17 / 44 / 62 / 65 commits on September
7–11, then 2, then a three-day gap, then 23 / 9 / 10 / 3. Peak effort, then collapse — not
because the work got harder, but because it stopped converting into anything.

The live blocker at the moment of the stall, from `.koholint/research_task.json`: an unarmed Link
at 24/24 HP is trying to cross a hostile cluster at room `240/0`'s right exit, looking for a
sword that may or may not be behind it. Six attempts, five methodologically distinct techniques,
all converging on the *identical* stop position (44,12) and the same 8/24 HP floor. The
ResearchTask is `exhausted`. That is where the project is parked.

---

## 2. What was actually built

### Emulator side (gemboy) — complete and solid

`Motherboard#dump` / `Motherboard.load` gives a full machine snapshot (~2.7 MB) in ~0.05–0.08 s.
`FakeKeys` drives input headlessly. That is the entire substrate the agent needs, and it works.
D6 (a headless session API) was asked for and effectively delivered this way.

### koholint `lib/` — seven components, three of them wired to nothing

| File | What it is | Used in production by |
|---|---|---|
| `navigator.rb` (275 l.) | Movement, snapshot probing, OAM census, hazard-avoidance primitive (D13) | the 7 checkpoint scripts, and every ad-hoc session script |
| `validation/checkpoint_*.rb` (7 files) | Replayable routes to 7 known positions | run by hand |
| `terrain.rb` (52 l.) | D8: walkability from the BG tilemap, "93.1 % validated", ratified as the **terrain source of truth** | **nothing.** Two comments mention it; no code path calls it |
| `autonomous_recovery.rb` (413 l.) | ResearchTask / hypotheses / experiments / evidence ledger, fail-closed persistence | **its own test suite only** |
| `hazard_index.rb` (333 l.) | Read-only hazard/creature cross-reference (built for ESC9) | **nothing** |
| `clue_cross_reference.rb` (92 l.) | Cross-references dialogue text against place names (built for ESC8) | **nothing** (run by hand, once) |
| `session_recorder.rb` (52 l.) | GIF traceability | optional keyword arg, off by default |

There is no `bin/`, no `Gemfile`, no `Rakefile`, no CI, no entry point. `README.md`'s "Commands"
section still reads *"None yet. They'll arrive with `lib/`."* — 256 commits later.

### The decision loop — never built

`docs/CONCEPT.md`'s architecture is three tiers: deterministic execution, triggers on RAM state,
LLM calls only at decision points, plus a planner/executor split and an append-only JSONL action
log. `PLAN.md` scheduled it as Sessions 5, 6 and 7, after four foundation sessions.

**The project never left Session 4.** There is no trigger, no planner, no executor, no action
log, anywhere in the repository. `data/world_model.json` — the store the concept designates as
the single source of truth — still carries its original note: *"Not yet wired into a driver"*,
and still describes 4 rooms while the registry describes 28.

What ran instead, for two weeks: a Claude session reading `NEXT.md`, writing a throwaway Ruby
script, calling `Navigator` directly, reading the result, and appending a paragraph to
`ram_registry.json`. The LLM was not making decisions *inside* a loop; the LLM **was** the loop,
by hand, one session at a time.

### Process machinery — the largest thing in the repository

`AGENTS.md` (3 700 words) defines three roles, an anti-patch rule, an autonomy policy, subagent
conventions, three standing data-quality audits, a recovery protocol and a MetaPlanner role.
`METAPLANNER.md` (5 000 words) is the decision log *of the process*; `METAPLANNER_ESCALATIONS.md`
(3 600 words) is the queue between them; `docs/process/PROCESS_EVIDENCE.md` defines a schema for
measuring the process itself — and contains **zero recorded entries**.

---

## 3. What worked — keep these

These are real results. Several were expensive to obtain and would be expensive to lose.

**1. Betting on the emulator's determinism.** Snapshot/restore per probe (D7) eliminated an
entire category of bug the spike fought for days: drift, walk-backs, direction-order
contamination, recovery budgets. `probe_all` returning four independent edges from one identical
state is genuinely clean code, and the idea is the foundation of anything that comes next.

**2. Reading game state from RAM, not from pixels (D1).** `0xFF98`/`0xFF99` (X/Y), `0xFF9E`
(direction), `0xFFF6`/`0xFFF7` (room/map), `0xDB5A` (HP), `0xDB00` (B-slot item, hypothesis). The
method that found them — diff the *entire* `0x0000–0xFFFF` space across a controlled action, then
cross-check against the community disassembly — is the reusable part. Two earlier hunts failed
purely by scanning WRAM only.

**3. Separating engineering knowledge from game knowledge.** The spike had implicitly banned
both, and lost days rediscovering a memory map that was public. Allowing the disassembly as a
*source of hypotheses to verify* is a correct, load-bearing distinction. (Where the line sits for
*game* knowledge is a different matter — see Q2.)

**4. Frames as the unit of time, and measuring instead of guessing.** Two performance fixes in
one day: YJIT (~2×), then discovering that `run_steps` counts *instructions*, not T-cycles, so
every tap was over-simulating by 5.7× (~8×). Combined: ~20 s → ~1.15 s per tap, a 17× win found
by measuring a number nobody had measured.

**5. Text decoding by tile bitmap, not tile ID.** The renderer reuses a fixed scratch-buffer tile
range (`0xD0–0xDF` line 1, `0xE0–0xEF` line 2) and rewrites its pixels per textbox, so tile IDs
carry no information. Confirmed byte-for-byte across two different NPCs. Non-obvious, hard-won,
and still true.

**6. The falsification discipline.** One falsifiable question, one end criterion, one budget per
session. The word REFUTED appears 61 times across `NEXT.md`, the registry and
the session log. The negative space of this game world is genuinely mapped, and much of it is
correct and reusable.

**7. Cold review by a session with no history.** It caught real defects a self-review would have
missed: an oracle validator structurally capped at ~1 cell, a "4 books" count that was actually
8, ~15 registry entries claiming a verified tier they hadn't earned. The role separation idea is
sound.

**8. The tap-versus-hold discovery.** A single directional tap and a sustained ~110–400-frame
hold are *different actions* with different outcomes. At least four "confirmed hard walls" turned
out to be tap-timing false negatives (`227/0`, `163/0`, the `178/0` telephone booth, `240/0`'s
own discovery). Any future system that probes the world must treat "I tried it" as incomplete
without saying *how*.

**9. Screenshots in owner-facing reports.** Raised by the owner, and right: `room_id/map_id`
pairs and prose are unreadable to a human. This is an observability requirement, not a courtesy.

**10. The ResearchTask data model.** Hypothesis / experiment / evidence / budget / exhaustion,
persisted fail-closed, with tests that prove it survives a cold process. It is the only piece of
*agent epistemics* that actually got built, and the shape is reasonable.

---

## 4. What did not work, and why it stalls

Ten root causes, ordered by how much each one costs. Each ends with the question the brainstorm
has to answer — not with an answer.

### R1 — The agent was never built; a human-in-the-loop exploration campaign was built instead

**Symptom.** Two weeks of work, no autonomous loop, and the project's stated value ("an LLM that
plays") has not started — the same verdict as the previous review.

**Evidence.** No trigger, planner, executor or action log in `lib/`. `PLAN.md` Sessions 5–7 never
started. `world_model.json`: "not yet wired into a driver". Every game action in the entire
history was issued by an ad-hoc script written by a Claude session for that session.

**Cause.** The plan put four foundation sessions *before* the loop, and the foundation kept
growing: seven checkpoints, then D8 terrain, then D9 visual catalog, then D11 hazard
classification, then D13 the avoidance primitive. Each was individually justified. None had a
stopping rule that pointed back at the loop. And once Link was out of the house, the game offered
an immediately attractive target — find a weapon — which could be pursued *by hand* with the
primitives already at hand. Hand-playing always beat loop-building on short-term payoff, at every
single decision point, for fourteen days.

**For the brainstorm.** What forces the loop to exist before anything else? What is the smallest
thing that is a *real* autonomous loop, and can it be the first commit rather than the last?

### R2 — The world model is prose, so no code can reason about the world

**Symptom.** The agent cannot answer "where have I not been yet?", "what is the shortest route
from A to B?", or "is this fact contradicted by another?" — except by having an LLM re-read
essays.

**Evidence.** `data/ram_registry.json` is 494 KB, of which ~15 KB are actual addresses and
~65 400 words are English narrative stuffed into JSON string fields. One room's `description`
field (`224/0`) is **2 818 words**. The file contains **zero** structured exits: searching for
`"exits"`, `"edges"`, `"neighbors"`, `"connects_to"` returns nothing. The room graph — the single
most important data structure for a navigating agent — exists only as prose, and the Atlas that
visualises it is built by an unversioned Python script in a scratchpad.

Meanwhile the file designated as the world model (`world_model.json`, 18 KB) was abandoned at 4
rooms. Two stores, neither canonical.

**Cause.** Each `description` field became an append-only journal: every session appended its
addendum ("SURVEY, September 18 2026…", "RIGHT EXIT RETRY note…") because there was no schema to
put the finding *into*. Prose accepts anything, so prose is what got written, and once there was
a lot of it nobody could restructure it.

**For the brainstorm.** What is the world model's schema, what enforces it, and what queries must
it answer in code — not in tokens?

### R3 — Rules were enforced by documentation, so they were not enforced

**Symptom.** The project's most-audited rule is violated in most of the data.

**Evidence.** `AGENTS.md` mandates `verified` / `ram_read_verified` only at `verified_count >= 2`,
and makes it an *unconditional standing checklist item for every cold Reviewer session*, written
up three times (MP5, MP10, MP11). Today, of 92 registry entries carrying a `verified_count`:
**15 claim `confidence: verified` at count < 2** (exactly the number the September 9 cold review
already flagged — found, reported, never fixed) and **48 more claim a `ram_read_verified` source
tier at count 1**. 29 of 92 are compliant. Separately, 84 entries use the `status` field as a
free-text paragraph instead of the enum it is documented to be.

`docs/process/PROCESS_EVIDENCE.md` — the mechanism for measuring whether process rules work — has
never been used once.

**Cause.** Every rule was written as prose for a future LLM to remember and apply by hand. A
ten-line validator would have made all 63 violations impossible to commit. The project responded
to each incident by writing more words, and words do not run.

**For the brainstorm.** Which invariants get a validator in CI, and what is the rule for "if it
can be checked by a script, it must not be a paragraph"?

### R4 — The meta-levels were built before the object level worked

**Symptom.** A single-developer project with a role taxonomy, an escalation queue, a
process-decision log, a process-evidence schema, and a recovery protocol — and no running agent.

**Evidence.** 11 MetaPlanner decisions and 9 escalations, against 14 game decisions. Prose in
`*.md` (~58 600 words) outweighs Ruby in `lib/` (1 734 lines) by roughly 8:1 by volume. `lib/`
itself is 22 % comment lines, in a repository whose conventions say "almost no comments" — because
the facts had nowhere better to live.

**Cause.** Process problems are *tractable*: an escalation can be resolved in thirty minutes and
feels like progress. Game problems were not, so the system drifted to where it could still
succeed. MetaPlanner existed precisely to make that motion cheap, and it worked as designed.

**For the brainstorm.** How much process does one owner plus N ephemeral agents actually need,
and what is the smallest set of artefacts that a cold agent must read before acting?

### R5 — The indicators stopped pointing at the goal

**Symptom.** Room count rose from 7 to 28 while milestones stayed at 1.

**Evidence.** `AGENTS.md` mandates exactly three indicators: *progress in the game*, *trip A→B*,
*verified facts*, and explicitly says "a catalog size, a skip rate, a number of resolved cells are
means metrics". The indicator table in `NEXT.md` has six rows: rooms found, dialogues, terrain,
SELECT map, save mechanic, current position. **Not one of them is progress in the game.** The
anti-means-metrics rule was violated by the very table written to enforce it.

**Cause.** The mandated indicators were uncomfortable — two of the three had been flat for
eleven days — and the comfortable ones were the ones that moved. 14 of 20 logged sessions record
"game indicator unchanged" and nothing in the system treated that streak as a signal.

**For the brainstorm.** What is the primary score, who computes it (code, not prose), and what
happens automatically when it has not moved for N sessions?

### R6 — The action vocabulary is too small for the objective

**Symptom.** "Exploring" degenerated into walking into every wall in four directions. 61
refutations, 31 confirmed hard walls, 40 "no item found".

**Evidence.** The agent's entire repertoire is: tap a direction, hold a direction, tap A, hold B
(shield). `docs/GAME_MANUAL_NOTES.md` — written by this project — notes that **pushing** and
**diving** exist as mechanics and *"this project has never actually attempted"* them, while
repeatedly recording water edges and statue-shaped objects as impassable walls. There is no
attack (no weapon), no item use, no inventory interaction. Dialogue is advanced by tapping A and
probing whether movement resumed, because no text-state flag was ever found.

**Cause.** The action space was never designed; it accreted from whatever the next script needed.
A boolean per edge is all this vocabulary can produce, so the world model could only ever be a
wall map — and a wall map does not find items, solve puzzles, or finish a game.

**For the brainstorm.** What is the agent's action space, how is it declared, and how does a new
mechanic (push, dive, attack, use item) enter it without rewriting the navigator?

### R7 — Throughput was never budgeted against the size of the game

**Symptom.** Everything is slow in a way nobody ever priced.

**Evidence.** Best measured rate: ~1.15 s wall-clock per 30-frame tap, i.e. roughly **2× slower
than real time at best**, after a 17× optimisation. One `Navigator.move!` is up to 8 taps. One
`probe_all` is 4 × `move!` plus snapshots. `AGENTS.md` records helpers taking 13–30 s per `move!`
in some environments — a constraint significant enough that it produced its own workflow rule
(MP7) about foreground timeouts.

Against that: the previous review put the overworld at ~256 screens, excluding dungeons and
interiors. This project charted 28 rooms in 13 days. Nobody ever wrote down how many emulated
frames a full playthrough would take — that estimate is itself a missing number.

**Cause.** No frames-per-objective budget was ever written down, so an approach that cannot scale
by two orders of magnitude was adopted without anyone noticing it couldn't.

**For the brainstorm.** What is the emulation-time budget per real hour, what does that allow,
and does the answer change the shape of the whole system (parallel emulators, snapshot search,
input replay instead of live probing)?

### R8 — Blockers escalated in machinery instead of in abstraction level

**Symptom.** Room `240/0`: 6 attempts, 5 distinct techniques, one identical wall.

**Evidence.** The response to being blocked was, in order: a hostile-avoidance primitive (D13),
then radius tuning, then an alternate route, then a ResearchTask formalism, then a hazard index
tool (ESC9/MP11), then an opportunistic gap-dash, then a non-live terrain signature read. Every
one of them asked *"how do I get past this?"*. None asked *"is this the right goal?"*.

**Cause.** The system had a rich mechanism for "this technique failed" and none for "this subgoal
is wrong". The anti-patch rule does stop the bleeding after three patches — by handing the
decision to the owner. So the only component capable of abandoning a goal was a human, who is
asynchronous and frequently absent. An agent that cannot re-plan cannot recover; it can only
grind or stop.

**For the brainstorm.** What owns subgoal selection and abandonment, on what evidence, and what
does "this objective is not achievable right now" look like as a state the system can be in?

### R9 — The project's actual progress lives in `/tmp` on one machine

**Symptom.** Two weeks of game progress are unreproducible and one `rm -rf` from gone.

**Evidence.** The canonical state is `/tmp/zelda_checkpoints/main.dump`, overwritten in place
after each session. It is correctly not versioned — a Marshal dump embeds the copyrighted ROM.
The safe alternative was identified in `NEXT.md` (*"The game's own `.sav` file is the safe,
committable alternative … once we're ready to persist progress in git"*) and never adopted. A
fresh container cannot reach any of the 28 rooms; it cannot even run `lib/` (no ROM, no
checkpoints, no entry point, no dependency manifest).

**Cause.** Persistence was treated as a later chore. In practice it is the difference between a
project that can be resumed by anyone and one that can be resumed by exactly one laptop.

**For the brainstorm.** What is the durable unit of game progress — a `.sav`, a replayable input
log from boot, a snapshot tree — and what guarantees that any fresh machine can reproduce the
current state from the repository alone?

### R10 — Durable memory was a narrative, so every resumption paid to re-read it

**Symptom.** `NEXT.md` opens with *"Entry point for any resumption. One page, no more."* It is
**1 025 lines, ~13 900 words**.

**Evidence.** Its "Quest hypothesis" section alone is 620 lines; "What NOT to redo" is 288 lines
of accumulated scar tissue. This was escalated as a process failure (ESC6), marked *resolved*, and
the file is still 14× over its own limit. A cold session that follows the documented reading order
(`NEXT.md`, `DECISIONS.md`, `AGENTS.md`, the review, the concept) reads ~27 300 words
before its first action, and the context-rotation protocol makes that a *recurring* cost, paid
again on every rotation.

**Cause.** Context rotation was correctly identified as necessary (the conversation is working
memory, not durable memory) but the durable substitute was a document written for a reader, not
an index queryable by a program. Narrative memory can only grow, and re-reading it is the most
expensive operation in the system.

**For the brainstorm.** What does a cold agent read before acting, how long is it, and what is
retrieved on demand rather than read upfront?

---

## 5. Reusable learnings

### 5.1 Facts to carry over verbatim

Addresses (DMG mode, `zelda_la_dx.gbc`): `0xFF98` X, `0xFF99` Y, `0xFF9E` direction, `0xFFF6`
room id, `0xFFF7` map id, `0xDB5A` HP, `0xDB00` equipped B-slot item (hypothesis; 4 = shield).
Hardware: `0xFF40` LCDC, `0xFF42/43` SCY/SCX, BG tilemaps at `0x9800`/`0x9C00`, OAM at `0xFE00`.

Movement model: a directional tap commits ~14 px (not a full 16) or bounces, over ~24–28 frames.
Crossing a room boundary rebases the position, so an axis delta can read as "blocked" while a
real transition happened — never infer "nothing happened" from `:blocked` alone.

Dialogue: text tiles live in the scratch range `0xD0–0xEF`, rewritten per textbox; decode by 8×8
pixel bitmap, never by tile ID. No text-open flag was ever found — dialogue state is currently
inferred by probing whether movement resumed.

Terrain: a cell's walkability correlates with its 2×2 BG tile-ID signature, but the partition is
**per room** (tilesets reuse IDs), and the signature must be rebased onto SCX/SCY or it silently
reads another room's leftover tilemap. 93.1 % agreement against a live-probe oracle.

Rendering: the framebuffer is 160×144, below the reliability threshold for vision — always
upscale 4–6× before showing it to a model (~500–1 100 tokens per image).

Beyond that: 28 labelled rooms, 25 transcribed dialogues, a 20-entry visual catalog, and 61
recorded refutations, all in `data/ram_registry.json`. The prose is the problem (R2); the *facts*
are an asset and should be migrated, not discarded.

### 5.2 Technical lessons

- Snapshot/restore is cheap enough (~0.05–0.08 s) to be a primitive, not an optimisation.
- Measure the cost of the inner primitive early. A 5.7× over-simulation bug survived for days
  behind a plausible-looking constant.
- Time is frames. An instruction count is not a cycle count is not a frame count, and mixing them
  produces bugs that look like game behaviour.
- Emulation runs at best ~2× slower than real time here. Anything whose cost scales with emulated
  time must be budgeted before it is designed.
- A tap and a sustained hold are different actions. So are the approach angle and the row. A
  negative result is only meaningful when it records *how* it was obtained.
- Reading the game's own model (RAM) beats reading its rendered output (OAM/VRAM) every time the
  address is known. Finding the address is a one-off cost with a permanent payoff.

### 5.3 Methodological lessons

- One falsifiable question per session, with an end criterion, is a genuinely good unit of work.
- A fresh reviewer with no history finds things the builder cannot. Keep it.
- Record refutations as first-class results. Much of the value produced here is negative space.
- Rules that a script can check must be checked by a script. Prose rules decay; this project
  proved it with 63 violations of its own most-audited rule.
- Indicators must be computed, not narrated, or they drift toward whatever is moving.
- An escalation path that is cheaper than the real work will absorb the effort. Process work must
  be *harder* to reach for than game work, not easier.

### 5.4 Anti-patterns, explicitly

- Building a foundation with no stopping rule that points back at the goal.
- Letting a data store accept free text where a schema belongs.
- Adding a mechanism in response to a blocker instead of questioning the goal.
- Treating the process as the product when the product is stuck.
- Keeping the only copy of real progress in `/tmp`.
- Writing a "one page" file with no mechanism that enforces one page.

---

## 6. Open questions for the brainstorm

Ordered roughly by how much each one constrains everything else. Options listed are the ones this
experiment actually surfaced; none is recommended here.

**Q1 — What is the objective, precisely, and how is it scored?**
"Finish the game" / "reach and clear dungeon 1" / "maximise milestones per hour of emulation" are
three different systems. The score has to be computable from RAM by code, with no human in the
loop, or R5 repeats.

**Q2 — Where does knowledge of *this game* come from?**
Current rule: engineering knowledge allowed as hypotheses, game knowledge forbidden. That rule
has already moved once under pressure (D14 admitted the official manual). The honest framing for
the brainstorm: a full ban converts "find a weapon" into a blind search over ~256 screens at
~2× slower than real time, and that is precisely what consumed the last eleven days. The options
are a full ban, manual-only, a walkthrough as a *hypothesis source to verify in-game*, or full
knowledge. This is a values question — is the interesting part the discovery or the autonomy? —
and it changes the achievable objective more than any technical choice on this list.

**Q3 — Is rollback a debugging tool or a gameplay mechanic?**
The project owns cheap, exact snapshot/restore and used it only to probe collisions. It never
used it to *play*: try a crossing fifty times and keep the run that works. Under that framing,
`240/0`'s HP floor stops being a wall and becomes a search problem. Accepting it means the agent
does not play one continuous life, which has consequences for what "progress" and "the save file"
mean.

**Q4 — What is the world model's schema, and what enforces it?**
Typed store plus validator in CI, versus prose. What queries must it answer in code: frontier
("where have I not been"), routing ("path from A to B"), contradiction detection, "what do I know
about this tile/sprite/room".

**Q5 — What is the action space, and how does it grow?**
Movement only, versus a declared vocabulary covering attack, push, dive, item use, menus,
dialogue. How does a newly discovered mechanic enter it without a rewrite? How is "I tried X"
recorded so it carries *how* (tap/hold/angle/row)?

**Q6 — Who plans, at what frequency, and at what budget?**
An LLM in a tool-calling loop, versus a scripted policy escalating to an LLM only at decision
points (the original concept). Target: how many LLM calls per emulated game hour, and what is the
compact state each call receives?

**Q7 — What does a cold agent read before it acts, and how long is it?**
This is R10 as a design constraint: a bounded, indexed startup read with everything else
retrieved on demand.

**Q8 — What is the durable unit of progress?**
A committed `.sav`, a replayable input log from boot, a snapshot tree, or a hybrid. Requirement to
test the answer against: a fresh machine reproduces the current game state from the repository
alone.

**Q9 — What does the owner actually watch?**
Kader cannot read `room_id/map_id` pairs; he reads pictures. Live dashboard, replay GIFs, an
event stream, the Atlas — decide what observability *is* here, and make it a first-class output
of the loop rather than a reporting convention.

**Q10 — What is the throughput budget, and does it change the architecture?**
Emulated frames available per real hour, and whether parallel emulators, headless speedups, or
search over snapshots are in scope.

**Q11 — What owns "this goal is wrong"?**
The mechanism for abandoning a subgoal, on what evidence, and what the agent does next when the
current objective is unreachable — without waiting for a human.

**Q12 — How much process survives?**
Roles, escalation queue, MetaPlanner, decision log, session format. Which of these earned their
keep, and which are replaced by tests, CI and a schema?

---

## Appendix A — how to reproduce the numbers

```sh
# the clone is shallow by default -- `git fetch --unshallow` first
git log --oneline | wc -l                                     # 256 commits
git log --format='%ad' --date=short | sort | uniq -c          # per-day distribution
git log --oneline 7343453..HEAD | wc -l                       # 242 since the shield milestone
find lib -name '*.rb' | xargs wc -l                           # 1 734 lines
wc -w *.md docs/*.md docs/archive/*.md docs/process/*.md      # ~58 600 words
grep -c '"exits"\|"edges"\|"neighbors"\|"connects_to"' data/ram_registry.json   # 0
grep -c 'Indicators:' docs/archive/SESSION_LOG.md             # 20 logged sessions
grep -c 'game = unchanged\|no new milestone\|game = no new' \
        docs/archive/SESSION_LOG.md                           # 14 of them flat
```

Prose volume inside the registry (~65 400 words) counts the whitespace-separated tokens of every
string value in `data/ram_registry.json`, walking the structure recursively.

The provenance audit (15 strict violations, 48 mislabelled sources, 29 compliant of 92) walks
`data/ram_registry.json` for every object carrying `verified_count` and compares it against
`confidence` and `source`.

## Appendix B — where the durable material lives

| Material | Location | State |
|---|---|---|
| RAM addresses | `data/ram_registry.json` → `hram`, `hardware`, `wram_unmapped` | clean, ~15 KB, migrate as-is |
| Room facts, dialogues, visual catalog | same file → `room_labels`, `world_topology`, `dialogues`, `visual_catalog` | valuable but prose, ~65 000 words, needs extraction |
| Game decisions and their invalidation conditions | `DECISIONS.md` (D1–D14) | good reading before re-deciding anything |
| Narrative history | `docs/archive/SESSION_LOG.md`, `docs/archive/EXPLORATION_LOG.md` | archive; look facts up, do not read to resume |
| Mechanics not yet tried | `docs/GAME_MANUAL_NOTES.md` | short, and directly actionable |
| Previous review | `docs/ARCHITECTURE_REVIEW.md` | read it — its verdict repeated |
| Original concept | `docs/CONCEPT.md` | still unimplemented; the brainstorm's real starting point |
| Current blocker | `.koholint/research_task.json` | `exhausted` |
| Game progress | `/tmp/zelda_checkpoints/main.dump`, owner's machine only | not reproducible from this repository |
