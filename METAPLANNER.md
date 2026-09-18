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

## MP9: two explicit thread-status terms -- "closed" vs. "paused (gate: ...)" -- so a status summary can't conflate them

**Date**: September 17, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC7`.

**Context**: D12 (RAM writes to gameplay state are case-by-case, asked every time -- not a standing
tool) was ratified after the owner answered an `AskUserQuestion` about the Plage Coco health
blocker. The planner then folded that into a status report by grouping "Plage Coco (en pause, D12)"
under a "high-confidence leads are now exhausted" summary, alongside genuinely closed threads
(`shop_screen`'s door, the bush-contact test). The owner caught this immediately -- Plage Coco was
never eliminated, D12 explicitly left a live path open (ask per specific instance), and the planner
never actually made that specific ask before writing the summary. Nothing in `AGENTS.md` or the
reporting convention distinguished, in writing, a thread that's genuinely closed from one that's
paused behind a standing gate the planner hasn't yet exercised for this instance -- both rendered
identically ("en pause"/lumped into "épuisé") with no textual distinction.

**Options considered**:
1. Leave it to planner discipline / re-reading `DECISIONS.md` before each summary. Rejected: this is
   exactly what already failed -- the gate (D12) was known and cited correctly elsewhere in the same
   session, the failure was purely in how the status summary worded it, not in missing information.
2. A mechanical status enum enforced by tooling (e.g. a structured `NEXT.md` field, lint-checked).
   Rejected: over-engineering a wording problem into a schema/tooling problem before prose has even
   been tried once, and building such tooling is Builder-shaped work outside a short MetaPlanner
   session's mandate and context (no game/domain access here to design it well).
3. **Chosen**: add a "Thread status: closed vs. paused-behind-gate" subsection to `AGENTS.md`,
   defining exactly two terms for any non-active thread in a status summary -- `Closed` (anti-patch
   budget spent or every identified avenue tried and failed) and `Paused (gate: <decision>)` (blocked
   behind a standing gated decision not yet exercised for this instance) -- and stating the rule that
   a thread moves from paused to closed only once the gate-specific ask was actually made and
   declined, never by association with other threads nearby being exhausted. Placed right before the
   existing "End-of-session report" section since it governs the same kind of status communication.

**Invalidation condition**: if a future status summary still conflates the two despite the explicit
terms being written down (the same failure mode `MP4`/`MP8` already saw one level down, for
`NEXT.md` content instead of report wording), prose distinction isn't sufficient -- the fix needs a
mechanical check (e.g. a lint requiring every non-active thread mentioned in a session report to be
tagged with one of the two literal terms) instead of restating the rule.

## MP10: a tested-both-ways bar for decorative/non-interactive claims, and a spec-first route (not a MetaPlanner build) for promoting the validated clue cross-reference script

**Date**: September 17, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC8`.

**Context**: `ESC8` opened September 10, 2026 over dialogue clues not being cross-referenced against
newly-found spatial facts, with a four-part planner proposal (a `quest_clues` registry section, a
standing cross-reference step, spatial-vs-clue-directed Explorer mandates, a Reviewer checklist
item) offered as a starting point, not a final answer. A September 12 addendum validated one narrow
piece of that cheaply: a throwaway ~60-line Ruby prototype's mechanism (b) -- cross-referencing
dialogue text, case-insensitive, against the SELECT map's own known place-name vocabulary -- 
independently reproduced the `starting_house` -> "Plage Coco" link the owner had pointed out three
times, using only data already on file. A sibling mechanism (a) (capitalization-based term
extraction) was shown blind to that exact case, since the clue ("va sur *la plage*") is a lowercase
French common noun the game never capitalizes. The same addendum also surfaced a grounding bug:
checking a term against *any* field containing it (including open-discussion notes) falsely marks
debated-but-unresolved terms like "Loupe" as grounded; grounding must check only fields recording an
actual placed/observed fact (`room_labels`, `select_map_screen.note`).

A September 17 addendum reported the project's own "recur a few times first" bar (the same bar D13's
`Navigator` avoidance helper cleared, after the same tactic was independently re-derived across 4
sessions) now met for a second, related failure mode: an interactive object misclassified as
decorative because it was tested only one way. Three independent, dated instances: `crate_room`'s 6
"hard negative" books (tap-tested only, actually held the game's first named-item reference),
`overworld_screen2`'s "landmark" (catalogued decorative for a week, actually a telephone booth with
a real door), `riverside_screen`'s signpost (logged "not fully exhaustively" tested, actually opened
on a single plain tap and named a new location, "Cave Flagello"). The addendum scoped two concrete,
Builder-shaped asks -- a two-part tested field, and promoting the validated cross-reference script
out of scratchpad -- explicitly distinguishing this "world puzzle" misclassification problem from
proposal (2)'s clue-cross-referencing, and explicitly deferring "dungeon puzzle" process (not yet
reached by the project) as out of scope.

