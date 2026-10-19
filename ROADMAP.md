# Roadmap — what remains

Only what is left to do. When something lands, delete it here (git is the history). Amend freely.

**Goal:** an agent plays Link's Awakening DX through the engine. First milestones: shield, then sword.

## Next, in order
1. **Make the agent loop affordable and purposeful** — measured by the first run (`docs/runs/2026-10-first-agent-run.md`): 78 calls and 1 USD for 2601 frames without leaving the starting house. Needed: coarser or cheaper decisions (navigation skill on the known grid, cheaper tactical model, Jev); dialogue advance without a model call per page; objective kinds that mean something (explore the unknown, find an exit); counting failed attempts toward one target (and telling the agent); reconciling grid belief with repeated blocked walks. Jev wiring after that.
2. **Perception gaps** — inventory/items and Link's capabilities (find addresses by tracing), milestone detection (shield, sword), deterministic dialogue text decoding (the first loop reads dialogue as an image), `notable` events (so the feed's health stops being `unknown`).
3. **Dialogue to leads** — texts and leads (claims extracted by the agent, with status open/tested/refuted and evidence); Claude interprets NPC and sign dialogue.
4. **Interactions beyond walking** — push, dive/swim, item use; capabilities feed the beliefs of the vision plan.
5. **Combat** — open question: micro-decisions; settle by spike (Jev macros vs deterministic vs hybrid) after the first agent loop.
6. **Navigation spike** — A* on the known grid vs Jev macros vs hybrid, measured on success, frames, cost, latency.
7. **Live view, layout C** — clickable timeline of notable events and agent calls, fork from the UI, pause/stop.

## Open decisions and loose ends
- Addresses at `verified_count: 1` need a second independent check (`game_mode`, `game_submode`, `name_length`, `max_hearts`, `dialog_state`).
- Ladder beyond shield and sword; whether a run may inherit a map from a previous run.
- Viewer: Host-header check; per-macro fsync cost on long runs; `verify` replays from boot (use keyframes).
- Test runner: rspec vs minitest (not decided).
- Vision deferred (not fixed): sprite flips are not in the sprite pattern; sprites at y 1..8 in 8x8 mode; tile bytes not memoised per snapshot; BG-disable not handled; dialogue CLOSE never sampled in the overlay test; window-overlap overlay rule only unit-tested.
- Vision deferred: `World#add_screen` assumes event order and `places` dups shallowly; probe `moved` ignores `hp_delta`; control compares end positions only; the misaligned memo is keyed by pixel; left `:no` sits on the 4 px tolerance boundary; the 32-frame hold margin is unmeasured; no free-Link rule at one-way ledges.
- Vision deferred: policies receive the live `Beliefs` (could call `record`); the contradiction check judges with today's evidence and ignores knockback; `--grid` CLI test is weak and the replay test mostly covers the intro; grid colour-map test does not pin colours; the suite takes about 2 min; `Engine.resume` re-emits one `screen` event because the last emitted screen is not seeded from the trace.
- Agent loop deferred: `resume` without `--agent` on an agent run silently continues with WalkAndTalk (record the policy in the manifest or refuse); timed-out or cancelled client calls are counted as $0 and a call longer than the sleep gap is dropped from active time; the claude subprocess inherits HOME, so the model sees the user's email and the temp dir path (accepted; `--bare` needs an API key).
- Agent loop deferred: no controls section in `docs/AGENT_MANUAL.md`; add one only from the printed booklet (`manual/notice.txt`, absent locally) and mind the 3000-char sub-cap; `Run#fork` copies decision events carrying `prompt_sha` but not their prompt files, and a failed choose_objective prompt is stored as `<frame>-choose_skill.txt`; the `objective started` event is emitted before the `decision` that chose it (viewer ordering).
