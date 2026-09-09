# MetaPlanner

MetaPlanner's own decision log. One entry per workflow amendment: context, options considered, the
choice, and the condition that would invalidate it -- same shape as `DECISIONS.md`, but for the
process instead of the game. See `AGENTS.md`'s "MetaPlanner" section for the role's mandate and
access boundary.

**Written only by MetaPlanner sessions**, except the genesis entry below (MP1), authored jointly by
the owner and the planner session on the day the role was created, since MetaPlanner didn't exist
yet to write its own first entry.

Resolved escalations are drained from `METAPLANNER_ESCALATIONS.md` into an entry here; that file
keeps only a pointer back, not the rationale.

---

## MP1: create the MetaPlanner role

**Date**: September 9, 2026 (genesis entry, authored by the owner + planner session, not a
MetaPlanner session).

**Context**: the planner (whoever drives day-to-day sessions) had no way to fix a process-level
problem without either doing it ad hoc mid-session (risking exactly the kind of undocumented drift
`AGENTS.md`'s "Process" section already warns about) or letting it sit unaddressed. The existing
three roles (Explorer/Builder/Reviewer) all operate *inside* the workflow; none has a mandate to
amend it.

**Options considered**:
1. Let the planner amend `AGENTS.md` directly when needed, no separate role. Rejected: no
   discipline distinct from any other change, the exact failure mode `AGENTS.md` already exists to
   prevent (three-day drift, patches justified by their own author).
2. MetaPlanner as a subagent of the planner. Rejected: subagents are bounded, single-shot
   invocations that die at the end of their turn (root-caused this same day from a recurring
   "subagent stuck waiting for a notification that never arrives" incident) -- unfit for a role
   meant to act independently between planner sessions.
3. MetaPlanner as a peer session, coordinated via live cross-session messaging. Rejected as the
   primary mechanism: a remote/cloud session can be messaged but cannot message back through that
   channel with the tooling available at the time -- not a hard blocker (see MP2), but not
   something to depend on for the resolution signal.
4. **Chosen**: MetaPlanner as a peer session (side by side with the planner, not a child of it),
   coordinated asynchronously through durable files (`METAPLANNER_ESCALATIONS.md` for the handoff,
   `METAPLANNER.md` for the rationale), triggered by events rather than a timer. Matches the
   project's own standing bias for cold-readable state over live session memory.

**Choice**: MetaPlanner amends process/coordination artifacts only, never `DECISIONS.md` or game
data. Escalation and resolution go through `METAPLANNER_ESCALATIONS.md`, kept as a separate file
from this one so the access boundary (planner: append-only `open` entries; MetaPlanner: resolve and
prune) is a file-level rule, not a section-level convention easier to violate by mistake.

**Invalidation condition**: if a MetaPlanner session ever needs to touch `DECISIONS.md` or
`data/ram_registry.json` to actually fix a process problem, the mandate boundary itself is wrong and
needs revisiting -- that would mean process and domain aren't as separable as assumed here.

## MP2: direct dispatch via `create_session`

**Date**: September 9, 2026 (genesis entry, same authorship as MP1).

**Context**: MP1 assumed the owner would manually launch each MetaPlanner session. Checking the
available tooling the same day found `create_session`, which lets a session spawn a genuine peer
session (not a bounded subagent) with an initial prompt, inheriting the calling session's
environment.

**Choice**: the planner may dispatch a MetaPlanner session itself the moment it appends an `open`
escalation, via `create_session`, rather than requiring the owner to launch it by hand. The
one-way-messaging limitation from MP1 option 3 doesn't block this: the dispatch prompt only needs
to point the new session at `METAPLANNER_ESCALATIONS.md`, `METAPLANNER.md`, and `AGENTS.md`; the
resolution signal still travels through the committed file, not a reply. **Gated first use**: the
very first `create_session` dispatch of MetaPlanner requires an explicit `AskUserQuestion`
confirmation from the owner before firing, specifically to observe the real behavior (does it
actually stay in scope, does it produce a sane `METAPLANNER.md` entry) before trusting it
unattended. Owner-validated September 9, 2026. Once that first dispatch has been observed, later
ones proceed without asking, per this entry.

**Invalidation condition**: if autonomous dispatch turns out to spawn sessions faster than the owner
wants to track (cost, runaway escalation volume), fall back to owner-launched MetaPlanner sessions
only, gated by an explicit confirmation before each `create_session` call.

## MP3: document the subagent-stuck-on-notification failure mode as a hard prompt rule

**Date**: September 9, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC1`.

**Context**: a dispatched `Agent`-tool subagent is a bounded, single-shot invocation; when it stops
calling tools -- even to say "waiting for notification" -- the invocation just ends, and nothing
self-resumes it short of an explicit follow-up from the dispatching session. This recurred 7+ times
across Explorer/Builder dispatches in one planner session on September 9, 2026, each time mitigated
manually, and the mechanism lived only in that conversation, not in any file a future dispatching
session would read cold.

**Options considered**:
1. Build a dispatcher-side watchdog/timeout that auto-resumes a stuck subagent. Rejected: treats the
   symptom, not the cause -- the subagent prompt itself keeps inviting the mistake -- and adds a new
   mechanism to maintain.
2. Change subagent tool access (e.g. remove `Monitor` from what subagents can call). Rejected: tool
   availability isn't a coordination artifact within this mandate, and is too large/risky a change to
   make unilaterally from a short MetaPlanner session.
3. **Chosen**: write the failure mode and a hard rule directly into `AGENTS.md` as a new "Subagent
   prompts" subsection -- never write a subagent prompt that ends on a wait for an external
   notification; poll synchronously within the subagent's own turn, or keep the waiting in the
   dispatcher and have the subagent return a status report instead.

**Invalidation condition**: if this recurs even with the rule written and dispatch prompts
following it, prose documentation isn't sufficient and the fix needs a mechanical guard (e.g. a
prompt linter, or revisiting option 2's tool-access change) instead of restating the rule more
emphatically.

## MP4: a classification test for NEXT.md-vs-AGENTS.md content, not a retroactive split

**Date**: September 9, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC2`.

**Context**: `NEXT.md`'s "Standing conventions" section mixes durable engineering rules (e.g.
subagent dispatch practices) with genuinely session-specific resumption state, with no rule
distinguishing the two. The file already exceeded its own one-page limit twice in a single planner
session, requiring manual trimming with no structural fix.

