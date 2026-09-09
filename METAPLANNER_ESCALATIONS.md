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

**Status**: open
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
**Resolution** (MetaPlanner fills in):

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
