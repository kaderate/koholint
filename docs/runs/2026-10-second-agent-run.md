# Second agent runs (2026-10-19 to 2026-10-20)

Plan 4a (`goto`, `step`, `talk_to`, ledger and doubt, automatic dialogues, `plan`, triggers and interaction memory, `flow-3`) on branch `agent-loop`, Sonnet, 1 USD cap, `--realtime --grid`. Run 9 (`20261020-063841-3104`, code `11f5cea`) is the complete one; earlier runs of the same day informed the fixes (run 7: 6664 frames, 1.02 USD, objective lost to the 8-block guard; run 8: stopped at 0.32 USD by the Claude subscription session limit, the `agent_failures` stop worked).

## Run 9 against the first run

| Measure | First run (plan 3) | Run 9 (plan 4a) |
|---|---|---|
| Frames | 2601 | 4771 |
| Dollars | 1.0019 | 1.0042 |
| Model calls | 78 | 59 (15 with images) |
| Calls per 1000 frames | 30 | 12.4 |
| Dollars per 1000 frames | 0.385 | 0.21 |
| Automatic dialogue ticks (no model call) | 0 | 132 (120 `advance_dialogue`) |
| Call latency median / p90 / max | 4.2 s / 9.3 s / 15.2 s (run 7 sample) | 3.0 s / 9.9 s / 11.8 s |
| Total time waiting for the model | n/a | 267 s |
| Fallbacks | 0 | 0 |
| Objectives | 5 (all `reach_cell`) | 1 (`new_place`, never achieved) |
| Places seen | 1 | 1 (plus the title screen) |
| Left the starting house | no | no |

## What happened

- The loop is about twice as cheap per game frame and the agent keeps one coherent objective for the whole run, with a plan filled at every call.
- `goto` and aligned walks work: 6 `goto`, 3 `done`; no `no_path` loop (one `talk_to` ended `no_path` with a cause naming the three blocked standing cells).
- The scripted dialogue at the doorway still blocks the exit. Measured by replaying run 9 to frame 2242 (a dialogue had just closed, Link at the doorway, y 121) and holding one input: **only DOWN re-opens the dialogue (after 2 frames)**; idle, up, left and right do not (up walked freely to y 66). Four of eleven `talk_to` calls and several walks still ended `dialogue` because **our own centring presses DOWN**: the doorway cell centre is y 128 and Link stands at y 121 (7 px, over the 4 px tolerance), so the centring phase of `walk`, `goto` and `talk_to` presses down and triggers the dialogue (e.g. `walk right` at (7,4) ended `dialogue` after 10 frames). The agent reads the dialogue correctly and plans to talk to the person at (4,7), but its own skills keep pressing down.
- Three of eleven `talk_to` calls ended `target_free` on phantom cells: the grid marks a cell as occupied by a person where the sprite only straddles it by a pixel (the sprite-bleed risk found in the review of plan 4a Task 2).

## What was missing

- **Phantom object cells.** The sprite-to-cell mapping needs a minimum overlap (for example at least 8 px on both axes), otherwise the interaction memory lists cells that hold nobody.
- **Centring must not press an input that triggers a scripted dialogue.** Record the input pressed on the frame a dialogue opened (per place and cell), forbid it in the centring phase of every skill, and tell the agent. Moving up first, away from the trigger, works.
- **Shield milestone** is still not perceived (`highest_milestone: none`).
- **Objectives.** `new_place` was never achieved nor abandoned in 4771 frames: the unreachable guard no longer ends non-`reach_cell` objectives, so a stuck objective can last the whole budget. A per-objective call cap would bound it.
- **Speed.** The view still freezes while a model call runs (267 s of waiting out of the whole run).

## Run 10: the agent leaves the starting house (`20261020-070238-d8c5`, code `8d438cd`)

The trigger-input fix (record the input that opened a dialogue by itself, never press it while centring, avoid that edge in `goto` and `talk_to`) was added after the analysis above. Same 1 USD cap.

