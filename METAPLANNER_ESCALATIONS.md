# MetaPlanner escalations

The handoff queue between the planner and MetaPlanner. See `AGENTS.md`'s "MetaPlanner" section for
the roles and `METAPLANNER.md` for the rationale behind resolved entries.

**Access is per-file, not per-section**: the planner may only *append* a new entry with status
`open` -- never edit or resolve one, even its own. MetaPlanner drains the queue: flips an entry to
`resolved` with a one-line pointer to the `METAPLANNER.md` entry that addressed it, and periodically
prunes old `resolved` entries (archive elsewhere or delete) so this file doesn't grow unbounded --
it is exactly the kind of file that could repeat `NEXT.md`'s own one-page violation if left
untended.

Entry template:

```
## ESC<n>: <one-line symptom>

**Status**: open | resolved
**Opened**: <date>, by planner session
**Context**: what triggered this -- the process-level snag, not a game/domain question.
**Why process, not domain**: one line justifying this isn't a DECISIONS.md-scope issue.
**Resolution** (MetaPlanner fills in): -> METAPLANNER.md#MP<n>, one-line summary.
```

## ESC1: subagents recurringly get stuck waiting for a Monitor notification that never arrives

**Status**: resolved
**Opened**: September 9, 2026, by planner session
**Context**: root-caused this session -- a spawned `Agent`-tool subagent is a bounded, single-shot
invocation; when it stops calling tools (even to say "waiting for notification"), the invocation
just ends, nothing self-resumes it. Only an explicit external `SendMessage` from the dispatching
session continues it. This recurred 7+ times across Explorer/Builder dispatches this session, each
time mitigated manually. The mechanism is understood but lives only in this conversation, not in
any file a future dispatching session would read cold.
**Why process, not domain**: about how subagent prompts are written and what behavior to expect
from them, not a game fact or a decision about how to play.
**Resolution**: -> `METAPLANNER.md#MP3`, documented as a hard "Subagent prompts" rule in
`AGENTS.md`: never write a subagent prompt that ends on a wait for an external notification.

## ESC4: `create_session` dispatch instructions don't mention the repo must be explicitly attached

**Status**: resolved
**Opened**: September 9, 2026, by planner session
**Context**: the first real MetaPlanner dispatch (session `session_019ZMSHF5XTHtJx5yWS66eUz`) was
created without `source_url`/`source_revision`, on the mistaken assumption that "inherits the
calling session's environment" (the tool's own description) meant the repo would be checked out
too. It wasn't -- the session landed in an empty container, correctly identified this as either a
misconfiguration or a prompt injection (it had no way to tell which), and rightly refused to act
rather than fabricate a report. A retry with `source_url`/`source_revision` set fixed it. `MP2`
(the entry documenting `create_session` dispatch) doesn't mention this requirement, so the mistake
is one bad copy-paste away from repeating.
**Why process, not domain**: purely about how a peer session gets correctly provisioned before
dispatch, not a game fact.
**Resolution**: -> `METAPLANNER.md#MP6`, stated the `source_url`/`source_revision` requirement
directly in `AGENTS.md`'s MetaPlanner "Trigger" bullet, and logged as an amendment to MP2.

## ESC2: no rule for what belongs in NEXT.md vs. AGENTS.md, so durable rules pile up in NEXT.md

