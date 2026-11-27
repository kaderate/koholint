# Self-improvement loop: find the blocker, judge honestly, delete, then learn (2026-11-27)

Status: proposed. Step 1 is done below as a blocker report from existing runs; steps 2 and 3 are to build; step 4 and section 7 are parked. The owner paused new flows on 2026-11-27 pending this spec.

This is a handoff document. An agent that has read `AGENTS.md`, `ARCHITECTURE.md` and this file should be able to build steps 2 and 3, one pull request each, without asking what was meant. Where the text says "confirm in code", the fact was not checked when this was written (main at `5e0a7ded`, flow-116). Every figure comes from a run or a pull request; runs are named by their id suffix and live under `~/.capy/work/runs/` on the owner's Mac.

## Where this stands

| What | State | Evidence |
|---|---|---|
| flow-112 (#119) | deletes the one-heart autopilot hold | motivated by 5 held-out forks at one heart: 3.58 USD, 0 new places (KOHO-150). Not validated as a fix: in 27ab (flow-115) the beach stall still made 441 calls in 25,845 frames, 411 at one heart |
| flow-113 (#122) | no fight on sight and no `attack` offer without a sword | shield push on urchins measured on a stub copy of 6913 @40280. Not validated: 27ab reached the same urchin screens and did not pass (pushes moved 0 to 4 px, KOHO-167) |
| flow-114 (#124) | `explore(direction)` takes only work on that side, else stops `nothing_toward` | paid: used in 944a, 3d74 and 391b, `nothing_toward` 3, 3 and 6 times; every case read was true (KOHO-163) |
| flow-115 (#125) | objectives expire after 3600 frames without measured progress; lib net -43 | paid: fired in none of 944a, 3d74, 391b; in 27ab 2 objectives expired while `guarded` abandoned 547 |
| flow-116 (#128) | a model's own place objective hands over to the harness's exit taking after 1800 frames | no paid run yet |
| Tools | `tools/gates` (#118: 3 checkpoints, 2 on one run `abbe`, one stub play each); `tools/scoreboard` (#120, #123: measure, run, debt, alert) | merged |
| Paid evidence, flows 110 to 115 | 6 runs off the C7..F7 stretch: 6913, b32c, 944a, 3d74, 391b, 27ab; 143,489 frames, 24.01 USD, 0 deaths, shield only, no new key item | `scoreboard measure` on the six runs |
| Learning path | 1 hypothesis shape in `lib/koholint/learn.rb`; `data/capabilities.json` 1 `operational` entry of 11; `suggestions.md` written by nothing | main |
| What the owner decides next | step 2 at 0 USD; then a budget for the paid 3-vs-3 confirmations of step 3 | section 10 |

From now on no flow merges without a from-zero run or an off-stretch gate that improves, and every task runs in a fresh thread.

## 1. Goal, and why this order

"It improves itself" should mean: **the system gains game progress from changes it found, tested and proposed by itself, and those changes are data, not Ruby.** The number that would say so:

> **autonomous gains** = first gains of the progress vector that appear between two scoreboard lines whose only difference is a data-only commit produced by the loop.

It is 0 and steers nothing yet; it stays described here, and nothing is built for it before section 7 is unparked. The project stands at 0 dungeons of 8, and the evidence below shows learned facts are not what blocks it. The order:

1. **Diagnose** (done, from existing runs).
2. **A minimal judge**: measure its speed, then paired replicates with an A/A check.
3. **Delete or bound harness rules** with that judge as a filter and paid pairs as the verdict.
4. **A learner**, only if a later diagnosis points to one. The current one does not.

## 2. Non-goals

- No new flow or rule written from this document now (owner, 2026-11-27).
- No agent that edits Ruby, prompts or its own skill code. Code changes stay reviewed pull requests with a `flow_version` bump.
- No learning during a run: "a run only emits `suggestions.md`; `learn` and `capability` are offline commands" (`AGENTS.md`).
- No walkthrough knowledge from any source (section 6).
- No tooling ahead of a measured need: section 7 is not built from this document.

## 3. Principles

1. **Diagnose before building.** A step states the question it answers and the observation that would make the next step pointless.
2. **Deterministic is not reliable.** One changed decision shifts everything after it: 3d74 and 391b fork b32c at the same frame and found 14 and 3 new places for 0.70 USD each, mainly by the model's first objective (KOHO-163). A verdict needs several paired plays.
3. **Reward progress before safety.** A score that looks at deaths first teaches standing still; 27ab spent 90% of its dollars at one heart with 0 deaths.
4. **The stub measures the harness, not the agent.** The $0 stub picks up the mushroom and turns it into the powder as model runs do (`README.md`), so a stub number says what the rules do, not what the model would do with the freedom a deleted rule gives back; that is the limit KOHO-148 and KOHO-150 found. Every deletion and every published fact is confirmed by a paid pair or an A/B.
5. **Measure the time, then set the budget.** No speed figure is a promise until step 2 has measured it.
6. **What is learned is data with provenance**, `verified` at 2 root lineages, with its trials, negative ones included; everything that steers play is in a manifest digest.

## Step 1. Allowed knowledge, then the diagnosis

### 1.1 What may be written down for good

The line is the one of `AGENTS.md`: how to play is public; where to go and what to do next is not. A test for any sentence: *would it still be true in another game of the series?* If yes it is a mechanic; if only on this island, a walkthrough.

| Allowed (the manual and genre knowledge) | Not allowed |
|---|---|
| The goal: 8 dungeons, a boss in each, 8 instruments | Which dungeon comes first, or any order |
| Controls, screens, save, game over, hearts and heart pieces (already in `docs/AGENT_MANUAL.md`) | Where anything is: a key, an item, a dungeon entrance, a person |
| Nothing about what opens a dungeon: whether one has a key is observed per dungeon and recorded as an optional milestone (the scoreboard's `dungeon_keys`), never as a required step | Which dungeon has a key, which key opens which dungeon, where it is found |
| Inside a dungeon: small keys open locked doors and are spent; one special key opens the boss door; a map and a compass may be found; some doors open when a room's enemies are defeated or a switch is pressed; blocks can be pushed; stairs link floors | The solution of any room, the path through any dungeon |
| A dungeon usually holds an item, and such an item often opens ways that were closed before, inside and outside | Which item opens which obstacle |
| Some tasks are required and some are optional; people may ask for a thing and give another in return | The chain of exchanges, who wants what |
| Texts are the source of direction: signs, people, the map's marks | Any paraphrase of a hint the playthrough has not read |

When flows resume, this goes into `docs/AGENT_MANUAL.md` as a "Dungeons" section in its plain style, paraphrased, with a check in `test/agent_manual_test.rb` that the manual names no place or person of the island. The manual is joined to every play message, so that is a flow bump with its gate numbers. Anything with a number enters data as `hypothesis` with its source and is verified by a probe.

### 1.2 Blocker report

The two planned diagnosis runs are replaced by the paid runs already on file: 6913 (flow-110, from boot, KOHO-150), b32c (flow-112, from boot, capability review b32c), 944a (flow-115, from boot) and the forks 3d74 and 391b of b32c @13322 (KOHO-163), and 27ab (flow-115, from boot, 20 USD cap, KOHO-167). Spans are the scoreboard's `stalls` (4000 frames or more with no new place, counted from the second place or the fork frame), re-cut with its own code; frames, dollars, calls and rule counts are the trace's. 3d74 and 391b have none (longest 1,872 and 3,268). "What was missing" is stated only from what the run had read or seen (section 6).

| Run (flow) | Frames | Screens | USD, calls | Class | What was missing, from the run's own knowledge | Addressed by |
|---|---|---|---|---|---|---|
| 6913 (110) | 16,107-24,051 (7,944) | C11 (162/0), D11 (163/0), D12 (179/0), C12 (178/0) | 0.60, 23 | `direction` | a lead "the beach to the south" and no way south; the model reasoned from room numbers while exits north and west stayed untried; a loop break found a house at 24,051 | 114, 116 in part; no paid check of 116 |
| 6913 (110) | 36,156-40,841 (4,685) | B15 (225/0), C15 (226/0), D15 (227/0) | 1.48, 51 | `skill` | no sword; urchins block the way; refused attacks, zero cap (16) and retreat (4) sent Link back; the shield push was blocked | 113; 27ab at flow-115 still did not pass |
| b32c (112) | 15,520-19,686 (4,166) | C11, C12, D11, D12 | 0.43, 17 | `direction` | its own objective "reach D12 column 9" never closed and held the autopilot; 2,093 frames re-talking to people already read | 115 (expiry, revisit), 116 |
| 944a (115) | 8,211-12,666 (4,455) | D12, C12 | 0.36, 13 | `direction` | probed D12's south edge, a tree line the grid shows as unknown cells; the exits up and right of B12 (177/0) untried | 116 (its case); `perception` second |
| 27ab (115) | 10,269-14,429 (4,160) | D12, C12, B12 (177/0), B11 (161/0) | 0.36, 11 | `direction` | row 7 blocked; the way out was found on the left edge | 116 in part |
| 27ab (115) | 26,369-52,214 (25,845) | B15, C15, D15 | 14.91, 441 (411 at one heart) | `override` | at one heart from about 27,300 and nothing restores hearts: `guarded place (101)` answered 547 decisions and abandoned 547 objectives, `zero cap` 189, `heart pickup / disengage (94)` 106; the run had read the tip "if your hearts get too low, enter a house or a cave"; the model's own way out (stand by an enemy, die, continue, 51,701) was undone by autopilot walks | nothing |

Classes and what each points to:

| Class | Meaning | Points to |
|---|---|---|
| `direction` | no idea where to go: no lead, or leads never turned into objectives | story objectives from texts, the map's marks (ROADMAP 1(e), 3) |
| `override` | the model chose something sensible and a rule replaced or pre-empted it, or the model was never asked | step 3 |
| `model` | the model was asked, had what it needed, and chose badly | the prompt and the context, an A/B on the model |
| `fact` | a wrong or missing fact about a thing: hostile, solid, pushable, where an exit leads | a learner (step 4) |
| `skill` | the right intention and no skill able to carry it out | a skill or a learned capability |
| `perception` | the engine did not see what was on screen or read a text wrongly | perception (ROADMAP 4) |

**Frames lost per class** (51,255 frames and 18.14 USD over the six stalls): `override` 25,845 (50%, 14.91 USD); `direction` 20,725 over four runs (40%, 1.75 USD); `skill` 4,685 (9%, 1.48 USD); `model`, `fact` and `perception` 0 as the first class.

What this decides, by the tests this spec set itself:

- `direction` and `model` are 40%, under half, so the work is not only objectives and context. But `direction` recurs in every from-boot run at the same village screens, through flows 110 to 115; flows 114 to 116 address it and only 114 was seen in a paid run.
- `fact` and `skill` are 9%, under a fifth: step 4 builds no learner.
- `override` is half the frames and 82% of the dollars: step 3 comes first.
- Two kinds of evidence the first draft did not foresee. **Protective refusals are unbounded**: no window or count ended the 547 refusals of one place. **A run can burn most of its budget with 0 deaths**: 27ab spent 90% of 16.61 USD in one absorbing state, and its guard stopped on deaths only (stall guard off, KOHO-167).

## Step 2. A minimal judge

Two parts, both at 0 USD.

**(a) Speed, measured first.** Before any judge code: frames per second of one stub gate play, the fixed cost of one fork, and both again with plays in parallel on the Mac's cores, recorded in `tools/gates/README.md`. The figures on file disagree (the v2 design measured 96 frames per second per process; the exit bench 8 forks and 9909 frames in 251 s), so the size of (b) is set from this measure, not before.

**(b) Paired replicates at a few forks, and the A/A check.**

- Gates: the 3 of today plus 2 or 3 cut from the runs of step 1, at full health and off the C7..F7 stretch (a checkpoint at one heart tests the one-heart behaviour, not the rules: KOHO-150). `lineage` is recorded per gate (`Bench.lineage_root`) so a test can tell the stretch the rules came from from the others.
- Replicate `k` forks the checkpoint `k * 37` frames later (confirm that `Run#fork` at any frame is exact). A candidate and the baseline are compared replicate by replicate: same gate, same offset.
- Score per play, from `Scoreboard::Measure` on the fork's own segment, in this order: `gains` (key items, first deliveries, dungeons, instruments), `new_places`, `deaths`, then `stall_frames` and `calls`. `hp_lost` is reported, never compared.
- Each pair is a win, loss or tie: `better` when wins are at least twice the losses and at least 3 more, `worse` the other way, `equal` otherwise.
- **A/A:** the baseline against itself at offsets `k * 37 + 11` must say `equal`; if not, raise the replicate count or the thresholds until it holds 3 times in a row, and record them.
- The pin numbers of `tools/gates/metrics.rb` stay a regression check of replicate 0, not the judge.

It filters candidates; it never decides one (principle 4).

**Done when.** The timings are recorded, the A/A check passes 3 times with the recorded settings, and the paired comparison is tested ROM-free on tables of numbers.

## Step 3. First use of the judge: delete or bound

**Candidates, from evidence, not from a switch per family.** The ROADMAP's criterion is "a rule that fired in no held-out run". The scoreboard's `rules` table over the six runs of step 1 (143,489 frames off the stretch) names the families that fired in none: heal give-back (109), heal detour (101/105), loop re-offer (101), souvenir (102), offspring fight (110), danger / held back (106/108) and harness override of the model. Those that fired at all did so on the C7..F7 stretch they were written from (g6 to g8, KOHO-148 and KOHO-150). Before relying on a zero, confirm in code that the family's pattern in `Measure::FAMILIES` still matches the justification its rule writes today; a stale pattern reads as a rule that never fires.

**Bounded refusals.** The second target comes from the `override` row: every protective refusal is bounded, by a window or a count, and yields to the model's choice, as objective expiry (flow-115) and the model objective hand-over (flow-116) already do. Measured candidates: guarded place (101) 547 in 27ab, zero cap 189 in 27ab and 16 in 6913, heart pickup / disengage (94) 106, hostile no standing (100) 16, retreat (100) 4 in each of 6913 and 27ab, and the one-heart walls. This is a target for deletion or tightening, not a new rule to write now.

**Process.** A candidate is a branch that deletes or bounds one family. It goes through the judge of step 2 on every gate; not `worse`, it is confirmed by a paid 3-vs-3 (`ab-plan`, `ab-report`) from one stretch checkpoint and one off-stretch checkpoint, and by the merge rule of "Where this stands". Not worse there: delete the code and its tests in one pull request with a flow bump and the new gate numbers. Worse: the rule stays, with its measured reason in `tools/gates/README.md`.

**Done when.** Every candidate above has a verdict, and `scoreboard debt` shows fewer branch conditions than at the start.

## Step 4. A learner: not indicated by the evidence so far

`fact` and `skill` together are 9% of the lost frames, so none is built. If a later blocker report puts them above a fifth, the learner is the one that would have produced its top row, in its own plan under `docs/superpowers/plans/`, with: a digest of the play-steering fields of `data/entities.json` checked at resume before anything writes there; a control arm in every trial; no RAM write in a validation; publication through the judge and a paid pair.

## 5. Progress across runs: frontier checkpoints

No run is "the save". Progress carries through data and through checkpoints a later run may fork from.

- `data/checkpoints.json` entries gain `lineage`, `vector` (the progress vector at that frame) and `role`: `frontier`, `held_out` or `regression`.
- A new `frontier` is proposed when a run's vector is above every checkpoint's on the first component that differs (instruments, dungeons, key items, places), at the first ready keyframe after the gain. Paid runs that aim at new progress fork from the highest one.
- A frontier reached by one root lineage is `observed`; it is `verified` when a from-boot run of another lineage, at a frozen flow, reaches the same component. A passed frontier stays as a `regression` gate.

Build it with the gate metadata of step 2; `test/checkpoints_test.rb` checks the computed fields.

## 6. The walkthrough rule in this work

- The blocker report states what was needed only from what the run had read or seen. "It should have gone to X" from knowledge of the game is the walkthrough by the back door; "unknown from the run's own knowledge" is the honest entry and itself the finding (`direction`).
- No rule is written from the report; it selects among general mechanisms.
- A model used offline (section 7) may choose the right experiment because it knows the game; that leak cannot be checked mechanically, which is a reason to prefer deterministic templates and keep such a model for last.

## 7. Parked: later, only if steps 2 and 3 call for it

An outline, not a specification. Nothing here is indicated by the evidence so far.

| Piece | What it is | Build it when | Known trap |
|---|---|---|---|
| Judge, full version | known-bad and known-neutral calibration, a held-out split with a log of every look (`held_out_log.jsonl`) and rotation after 30 looks or each paid from-boot run, a baseline cache keyed by gate, replicate, harness sha and data digests, frames per gate tuned from the timelines (3000 to 4000 for most, 12000 where the length matters), a keyframe per replicate, a budget table (4 tune and 5 held-out gates at 5 replicates and 2 arms is 90 plays) | the minimal judge is too slow or too coarse for the candidates of step 3 | skipping a gate a candidate "cannot affect" needs every data read instrumented; one missed read gives a silent wrong `equal` |
| `anomaly` trace events | every action carries the outcome the world model expects; a mismatch is traced, counted and fills `suggestions.md` | a learner is indicated and its facts were found by a person reading traces | emitting must change no decision |
| Generic experiment bench | `learn.rb` and `bench.rb` as one machine, with `data/experiments.json` | a third hypothesis shape is needed | generality before a third user is a guess |
| Offline analyst | a strong model turns an anomaly into experiments in the bench's format; data only | templates leave anomalies unexplained | the leak of section 6; drop it if its validated share is below the templates' |
| Parameters as data | the unmeasured thresholds of `docs/loose-ends.md` in `data/params.json` | step 3 left rules whose threshold visibly matters | one parameter at a time, each confirmed by a paid run |
| The nightly cycle | collect, propose, experiment, judge, record in `data/improvements.json`, open a data-only pull request | facts were published by hand at least 3 times | see "automatic merge" below |
| Scoreboard `autonomy` | autonomous gains (section 1), published facts, deleted rules, data commits against flow bumps | the cycle exists | a number that stays 0 steers nothing |
| Dungeon perception | place kind `dungeon`, small keys, boss key, instruments, as typed data verified at pickups | a run stands in a first dungeon | cataloguing dungeon maps in advance would say where they are |

**Automatic merge of data-only pull requests** (owner's decision 2). It takes effect with the nightly cycle, by a standing grant added to the root `AGENTS.md` in a pull request the owner merges by hand, limited to pull requests that touch only `data/` and `tools/gates/expected.json` with every check passed, and backed by a test that fails on anything else. A published fact changes a digest, so a run recorded before it cannot resume: publish in batches, at most once a day, never while a paid run is in progress.

**The analyst's system prompt**, kept so it is not rewritten from nothing. It would live outside `Agents::Prompts` (`Prompts.digest` hashes every string constant of that module, so adding it there would break the resume of every run). Its picture input would be a filmstrip: 8 frames around the anomaly, each labelled with its frame, Link's cell and hp, and what changed in the entity table.

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

- Time is the frame; no sleep or wall clock in game logic. Offline tools may use wall time.
- Only the engine writes a run's `trace.jsonl` and `save/`; judge forks live under `tmp/` or `--root`; a fork may add keyframes to its parent's `keyframes/`.
- `verified` never below 2 independent checks.
- Docs in the same commit (`ARCHITECTURE.md`, `docs/OPERATING.md`, `docs/AGENT_SKILLS.md`, `ROADMAP.md` loses what lands); a flow bump lands with its gate numbers.
- When this spec is done or superseded, change its status line.

## 9. Risks

| Risk | Guard |
|---|---|
| Meta-work feels like progress while the game stalls | the blocker report decides; step 4 and section 7 are parked |
| The judge rewards standing still | progress before safety in the score order |
| A verdict is a chaotic accident | replicates, paired comparison, the A/A check |
| The stub is not the model | every deletion and published fact is confirmed by a paid pair or an A/B |
| A protective rule makes a state absorbing | step 3's bounded refusals; a stall guard on every paid run |
| The diagnosis smuggles the walkthrough in | section 6 |

## 10. Owner's decisions (2026-11-27)

1. Budget for the two from-boot runs of step 1: approved.
2. Data-only pull requests merge automatically once the nightly cycle exists, under the grant described in section 7.
3. Stop and measure before the pieces of section 7; in this version that pause is the structure itself.
4. A model used offline runs through the Claude CLI on the owner's Claude plan; a dollar cap stays as a guard.
5. The loop must run fast and stay reliable: step 2 (a).
6. The owner paused new flows on 2026-11-27 pending this spec.
