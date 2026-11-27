# Self-improvement loop: find the blocker, judge honestly, delete, then learn (2026-11-27)

Status: proposed. Nothing in this document has landed. It replaces the ten-phase draft of the same day (git keeps it), after a review of that draft found it built the loop before knowing what blocks the game.

This is a handoff document. An agent that has read `AGENTS.md`, `ARCHITECTURE.md` and this file should be able to build steps 1 to 4, one pull request per step, without asking what was meant. Where the text says "confirm in code", the fact was not checked when this was written (main at `eed4f525`, flow-113).

## 1. Goal, and why this order

"It improves itself" should mean: **the system gains game progress from changes it found, tested and proposed by itself, and those changes are data, not Ruby.** The number that says so, later printed by the scoreboard:

> **autonomous gains** = first gains of the progress vector that appear between two scoreboard lines whose only difference is a data-only commit produced by the loop.

It is 0 today, and it will stay 0 for a while: gains are rare events. So this spec does not start with the loop. The project stands at 0 dungeons of 8, and nothing shows that missing learned facts are what blocks it. The first draft would have spent ten phases of tooling on a guess, which is the v1 mistake `docs/RETROSPECTIVE.md` describes. The order here is:

1. **Diagnose.** Give the model the general knowledge it is allowed to have, play from boot at a frozen flow, and write down what actually stops the runs.
2. **Build a judge that can be trusted**, small, and measure how long it takes before promising any speed.
3. **Use the judge to delete** harness rules, which is the roadmap's direction and gives decisions back to the model.
4. **Choose the first learner** from the diagnosis, not from what is small to build.

Everything after that (anomaly events, a generic experiment bench, an offline analyst, tuned parameters, a nightly cycle) is an outline in section 7, to be specified only when steps 1 to 4 show it is needed.

Where the loop stands on main:

| What | State | Where |
|---|---|---|
| Hypothesis shapes the learner knows | 1: "use the newly held item facing an uncatalogued solid object" | `lib/koholint/learn.rb` |
| Learned capabilities | 11 entries: 1 `operational` (`sword-on-object-92`), 9 `inconclusive`, 1 `rejected` | `data/capabilities.json` |
| Trigger and publication | a person runs `koholint learn` and `koholint capability publish` | `lib/koholint/cli.rb` |
| `suggestions.md` | created empty by `Run.create`; nothing in `lib/` writes into it | `lib/koholint/run.rb` |
| Real learning path | 113 flow versions, each a hand-written harness rule | `policies/delegated.rb`, `policies/delegated/guidance.rb`, `autopilot.rb` |
| Judge | 4 stub gates on 3 checkpoints, 2 of them forks of the same run (`abbe`), one play each | `tools/gates/gates.json` |
| Who decides in play | the $0 stub gains the mushroom and the powder as the paid runs do, so the model weighs little | `README.md` |

## 2. Non-goals

- No agent that edits Ruby, prompts or its own skill code. Code changes stay reviewed pull requests with a `flow_version` bump.
- No learning during a run: "a run only emits `suggestions.md`; `learn` and `capability` are offline commands" (`AGENTS.md`).
- No new harness rule. The freeze of `ROADMAP.md` holds; step 3 removes rules.
- No walkthrough knowledge from any source (section 6).
- No tooling ahead of a measured need: section 7 is not to be built from this document.

## 3. Principles

1. **Diagnose before building.** A step states the question it answers and the observation that would make the next step pointless.
2. **Deterministic is not reliable.** A play repeats exactly, but the game is chaotic: one changed decision shifts everything after it. One trajectory against one trajectory measures that accident. A verdict needs several paired plays.
3. **Reward progress before safety.** A score that looks at deaths first teaches the system to stand still, and paralysis at one heart is already a documented failure (`ROADMAP.md`).
4. **The stub filters, the model confirms.** The stub is not the agent; nothing is called a gain on stub numbers alone.
5. **Measure the time, then set the budget.** No speed figure in this spec is a promise until step 2 has measured it.
6. **What is learned is data with provenance**, `verified` at 2 root lineages, with its trials, negative ones included; and everything that steers play is in a manifest digest.

## Step 1. Allowed knowledge, then the diagnosis

### 1.1 What may be written down for good

