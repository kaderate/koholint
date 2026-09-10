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
  1`. Check this before writing to the registry, not after. Audited on a fixed cadence, not left to
  chance: every cold Reviewer session (see "Three roles" below) scans `data/ram_registry.json` for
  entries claiming `verified`/`ram_read_verified` below the `verified_count >= 2` bar as a standing,
  unconditional checklist item, reported alongside its compliance judgment -- riding the same
  every-N-commits/mornings cadence `PLAN.md` already runs cold reviews on (see
  `METAPLANNER.md#MP5`).
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
| Reviewer | reads cold, judges against `docs/CONCEPT.md` and `DECISIONS.md`, audits `ram_registry.json` provenance (`verified_count` bar) | read the narrative log before judging, fix things itself |

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
- **What belongs in `NEXT.md` versus here**: before adding a line to `NEXT.md`, ask whether it would
  still be true and worth knowing once the current question is answered and forgotten. If yes -- a
  standing engineering convention, a naming scheme, a dispatch practice -- it belongs here, in this
  Process section, not there. `NEXT.md` holds only what's bound to the current state of exploration:
  indicators, decisions-in-force pointers, the next question, and a bounded "what not to redo" list
  of recent traps. See `METAPLANNER.md#MP4`.
- **Archive on resolution, not just classify on write**: the test above governs content at the
  moment it's *written*. It says nothing about content that later *becomes* historical without
  anyone adding a new line -- a "Paradigm to question" section reaching RESOLVED, a state paragraph
  superseded by a newer one. The same session that marks such a section resolved must, in that same
  edit, move its full text to `docs/archive/SESSION_LOG.md` (append at the end, chronological, in
  that file's existing entry style) and either delete it from `NEXT.md` outright or leave at most a
  one-line pointer -- never keep it in place "as a worked example" or "for reference". Before
  deleting, check for and fix any other line in `NEXT.md` that cross-references the section being
  archived (e.g. "see 'Paradigm to question' above"), since the archival makes that pointer dangle.
  If the outcome is already fully restated elsewhere in `NEXT.md` (commonly the State section),
  archiving loses nothing left to know. See `METAPLANNER.md#MP8`.

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

### Subagent prompts: never end on a wait for a notification

A dispatched `Agent`-tool subagent is a bounded, single-shot invocation, not a peer session: when
it stops calling tools -- including to report "waiting for X" -- the invocation simply ends.
Nothing inside it self-resumes; only an explicit follow-up from the dispatching session continues
it, and if the dispatcher isn't watching for that gap the subagent looks "stuck" indefinitely. This
recurred 7+ times across Explorer/Builder dispatches on September 9, 2026, mitigated manually each
time, before being written down anywhere a future dispatch would read cold (see
`METAPLANNER.md#MP3`).

- Never write a subagent prompt that tells it to wait for a `Monitor` notification, another
  session's completion, or any other external event and then continue. If the subagent's task
  depends on an external condition, either poll it synchronously in a loop within the subagent's
  own turn (tool calls only, never relying on being re-invoked), or don't delegate that step at all
  -- keep the waiting in the dispatching session, which can actually be resumed by an external
  event, and have the subagent return a status report instead.
- `run_in_background`/`Monitor` are dispatcher-side tools. Never instruct a subagent to use them on
  itself.

### Subagent prompts: bound multi-step helper calls under the foreground timeout

A different, easier-to-hit door onto the same trap: a subagent's own foreground tool call -- not a
deliberate wait, just an ordinary call chaining many slow steps (e.g. a `nudge_axis!`-style helper
issuing ~20 `Navigator.move!` calls at 13-30s wall-clock each in this environment) -- can itself
exceed the tool's foreground timeout and get silently auto-backgrounded mid-call. The subagent
never chose to wait; the platform just handed it back a running background task instead of a
result. From there it's the exact same stuck-subagent trap the rule above already names, just
reached without anyone writing a "wait for notification" instruction. Caught as a live risk on
September 10, 2026, before it produced an actual incident (see `METAPLANNER.md#MP7`).

- Before chaining several slow primitive calls (measured or conservatively estimated wall-clock,
  never guessed) into one foreground tool invocation, keep the batch's worst case (steps x
  per-step worst case) safely under the timeout actually in effect -- the tool's default, or an
  explicit `timeout` you set, whichever applies. Don't assume slack you haven't checked for.
