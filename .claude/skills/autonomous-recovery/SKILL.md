# Autonomous Recovery

You are the Planner and game-playing agent for Koholint. There is no separate Planner runtime. Use this skill to turn a blocked game objective into a bounded research loop while keeping the conversational context disposable.

## Core rule

The repository is the durable memory; the Claude conversation is working memory.

Never keep a large conversational history alive merely because it contains useful game knowledge. Persist useful knowledge first, then start the next context from the durable artifacts.

## When to enter recovery

Enter recovery when a bounded game objective is genuinely blocked, not merely when an action failed once.

A blocker is genuine when:

- the current deterministic/executor strategy has reached its declared attempt boundary;
- the same action is no longer producing new information; or
- continuing would require guessing, brute force, or unbounded exploration.

Do not use recovery to bypass an ordinary transient execution failure.

## Recovery protocol

### 1. Capture the blocker

Produce a `BlockedResult` containing at least:

- the original goal;
- current location;
- a usable checkpoint;
- attempts;
- blocker type;
- observations;
- failed actions;
- known constraints.

Do not replace the original goal with the research problem.

### 2. Persist the research task

Create or load the durable `ResearchTask` using the AutonomousRecovery Ruby layer.

The task is the handoff between Claude contexts. It must contain the hypotheses, bounded experiment budget, and experiment ledger. Do not rely on the current conversation to carry any of this state forward.

### 3. Form falsifiable hypotheses

Write concrete hypotheses that can be distinguished by an experiment.

Bad:

> Maybe there is something interesting here.

Good:

> The blocked transition is caused by an interaction flag set by object X; interacting with X from checkpoint C should change observation Y.

Prefer a small number of competing hypotheses over one broad theory.

### 4. Run one bounded experiment

Use a checkpoint-backed experiment through the Ruby recovery layer.

The experiment must:

- start from the recorded checkpoint;
- have an explicit frame/action budget;
- have a clear expected observation;
- avoid durable progression mutation;
- record its outcome and observation.

Do not modify game state directly to make the hypothesis true. D12 still applies.

Do not repeat an identical `(hypothesis, action)` experiment. Let the Ruby layer reject duplicates and budget violations.

### 5. Treat evidence conservatively

One supporting observation is evidence, not proof. By default, a hypothesis needs two independent supporting experiments before being marked `supported`.

A refuting observation may mark a hypothesis `refuted` immediately.

Only after the research result satisfies the evidence threshold should the Planner consider promoting the result into the World Model or a Builder task, using the existing provenance rules.

### 6. Persist before changing context

Before ending a context, ensure the durable state contains:

- the ResearchTask;
- the latest experiment result;
- the checkpoint reference;
- any newly verified registry/World Model facts;
- the original game goal and its current status;
- the next research action, if one remains.

The next context must be able to continue without reading the previous conversation.

## Context rotation

Do not wait for the platform to force a context limit.

Rotate the Claude context when:

- a blocked objective has produced its durable ResearchTask;
- another independent research step is required;
- the working context is accumulating stale/redundant exploration history; or
- the current bounded session has reached its declared context/turn budget.

A context rotation is successful only if the next context can reconstruct the task from the repository.

## Fresh-context startup

At the beginning of a fresh Koholint context:

1. Read `AGENTS.md`.
2. Read `NEXT.md`.
3. Read `DECISIONS.md`.
4. Inspect the active `ResearchTask`, if any.
5. Inspect the relevant World Model / RAM registry data.
6. Inspect the referenced checkpoint and recent action history when needed.
7. Decide the next bounded action from durable state only.

Do not assume that anything said in the previous Claude conversation is still available or correct.

If an active ResearchTask exists, recovery has priority over unrelated new exploration until the task is resolved, refuted, or explicitly escalated.

## Returning to the game objective

Research is subordinate to the original game goal.

When a hypothesis is sufficiently supported:

1. promote only the facts justified by the evidence and provenance rules;
2. update the World Model/registry or create the appropriate Builder task;
3. mark the ResearchTask resolved;
4. return to the original blocked game objective;
5. do not keep researching the same blocker without a new falsifiable question.

If the research budget is exhausted without resolution, stop guessing and escalate. Do not silently turn exhausted research into unbounded exploration.

## MetaPlanner boundary

Escalate to MetaPlanner only for a process/workflow problem: a broken convention, coordination rule, handoff rule, or other issue with how Koholint operates.

A game-domain blocker is Planner recovery work, not a MetaPlanner problem.

## Ruby glue

Use `lib/autonomous_recovery.rb` as the deterministic enforcement layer. The Ruby layer owns:

- `BlockedResult` structure;
- `ResearchTask` persistence and validation;
- hypothesis/experiment budgets and duplicate rejection;
- checkpoint restoration;
- bounded experiment execution;
- durable-state fingerprint protection;
- evidence bookkeeping.

The skill owns the agent behavior: when to invoke those primitives, what to research, when to rotate context, and when to resume the original objective.

Do not implement a second Planner runtime in Ruby.

## Session completion

End every recovery step with a durable result, not a narrative-only conclusion:

```text
Question: ...
Answer: confirmed / refuted / inconclusive
ResearchTask: ...
Experiment: ...
Evidence: ...
Original goal: ...
Next action: ...
What NOT to redo: ...
```
