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

## Contracts

`BlockedResult` captures the goal, location, checkpoint, blocker type, attempts, failed actions, observations, and known constraints. It is persisted before another reasoning context is created.

`ResearchTask` owns a bounded hypothesis/experiment ledger. Hypotheses have status and evidence. Experiments record checkpoint, action, observation, outcome, cost, and optional state fingerprint.

Research produces observations; it does not silently promote observations into game facts. Promotion into the World Model or a Builder task remains an explicit step governed by existing provenance rules.

## Research loop

1. Load the persisted blocker and a compact World Model projection.
2. Generate a small set of falsifiable hypotheses.
3. Select one bounded experiment.
4. Restore its experimental checkpoint.
5. Execute the experiment through an existing tool/script boundary.
6. Record observation and outcome.
7. Confirm, reject, or weaken the hypothesis.
8. Replicate/control before treating a discovery as verified.
9. Promote reusable evidence when justified.
10. Re-enter Planner with a fresh context.

## Isolation and bounds

The runner restores the supplied checkpoint before every experiment. Durable progression is outside its mutation contract. Research is bounded by `max_experiments`, and duplicate `(hypothesis, action)` experiments are rejected so superficial retries cannot consume autonomy indefinitely.

RAM writes that bypass genuine gameplay remain subject to the existing D12 rule and are not enabled by this seam.

## Context lifecycle

Each Planner/Research invocation receives a projection rather than the previous conversation: active goal/blocker, unresolved hypotheses, recent experiment outcomes, relevant World Model facts, available tools, and remaining budget.

The persisted `ResearchTask` is the handoff boundary. A fresh process can reload it without access to the previous LLM context.

## Routing

- `execute`: known execution path succeeds/remains appropriate;
- `explore`: discover unknown reachable state;
- `research`: execution is blocked and research budget remains;
- `escalate`: execution is blocked and research budget is exhausted.

Game-problem `escalate` means owner escalation. Workflow/process failures continue to use MetaPlanner under `AGENTS.md`.

## Implemented seam

The first implementation provides `BlockedResult`, persisted `ResearchTask`/`Hypothesis`/`Experiment`, atomic JSON `Store`, compact `Context`, checkpoint-first `ExperimentRunner`, and Planner-level `Router`. Deterministic tests cover persistence/reload, checkpoint restoration, duplicate protection, and budget exhaustion.

The seam deliberately does not yet invoke an LLM, mutate the World Model, or run expensive live exploration. The next integration step is to connect a real Planner blocked result to this task and supply an existing checkpoint/tool executor.