The line is the one of `AGENTS.md`: how to play is public; where to go and what to do next is not. A test for any sentence: *would it still be true in another game of the series?* If yes it is a mechanic; if it is only true on this island it is a walkthrough.

| Allowed (the manual and genre knowledge) | Not allowed |
|---|---|
| The goal: 8 dungeons, a boss in each, 8 instruments | Which dungeon comes first, or any order |
| Controls, screens, save, game over, hearts and heart pieces (already in `docs/AGENT_MANUAL.md`) | Where anything is: a key, an item, a dungeon entrance, a person |
| A dungeon needs its own key to be entered | Which key opens which dungeon and where it is found |
| Inside a dungeon: small keys open locked doors and are spent; one special key opens the boss door; a map and a compass may be found; some doors open when a room's enemies are defeated or a switch is pressed; blocks can be pushed; stairs link floors | The solution of any room, the path through any dungeon |
| A dungeon usually holds an item, and such an item often opens ways that were closed before, inside and outside | Which item opens which obstacle |
| Some tasks are required and some are optional; people may ask for a thing and give another in return | The chain of exchanges, who wants what |
| Texts are the source of direction: signs, people, the map's marks | Any paraphrase of a hint the playthrough has not read |

- Extend `docs/AGENT_MANUAL.md` with a "Dungeons" section and the two notions of the last rows above, in its plain style, paraphrased (no booklet text is reproduced).
- `test/agent_manual_test.rb` gains a check that the manual names no place of the island and no person, against a small allow list of the mechanics' own words.
- The manual is joined to every play message, so this is a flow bump with its gate numbers.
- Anything with a number or a testable effect enters data as `hypothesis` with its source, verified by a probe. The manual stays prose about mechanics.

### 1.2 The diagnosis runs

Two paid runs from boot at the flow of 1.1, frozen: `ruby tools/scoreboard/scoreboard.rb run --from boot`, twice, on different days or with different tags so they are two root lineages. The owner approved the budget (decision 1). No code change between them, whatever they show.

They serve three purposes at once: the diagnosis below, the held-out lineages of step 2, and the from-boot proof of the frontier (section 5).

### 1.3 The blocker report