**Status**: resolved
**Opened**: September 9, 2026, by planner session
**Context**: `NEXT.md`'s "Standing conventions" section holds durable engineering rules (e.g. "never
`run_in_background` inside an Explorer's own script") indistinguishable in permanence from rules
that live in `AGENTS.md`, mixed in with genuinely session-specific resumption state. The file has
already exceeded its own "one page, no more" limit and needed manual trimming twice this session,
with no structural fix -- likely because there's no rule saying which kind of content is allowed to
accumulate there.
**Why process, not domain**: purely about where documentation lives and what NEXT.md is scoped to
hold, not a game fact.
**Resolution**: -> `METAPLANNER.md#MP4`, added a classification test ("would this line still be
true once the current question is forgotten?") to both `NEXT.md`'s preamble and `AGENTS.md`'s
Process section; existing content left untouched, out of mandate.

## ESC3: no audit cadence for the verified-status provenance rule, already violated once in the field

**Status**: resolved
**Opened**: September 9, 2026, by planner session
**Context**: a cold review on September 9, 2026 found ~15 `world_topology`/`dialogues` entries
carrying `verified`/`ram_read_verified` at `verified_count: 1` (below the required bar).
`AGENTS.md` now states the rule and cites the incident, but nothing assigns responsibility or
cadence for catching a recurrence -- this instance was found because someone happened to check, not
because any process step audits for it.
**Why process, not domain**: a data-integrity/process gap in how facts get promoted to trusted
status, not a fact about the game itself.
**Resolution**: -> `METAPLANNER.md#MP5`, assigned as a standing checklist item of the existing
Reviewer role and cold-review cadence, in `AGENTS.md`'s role table and provenance rule.

## ESC5: multi-step Explorer helpers risk exceeding the foreground Bash timeout and auto-backgrounding

**Status**: open
**Opened**: September 10, 2026, by planner session
**Context**: an Explorer session this day found that a single `Navigator.move!` call took
13-30s wall-clock in this environment, and a `nudge_axis!`-style helper chaining ~20 such calls
exceeded a 300s foreground Bash timeout and got auto-backgrounded. `AGENTS.md`'s existing
"Subagent prompts: never end on a wait for a notification" rule (from `METAPLANNER.md#MP3`)
already covers a subagent that deliberately waits on a background task -- but this is a different,
easier-to-hit variant: a subagent that starts a long *foreground* multi-step helper call not
expecting it to background, has it silently backgrounded by a timeout, and only avoids the MP3
trap by luck/habit (this session's Explorer broke work into single/paired `move!` calls per
invocation instead, but nothing tells a future Explorer to do that). This recurred as a live risk,
not yet as an actual stuck-subagent incident -- catching it now, before it becomes one.
**Why process, not domain**: about how Explorer scripts should be structured to avoid a tooling
trap, not a game fact.
**Resolution**: -> `METAPLANNER.md#MP7`, added a "Subagent prompts: bound multi-step helper calls
under the foreground timeout" subsection to `AGENTS.md`: estimate a chained batch's worst case
against the timeout in effect before issuing it, split into sequential foreground calls when it
doesn't fit, and fall back to `MP3`'s poll-synchronously rule if a call backgrounds anyway.

## ESC6: NEXT.md still exceeds its one-page limit despite ESC2/MP4's classification test

**Status**: resolved
**Opened**: September 10, 2026, by planner session
**Context**: `NEXT.md` is at 239 lines. `MP4`'s classification test ("would this line still be
true once the current question is forgotten?") stops new content from being misfiled into
`NEXT.md` going forward, but does nothing about content that was already there and has since
become historical -- e.g. the house2_interior "Paradigm to question" section, marked RESOLVED
September 9, is still sitting in full in `NEXT.md` rather than having moved to
`docs/archive/SESSION_LOG.md` (which `AGENTS.md` already designates as the place for resolved
history). The file needs an archival pass, not just a going-forward filter.
**Why process, not domain**: purely about how `NEXT.md`'s own size is maintained over time, not a
game fact.
**Resolution**: -> `METAPLANNER.md#MP8`, added a standing "archive on resolution" rule to
`AGENTS.md` (a resolved `NEXT.md` section moves to `docs/archive/SESSION_LOG.md` in the same edit
that resolves it, dangling cross-references fixed, at most a one-line pointer left behind) and did
the house2_interior section itself as the one-time worked example.

## ESC7: planner status summaries conflate "closed/exhausted" with "paused pending a specific ask", drifting the owner's read of live state

**Status**: open
**Opened**: September 10, 2026, by planner session
**Context**: D12 (RAM writes to gameplay state are case-by-case, asked every time -- not a
standing tool) was ratified after the owner answered an `AskUserQuestion` about the Plage Coco
health blocker. The planner then folded that into a status report by grouping "Plage Coco (en
pause, D12)" under a "high-confidence leads are now exhausted" summary, alongside genuinely closed
threads (`shop_screen`'s door, the bush-contact test). The owner caught this immediately ("Pourquoi
tu as éliminé la plage ?") -- Plage Coco was never eliminated, D12 explicitly left a live path open
(ask per specific instance), and the planner never actually made that specific ask before writing
the summary. The underlying gap: nothing in `AGENTS.md`/the reporting convention distinguishes, in
writing, a thread that is genuinely closed (anti-patch budget spent, no further avenue identified)
from one that is paused behind a standing case-by-case gate the planner hasn't yet exercised for
this instance -- both ended up rendered identically ("en pause"/lumped into "épuisé") in the status
artifact and the chat summary, with no visual or textual distinction.
**Why process, not domain**: about how the planner represents thread status to the owner (report
structure/wording discipline), not a game fact or a navigation finding.
**Resolution** (MetaPlanner fills in): -> pending.

## ESC8: no standing process for narrative-clue cross-referencing, so a "puzzle" gets misread as unfinished "mapping"

**Status**: open
**Opened**: September 10, 2026, by planner session (owner-prompted introspection)
**Context**: several sessions spent real budget doing spatial/navigational exploration (sweeping
`riverside_ne_cove`/`riverside_south_river_room` for an item) after multiple dialogue clues
already pointed at a specific place ("la plage"/"Plage Coco", both starting_house NPCs plus the
game's own SELECT-map place name). The owner had to prompt the connection each time ("tu es sûr
que tu dois partir au sud...", "pourquoi tu as éliminé la plage") rather than the planner making
it proactively. The underlying gap: `dialogues` entries capture text with full provenance, but the
GAMEPLAY IMPLICATION of each line lives only in a free-text `note` field, never cross-referenced
against other clues or against newly-found spatial facts (a new room name, a new sign) as a
deliberate, repeatable step. There's no signal that distinguishes "this area needs more mapping"
from "this area is mapped, the answer is a clue I haven't connected yet" -- both look the same
(a stalled Explorer thread) from the planner's seat, and the planner has been defaulting to "map
more" when "re-read what's already known" was the right move at least twice tonight. Also worth
noting: some interactive objects in this game are confirmed to be invisible BG-tile/no-OAM
triggers (the `225/0` signpost, `house2_interior`'s telephone-adjacent floor trigger) -- an
Explorer scanning for OAM sprites or new rooms could walk right past the actual answer if it's an
untested `:a`-interaction at an already-visited position, not a new room at all.
**Why process, not domain**: about how the planner should recognize and route a narrative/clue
puzzle differently from an open-ended spatial mapping task -- a workflow gap, not a game fact
(no specific clue's *meaning* is asserted here, only that clue cross-referencing isn't a step).
**Resolution** (MetaPlanner fills in): -> pending. Planner's own proposal, offered as a starting
point, not a final answer: (1) a lightweight `quest_clues` registry section, one entry per
interpreted clue (source dialogue key, literal quote, current interpretation, status
unresolved/partial/resolved, linked location once found) -- separate from `dialogues`' raw
provenance, so clues are a trackable/queryable set, not buried prose; (2) a standing
cross-reference step, run whenever a new spatial fact (room, place name, sign) or new dialogue is
captured: does it resolve or refine an existing unresolved `quest_clues` entry? (3) Explorer
mandates should say explicitly whether the task is "spatial" (map an edge/room) or "clue-directed"
(test whether a specific already-known location/object matches a specific already-known clue),
the latter citing the clue up front rather than exploring blind; (4) fold a
"any `quest_clues` unresolved in an already-fully-mapped area?" check into the existing Reviewer
cold-review cadence (same shape as the provenance-bar audit `MP5` already assigned it).

**Addendum, September 12 2026 (planner session, owner-prompted "would a puzzle-solver proto
help?")**: built and ran a throwaway ~60-line Ruby prototype (`/tmp/koholint_proto/puzzle_solver.rb`,
not committed -- an Explorer-role spike, per the role table) to test proposal (2) above cheaply
before any real design investment. Two mechanisms tried against the current `ram_registry.json`:
(a) extract mid-sentence-capitalized words from `dialogues.*.text` (a French orthographic signal
for a game-defined proper term) and check whether the term also appears anywhere in
`room_labels`/`select_map_screen.note` ("grounded") or nowhere else ("ungrounded"); (b) cross-
reference every dialogue text's own words, case-insensitive, against the SELECT map's own known
place-name vocabulary (`select_map_screen.note`'s quoted names), to catch a place mentioned as an
ordinary lowercase common noun.

Result: (a) correctly flags "Loupe" and "Warp" as ungrounded (both already-known open threads,
nothing new) and correctly recognizes "Ramollo" as already grounded -- but is fundamentally blind
to exactly the case this ESC was opened over, because (b) shows why: `starting_house_npc_bench`/
`starting_house_npc_beds`'s "va sur *la plage*" is a lowercase common noun in French, never
capitalized by the game, so mechanism (a) would never have caught it. Mechanism (b) -- pure
substring cross-referencing against the SELECT map's own vocabulary, no capitalization assumption
-- DOES catch it: it independently reproduces the exact `starting_house` -> "Plage Coco" link the
owner had to point out three times this session, from data already on file, with no owner prompt
and no pre-trained game knowledge (only cross-referencing observed text against other observed
text, consistent with `AGENTS.md`'s "observed, never assumed"). First run also surfaced a real bug
in the prototype itself worth noting for any real implementation: naive "does this word appear
anywhere else in the registry" grounding falsely marked "Loupe" as grounded, because our own
English discussion notes (`world_topology.*.note`) repeat the word while discussing the very fact
that it's unresolved -- grounding must be checked against fields that record an actual placed/
observed fact (`room_labels`, `select_map_screen.note`), never against open-discussion prose, or
every debated term reads as resolved.

Bottom line for whoever resolves this ESC: proposal (2)'s cross-reference step is cheap and
tractable -- mechanism (b) alone, run once per new dialogue/place-name fact, would have shortened
this session's Plage Coco thread by at least the owner's first two corrections. Not yet evidence
that a full `quest_clues` registry (proposal 1) is warranted -- this was one prototype run against
a 19-entry dialogue corpus, re-deriving already-known findings, not yet tested on a genuinely fresh
unread clue. Planner did not commit the script or wire it into any live session (D13's "recur a
few times first" bar isn't met by a single validation run) -- leaving the resolution itself to
MetaPlanner, per this file's standing rule that Planner may append evidence but not close an entry.
