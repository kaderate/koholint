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

## MP6: amend MP2's dispatch instructions to require `source_url`/`source_revision` explicitly

**Date**: September 9, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC4`.

**Context**: the first real MetaPlanner dispatch (session `session_019ZMSHF5XTHtJx5yWS66eUz`) was
created without `source_url`/`source_revision`, on the mistaken reading that `create_session`'s own
"inherits the calling session's environment" meant the repo would be checked out too. It wasn't --
the session landed in an empty container, correctly identified this as either a misconfiguration or
a prompt injection with no way to tell which, and rightly refused to act rather than fabricate a
report. A retry with `source_url`/`source_revision` set fixed it. `MP2` documented `create_session`
dispatch without mentioning this requirement, leaving it one bad copy-paste away from repeating.

**Options considered**:
1. Rewrite `MP2` in place to add the missing detail. Rejected: `MP2` is a genesis entry recording
   what was actually decided and owner-validated at the time; editing it in place would blur the
   record of what the first observed dispatch actually tested versus what was learned afterward.
2. Fix only wherever the dispatch prompt/example is written, without logging a decision. Rejected:
   this project's own rule -- a change with no `METAPLANNER.md` entry didn't happen, as far as a
   future cold session is concerned -- applies to MetaPlanner's own dispatch mechanics as much as to
   anything else.
3. **Chosen**: log this as a new, separate entry amending `MP2`'s instructions, and state the
   concrete requirement directly in `AGENTS.md`'s MetaPlanner section (the "Trigger" bullet) so a
   future dispatch reads it before calling `create_session`, not only in the decision log.

**Invalidation condition**: if a dispatch still omits `source_url`/`source_revision` despite this
being stated in `AGENTS.md`, the fix needs to move from documentation to a checklist the dispatching
session is forced to fill in, not another restatement.

## MP7: bound multi-step Explorer helper calls under the foreground timeout, as a named variant of MP3's trap

**Date**: September 10, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC5`.

**Context**: an Explorer session on September 10, 2026 found that a single `Navigator.move!` call
took 13-30s wall-clock in this environment, and a `nudge_axis!`-style helper chaining ~20 such calls
would exceed the foreground Bash timeout and get silently auto-backgrounded. `AGENTS.md`'s existing
"Subagent prompts: never end on a wait for a notification" rule (`METAPLANNER.md#MP3`) already
covers a subagent that deliberately waits on a background task, but this is a different root cause:
an ordinary foreground call, never intended to background at all, crossing the timeout by sheer
chained duration and landing the subagent in the same stuck state by accident. That session avoided
it only by habit (breaking work into single/paired `move!` calls per invocation), with nothing
written down telling a future Explorer to do the same. Caught as a live risk, not yet an actual
stuck-subagent incident.

**Options considered**:
1. A dispatcher-side watchdog that detects an auto-backgrounded subagent task and force-resumes it.
   Rejected: same reasoning as `MP3`'s option 1 -- treats the symptom, adds a mechanism to maintain,
   and the poll-synchronously fix already in `AGENTS.md` handles it once it happens without any new
   machinery.
2. A fixed hardcoded batch-size cap (e.g. "never more than 10 `move!` calls per invocation").
   Rejected: hardcoding a step count ties the rule to today's measured 13-30s figure and to this one
   helper; a future helper with different per-step cost would be either needlessly restricted or
   unsafely permitted. Reasoning from measured/estimated cost against the timeout actually in effect
   generalizes past `Navigator.move!`.
3. Rely on `MP3`'s existing rule alone, on the theory poll-synchronously already covers any
   backgrounding. Rejected: `MP3` tells you what to do once a call is already backgrounded, but a
   subagent that never expects an ordinary foreground call to background at all has no cue this can
   happen outside a deliberate wait -- a distinct root cause (call-duration budget vs. deliberate
   wait pattern) that needs naming so a future dispatch prompt anticipates it, not just survives it
   by luck.