**Options considered**:
1. Retroactively split `NEXT.md`'s existing content between the two files now. Rejected: out of
   mandate (edits `NEXT.md`'s content, not its structural rules), and a judgment-heavy migration
   better done by whoever is tracking which existing lines are still load-bearing versus obsolete --
   not something to do blind, cold, in a short MetaPlanner session.
2. A hard size limit (e.g. a bullet-count cap) instead of a classification rule. Rejected: doesn't
   address which content belongs where, just delays the same overflow.
3. **Chosen**: add a one-question classification test -- "would this line still be true and worth
   knowing once the current question is answered and forgotten?" -- to both files: `NEXT.md`'s own
   preamble (structural, in-mandate) and `AGENTS.md`'s Process section, so future additions get
   routed correctly without a retroactive rewrite.

**Invalidation condition**: if `NEXT.md` exceeds one page again despite the test being applied at
write time, the test is too permissive or too easy to rationalize past, and needs a stricter
mechanical check (e.g. a line-count lint) instead.

## MP5: assign the provenance audit to the existing Reviewer role and cold-review cadence

**Date**: September 9, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC3`.

**Context**: a cold review on September 9, 2026 found ~15 `world_topology`/`dialogues` registry
entries carrying `verified`/`ram_read_verified` status below the required `verified_count >= 2`
bar. `AGENTS.md` stated the rule and cited the incident, but assigned no responsibility or cadence
for catching a recurrence -- this instance was found because someone happened to check, not because
any process step audits for it.

**Options considered**:
1. A new standalone audit session/role on its own cadence. Rejected: adds a fourth role and cadence
   when a fitting one (cold review, every 3 sessions or every morning per `PLAN.md`) already exists
   and already reads `DECISIONS.md`/the registry cold.
2. An automated pre-commit script. Rejected: would require designing `lib/` tooling, which is a
   Builder-role decision (and possibly more machinery than a periodic manual scan needs) -- outside
   what a short MetaPlanner session should decide unilaterally.
3. **Chosen**: assign the audit explicitly to the existing Reviewer role and cold-review cadence --
   added as a standing, unconditional checklist item in `AGENTS.md`'s role table and provenance rule,
   riding the cadence that already exists rather than inventing a new one.

**Invalidation condition**: if a provenance violation is later found to have survived a cold review
that was supposed to catch it (the audit ran but missed it), a checklist item isn't enough and the
audit needs to be a mechanical script the Reviewer runs, not a manual scan.
