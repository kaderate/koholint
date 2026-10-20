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
