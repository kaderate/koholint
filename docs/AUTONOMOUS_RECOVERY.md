# Autonomous Recovery

A blocked game-level task becomes a bounded research problem before it becomes a human request.

## Architecture

Koholint's existing MetaPlanner remains a process/workflow role. Game recovery lives at Planner level:

```text
Persistent World State
        |
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

A Claude context is disposable. `ResearchTask` is the durable handoff between contexts.

## Contracts

`BlockedResult` captures goal, location, checkpoint, blocker type, attempts, failed actions, observations, and known constraints.

`ResearchTask` owns a bounded hypothesis/experiment ledger. Hypotheses have status and evidence. Experiments record checkpoint, action, observation, outcome, cost, and optional state fingerprint.

Research produces observations; it does not silently promote observations into game facts. Promotion into the World Model or a Builder task remains an explicit step governed by existing provenance rules.

## Runtime seam

- `BlockedResult`: structured blocked execution result.
- `Store`: atomic JSON persistence and reload of research state, with validation on load/save.
- `Context`: bounded projection for a fresh Planner/Research invocation.
- `ExperimentRunner`: restores an experimental checkpoint, enforces a frame budget, and rejects detected durable-state mutation when the checkpoint adapter exposes a durable fingerprint.
- `ResearchTask#record_experiment!`: enforces the experiment budget and rejects duplicate `(hypothesis, action)` retries.
- `RecoveryCoordinator`: turns a blocked execution into a persisted research task, asks a bounded researcher for one experiment, executes it, records the observation, updates hypothesis status, and returns to execute or escalates when exhausted.
- `Router`: maps successful execution to `execute`, an unexhausted blocker to `research`, and an exhausted blocker to `escalate`.

## Safety

The recovery seam does not invoke an LLM by itself, mutate the World Model, or enable RAM writes. D12 remains in force. Experimental executors must honor the supplied frame budget and must not mutate durable progression; adapters that expose a durable fingerprint are checked after each experiment.

A successful scratch experiment is not automatically durable progression or a verified game fact. Research exhaustion is an owner escalation. Workflow/process failures remain MetaPlanner escalations under `AGENTS.md`.

## Fresh-context acceptance property

A persisted `ResearchTask` is written to disk and loaded by a separate Ruby process, so the recovery state does not depend on the previous in-memory context. `Context.project` then applies fixed bounds to hypotheses, experiments, facts, and tools so the reset cannot simply recreate the original context-bloat problem.

The deterministic test suite covers fresh-process persistence, bounded execution, durable-state mutation detection, duplicate protection, validation, coordinator orchestration, and budget exhaustion. The remaining integration is to connect a real Planner blocked result to this seam and supply the existing checkpoint/tool executor.

## Example

```text
Execute
  -> blocked
  -> persist ResearchTask
  -> fresh Research context
       -> hypothesis
       -> bounded checkpoint-backed experiment
       -> observation
       -> supported/refuted hypothesis
       -> Builder / World Model promotion
  -> Execute again
```
