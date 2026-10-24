# Jev spike (2026-10-24): choose_skill / explore direction

Code and data: git branch `jev-spike` (`spikes/jev/`, not merged). Raw output: `spikes/jev/data/run.log` on that branch. Assessment before the spike: Jev classifies options described by code, ~100x cheaper and ~10x faster than Claude, best with <= 5 options, no reasoning, not deterministic. Verdict: skip for exploration; combat only after a deterministic baseline; puzzles, text reading, menus, objectives: skip.


**Status: run done (600 Jev calls, 0.0197 USD). Verdict: Jev does not pass; it is no better than random on these options.**

## Dataset
- 1010 paid Claude `choose_skill` decisions (explore/walk/goto/talk_to/step, 19 runs), 989 mapped (98 %).
- Options: 4 `explore_<dir>` + 1 `talk`, 4.5 on average, with descriptors (distance, frontier/exit, targets on that side, unknown cells and walls, exits tried, past failures); ASCII 8x10 grid state.
- Candidates computed by the real `Explore::Run#candidates`; target direction matches the trace on 25/25 single-step explores.
- Explore era (flow-6+): 135 decisions, 81 directed. Older era: 854 (walk/goto/step reduced to a direction, rough).

## Top-1 agreement with Claude
| | explore era (135) | directed (81) | older (854) |
|---|---|---|---|
| nearest-frontier baseline | 59 % | 32 % | 26 % |
| random (top-1 / top-2) | 23 % / 45 % | 22 % / 44 % | 21 % / 42 % |
| Jev | 15 % (top-2 25 %) | 22 % (top-2 40 %) | 20 % (top-2 46 %) |

Undirected explores take the baseline direction by construction: the honest figure is the directed one (Claude follows the nearest frontier 1 time in 3).

## Outcome (Claude's own choices; the counterfactual is unobservable in replay)
- Strict good outcome (new place, new cells or dialogue): explore era 55 %, directed 67 %, older 49 %.
- Directed decisions: same outcome whether Claude follows the baseline or not (65 % vs 67 %).

## Latency and cost
Claude, explore era: 0.0157 USD per decision, p50 2.2 s, p95 9.3 s. Jev: 0.000033 USD per call, p50 0.21 s, p95 0.32 s (600 calls).

## Verdict on the pre-registered criterion
- Criterion failed on agreement: Jev~Claude top-1 18 % over 600 calls (random 21 %, nearest-frontier rule 31 %); among Claude's good outcomes 19 % (rule 33 %). Latency and cost pass by orders of magnitude.
- Side finding: Claude's outcome is the same whether the nearest-frontier rule agrees or not (49 % vs 50 %), so the direction choice of explore carries little measurable signal; the cheapest saving is to stop asking the model for it (auto-continue explore with no direction after benign stops).
- Unfavourable signal: Jev~Claude >= 75 % looks out of reach with these descriptors (best deterministic rule reproduces Claude at 32 % on directed decisions; Claude uses the image and the leads, which options do not encode). Agreement with Claude is probably the wrong yardstick.

## A live A/B would need
- A Jev policy on `choose_skill` with the answer traced in the `decision` event (replayable).
- Three arms from the same keyframes (Claude, deterministic baseline alone, Jev), >= 3 forks per arm, about 3000 frames each; metrics: new places and cells per 1000 frames, stalls, cost per 1000 frames.
- Test the baseline alone first: if it matches Claude within 10 %, Jev is not needed.
