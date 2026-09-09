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
