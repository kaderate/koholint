# First agent run (2026-10-19)

Run `20261019-092839-1af5`: `bin/koholint run --agent --realtime --max-dollars 1 --minutes 25` on branch `agent-loop` at `9245b30`, model Sonnet, no walkthrough, manual digest `docs/AGENT_MANUAL.md` (no controls section).

## Result

| Measure | Value |
|---|---|
| Stop reason | dollars (cap 1.0 reached, 1.0019 spent) |
| Left the starting house place | **no** |
| Frames played | 2601 (about 26 s of game time) |
| Agent calls | 78 (5 `choose_objective`, 73 `choose_skill`), 0 fallbacks, 22 with a dialogue image |
| Cost per call | about 0.0128 USD (0.0098 to 0.019) |
| Latency per call | about 2 to 6 s |
| Objectives | 5 started, 4 achieved, 1 open at the stop; all `reach_cell` inside the starting place |
| Walks | 52, of which 18 `blocked` |
| Deterministic waits (hemmed in) | 5 (frames 293 to 773, cost 0) |

| Phase | Calls | Cost |
|---|---|---|
| Boot and bed (< f893) | 6 | 0.068 |
| Intro dialogue (f893 to f1453) | 18 | 0.261 |
| Exploring (> f1453) | 54 | 0.673 |

## What happened

- The agent chose "Explore upward" (`reach_cell` row 2, col 5) as its first objective, then four more `reach_cell` objectives on cells the grid already showed passable. It never chose `leave_place`: the exit was unknown.
- Link is locked until a dialogue opens (f893 here). The four blocked walks triggered the deterministic wait five times at zero cost; the dialogue then opened by itself.
- The agent read the dialogue boxes from the image (French text: "Ah! Enfin... J'ai cru que tu...", "Tu es sur l'île Cocolint!", "Oh là... C'est bien trop..."), and advanced them one A cycle per call: 18 calls, a quarter of the budget, to read an intro. It also tried B and A presses that did nothing.
- Objective 5 (`reach_cell` row 1, col 1) took 25 calls and 450 frames: the grid said passable, every walk left was blocked at the same place. Loop detection did not fire (the choices varied between walk directions); the stall limit (1800 frames) was not reached; the dollar cap ended the run.
- No crash, no invalid output, no fallback, no hot spin; the stop was clean (`budget_stop` dollars, then `stop`).

## What was missing

- **Cost per game second.** Calls move 1 to 3 cells each: about 78 calls for 26 s of play. One dollar buys far less than the starting house. A call per cell is not viable; the decision granularity or the model needs to change (fewer, longer actions; a navigation skill on the known grid; a cheaper tactical model).
- **Dialogue advance should not need a model call.** While a dialogue is open and unread, advancing it is mechanical. The agent only needs the transcription once per page, or the transcription could be skipped when the page text is unchanged.
- **Objectives that mean something.** `reach_cell` on a known-passable cell is trivially achieved and teaches nothing. The agent has no way to say "find a way out" or "explore the unknown": no frontier concept, no `explore` predicate.
- **Repeated failure toward one target.** The agent retried the same unreachable cell 18 times with varying walks. Loop detection keys on identical choices; nothing counts failed attempts toward the same target or tells the agent "this cell was blocked N times".
- **Belief versus reality.** The grid showed (1,1) as passable while the game blocked every approach; the context did not reconcile belief and failed walks beyond a "last walk" line per direction.
- **Controls.** No controls section in the manual digest; the agent used A and B by genre knowledge and sometimes pointlessly.
- **Facts to correct.** The dialogue opened at f893, not f778 as in the plan's facts (the agent run idles differently); `dialog_state` changes 130 to 140 during a dialogue.
