# Koholint — notes for agents

Agent that plays Link's Awakening DX through gemboy. Read `README.md` for the layout and reading
order, `NEXT.md` before any action.

## Conventions

- **Language**: everything — documentation, messages, code, comments — in English.
- **Commits**: a single line, imperative mood, no body. Impact in parentheses if useful.
- **Comments**: almost none. Only a hidden constraint or a *why* that can't be deduced from the
  code, in one line. Reasoning goes in the commit message or in `DECISIONS.md`.
- **Time**: the unit is the frame. Never an instruction counter, never a `sleep`. Wait for a state
  condition, not a duration.
- **Facts about the game**: every measured fact becomes a checkpoint spec or an entry in
  `data/ram_registry.json` with provenance and `verified_count`. A fact that is neither will be
  rediscovered by the next agent, at full cost.
- **`confidence: verified` / `source: ram_read_verified` requires `verified_count >= 2` from
  genuinely independent checks** — a different session, a different method, or at minimum a
  separately-run probe, never two reads from the same script's internal repetition. Below that
  bar, label it `hypothesis` (`verified_count: 1`) and say so; a future session or a fresh probe
  closes the gap. Found violated in the field once already (cold review, September 9, 2026): ~15
  `world_topology`/`dialogues` entries carried `verified`/`ram_read_verified` at `verified_count:
  1`. Check this before writing to the registry, not after.
- **Pre-trained knowledge**: the game's memory map (community disassembly) is a source of
  hypotheses to verify, consistent with the provenance model. *Game* knowledge (where the sword
  is, who an NPC is) is forbidden: it is observed, never assumed.

## Process

This project has already drifted once: three days of autonomy, five successive patches on the
same mechanism, means metrics mistaken for progress, and one agent's decisions inherited as facts
by the next. The rules below exist so it doesn't happen again. They override your judgment of
"there's just one small fix left".

### One session, one question

- Every session starts with **one falsifiable question, one end criterion, and one budget** (time
  or number of commits), written in the first message or in `NEXT.md`. Valid example: "Confirm or
  refute Link's position in HRAM, budget 2h, deliverable: RAM registry entry promoted or refuted
  plus a spec." Invalid example: "Make progress on navigation."
- Once the boundary is reached, you stop and hand in a report, even if you "can see what's next".
  What's next is a new question for a new session.
- Before writing code, you **restate the mandate as a testable criterion** in two lines and get it
  validated. "Look at the screen like a human would" is not a criterion. "A screen whose tiles are
  all catalogued can be traversed from A to B with no live probe at all" is one.

### Three roles, never in the same session

| Role | Does | Does not do |
|---|---|---|
| Explorer | throwaway spikes, measurements, memory diffs, scripts in the scratchpad | commit to `lib/`, decide |
| Builder | implements a decision already made, with specs, in its worktree | change paradigm, "take the opportunity" to fix something else |
| Reviewer | reads cold, judges against `docs/CONCEPT.md` and `DECISIONS.md` | read the narrative log before judging, fix things itself |

You never judge your own build. A review is triggered by the owner every N commits or every
morning after a night of autonomy, by a fresh session with no history.

### Decisions, not narratives

- `DECISIONS.md` is the only memory of choices made. One entry per decision: context, options,
  choice, **and the condition that would invalidate it**. Example: "OAM as the position source.
  Invalidated if a room contains a moving sprite other than Link."
- When the invalidation condition occurs, that's a **return to the decision**, not a workaround. A
  wandering villager blocking a cell is not a case to handle with a retry budget, it's proof the
  decision has fallen.
- `docs/archive/EXPLORATION_LOG.md` is an archive. You don't read it to resume a project, you read
  `NEXT.md` and `DECISIONS.md`. You don't write decisions into it.
- `NEXT.md` fits on one page: state, decisions in force, next question, how to verify it. Every
  resumption starts there. If a resumption requires more than one page of reading, `NEXT.md` is
  broken, not the resumption.

### Goal metrics, not means metrics

Three indicators, kept up to date in `NEXT.md`, cited in every session report:

1. **Progress in the game**: last milestone reached (sword, dungeon 1, etc.).
2. **Trip A to B**: frames emulated to cross an already-known screen, with no live probe.
3. **Verified facts**: RAM registry entries at `verified` status.

A catalog size, a skip rate, a number of resolved cells are means metrics. A commit that moves
none of the three indicators must say why it exists.

### Anti-patch rule

**Three successive patches on the same mechanism with no progress on a goal indicator means
mandatory stop.** You write a "paradigm to question" note in `NEXT.md` with the question the owner
must decide, and you stop. The fourth fix isn't "almost there", it's the sign the problem is
elsewhere.

### Autonomy executes, it does not design

- A session with no human present (overnight, routine) **executes decisions already made**: long
  runs, rebuilds, measurement campaigns, specs on established facts.
- It does not choose an architecture, does not change a source of truth, does not create a new
  component, does not introduce a new coordinate frame.
- Its morning deliverable is **a table of measurements and a list of questions**, not a pile of
  commits. If you made a design decision during an autonomous session, mark it explicitly
  `DECISION MADE WITHOUT VALIDATION` in the report and in `DECISIONS.md`.

### Fundamental decisions belong to the owner

You don't decide, you propose with options and their costs:

- the observation layer (game state in RAM vs. PPU output vs. pixels);
- exhaustive exploration vs. on-demand navigation;
- the hardware mode (DMG vs. CGB);
- what counts as forbidden *game* knowledge vs. allowed *engineering* knowledge as a hypothesis to
  verify.

### Memory is specs and data

- Every fact measured about the game becomes **a checkpoint spec** or **a registry entry with
  provenance**.
- No essay-comments in the code. An exploration that produced neither a spec nor a registry entry
  produced nothing.

### Parallelism

- Multiple agents only on **independent, bounded questions**, each in its own worktree,
  integration by the owner.
- Never two agents on the same mechanism. Never an agent building on a decision another agent is
  currently reopening.

### End-of-session report

Always the same format, in `NEXT.md`, so the next agent can resume without reading you:

```
Question: ...
Answer: confirmed / refuted / inconclusive (and why)
Indicators: game = ... | trip A→B = ... | verified facts = ...
Decisions made: (none, or a list marked validated / not validated)
Next question proposed: ...
What NOT to redo: ...
```
