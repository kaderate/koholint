# Autonomous Recovery

A blocked game-level task becomes a bounded research problem before it becomes a human request.

## Architecture

Koholint's existing MetaPlanner remains a process/workflow role. The **Planner is the game-playing LLM agent**: it owns the long-horizon game objective, decides what to do next, and routes blockers into Execute, Explore, or Research.

```text
MetaPlanner
  | workflow / coordination repair
  v
Planner (LLM agent)
  +-- Execute -> Worker
  +-- Explore -> Explorer
  +-- Research -> Investigator
  +-- process failure -> MetaPlanner
```

The Planner context is disposable. World Model, checkpoints, action history, and `ResearchTask` are the durable state that lets a fresh Planner context continue the same run.

## Contracts

`BlockedResult` captures goal, location, checkpoint, blocker type, attempts, failed actions, observations, and known constraints.

`ResearchTask` owns a bounded hypothesis/experiment ledger. Hypotheses have status and evidence. Experiments record checkpoint, action, observation, outcome, cost, and the durable state fingerprint observed after execution.

A supporting observation is evidence, not immediate proof: by default a hypothesis needs two distinct supporting experiments before it becomes `supported`. A refutation can mark a hypothesis `refuted` immediately. Duplicate `(hypothesis, action)` experiments are rejected so the support threshold requires independent actions.

Research produces observations; it does not silently promote observations into game facts. Promotion into the World Model or a Builder task remains an explicit step governed by existing provenance rules.

## Runtime seam

- `BlockedResult`: structured blocked execution result.
- `Store`: atomic JSON persistence and reload of research state, with validation on load/save.
- `Context`: bounded projection for a fresh Planner invocation.
- `ExperimentRunner`: restores an experimental checkpoint, enforces a frame budget, requires a durable fingerprint by default, rejects durable-state mutation, and verifies any executor-reported fingerprint against the post-experiment fingerprint.
- `ResearchTask#record_experiment!`: enforces the experiment budget and rejects duplicate `(hypothesis, action)` retries.
- `RecoveryCoordinator`: turns a blocked execution into a persisted research task, asks for one bounded experiment, executes it, records the observation, updates hypothesis evidence/status, and returns to execute/research/escalate.
- `Router`: maps successful execution to `execute`, an unexhausted blocker to `research`, and an exhausted blocker to `escalate`.

## Planner integration

There is deliberately no second Planner runtime. The existing Planner agent treats recovery as another branch in its normal session loop:

```text
Planner context
  -> bounded Execute / Explore
  -> BlockedResult
  -> persist ResearchTask
  -> fresh Planner context
  -> Research: hypothesis -> bounded experiment -> observation
  -> persist result
  -> Planner resumes with bounded persistent context
  -> Execute again, or escalate when research is exhausted
```

The recovery layer is a harness around successive Planner contexts, not a replacement for the Planner. The repository currently does not contain a concrete Planner/session runtime implementation to wire directly, so this branch makes the integration contract executable at the recovery seam without inventing a second agent runtime.

The existing Planner loop must supply the `BlockedResult`, persistent World Model facts/tools, checkpoint adapter, and executor; it then consumes the coordinator's `execute`, `research`, or `escalate` route. A fresh Planner invocation reconstructs its prompt from `Context.project` rather than carrying the previous LLM context forward.

## Safety

The recovery seam does not invoke an LLM by itself, mutate the World Model, or enable RAM writes. D12 remains in force. Experimental executors must honor the supplied frame budget and must not mutate durable progression. A checkpoint adapter without `durable_fingerprint` is rejected by default; callers may only relax that requirement when they explicitly accept the weaker isolation contract.

A successful scratch experiment is not automatically durable progression or a verified game fact. Research exhaustion is an owner escalation. Workflow/process failures remain MetaPlanner escalations under `AGENTS.md`.

## Fresh-context acceptance property

A persisted `ResearchTask` is written to disk and loaded by a separate Ruby process, so recovery state does not depend on the previous in-memory context. `Context.project` then applies fixed bounds to hypotheses, experiments, facts, and tools so the reset cannot simply recreate the original context-bloat problem.

The tests also exercise two independent supporting experiments before resolution, fingerprint mismatch/mutation rejection, duplicate protection, validation, coordinator orchestration, and budget exhaustion.

## Example

```text
Execute
  -> blocked
  -> persist ResearchTask
  -> fresh Planner context
       -> hypothesis
       -> bounded checkpoint-backed experiment #1
       -> observation: supports
       -> fresh Planner context
       -> bounded checkpoint-backed experiment #2
       -> observation: supports
       -> hypothesis supported
       -> Builder / World Model promotion
  -> Execute again
```
