# Process Evidence

A lightweight record of evidence about how the Koholint workflow performs.

This is **not** a scorecard and is not a replacement for `NEXT.md`, `DECISIONS.md`, or
`METAPLANNER.md`. Its purpose is to let future cold sessions distinguish a one-off incident
from a recurring process failure and to evaluate whether workflow amendments actually helped.

## Session record

Record one entry per completed Planner, Explorer, Builder, Reviewer, or MetaPlanner session when
there is meaningful process evidence to preserve.

Use this shape:

```yaml
session: <stable session identifier>
role: Planner | Explorer | Builder | Reviewer | MetaPlanner
objective: <one-sentence intended outcome>
outcome: confirmed | partial | blocked | invalidated | no_change
new_facts: <integer>
attempts: <integer>
rework: false | true
rework_reason: <optional>
escalation: false | true
artifacts_changed:
  - <path>
duration_seconds: <optional number>
notes: <optional one sentence>
```

The fields are deliberately small. Prefer evidence that can be reconstructed from the session
and repository state over subjective productivity ratings.

## Interpretation rules

- `new_facts` counts durable, verified additions to project knowledge; it is not a count of tool
  calls or observations that remain uncertain.
- `rework` means materially repeating or correcting work because the workflow failed to preserve,
  communicate, or apply something it already knew.
- `escalation` means the session surfaced a process-level problem that belongs in
  `METAPLANNER_ESCALATIONS.md`.
- `duration_seconds` is optional because wall-clock time is environment-dependent. Do not use it
  alone to judge a session.
- A single bad session is an observation, not evidence that a policy is wrong.

## MetaPlanner review trigger

After enough comparable sessions exist to distinguish a pattern from an anecdote, MetaPlanner may
review the records for recurring process failures or successful amendments.

A proposed workflow change should state:

1. **Signal** — what repeated evidence was observed.
2. **Hypothesis** — what process property is believed to cause it.
3. **Intervention** — the smallest workflow change that tests the hypothesis.
4. **Evaluation window** — which subsequent sessions will provide evidence.
5. **Invalidation condition** — what result would show the intervention is ineffective or harmful.

Do not create a new policy merely because a single session was slow, awkward, or unsuccessful.

## Policy evaluation

When an amendment in `METAPLANNER.md` has an explicit evaluation window, later MetaPlanner reviews
should compare the relevant evidence before deciding whether to retain, revise, or invalidate it.

The goal is not to optimize for fewer tool calls. Optimize for reliable progress: durable knowledge,
correct artifacts, less avoidable rework, and fewer recurring coordination failures.
