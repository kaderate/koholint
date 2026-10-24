# Roadmap — what remains

Only what is left to do. When something lands, delete it here (git is the history). Amend freely.

**Goal:** an agent plays Link's Awakening DX through the engine. First milestones: shield, then sword.

## Next, in order
1. **Make the starting-house run reliable and cheaper.** Runs 10 and 13 left the house (about 1 USD each, `docs/runs/2026-10-second-agent-run.md`); it is two successes, not a rate. Needed: repeated runs to measure a success rate and the cost spread; a per-objective call cap; `no_path` should name a forbidden edge; `target_free` should trigger a `talk_to` retry.
2. **Analysis loop.** `koholint analyze <run>` (standard report, comparison with previous runs), symptom detectors writing `suggestions.md` and filling `summary.json` `symptoms`, scenario runs forked from keyframes, recorded agent answers replayed by a fake client, owner annotations from the viewer. Open question: how much of the harness the agent may amend itself during a run (Continual Harness, arXiv 2605.09998) versus code-versioned changes.
3. **Plan 4b: finer navigation** — tile lattice and tile-level beliefs, per-appearance room survey, exits that straddle two cells, Jev routing for `choose_skill`.
4. **Perception gaps** — inventory/items and Link's capabilities (find addresses by tracing), the sword milestone (find its address by RAM diff like `shield_level`), deterministic dialogue text decoding from VRAM (dialogue is read as an image, then stitched from overlapping transcribed pages), `notable` events (so `last_notable` stops being empty).
5. **Lead statuses** — leads are only open claims today: add a status open/tested/refuted with evidence, and measure whether goal, leads and people's memory give the agent a progress signal (Jev wiring after that).
6. **Interactions beyond walking** — push, dive/swim, item use; capabilities feed the beliefs of the vision plan.
7. **Combat** — open question: micro-decisions; settle by spike (Jev macros vs deterministic vs hybrid) after the first agent loop.
8. **Navigation spike** — A* on the known grid vs Jev macros vs hybrid, measured on success, frames, cost, latency.
9. **Live view, layout C** — clickable timeline of notable events and agent calls, fork from the UI, pause/stop.
10. **Real-time play** — the emulator stays paused between decisions; an optional `--live-clock` with pause-on-danger and a reflex layer (Jev or deterministic) is undecided.

