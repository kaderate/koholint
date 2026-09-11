# Autonomous Recovery

A blocked game-level task becomes a bounded research problem before it becomes a human request.

## Architecture

Koholint's existing MetaPlanner remains a process/workflow role. The **Planner is Claude Code itself**: the game-playing agent driving the repository, owning the long-horizon game objective, deciding what to do next, and routing blockers into Execute, Explore, or Research.

```text
MetaPlanner
  | workflow / coordination repair
  v
Claude Code = Planner / game agent
  +-- Execute -> Worker / deterministic scripts
  +-- Explore -> Explorer
  +-- Research -> bounded investigation
  +-- process failure -> MetaPlanner
```

There is intentionally no Ruby Planner runtime and no second LLM runtime to wire. The Ruby recovery layer is a deterministic persistence and safety seam that Claude Code uses between sessions.

The Claude conversation context is disposable. The durable state is the contract that survives it: World Model, `NEXT.md`, `DECISIONS.md`, checkpoints, action history, and the persisted `ResearchTask`.

## Contracts

`BlockedResult` captures goal, location, checkpoint, blocker type, attempts, failed actions, observations, and known constraints.

`ResearchTask` owns a bounded hypothesis/experiment ledger. Hypotheses have status and evidence. Experiments record checkpoint, action, observation, outcome, cost, and the durable state fingerprint observed after execution.

A supporting observation is evidence, not immediate proof: by default a hypothesis needs two distinct supporting experiments before it becomes `supported`. A refutation can mark a hypothesis `refuted` immediately. Duplicate `(hypothesis, action)` experiments are rejected so the support threshold requires independent actions.

Research produces observations; it does not silently promote observations into game facts. Promotion into the World Model or a Builder task remains an explicit step governed by existing provenance rules.

## Ruby safety seam

- `BlockedResult`: structured blocked execution result.
- `Store`: atomic JSON persistence and reload of research state, with validation on load/save.
- `Context`: bounded projection for a fresh Claude invocation.
- `ExperimentRunner`: restores an experimental checkpoint, enforces a frame budget, requires a durable fingerprint by default, rejects durable-state mutation, and verifies any executor-reported fingerprint against the post-experiment fingerprint.
- `ResearchTask#record_experiment!`: enforces the experiment budget and rejects duplicate `(hypothesis, action)` retries.
- `RecoveryCoordinator`: turns a blocked execution into a persisted research task, asks for one bounded experiment, executes it, records the observation, updates hypothesis evidence/status, and returns to execute/research/escalate.
- `Router`: maps successful execution to `execute`, an unexhausted blocker to `research`, and an exhausted blocker to `escalate`.

These classes do **not** create, resume, or replace a Claude session. They make the state handed from one Claude context to the next explicit and safe.

## Claude context handoff protocol

A context reset is a normal control-flow operation, not an emergency reserved for hitting the token limit. Claude Code should use a fresh context when a bounded game goal is blocked, when a research experiment needs a clean observer, when the current context has accumulated stale/redundant history, or when the session reaches its agreed turn/time budget.

### 1. Before leaving the current context

When Execute or Explore is genuinely blocked:

1. Stop retrying the same action.
2. Write a structured `BlockedResult` with the current checkpoint and observed blocker.
3. Create or update the durable `ResearchTask`.
4. Persist the task before ending the context.
5. Record the original game goal so research remains subordinate to it.
6. Do **not** dump the whole conversation into the durable state. Persist facts, hypotheses, experiments, checkpoints, and concise failure observations only.

If the task is not blocked but the context is simply getting stale or large, update `NEXT.md` with the bounded session report and start the next context from durable state rather than carrying the transcript forward.

### 2. Start the next Claude context cold

The new Claude Code session must assume that it has **no access to the previous conversation**. Its first reads are:

