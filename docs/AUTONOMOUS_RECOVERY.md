# Autonomous Recovery

## Goal

A blocked game-level task becomes a bounded research problem before it becomes a human request.

Koholint already has persistent world state, checkpoints, deterministic navigation primitives, provenance, and Explorer/Builder roles. This design connects those pieces into a recoverable runtime seam.

## Design principle

A Claude context is disposable. Persistent state is the source of truth.

```text
Persistent World State
        |
        v
      Planner
     /   |    \
 Execute Explore Research
              |
          experiments
              |
          observations
              |
       Persistent state
```

MetaPlanner remains separate. It repairs workflow and coordination; it does not solve game blockers.

## Blocked task contract

An Executor can return a structured blocker before another reasoning context is created:

```json
{
  "status": "blocked",
  "goal": "find the sword",
  "location": "169/16",
  "checkpoint": "villager_screen",
  "attempts": 8,
  "blocker_type": "unknown_route",
  "observations": [],
  "failed_actions": [],
  "known_constraints": []
}
```

The blocker is persisted as part of a `ResearchTask`. `attempts` is not treated as evidence: experiments must represent distinct tests of hypotheses.

## Research task

A `ResearchTask` contains a bounded hypothesis and experiment ledger. Each hypothesis has an explicit status and evidence references. Each experiment records the checkpoint used, action, observation, outcome, cost, and optional state fingerprint.

Research produces observations; it does not silently promote observations into game facts. Promotion into the World Model or a Builder task is an explicit later step with the existing provenance rules.

## Research loop

1. Load the persisted blocker and a compact World Model projection.
2. Generate a small set of falsifiable hypotheses.
3. Select a bounded experiment.
4. Restore the experimental checkpoint.
5. Execute exactly that experiment through an existing tool/script boundary.
6. Record the observation and outcome.
7. Confirm, reject, or weaken the hypothesis.
8. Require replication/control evidence before treating a discovery as verified.
9. Promote reusable evidence to the World Model or Builder when justified.
10. Re-enter Planner with a fresh context.

The current implementation deliberately does not choose hypotheses or promote facts itself; it provides the durable seam those higher-level decisions use.

## Checkpoint isolation

The runner restores the supplied experimental checkpoint before every experiment. Durable progression is outside the runner's mutation contract.

```text
 durable state
      |
      +---- experimental checkpoint
                  |
             experiment N
                  |
             observation
                  |
             discard/restore
```

An experiment is not a durable game action merely because it succeeds in its scratch state.

## Context lifecycle

Each Planner/Research invocation receives a projection rather than the previous conversation:

- active goal and blocker;
- unresolved hypotheses;
- recent experiment outcomes;
- relevant World Model facts;
- available tools;
- remaining research budget.

The persisted `ResearchTask` is the handoff boundary. A fresh process can reload it without access to the previous LLM context.

## Routing

The Planner-level router has four modes:

- `execute`: the previous execution succeeded or a known route/tool remains appropriate;
- `explore`: discover unknown reachable state;
- `research`: execution is blocked and research budget remains;
- `escalate`: execution is blocked and the research budget is exhausted.

`escalate` means owner escalation for an unresolved game problem. A workflow/process failure remains a MetaPlanner escalation under `AGENTS.md`.

## Safety and loop bounds

Research is bounded by `max_experiments`. The task rejects duplicate `(hypothesis, action)` experiments so superficial retries cannot consume autonomy indefinitely. A caller must still supply a distinct checkpoint and experiment action for genuinely different tests.

RAM writes that bypass genuine gameplay remain subject to the existing D12 rule and are not enabled by this seam.

## Example

If `house2_interior` navigation fails:

```text
Execute
  -> blocked
  -> Research
       -> hypothesis: target requires sub-tile alignment
       -> restore checkpoint
       -> experiment: vary approach alignment
       -> observation
       -> replicate/control if needed
       -> promote route/evidence
       -> Builder task
  -> Execute again
```

This is the pattern already demonstrated manually during the house2 discovery; the runtime seam makes the recovery state durable and repeatable.

## Implemented seam

The first implementation provides:

- `Koholint::AutonomousRecovery::BlockedResult`;
- persisted `ResearchTask`, `Hypothesis`, and `Experiment` records;
- atomic JSON persistence through `Store`;
- compact fresh-context projection through `Context`;
- checkpoint-first `ExperimentRunner`;
- Planner routing through `Router`;
- deterministic tests covering persistence/reload, checkpoint restoration, duplicate protection, and budget exhaustion.

The seam deliberately does not yet invoke an LLM, mutate the World Model, or run expensive live exploration. The next integration step is to connect a real Planner blocked result to this persisted task and supply an existing checkpoint/tool executor.