**Options considered**:
1. Adopt the full `quest_clues` registry (the original proposal 1) now. Rejected: that's a new
   `data/ram_registry.json` schema section -- game-data territory outside this mandate (`AGENTS.md`'s
   "never `data/ram_registry.json`" line) -- and the addendum's own recurrence bar was demonstrated
   met only for the two narrower September 17 asks, not for the full registry redesign across the
   whole quest-clue space (one prototype run against a 19-entry corpus, re-deriving already-known
   findings, per the September 12 addendum's own "not yet evidence" caveat). Left undecided at this
   scope; a planner/`DECISIONS.md`-scoped call if the evidence bar is met later.
2. Have this MetaPlanner session write the promoted cross-reference script into `lib/` directly, and/
   or edit the two-part `tested` field directly into existing `room_labels`/`visual_catalog` entries.
   Rejected: both are Builder-shaped implementation work over game data and game tooling, requiring
   ROM/emulator context this session explicitly doesn't have (a process-only MetaPlanner session, no
   gameplay work) -- exactly `MP1`'s mandate boundary. Mirrors why `MP5` assigned the provenance audit
   to the existing Reviewer role instead of building an audit script itself.
3. Adopt only the two-part `tested` field convention now and leave the script-promotion ask
   unrouted, pending further Explorer validation. Rejected: the addendum was explicit that both asks
   already cleared the validation bar ("Builder-shaped work now, not further Explorer validation");
   leaving a second, already-validated finding sitting unrouted would just recreate the exact
   evidence-drift problem `ESC8` itself was opened over.
4. **Chosen**, two-part:
   (a) Add a registry-entry convention to `AGENTS.md`, same form and location as the existing
   `verified_count` rule: a `room_labels`/`visual_catalog` entry may only claim
   `decorative`/`non-interactive` once it carries a two-part `tested` field -- a short tap AND a
   sustained ~110-150f hold, each from at least one approach angle -- and an entry missing either
   half reads as `untested`, not decorative. Folded into the existing Reviewer cold-review checklist
   alongside the `verified_count` audit, same cadence `MP5` already established (no new cadence
   invented). The Reviewer role-table row updated to name both audits explicitly.
   (b) Add a general "Promoting validated Explorer prototypes" process rule to `AGENTS.md`: a
   scratchpad spike that clears the same recurrence bar as the anti-patch rule/D13 (validated more
   than once, independently) is Builder-shaped work to route with a fixed spec, not something
   MetaPlanner builds or the proposing session keeps generalizing. Applied here as the worked
   example: direct a Builder session to promote mechanism (b) alone (never mechanism (a), documented
   blind to the target case) from the September 12 prototype into a committed `lib/` tool, scoped
   exactly as validated -- cross-reference dialogue text against `select_map_screen.note`'s place-name
   vocabulary, run once per new dialogue/place-name fact captured, grounding checked only against
   `room_labels`/`select_map_screen.note`, never open-discussion prose (`world_topology.*.note`) per
   the documented "Loupe" false-positive.
   The original proposal 1 (full `quest_clues` registry) and its remaining pieces (spatial-vs-clue-
   directed Explorer mandates) are not adopted at this scope -- left as a planner/domain call if the
   evidence bar is met later, per option 1 above.

**Invalidation condition**: if a `room_labels`/`visual_catalog` entry still claims
decorative/non-interactive without the two-part field despite this rule and the Reviewer checklist
item, or if the Builder-shaped script promotion doesn't happen within a reasonable number of
sessions after being routed this concretely, prose/routing isn't sufficient -- the fix needs a
mechanical guard (e.g. a lint rejecting a decorative claim missing either tested sub-field) or a
stronger directive prioritizing the next Builder session on it, instead of restating the rule.

## MP11: a cross-reference-before-classify convention for hazard/creature facts, and a spec-first route (not a MetaPlanner build) for a derived hazard/creature index tool

**Date**: September 18, 2026. Resolves `METAPLANNER_ESCALATIONS.md#ESC9`.

**Context**: `ESC9` opened September 18, 2026 over creature/hazard facts being scattered per-room
with no canonical cross-reference, so the same identification work repeats and code hazard-tracking
silently drifts out of sync with what's already catalogued. Four concrete, evidenced instances,
same root shape, clearing this project's own "recur a few times first" bar (the one `ESC8`/`MP10`
already used): (1) a live `240/0` hazard-avoidance experiment filtered on `Navigator::HOSTILE_TILE_IDS`
alone and took a real -12 HP hit from `tile=0x6c`, already a known member of the separate
`Navigator::UNKNOWN_HAZARD_TILE_IDS` set, before the gap was caught and fixed mid-session; (2) a
signpost's explicit, falsifiable claim ("a shield counters oursins") sat unqueried for 8 days with
nothing surfacing it as an open claim to test; (3) at least 4 separate `visual_catalog` entries
across different rooms independently carry "hazard status unknown, not tested" with no shared place
recording that once; (4) a CHR-byte-confirmed identity match (friendly creature at `177/0` = same
sprite at `162/0`) is on file but didn't propagate, so the second sighting stayed queued as a fresh
unknown many sessions later. The escalation itself is explicit that the actual facts about any given
creature are `DECISIONS.md`/`data/ram_registry.json`-scope, out of MetaPlanner's mandate, while
whether a canonical cross-reference structure and audit habit exist at all is process-level, same
split `ESC8`/`MP10` already drew between claim content and claim-tracking structure.