1. `AGENTS.md`
2. `NEXT.md`
3. `DECISIONS.md`
4. the active `ResearchTask` store, when one exists
5. the World Model / relevant registry data
6. the checkpoint metadata needed to reproduce the blocked state
7. recent action history only as needed to understand the bounded failure

It must not ask the previous context what happened. The durable artifacts are the handoff.

### 3. Reconstruct only the bounded working context

The fresh session should use `Context.project` (or an equivalent bounded projection) to reconstruct the research problem. Keep hypotheses, recent experiments, relevant World Model facts, and available tools bounded. Do not rehydrate the old transcript merely because it exists.

The first question in the fresh context is: **what is the smallest falsifiable experiment that can distinguish the leading hypotheses without mutating durable progression?**

### 4. Run one bounded experiment

The fresh session chooses one hypothesis and one action, restores the checkpoint, and runs the experiment through the recovery seam. The experiment must stay within the frame budget and must leave durable progression unchanged. The runner verifies the durable fingerprint before and after execution.

The session records the observation and outcome immediately. It does not rely on remembering the result for the next context.

### 5. Continue through another fresh context when useful

After an experiment, the session may update the `ResearchTask` and start another fresh context rather than growing one immortal research conversation. This is especially important when the task requires multiple independent experiments.

Only after the evidence threshold is met should a hypothesis become `supported`. Once research resolves the blocker, Claude Code returns to the original game goal and resumes Execute. If the research budget is exhausted without resolution, it escalates to the owner rather than inventing more retries.

### 6. Separate process escalation from game escalation

A **game/domain blocker** follows the ResearchTask path above.

A **workflow/process blocker** — for example, a rule in `AGENTS.md` that cannot handle a recurring case — goes to the existing MetaPlanner flow and `METAPLANNER_ESCALATIONS.md`. MetaPlanner does not decide where the sword is, mutate the World Model, or choose game strategy.

## Fresh-context invariant

The recovery loop is successful only if the next Claude session can resume the game without the previous chat transcript. In compact form:

```text
blocked
  -> BlockedResult
  -> persist ResearchTask
  -> end / reset Claude context
  -> cold Claude session reads durable state
  -> choose hypothesis
  -> bounded checkpoint-backed experiment
  -> persist observation
  -> reset again if more evidence is needed
  -> hypothesis supported / refuted / exhausted
  -> resume original game goal
```

This is the key inter-context memory mechanism: **the memory is external to Claude's context**. The model does not need to remain alive for hundreds of hours; it needs a small, trustworthy durable state that every new context can reconstruct.

## Safety

The recovery seam does not invoke an LLM by itself, mutate the World Model, or enable RAM writes. D12 remains in force. Experimental executors must honor the supplied frame budget and must not mutate durable progression. A checkpoint adapter without `durable_fingerprint` is rejected by default; callers may only relax that requirement when they explicitly accept the weaker isolation contract.

A successful scratch experiment is not automatically durable progression or a verified game fact. Research exhaustion is an owner escalation. Workflow/process failures remain MetaPlanner escalations under `AGENTS.md`.

## Acceptance property

A persisted `ResearchTask` is written to disk and loaded by a separate Ruby process, so recovery state does not depend on the previous in-memory context. `Context.project` then applies fixed bounds to hypotheses, experiments, facts, and tools so a fresh session cannot simply recreate the original context-bloat problem.

The tests exercise two independent supporting experiments before resolution, fingerprint mismatch/mutation rejection, duplicate protection, validation, coordinator orchestration, and budget exhaustion.

## Example

```text
Claude Execute
  -> blocked
  -> persist ResearchTask
  -> end context

New Claude context
  -> read AGENTS / NEXT / DECISIONS / World Model / ResearchTask
  -> hypothesis A
  -> bounded experiment #1
  -> observation: supports
  -> persist
  -> end context

New Claude context
  -> read durable state
  -> independent experiment #2
  -> observation: supports
  -> hypothesis supported
  -> promote verified result through existing provenance rules
  -> resume original Execute goal
```
