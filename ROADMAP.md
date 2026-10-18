# Roadmap — what remains

Only what is left to do. When something lands, delete it here (git is the history). Amend freely.

**Goal:** an agent plays Link's Awakening DX through the engine. First milestones: shield, then sword.

## Next, in order
1. **Vision and collision grid** — plan `docs/superpowers/plans/2026-10-18-vision-and-grid.md` (in progress).
2. **Generic actions and the first agent loop** — action registry (move, press, interact, advance dialogue) with typed results; minimal world view; Jev/Claude decision contracts (`claude -p` isolated, no tools, schema-validated output, deterministic fallback); objective/step lifecycle with a stall limit; loop detection. End criterion: the agent exits the starting house, measured in frames, calls and cost.
3. **Perception gaps** — inventory/items and Link's capabilities (find addresses by tracing), milestone detection (shield, sword), "dialogue open" state and dialogue text decoding, `notable` events (so the feed's health stops being `unknown`).
4. **Dialogue to leads** — texts and leads (claims extracted by the agent, with status open/tested/refuted and evidence); Claude interprets NPC and sign dialogue.
5. **Interactions beyond walking** — push, dive/swim, item use; capabilities feed the beliefs of the vision plan.
6. **Combat** — open question: micro-decisions; settle by spike (Jev macros vs deterministic vs hybrid) after the first agent loop.
7. **Navigation spike** — A* on the known grid vs Jev macros vs hybrid, measured on success, frames, cost, latency.
8. **Live view, layout C** — clickable timeline of notable events and agent calls, fork from the UI, pause/stop.
9. **Budgets in practice** — dollar budgets from `claude -p` usage fields, step budgets once objectives exist.

## Open decisions and loose ends
- Addresses at `verified_count: 1` need a second independent check (`game_mode`, `game_submode`, `name_length`, `max_hearts`).
- Ladder beyond shield and sword; whether a run may inherit a map from a previous run.
- Viewer: Host-header check; per-macro fsync cost on long runs; pacer catch-up cap after long stalls; `verify` replays from boot (use keyframes).
- Test runner: rspec vs minitest (not decided).