4. **Chosen**: add a new "Subagent prompts: bound multi-step helper calls under the foreground
   timeout" subsection to `AGENTS.md`, requiring a worst-case-vs-timeout check before chaining slow
   primitive calls, splitting into sequential foreground calls when the estimate doesn't fit, and
   falling back to `MP3`'s poll-synchronously rule if a call backgrounds anyway.

**Invalidation condition**: if a subagent still gets stuck this way despite estimating batch sizes
against the timeout (e.g. because per-step cost is unmeasurable or unpredictable in a given
environment), prose asking the subagent to compute the budget isn't sufficient -- the fix needs a
mechanical guard (e.g. a helper wrapper that always sets an explicit conservative per-batch
`timeout` and hard-caps its own batch count) instead of restating the rule.

## MP8: archive-on-resolution rule for `NEXT.md`, plus a one-time archival pass on house2_interior

**Date**: September 10, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC6`.

**Context**: `NEXT.md` had grown to 239 lines despite `MP4`'s classification test, which routes
*new* content to the right file at write time but has nothing to say about content that starts
current and later *becomes* historical without any new line being added -- e.g. the
house2_interior "Paradigm to question" section, marked RESOLVED September 9, was still sitting in
`NEXT.md` in full, explicitly "kept ... as a worked example", instead of moving to
`docs/archive/SESSION_LOG.md` (which `AGENTS.md` already designates for exactly this kind of
resolved history, and which every other past session report already lives in). This is a
timing gap in `MP4`'s test, not evidence the test itself is too permissive: it was never asked to
watch content already written for a later change of status.

**Options considered**:
1. Treat this as `MP4`'s invalidation condition firing and tighten that test (e.g. a mechanical
   line-count lint). Rejected: the test isn't the problem -- it correctly keeps genuinely-durable
   conventions out of `NEXT.md` at write time. The gap is a missing *second* rule for a different
   trigger (status change, not authorship), not a flaw in the first rule to fix by making it
   stricter.
2. A hard `NEXT.md` line-count cap enforced some other way (pre-commit hook, CI check). Rejected:
   out of mandate to design tooling unilaterally from a short MetaPlanner session (same reasoning
   as `MP5`'s rejection of an automated pre-commit script), and doesn't say *what* to cut, just
   that something must be -- the actual judgment call (is this section truly resolved, is its
   content duplicated elsewhere) still needs a rule, not just a trigger.
3. Do the retroactive full split of `NEXT.md`'s current content now, beyond just the one RESOLVED
   section named in the escalation. Rejected: same reasoning as `MP4`'s rejected option 1 -- most of
   `NEXT.md`'s bulk is legitimately current state/indicators/traps, not historical filler, and
   sorting that out wholesale is a judgment-heavy pass better left to whoever is actively tracking
   which lines are still load-bearing, not a blind cold pass from this role. The escalation named
   one clear, uncontroversial candidate (a section explicitly marked RESOLVED, whose content is
   already duplicated in the State section); scope the fix to that.
4. **Chosen**: add a standing "archive on resolution" rule to `AGENTS.md` (companion to `MP4`'s
   test, not a replacement) -- the session that marks a `NEXT.md` section resolved must move its
   full text to `docs/archive/SESSION_LOG.md` in the same edit, fix any dangling cross-reference
   left behind, and leave at most a one-line pointer in `NEXT.md` (or nothing, if the outcome is
   already restated elsewhere, e.g. the State section). Do the house2_interior section itself as the
   one-time worked example the escalation asked for: moved to `SESSION_LOG.md`'s end (matching its
   existing chronological entry style), deleted from `NEXT.md`, and the one dangling "what not to
   redo" cross-reference to it rewritten to point at the State section and the registry directly.
   Net effect: 239 -> 234 lines -- a small cut, because most of the file's length is legitimately
   current, not historical; the rule matters more than this single pass's line count.

**Invalidation condition**: if a future session marks a `NEXT.md` section resolved and leaves it in
place anyway despite this rule being written (the same failure mode `MP4` already had, one level
up), prose isn't sufficient for this either -- the fix needs a mechanical check (e.g. a lint that
flags any line containing "RESOLVED" still present in `NEXT.md`, or a pre-commit hook), not a
restated rule.
