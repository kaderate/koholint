# Autonomous Recovery

## Goal

A blocked exploration task must become a bounded research problem before it becomes a human request.

Koholint already has persistent world state, checkpoints, deterministic navigation primitives, provenance, and Explorer/Builder roles. This design connects those pieces into a self-recovering loop.

## Design principle

Do not make Claude's context the system's memory. A Claude context is disposable. Persistent state is the source of truth.

```text
Persistent World State
        |
        v
    Controller
     /  |  \
 Explore Research Execute
          |
       experiments
          |
          v
    Observation
          |
          v
 Persistent World State
```

## Controller vs. Meta Planner

Avoid a mandatory Meta Planner -> Planner -> Worker hierarchy.

The controller should select the smallest useful mode for the current state:

- `execute`: known route/tool can achieve the goal;
- `explore`: discover reachable unknown world state;
- `research`: current plan is blocked and the cause is uncertain;
- `escalate`: the research budget is exhausted or human authorization is required.

A second planner is justified only when there is evidence that the controller cannot make this choice reliably. Hierarchy should be earned by demonstrated need, not added pre-emptively.

## Blocked task contract

An Executor must be able to return a structured blocked result:

```json
{
  "status": "blocked",
  "goal": "find the sword",
  "location": "169/16",
  "checkpoint": "villager_screen",
  "attempts": 8,
  "observations": [],
  "hypotheses": [],
  "suggested_research": []
}
```

The blocked result is persisted before any new reasoning context is created.

## Research loop

A Research task has a bounded budget and a hypothesis ledger.

1. Load the blocked task and relevant World Model projection.
2. Generate a small set of falsifiable hypotheses.
3. Rank experiments by expected information gain / cost.
4. Restore an experimental checkpoint.
5. Run one experiment using existing tools or a temporary script.
6. Record observation and outcome.
7. Confirm, reject, or weaken the hypothesis.
8. Promote reusable discoveries into the World Model or a Builder task.
9. Re-enter the Controller with a fresh compact context.

Experiments must not silently modify durable progression. The existing D12 rule remains in force for RAM writes that could bypass genuine game obstacles.

## Context lifecycle

Each LLM invocation receives a projection, not the complete history:

- current room/state;
- active goal;
- relevant World Model facts;
- unresolved hypotheses;
- recent experiment outcomes;
- available tools;
- explicit constraints and budget.

After a decision or research iteration, the context may be discarded. Persistent state carries the run forward.

## Example

If `house2_interior` navigation fails:

```text
Execute
  -> blocked
  -> Research
       -> hypothesis: target requires sub-tile alignment
       -> restore checkpoint
       -> experiment: vary approach alignment
       -> success
       -> record route/evidence
       -> Builder promotes route into Navigator primitive
  -> Execute again
```

This is the pattern already demonstrated manually during the house2 discovery; this feature makes the recovery loop explicit and repeatable.

## Autonomy boundary

The system should stop and notify the owner only for:

- destructive or irreversible progression changes;
- actions explicitly requiring owner authorization;
- exhausted research budget;
- contradictory evidence that cannot be resolved automatically;
- infrastructure failures rather than game-state uncertainty.

A normal game blocker is not, by itself, a reason to ask the owner.

## Initial implementation scope

This PR should initially implement the contracts and orchestration seam, not a new general-purpose Meta Planner:

1. `BlockedResult` structured result.
2. `ResearchTask` persisted representation.
3. hypothesis/experiment records.
4. checkpoint-backed experiment runner.
5. compact context builder for controller/research invocations.
6. Controller routing between execute/research/escalate.
7. tests with deterministic fake experiments.

The first real acceptance test should be a synthetic blocker that discovers a known fact without human input. Only then should the loop be connected to expensive live exploration.