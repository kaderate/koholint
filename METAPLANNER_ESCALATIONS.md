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

No open entries yet.