**Options considered**:
1. Adopt a full canonical creature/hazard registry schema now (e.g. a new `bestiary` section in
   `data/ram_registry.json`). Rejected: a new game-data schema is domain territory outside this
   mandate (`AGENTS.md`'s "never `data/ram_registry.json`" line), same reasoning `MP10` already used
   to reject adopting the full `quest_clues` registry at MetaPlanner's own scope -- left undecided
   here, a planner/`DECISIONS.md`-scoped call if evidence for that specific shape accumulates.
2. Have this MetaPlanner session build the cross-reference index/tool itself. Rejected: Builder-shaped
   implementation work requiring ROM/registry content context this session doesn't have -- exactly
   `MP1`'s mandate boundary, and the same reasoning `MP10`'s option 2 already used to reject building
   the promoted script itself instead of routing it.
3. Adopt only the convention/Reviewer-audit half now, leave the index/tool routing for a later
   MetaPlanner pass pending further validation. Rejected: unlike `MP10`'s full `quest_clues`
   registry (evidenced by one prototype run against one corpus), `ESC9`'s four instances already
   independently clear this project's own recurrence bar for the narrower, already-scoped ask (a
   derived index over facts already on file, not a new schema) -- leaving it unrouted would
   recreate the exact drift this escalation was opened over.
4. **Chosen**, two-part:
   (a) Add a "cross-reference before classify" convention to `AGENTS.md`, same form and location as
   the existing `verified_count`/`tested`-field rules: before logging a new hazard/creature
   classification entry, check whether the same tile ID, CHR pattern, or cross-room identity is
   already recorded elsewhere; before writing or using a hazard-tile filter, reference the canonical
   union (`Navigator::HAZARD_TILE_IDS`), never a narrower set picked without checking for a broader
   one. Folded into the existing Reviewer cold-review checklist alongside the `verified_count` and
   `tested`-field audits, same cadence `MP5`/`MP10` already established (no new cadence invented).
   The Reviewer role-table row updated to name all three audits.
   (b) Route (not build) a precisely-scoped Builder task, per `AGENTS.md`'s "Promoting validated
   Explorer prototypes" precedent of routing rather than MetaPlanner building: a derived, read-only
   index/tool (e.g. `lib/hazard_index.rb`) generated from `data/ram_registry.json`'s
   `visual_catalog`/`room_labels`/`world_topology` entries and `lib/navigator.rb`'s
   `HOSTILE_TILE_IDS`/`UNKNOWN_HAZARD_TILE_IDS`/`HAZARD_TILE_IDS` constants -- given a tile ID, CHR
   signature, or room+object key, it reports every registry location that already records something
   about it, so a session about to log a new hazard/creature entry can query first instead of
   quietly duplicating one. It also scans `dialogues.*.note` for an already-flagged specific
   falsifiable behavioral claim about a creature/hazard and surfaces it if no other entry's status
   reflects that claim being tested yet. Grounding rule, same as `MP10`'s mechanism (b): match only
   against fields recording an actual placed/observed fact (`room_labels`, `visual_catalog`,
   `world_topology`'s tile/CHR fields), never open-discussion `note` prose, to avoid the exact
   false-grounding bug `MP10`'s own addendum already found once ("Loupe"). Explicitly out of scope
   for this routed task: designing a new `data/ram_registry.json` schema section -- that's option 1
   above, left undecided. This MetaPlanner session does not call `create_session` to dispatch the
   Builder work itself, matching `MP10`'s own precedent (its routed promotion, commit `af62929`, was
   made by a later Builder session, not from within the MetaPlanner session that wrote the spec) --
   the spec above is fixed here for whichever Builder session picks it up next.

**Invalidation condition**: if any of the four evidenced instances' shape recurs despite the
cross-reference convention and Reviewer checklist item being written (a new duplicated hazard entry,
or a hazard filter still referencing a narrower tile-ID set without justification), or if the routed
Builder task doesn't get picked up within a reasonable number of sessions after being scoped this
concretely, prose/routing isn't sufficient -- the fix needs a mechanical guard (e.g. a lint rejecting
a hazard-status entry or tile-ID filter that doesn't cite a cross-reference check) or a stronger
directive prioritizing the next Builder session on it, instead of restating the rule -- the same
fallback `MP10` already named for its own routed piece.