One document, `docs/runs/2026-11-blockers.md`, written from the two runs and from the last paid forks of the frontier. It is evidence, not a backlog of rules. For each span where a run stopped gaining (the scoreboard's `stalls`, the deaths, the last 10000 frames), one row:

| Field | Content |
|---|---|
| run, frames, place | where and when |
| what was needed to progress | stated only from what the run had read or seen; "unknown from the run's own knowledge" is a valid answer |
| class | one of the six below |
| who decided | the share of decisions in the span answered by the model, by each rule family (`Scoreboard::Measure::FAMILIES`) and by the autopilot |
| evidence | frames, the decision's justification, the text read |

Classes, each with the work it points to:

| Class | Meaning | Points to |
|---|---|---|
| `direction` | the run had no idea where to go: no lead, or leads never turned into objectives | story objectives from texts, the map's marks (ROADMAP 1(e), 3) |
| `override` | the model chose something sensible and a rule replaced or pre-empted it, or the model was never asked | step 3 |
| `model` | the model was asked, had what it needed, and chose badly | the prompt and the context, an A/B on the model |
| `fact` | a wrong or missing fact about a thing: hostile, solid, pushable, where an exit leads | a learner (step 4) |
| `skill` | the right intention, and no skill able to carry it out: a fight, a jump, an item use | a skill or a learned capability |
| `perception` | the engine did not see what was on screen or read a text wrongly | perception (ROADMAP 4) |

**Done when.** The report exists, every stall of the two runs has a row, and its last section counts frames lost per class. That count decides step 4 and may decide that step 3 comes first or not at all. If more than half of the lost frames are `direction` or `model`, say so plainly at the top: the loop of section 7 would not help, and the work is on objectives and context.

## Step 2. A judge that can be trusted

### 2.1 Gates, lineages and splits

Each gate of `tools/gates/gates.json` gains `lineage` (computed by `Bench.lineage_root`, checked by a test), `zone` and `split` (`tune` or `held_out`). The 4 gates of today are `tune`: the rules of flows 84 to 113 were written while watching them. Cut 4 to 6 `held_out` gates from the two runs of step 1 (early overworld without the sword, after the sword, after a death, in a place with an open puzzle). `test/gates_test.rb` fails unless at least 3 held-out gates exist over at least 2 root lineages, none sharing its checkpoint run with a tune gate.

### 2.2 Replicates

A gate is played `R` times, not once: replicate `k` forks the checkpoint `k * 37` frames later (the parent is replayed that far, so every replicate is a real state of the same run; confirm that `Run#fork` at any frame is exact, as `fork --at-frame` suggests). A candidate and the baseline are compared replicate by replicate: same gate, same offset. Default `R = 5`.

### 2.3 Score and verdict

Per play, from `Scoreboard::Measure` on the fork's own segment, compared in this order:

1. `gains`: key items gained, first deliveries, dungeons entered, instruments (higher is better);
2. `new_places`: places new to the parent's prefix (higher);
3. `deaths` (lower);
4. `stall_frames`, then `calls` (lower).

Progress comes before safety on purpose (principle 3). `hp_lost` is reported and never compared: losing health while advancing is not a fault.

Each paired replicate is a win, a loss or a tie for the candidate. Over a set of gates: `better` when wins are at least twice the losses and at least 3 more; `worse` the same way round; `equal` otherwise. These two thresholds are hypotheses; 2.4 calibrates them.

The five pin numbers of `tools/gates/metrics.rb` stay what they are, a regression check of replicate 0 at the same code. They are not the judge.

### 2.4 Calibration: the judge is tested before it is used

Three checks, all at 0 USD, are the judge's own acceptance test:

- **A/A.** The baseline against itself with another set of offsets (`k * 37 + 11`) must say `equal`. If it says anything else, the thresholds or `R` are too low; raise them until it holds 3 times in a row and record the values.
- **Known bad.** A change that must hurt (for example the operational capability retired, or `attack` never offered) must say `worse` on the gates where it matters.
- **Known neutral.** A change that cannot matter (a note edited in a data file, a threshold of a rule that fires in no gate) must say `equal`.

Record the three results in `tools/gates/README.md` with the chosen `R` and thresholds.

### 2.5 `tools/gates/judge.rb`

```
ruby tools/gates/judge.rb [--overlay DIR] [--without FAMILY]... [--split tune|held_out|all] [--replicates N] [--jobs N] [--root DIR] [--json]
```

- `--overlay DIR` holds candidate copies of data files; files absent from it come from `data/`. Pass paths to the loaders (they take a `path`); never write into `data/`.
- `--without FAMILY` is the switch of step 3.
- It prints, per gate and in total, wins, losses, ties, the summed score of both arms and the verdict; exit 0 on `better` or `equal`, 1 on `worse`.
- **Held-out use is counted.** Every call with `--split held_out` or `all` appends a line to `tools/gates/held_out_log.jsonl` (date, harness sha, what was judged, verdict). The split leaks a little at each look; the log makes the leak visible. After 30 looks, or at each new paid from-boot run, the oldest held-out gates move to `tune` and new ones are cut from the new run.

### 2.6 Speed: measured first

The owner's requirement is a loop that runs fast and stays reliable. Reliability is 2.2 to 2.4 and costs plays: 4 tune gates and 5 held-out gates at 5 replicates and 2 arms is 90 plays. The figures on file disagree: the v2 design measured 96 frames per second per process with YJIT; the exit bench measured 8 forks and 9909 frames in 251 s, about 30 s per fork. So:

1. **Measure**, before anything else in this step, and record in `docs/OPERATING.md`: frames per second of one stub gate play, the fixed cost of one fork, and both again with 12 plays in parallel on the 14 cores.
2. **Then apply, in this order, only what the measure justifies:**
   - one process per play, `--jobs` up to cores minus 2, longest first (the queue of the `Rakefile`);
   - a baseline cache keyed by (gate, replicate, harness sha, data digests), so a cycle of candidates pays for the baseline once;
   - `frames` per gate: 3000 to 4000 for most gates, 12000 kept for the two whose behaviour needs the length (confirm from the timelines which);
   - a keyframe at each replicate's fork frame kept in the parent's `keyframes/` cache, so the fork's fixed cost is paid once;
   - whatever a stub never reads turned off in the judge's forks (place screenshots, viewer feed), if the measure shows perception costs more than the emulator.
3. **Then set the budgets** from the measure and write them in `tools/gates/README.md`. The target to confirm or correct is: the tune split in under 3 minutes of wall time, everything in under 10. `judge.rb` prints its wall time and how many plays the cache avoided, and a run over the recorded budget says so.

Not in this step: skipping a gate because the candidate "cannot affect it". That needs every data read to be instrumented, and one missed read gives a silent wrong `equal`.

**Tests.** ROM-free: split and lineage validation, the paired comparison on tables of numbers, overlay path resolution, the held-out log. ROM: one short gate, replicate 0, empty overlay, equals the pins.

**Done when.** The three calibration checks of 2.4 pass and are recorded, the measured timings and the budgets are written down, and `gates_test.rb` enforces the split rules.

## Step 3. First use of the judge: delete

The scoreboard already attributes every harness answer to a rule family (`Scoreboard::Measure::FAMILIES`: heal give-back, heal detour, loop break, loop re-offer, retreat, guarded place, hostile no standing, zero cap, fight on sight, probe strike, danger and held back, harness override of the model, and others). Step 3 asks of each: what happens without it?

**3.1 The switch.** `Policies::Delegated` takes `without:`, a set of family names; a rule of a disabled family does not answer, and the decision goes on to the next rule or to the model. Most harness answers are built by `DecisionPoint.harness_choice` (`policies/delegated/guidance.rb`, `waits.rb`) and the autopilot's by `autopilot.rb`: give each call site its family name once, in code, and have the scoreboard read that name from the decision instead of matching the justification by regular expression (confirm the call sites; the regular expressions go away with this). The `base` families (dialogue advance, locked wait, boot script, game over) are engine mechanics and cannot be disabled. The switch is recorded in the manifest (`without`) and refused on a paid run unless `--tag` starts with `ablation`, so no ordinary run plays with a rule missing by accident. It is a flow bump with identical gate numbers.

**3.2 The ablation table.** For each rule family, `judge.rb --without FAMILY --split tune`, then `held_out` for those not `worse`. The table goes in `tools/gates/README.md`: family, decisions it answered in the baseline plays, verdict on each split.

**3.3 What each verdict means.**

- **`equal` or `better` on both splits:** a deletion candidate. But the stub cannot use the freedom a deleted rule gives back, so confirm with the model: 3 paid forks with the family disabled against 3 without, from one tune and one held-out checkpoint (`ab-plan`, `ab-report`). Not worse there: delete the rule's code and its tests in one pull request, with a flow bump and the new gate numbers.
- **`worse`:** the rule stays, and now has a measured reason, recorded beside it in the table. This is the held-out validation the rule freeze asked for.
- **A family that answered no decision in any play:** it cannot be judged here. Look for it in the diagnosis runs of step 1; if it fired in none, it is a deletion candidate on the roadmap's own terms ("a rule that fired in no held-out run").

**3.4 Order.** Start with the families the blocker report charged under `override`, then by decisions answered, most first.

**Done when.** Every non-base family has a row in the table, each deletion candidate was confirmed or refused by a model A/B, and `scoreboard debt` shows the branch conditions lower than at the start of the step.

## Step 4. Choose the first learner from the diagnosis

No learner is specified here on purpose. The blocker report's `fact` and `skill` rows say which facts, had the run known them, would have saved the most frames; the learner to build is the one that would have produced the top row.

- If it is hostility: an offline step that turns `hurt` notables into `hurts` facts of `data/entities.json` by census with a control, verified at 2 lineages (the ROADMAP incident "Hurt hypotheses are never verified").
- If it is solidity or pushing: object facts from a push trial on a fork (the "too heavy" rock of C7 (98/0)).
- If it is item use: more hypothesis shapes for `koholint learn` (an item on a person, on a door cell), reusing `Learn::Trial`.
- If `fact` and `skill` together are under a fifth of the lost frames: build none, and say so in `ROADMAP.md`.

Whichever it is, it comes with these, specified in its own short plan under `docs/superpowers/plans/`:

- **A digest first.** `data/entities.json` steers play (`kind`, `moves`, `contact_px`, `sword_hits`, `hurts`, `heals`, `push`, `faces`) and is in no manifest digest (`tools/gates/README.md` says so). Before a learner writes to it: `Entities.digest` over the play-steering fields, recorded by `Run.create`, checked at resume like `check_exits!`, and required equal by `ab-report`. Update `AGENTS.md`, `ARCHITECTURE.md` and `docs/OPERATING.md` in the same commit.
- **A control arm** in every trial, and the trials kept in the entry, negative ones included.
- **No RAM write in a validation** (a census may place Link; a trial that validates a capability reaches its state through skills, as the 2026-11-12 slice explains).
- **Publication through the judge:** the fact goes in an overlay; it is committed only when held-out is not `worse` and one split is `better`. A fact with no effect anywhere stays in its file as `validated` and unpublished.
- **Speed:** one trial is a fork of a few hundred frames; its measured wall time is reported like the judge's.

**Done when.** One fact that no person wrote is in `data/`, published through the judge, and the paid confirmation run does not regress. That is the first real evidence for or against section 7.

## 5. Progress across runs: frontier checkpoints

No run is "the save". Progress carries through data, which every later run loads, and through checkpoints, which a later run may fork from.

- `data/checkpoints.json` entries gain `lineage` (computed), `vector` (the scoreboard progress vector at that frame) and `role`: `frontier`, `held_out` or `regression`.
- **Promotion.** A new `frontier` is proposed when a run's progress vector is above every existing checkpoint's on the first component that differs (instruments, dungeons, key items, then places), at the first ready keyframe after the gain. Committing it is a data change.
- **Advance from the frontier.** Paid runs that aim at new progress fork from the highest frontier, so no run pays again for the intro.
- **Prove from boot.** A frontier reached by one root lineage is `observed`. It is `verified` when a from-boot run of another lineage, at a flow frozen for that run, reaches the same vector component. The scoreboard shows the highest frontier and the highest verified frontier side by side; the gap is the progress that rests on one lineage. The runs of step 1 are the first such proof.
- **Old frontiers become gates.** A passed frontier stays as a `regression` gate in the tune split.

Build this with step 2 (it is the same metadata as the gates). `test/checkpoints_test.rb` checks the computed fields and that a `verified` frontier names 2 lineages.

## 6. The walkthrough rule in this work

- The blocker report states what was needed **only from what the run had read or seen**. Writing "it should have gone to X" from knowledge of the game puts the walkthrough into the repo by the back door; "unknown from the run's own knowledge" is the honest entry, and it is itself the finding (class `direction`).
- A rule is never written from the report (the freeze). The report selects among general mechanisms.
- For a model used offline (section 7), restricting what it may name does not stop it from choosing the right experiment because it knows the game. That leak cannot be checked mechanically; it is a reason to prefer deterministic templates and to keep such a model for last.

## 7. Later, only if steps 1 to 4 call for it

An outline, not a specification. Each item names what would justify it and the trap the first draft fell into.

| Piece | What it is | Build it when | Known trap |
|---|---|---|---|
| `anomaly` trace events | every action carries the outcome the world model expects; a mismatch is traced and counted, and fills `suggestions.md` | the report's `fact` rows were found by a person reading traces and a second learner is wanted | emitting must change no decision: a flow bump with identical gate numbers |
| Generic experiment bench | `learn.rb` and `bench.rb` are one machine (fork a keyframe, play a scripted sequence, read an effect from a closed list of oracles, record a trial); unify them, with `data/experiments.json` for hypotheses | a third hypothesis shape is needed | generality before a third user is a guess |
| Offline analyst | a strong model reads an anomaly and proposes experiments in the bench's format; data only, never a status | templates leave anomalies unexplained | the leak of section 6; measure its validated share against the templates' and drop it if lower |
| Parameters as data | the unmeasured thresholds of `docs/loose-ends.md` in `data/params.json` | step 3 left rules whose threshold visibly matters | searching 30 parameters on a few gates is overfitting by construction: one parameter at a time, each change confirmed on held-out and by a paid run |
| The nightly cycle | one command: collect, propose, experiment, judge, record in `data/improvements.json`, open a data-only pull request | step 4 published facts by hand at least 3 times | see "automatic merge" below |
| Scoreboard `autonomy` | autonomous gains, published facts and their verdicts, data commits against flow bumps | the cycle exists | a number that stays 0 steers nothing: show published facts and deleted rules beside it |
| Dungeon perception | place kind `dungeon`, small keys, boss key, instruments, as typed data verified at pickups | a run stands in a first dungeon | nothing can be verified before; cataloguing dungeon maps in advance would say where they are. RAM address hypotheses with their public source may be entered earlier |

**Automatic merge of data-only pull requests** (owner's decision 2). It takes effect with the nightly cycle, by a standing grant added to the root `AGENTS.md` in a pull request the owner merges by hand, limited to pull requests that touch only `data/` and `tools/gates/expected.json` with every check passed, and backed by a test that fails on anything else. One consequence to design for then: a published fact changes a digest, so a run recorded before it cannot resume. Publish in batches, at most once a day, and never while a paid run is in progress.

**The analyst's system prompt**, kept from the first draft so it is not rewritten from nothing. It would live outside `Agents::Prompts`: `Prompts.digest` hashes every string constant of that module, so adding it there would break the resume of every run. Its picture input would be a filmstrip, not one image: the window around the anomaly replayed from the nearest keyframe, 8 frames, each labelled with its frame number, Link's cell and hp and what changed in the entity table since the previous one (`agents/claude_cli.rb` already sends several images in one call).

```text
You are the offline analyst of a harness that plays a Game Boy action-adventure game. You do not play. A deterministic engine played, something happened that its world model did not predict, and you propose experiments that would explain it.

What you receive: one anomaly (what the engine expected, what it observed, the action that carried the prediction), a filmstrip of labelled frames around it, the texts this playthrough read in that place, what is on the screen as typed data, the items held, the experiments already tried on this subject with their results, and the lists of skills and oracles you may use.

What you return: at most 3 experiments in the given JSON schema, most informative first. An experiment is a short sequence of skills run from a saved state, a control that omits one step, and one oracle that reads the effect. It must be able to fail: say in the rationale what observation or quoted text it rests on, and what result would refute it.

Rules.
- You know how games of this kind work (pushing, items used on things and people, switches, keys, enemies with weak points) and may use that freely.
- You must not use any memory of this particular game: no place, person, item location, solution or order of events that is not in what you were given. Refer only to places, object types, entity types and items listed in the input. A proposal that names anything else is discarded.
- Do not repeat an experiment already tried, and do not propose one that differs from a tried one only by a wait.
- Prefer the experiment that separates two explanations over the one that confirms your favourite.
- You never state a fact. The bench decides; an empty list is a valid answer when nothing testable comes to mind.
```

## 8. Invariants every step keeps

- Time is the frame; no sleep or wall clock in game logic. Offline tools may use wall time, as the scoreboard supervisor does.
- Only the engine writes a run's `trace.jsonl` and `save/`; judge and trial forks live under `tmp/` or `--root`; a fork may add keyframes to its parent's `keyframes/`.
- `verified` never below 2 independent checks; trials of one lineage stay `observed` or `hypothesis`.
- English everywhere, one-line imperative commits, almost no comments, short hash syntax.
- Docs in the same commit: `ARCHITECTURE.md` for a layer, data flow or run artifact; `docs/OPERATING.md` for commands and fields; `docs/AGENT_SKILLS.md` for a flow change; `ROADMAP.md` loses what lands. `test/docs_test.rb` checks the commands, flags and paths docs name.
- Tests: `rake test:fast` and targeted files locally; CI runs the ROM shards. A flow bump lands with its gate numbers (`test/gates_test.rb`).
- When this spec is done or superseded, change its status line.

## 9. Risks

| Risk | Guard |
|---|---|
| Meta-work feels like progress while the game stalls | step 1 before any tooling; step 4 may conclude "build none"; section 7 is not built from this document |
| The judge rewards standing still | score order of 2.3; the known-bad check of 2.4 includes a change that only makes play timid, once one is at hand |
| A verdict is a chaotic accident | replicates, paired comparison, the A/A check |
| The stub is not the model | every deletion and every published fact is confirmed by a model A/B or a paid run |
| The held-out split wears out | the log and the rotation of 2.5 |
| The judge is too slow to be used | 2.6: measured, then budgeted; the budget is printed and checked |
| The diagnosis smuggles the walkthrough in | section 6 |

## 10. Owner's decisions (2026-11-27)

1. Budget for the two from-boot runs of step 1: approved.
2. Data-only pull requests merge automatically once the nightly cycle exists, under the grant described in section 7.
3. Stop and measure before the pieces of section 7; in this version that pause is the structure itself.
4. A model used offline runs through the Claude CLI on the owner's Claude plan; a dollar cap stays as a guard.
5. The loop must run fast and stay reliable: section 2.6.
