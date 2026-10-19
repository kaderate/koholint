# Koholint

A deterministic engine that plays Link's Awakening DX headless through emu-gb and calls agents
(Jev for tactical choices, Claude for strategy) at defined decision points. Each run lives in
`runs/<id>/`: manifest, trace, input journal, saves, keyframes.

- Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`
- Plans: `docs/superpowers/plans/`
- v1 (agent session driving the game): git tag `v1-archive`, analysis in `docs/RETROSPECTIVE.md`

Needs Ruby 4.0.1, an emu-gb checkout and the ROM. Copy `.env.example` to `.env` (gitignored) and set
`EMU_GB_HOME` and `KOHOLINT_ROM`; real environment variables take precedence. Tests: `rake test` (one process per file, in parallel, ~40 s; the first run builds a local emulator
state cache in `tmp/`), `rake test:e2e` to also play the full boot from frame 0.

Live view: `bin/koholint watch runs/<id> [--port N] [--host H] [--from live|start] [--speed X]` prints
`watching http://127.0.0.1:PORT` and serves the run as video, status and feed from a read-only replay (works on a
finished run or one being written; Ctrl-C to stop). `run`/`resume --realtime` paces the engine at about 60 fps of
wall time so the viewer can keep up; pacing never changes the journal or the game state.
The viewer listens on 127.0.0.1 only; `--host 0.0.0.0` opens it to other devices on the same network (read-only,
no authentication: use it on a network you trust).

Collision grid: `run --grid` (engine option `grid: true`) reads the screen each observation and probes unknown neighbour
cells by walking. The trace gains `screen` and `screen_changed` (what the screen looks like), `affordance` (walk
evidence per tile appearance), `grid_contradiction` (Link entered a cell believed blocked) and a `notable` of kind
`grid_overlay_stuck` (more than 600 frames of overlay in one place, so the grid went dark). The live view has a grid
toggle that overlays the believed passability on the video.

Budgets: `run`/`resume` accept `--frames N`, `--minutes N`, `--dollars X` and `--steps N` (objectives that reach a terminal outcome;
only meaningful with `--agent`). With `--agent`, the engine also writes what the agent saw to `runs/<id>/prompts/<frame>-<decision_point>.txt`
(and `.png` when an image was sent; gitignored, not part of replay); the `decision` trace event carries its `prompt_sha`. Ctrl-C cancels an in-flight agent call.

Agent skills: `goto row col` walks to a cell of the known grid with a shortest path with the fewest turns (stops `done`, `blocked`, `no_path`, ...; a result carries
`blocked_at` when a move hit a wall), and `step direction pixels` moves a few pixels. A ledger counts blocked edges per place; an edge
blocked twice is marked doubtful in the context, and an objective that keeps failing is abandoned as `unreachable`. Dialogue pages are
advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once from the page sheets. `--steps N` counts
finished objectives. `resume` rebuilds the ledger and the visited places from the trace; the flow version is `flow-2`.