## Open decisions and loose ends
- Addresses at `verified_count: 1` need a second independent check (`name_length`, `max_hearts`, `dialog_state`).
- Ladder beyond shield and sword; whether a run may inherit a map, a goal or leads from a previous run.
- Dialogues and people: a text is attributed to the last successful `talk_to` target (a text that opens by itself, or a person who moved, is not attributed; people who moved split into two entries); a dialogue longer than the page limit is read page by page and counts as several talks; the world stamp (milestone, places visited, leads) misses other changes such as items; `new_text` and people's memory compare letters and digits only, so a transcription variant beyond punctuation counts as new; stitching joins on an overlap of 7+ characters that starts on a word and may end mid-word (a scrolling box cuts words), so a real repeated phrase of that length across two pages is merged once.
- Leads: sheets are attached only to `choose_skill`, so an objective chosen right after a dialogue cannot cite its leads yet; the lead `source` is the last `talk_to` target cell, null for texts that opened by themselves.
- Viewer: Host-header check on GET routes (only `POST /star` checks it); per-macro fsync cost on long runs; `verify` replays from boot (use keyframes).
- Test runner: rspec vs minitest (not decided).
- Vision deferred (not fixed): sprite flips are not in the sprite pattern; sprites at y 1..8 in 8x8 mode; tile bytes not memoised per snapshot; BG-disable not handled; dialogue CLOSE never sampled in the overlay test; window-overlap overlay rule only unit-tested.
- Vision deferred: `World#add_screen` assumes event order and `places` dups shallowly; probe `moved` ignores `hp_delta`; control compares end positions only; the misaligned memo is keyed by pixel; left `:no` sits on the 4 px tolerance boundary; the 32-frame hold margin is unmeasured; no free-Link rule at one-way ledges.
- Vision deferred: policies receive the live `Beliefs` (could call `record`); the contradiction check judges with today's evidence and ignores knockback; `--grid` CLI test is weak and the replay test mostly covers the intro; grid colour-map test does not pin colours; the suite takes about 2 min; `Engine.resume` re-emits one `screen` event because the last emitted screen is not seeded from the trace.
- Agent loop deferred: `resume` without `--agent` on an agent run silently continues with WalkAndTalk (record the policy in the manifest or refuse); timed-out or cancelled client calls are counted as $0 and a call longer than the sleep gap is dropped from active time; the claude subprocess inherits HOME, so the model sees the user's email and the temp dir path (accepted; `--bare` needs an API key).
- Agent loop deferred: `Run#fork` copies decision events carrying `prompt_sha` but not their prompt files, and a failed choose_objective prompt is stored as `<frame>-choose_skill.txt`; the `objective started` event is emitted before the `decision` that chose it (viewer ordering).
- Plan 4a parked: sprite height is hardcoded to 16 (8x8 mode over-covers; carry LCDC bit 2 through `ScreenVision.sprites`); `GRID_ROWS`/`GRID_COLS` in `game_state.rb` duplicate `Geometry`.
- Plan 4a parked: `goto` settle duplicates the perpendicular centring logic (own `SETTLE_FRAMES`); `sync` ignores an earlier path cell; no goto-level test with a ledger in context.
- Plan 4a parked: `Ledger` doubtful cells are recomputed per direction; `pick`/`place_of` are public class methods; a 170-char line in `agents/context.rb`.
- Plan 4a parked: the ROM goto/walk tests hardcode distances and read `@centring`; no test for centring falling back to the other axis.
- Plan 4a parked: automatic dialogue pages flush only on `choose_skill` tours; step results never carry `blocked_at` by decision.
- Agent loop deferred: the interaction log attributes a talk_to to the object at (or within one cell of) its target in the current grid, so NPCs that move can read as never tried.
- Run storage: `places_seen` counts perceived places only.
- `explore`: walls and tried exits in the exploration log are permanent per place (never expire, even if the place changes).
- `explore`: next steps are a candidate menu (the model picks among the frontiers and exits the engine lists) and place labels; its walked cells and walls are per-place memory outside the beliefs (not appearance evidence), an exit whose step opens a dialogue by itself is skipped silently (not listed in `no_frontier`), and its `untried_object` range (3 cells) and leg/outward frame limits are unmeasured.
- Agent loop deferred: a failed sheet call loses the dialogue pages (their PNGs remain under `prompts/`).
- Explore: border exits are tried blindly (no passability or static-sprite check) and a dead border cell costs two paid calls before it is marked tried.
- Game modes left to measure: game modes 1, 4, 5, 8, 9, 10 and above 12 (credits, file copy and delete, other scripted scenes) are not in `data/modes.json`; they surface as `unknown` with a `notable` `unknown_mode`. Dialogue choices inside a text box (yes/no) are not modelled; signs and objects were not probed apart from people's dialogues.
- `scene_lock` (`scene_state` 1, phase `locked`) stays a hypothesis: run 20261022-111719-ac88 read it at frame 8220 while START and SELECT worked, so the `locked` phase may hold free play until the 900-frame cap; probe it.
- Map: the map cursor did not move in either census state and its address is unknown; only `open_map`/`close_map` exist.
- `save_game` skill: the save screen is measured (mode 6, settled submode 5, arrow `menu_option`, option 1 saves and quits to the opening scenes); it needs the boot script to resume from the title after quitting and a check that the cartridge RAM changed. The four-button combination is not reachable through `press` (one button).
- The game ignores START and SELECT about 12 frames after returning to play and a SELECT shorter than 4 frames; the screen skills repeat an unanswered press, the exact windows are unmeasured.