- If a batch's worst case can't fit under that ceiling, split it into multiple sequential
  foreground calls issued back-to-back within the same turn, instead of one call spanning the
  whole chain.
- If a call still comes back auto-backgrounded despite the above (the estimate was wrong, or the
  environment ran slower than expected), handle it exactly per the rule above: poll it
  synchronously within the same turn until it resolves. Never treat the backgrounding itself as
  license to stop mid-turn waiting for a notification.

### MetaPlanner: amending the workflow itself

Cascades the planner -> worker split one level up. The planner (whoever is driving day-to-day
sessions and dispatching Explorer/Builder/Reviewer work) can get stuck on a problem that isn't
about the game at all -- it's about *this process*: a rule that doesn't fit a case it hits, a
convention two files disagree on, a file that's outgrown its own stated shape. MetaPlanner exists
to fix exactly that, and nothing else.

- **Mandate**: amend process/coordination artifacts only -- `AGENTS.md`, `NEXT.md`'s own structural
  rules (not its content), `PLAN.md`, subagent-prompt conventions. Never `DECISIONS.md`, never
  `data/ram_registry.json`, never anything that is a fact about the game or a decision about how to
  play it. If a proposed change touches game/domain territory, it isn't a MetaPlanner change --
  it's a planner decision, logged in `DECISIONS.md` like any other.
- **Trigger**: event-based, not a fixed timer or a schedule. A planner session that hits a
  process-level snag escalates it (see below); the owner can also launch a MetaPlanner session
  directly at any time. The planner may dispatch MetaPlanner itself via `create_session` the moment
  it appends an `open` escalation -- except the very first such dispatch, which requires an
  explicit `AskUserQuestion` confirmation from the owner first, to observe real behavior before
  trusting it unattended (see `METAPLANNER.md#MP2`). After that first observed run, later
  dispatches proceed without asking. **The dispatch call must set `source_url`/`source_revision`
  explicitly**: `create_session`'s "inherits the calling session's environment" phrasing covers the
  `environment_id` only, not an automatic repo checkout -- omitting them lands the new session in an
  empty container with nothing to act on (see `METAPLANNER.md#MP6`).
- **Session shape**: same discipline as "One session, one question" above, cascaded up -- short (5
  to 30 minutes), one escalation in, one workflow amendment (or explicit non-amendment) out. Starts
  cold: reads `METAPLANNER.md`, `METAPLANNER_ESCALATIONS.md`, and `AGENTS.md` itself, nothing else
  from the planner's live conversation.
- **Memory**: `METAPLANNER.md` is MetaPlanner's own decision log, one entry per workflow change --
  same shape as `DECISIONS.md`'s entries (context, options, choice, invalidation condition), but for
  the workflow instead of the game. Written only by MetaPlanner sessions.
- **Handoff**: `METAPLANNER_ESCALATIONS.md` is the shared queue between the two roles, separate from
  `METAPLANNER.md` so the access boundary is a file, not a section inside one. The planner may only
  *append* an entry with status `open` (context, symptom, why it's process and not domain) --
  never edit or resolve one itself. MetaPlanner drains the queue: marks an entry `resolved` with a
  pointer to the `METAPLANNER.md` entry that addressed it, and prunes old resolved entries
  periodically (archive or trim) so the queue doesn't drift into the same one-page violation
  `NEXT.md` already hit once.
- Same rule as everywhere else in this project: a change with no entry in `METAPLANNER.md` and no
  resolved line in `METAPLANNER_ESCALATIONS.md` didn't happen, as far as the next cold session is
  concerned.

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
