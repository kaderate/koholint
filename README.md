# Koholint

A deterministic engine that plays Link's Awakening DX headless through emu-gb and calls agents
(Jev for tactical choices, Claude for strategy) at defined decision points. Each run lives in
`runs/<id>/`: manifest, trace, input journal, saves, keyframes, summary; finished runs are archived in git
as a light bundle (see Run storage) and listed in `docs/runs/index.md`.

- Architecture: `ARCHITECTURE.md` (layers, data flow, invariants); what remains: `ROADMAP.md`

- Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`
- Plans: `docs/superpowers/plans/`
- v1 (agent session driving the game): git tag `v1-archive` (its notes, screenshots and decisions were removed from the tree), analysis in `docs/RETROSPECTIVE.md`

Needs Ruby 4.0.1, an emu-gb checkout and the ROM. Copy `.env.example` to `.env` (gitignored) and set
`EMU_GB_HOME` and `KOHOLINT_ROM`; real environment variables take precedence. Tests: `rake test` (one process per file, ~2.5 min; the first run builds a local emulator
state cache in `tmp/`), `rake test:e2e` to also play the full boot from frame 0.

Live view: `bin/koholint watch runs/<id> [--port N] [--host H] [--from live|start] [--speed X] [--runs-root DIR]` prints
`watching http://127.0.0.1:PORT` and serves the run as video, status and feed from a read-only replay (works on a
finished run or one being written; Ctrl-C to stop). `run`/`resume --realtime` paces the engine at about 60 fps of
wall time so the viewer can keep up; pacing never changes the journal or the game state.
The viewer listens on 127.0.0.1 only; `--host 0.0.0.0` opens it to other devices on the same network (no
authentication: use it on a network you trust).

Past runs: `watch` also explores the runs under `--runs-root DIR` (default: the watched run's parent directory when it
holds other runs, else `runs`). Routes besides `/`, `/frame.png` and `/state.json`:

- `/runs` (table: sort by column, filter by minimum milestone, maximum dollars, tag substring, starred only; pick two
  runs to compare) and `/runs.json` (one entry per run directory with a `summary.json`).
- `/run/<id>`: the live page as a read-only replay of that run, from boot; `/frame.png?run=<id>` and
  `/state.json?run=<id>` serve it. At most 3 replays are kept (least recently used evicted, idle ones dropped after
  5 minutes); an evicted replay answers 410 until its page is reloaded, and a run that cannot be replayed answers 404
  or 422. `/control?run=<id>&speed=1|4|16` and `&pause=0|1` drive a replay.
- `/compare/<a>/<b>` and `/compare.json?a=<a>&b=<b>`: summaries side by side with the differing fields marked, and the
  first frame at which each run reached each milestone and place.
- `POST /star?run=<id>` with the form body `why=...` does what `bin/koholint star` does; the `Host` header must name the
  viewer itself and an `Origin` header, if sent, must match it.

Run ids are plain names directly under the runs root (`[A-Za-z0-9_.-]`, no leading dot, no `..`); anything else is a 404.

Collision grid: `run --grid` (engine option `grid: true`) reads the screen each observation and probes unknown neighbour
cells by walking. The trace gains `screen` and `screen_changed` (what the screen looks like), `affordance` (walk
evidence per tile appearance), `grid_contradiction` (Link entered a cell believed blocked) and a `notable` of kind
`grid_overlay_stuck` (more than 600 frames of overlay in one place, so the grid went dark). The live view has a grid
toggle that overlays the believed passability on the video.

Budgets: `run`/`resume` accept `--frames N`, `--minutes N`, `--dollars X` and `--steps N` (objectives that reach a terminal outcome;
only meaningful with `--agent`). With `--agent`, the engine also writes what the agent saw to `runs/<id>/prompts/<frame>-<decision_point>.txt`
(and `.png` when an image was sent; gitignored, not part of replay); the `decision` trace event carries its `prompt_sha`. Ctrl-C cancels an in-flight agent call.

Agent skills (`flow-3`):

- `goto row col` walks to a cell of the known grid by a shortest path with the fewest turns (stops `done`, `blocked`,
  `no_path`, ...; a result carries `blocked_at` when a move hit a wall); `step direction pixels` moves a few pixels;
  `talk_to row col` walks next to a person, faces them and presses A, trying other sides on no response.
- A ledger counts blocked edges per place; an edge blocked twice is marked doubtful in the context, and an objective
  that keeps failing is abandoned as `unreachable`.
- Dialogue pages are advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once
  from page sheets. `--steps N` counts finished objectives.
- The agent writes a one-line `plan` that the next call sees; the live view shows its reasoning and plan under each
  decision. `resume` rebuilds the ledger and the visited places from the trace.

## Run storage

Every finished run is kept in git as a light bundle under `runs/<id>/` (about 60 KB): `manifest.json` (with `tag`,
`harness_sha`, `prompts_sha`, `model`), `inputs.log`, `trace.jsonl.gz`, `world.json`, `suggestions.md`, `summary.json`
(written by the engine at every stop) and `star.json` when starred. `prompts/`, `keyframes/`, `save/`, `video/`,
`activity.json`, `run.lock` and the plain `trace.jsonl` are gitignored: saves and keyframes are derivable by replay.

- `bin/koholint run --tag NAME` labels a run.
- `bin/koholint archive [--from DIR] [--root DIR] [--commit] [--full]` imports finished runs from `--from` (copying only the
  light bundle and refreshing it when the source changed, e.g. after a resume or a star; the source is never modified),
  gzips the trace, writes a missing `summary.json` and regenerates `docs/runs/index.md` at the repository root. `--commit` makes one commit (`Archive runs A..B`); `--full` also force-adds `prompts/`. Running it
  twice changes nothing. Runs without a final `stop` event or with a live lock are skipped.
- `bin/koholint star <run_dir> "why"` marks a run worth keeping (`star.json`, `summary.json` `starred`).
- `bin/koholint prune-heavy [--keep N] [--yes]` deletes `prompts/` and `keyframes/` of unstarred runs older than the N most
  recent (default 5); without `--yes` it only lists them.

`resume` and `fork` work on an archived run, also on a fresh clone: the trace is decompressed back to `trace.jsonl`
(archive again after the stop), and `fork` rebuilds missing saves by replay (checked against their `sav_sha256`).
