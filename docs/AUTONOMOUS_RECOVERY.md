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
- `Store`: atomic JSON persistence and reload of research state.
- `Context`: compact projection for a fresh Planner/Research invocation.
- `ExperimentRunner`: restores an experimental checkpoint before executing a bounded experiment.
- `ResearchTask#record_experiment!`: enforces the experiment budget and rejects duplicate `(hypothesis, action)` retries.
- `Router`: maps successful execution to `execute`, an unexhausted blocker to `research`, and an exhausted blocker to `escalate`.

## Safety

The seam does not invoke an LLM, mutate the World Model, or enable RAM writes. D12 remains in force. A successful scratch experiment is not automatically durable progression or a verified game fact.

Research exhaustion is an owner escalation. Workflow/process failures remain MetaPlanner escalations under `AGENTS.md`.

## Fresh-context acceptance property

A persisted `ResearchTask` can be loaded independently of the previous conversation and projected into a compact context containing the goal, blocker, unresolved hypotheses, recent experiments, relevant facts/tools, and remaining budget. This is the mechanism that makes LLM context disposable rather than authoritative.

The deterministic test suite covers persistence/reload, checkpoint restoration, duplicate protection, and budget exhaustion. The next integration is to connect a real Planner blocked result to this seam and supply the existing checkpoint/tool executor.

## Example

```text
Execute
  -> blocked
  -> persist ResearchTask
  -> fresh Research context
       -> hypothesis
       -> checkpoint-backed experiment
       -> observation
       -> replicate/control
       -> Builder / World Model promotion
  -> Execute again
```