| Measure | Run 9 | Run 10 |
|---|---|---|
| Frames / dollars | 4771 / 1.004 | 3593 / 1.003 |
| Model calls | 59 | 69 (4 with images) |
| Calls per 1000 frames / dollars per 1000 frames | 12.4 / 0.21 | 19.2 / 0.279 |
| Latency median / p90 | 3.0 s / 9.9 s | 3.3 s / 6.0 s |
| Time waiting for the model | 267 s | 291 s |
| Automatic dialogue ticks | 132 | 58 |
| Places seen | 1 | 3 (`163/16` the house, then `162/0`, `161/0`) |
| Objectives | 1 never achieved | 3 `new_place`: 2 achieved (frames 3452 and 3593) |
| Left the starting house | no | **yes, first room change at frame 3422, 63 calls, 0.936 USD** |

- The agent talked to the person it had to talk to (`talk_to (4,7)` ended `done`, `talked: true`, at frame 2067, 43 calls and 0.60 USD in) after the earlier runs kept failing; a long dialogue followed. After it Link stood blocked in all directions for about 300 frames (an item animation, not understood by the agent, which tried A, B, waiting and every direction) before moving again.
- The exit worked from the doorway after that; the agent stepped through and then explored two new rooms by `goto` along row 7 and the screen edges.
- Only one trigger input was recorded (a `goto` left, from a dialogue opened by pushing into a pot): the guard on the exit did not re-fire this time because the dialogue had been resolved.
- Cost to leave: 63 calls and 0.936 USD, 3422 frames. A rerun with identical code is not deterministic (model answers vary): this is one success, not a rate.

### Still missing after run 10
- The shield milestone is not perceived (`highest_milestone: none`) although the agent obtained it.
- About 300 frames of "blocked in every direction" after the dialogue cost 7 calls: the agent should be told that movement can be locked by an animation (no cause is visible) and that waiting is the answer; an `animation locked` signal from perception would help.
- The forbidden-input memory never expires within a place; a one-off cutscene input could block a `goto` edge (review follow-up): clear the entry when the same input is pressed explicitly later without any dialogue.
- `Planner#why_not` does not name a forbidden edge as the cause of `no_path`.

## Runs 12 and 13 (boot probes, locked phase, shield milestone, talk_to side retries)

| Measure | Run 12 (`20261020-081957-3aa4`) | Run 13 (`20261020-085011-8330`, cap 1.50) |
|---|---|---|
| Frames / dollars | 5619 / 1.002 | 5913 / 1.120 (stopped by the Claude subscription session limit: `agent_failures`) |
| Model calls | 65 | 87 (5 fallbacks, all the session limit) |
| Calls per 1000 frames / dollars per 1000 frames | 11.6 / 0.178 | 14.7 / 0.189 |
| First model call | frame 800 (the intro dialogue; none before) | frame 800 |
| Left the starting house | no | **yes** (first room change after the shield, 28 calls and 0.43 USD in at frame 3747) |
| Shield milestone | no | **yes**, frame 3193, 18 calls, 0.28 USD (`highest_milestone: shield` from RAM 0xDB44) |
| Places seen | 1 | 5 (house, then `162/0`, `161/0`, `160/0`, `144/0`) |
| Objectives | `dialogue_closed`, then `new_place` (not achieved) | `dialogue_closed`, then five `new_place` objectives, all achieved |

- Run 12 failed to talk to the person: `talk_to (4,7)` was tried from the cell below three times and got `no_response`. Run 13 (with the side retry) talked to the person from the cell above on the first call (`tried: [(3,7) done]`) and obtained the shield at frame 3193.
- The only objective the agent ever chose after the intro was "Explore to a new place": it is achieved at each room change, which says nothing about progress. Long-term planning is now the limiting piece.
- Both 1.0 and 1.5 USD runs end in the 12th to 14th calls per 1000 frames range; `agent_failures` stopped runs 8 and 13 cleanly when the subscription session limit was hit.
