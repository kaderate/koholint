# Koholint

A deterministic engine that plays Link's Awakening DX headless through emu-gb and calls agents (Claude for
strategy and dialogue, Jev for tactical choices later) only at defined decision points. Every run is stored in
`runs/<id>/`, replayable from its input journal, observable live in a browser, and bounded by time and money budgets.

Where to look: [`ARCHITECTURE.md`](ARCHITECTURE.md) (layers, data flow, invariants) · [`ROADMAP.md`](ROADMAP.md) (what
remains) · [`AGENTS.md`](AGENTS.md) (conventions) · [`docs/runs/index.md`](docs/runs/index.md) (every archived run) ·
design in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/` · v1 lives under the git tag `v1-archive`
(analysis in `docs/RETROSPECTIVE.md`).

## Setup

Needs Ruby 4.0.1, an emu-gb checkout and the ROM. Copy `.env.example` to `.env` (gitignored) and set `EMU_GB_HOME` and
`KOHOLINT_ROM`; real environment variables take precedence.

Tests: `rake test` (one process per file, about 2.5 min; the first run builds an emulator state cache in `tmp/`);
`rake test:e2e` also plays the full boot from frame 0.

## Quick start

```sh
# play with the agent, paced to real time, with the collision grid
bin/koholint run --agent --realtime --grid --max-dollars 1.5 --minutes 25 --root /tmp/koholint-live

# watch it in a browser (replays the run being written)
bin/koholint watch /tmp/koholint-live/<id> --port 8123 --from live

# afterwards: keep it in git
bin/koholint archive --from /tmp/koholint-live --commit
```

Commands: `run`, `resume <run_dir>`, `fork <run_dir> --at-frame N`, `verify <run_dir>`, `summary <run_dir>`,
`watch <run_dir>`, `archive`, `star <run_dir> WHY`, `prune-heavy`, `census boot|<run_dir> FRAME...`.

## Running

**Budgets.** `run`/`resume` accept `--frames N`, `--minutes N`, `--dollars X` (or `--max-dollars X`, default 1.5 with
`--agent`) and `--steps N` (finished objectives, only meaningful with `--agent`). Ctrl-C stops cleanly and cancels an
in-flight agent call. A run that hits the Claude subscription session limit stops as `agent_failures`; five
consecutive fallbacks stop a run the same way.

**Agent.** `--agent` uses `claude -p` (`--model`, default `sonnet`; `--claude-command PATH`). The engine writes what the
agent saw to `runs/<id>/prompts/<frame>-<decision_point>.txt` (and `.png` when an image was sent; gitignored, not part
of replay); the `decision` trace event carries its `prompt_sha`. `--tag NAME` labels a run.

**Pacing.** `--realtime` paces the engine at about 60 fps of wall time so the viewer can keep up; it never changes the
journal or the game state.

**Collision grid.** `--grid` reads the screen at each observation and probes unknown neighbour cells by walking. The
trace gains `screen` and `screen_changed`, `affordance` (walk evidence per tile appearance), `grid_contradiction`
(Link entered a cell believed blocked) and a `notable` of kind `grid_overlay_stuck` (over 600 frames of overlay in one
place, so the grid went dark). The live view has a grid toggle that overlays the believed passability.

**Resume and fork.** `resume` continues a run with the same `flow_version` and ROM hash and rebuilds the ledger and
visited places from the trace; `fork` branches a run at a frame. Both work on an archived run, also on a fresh clone
(see Run storage).

## Agent skills (`flow-9`)

- `explore [direction]` explores by itself: it walks to the nearest frontier (a known cell next to an unknown one) or
  untried border exit (`direction` prefers that side), steps out, re-plans, and returns to the model only at an event:
  `new_place`, `dialogue`, `untried_object` (once per thing never talked to within 3 cells), `blocked`, `stalled` (3
  attempts in a row walked no new cell), `no_frontier` (with the exits already tried), `locked`, `damage` or `budget` (600 frames). What it walked, the walls it found, the
  exits it tried and the things it offered are kept per place and rebuilt from the trace on resume.
- `goto row col` walks to a cell of the known grid by a shortest path with the fewest turns (stops `done`, `blocked`,
  `no_path`, ...; a result carries `blocked_at` when a move hit a wall); `step direction pixels` moves a few pixels;
  `talk_to row col` walks next to a person, faces them and presses A, trying other sides on no response.
- A ledger counts blocked edges per place; an edge blocked twice is marked doubtful in the context, and an objective
  that keeps failing is abandoned as `unreachable`.
- Dialogue pages are advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once
  from page sheets.
- The agent writes a one-line `plan` that the next call sees; the live view shows its reasoning and plan under each
  decision.
- The agent sets its own long-term `goal`, restates or revises it at every objective (the context says when it was set) and, in the call that transcribes a text (dialogue, sign, object), extracts up
  to five leads (`quote`, `claim`, importance `high|normal|low`); a lead whose quote is not in that transcription is
  dropped. Both are trace events (`goal`, `lead`), shown in the context and the live view and written to `world.json`;
  an objective can cite the lead behind it (`because`).
- Screens are modes of the catalogue `data/modes.json`: the context names the open screen, how to leave it, its inputs,
  cursor and options, and offers only the skills that work there. `open_menu`/`close_menu` (START), `menu_move slot`
  (inventory cursor 0-9), `menu_assign a|b` (swap the selected item with that button's item), `open_map`/`close_map`
  (SELECT, B), `choose_option option` (save and game-over screens); used elsewhere they stop with `wrong_mode`. An
  uncatalogued screen gets `press` and `wait` and a `notable` `unknown_mode` in the trace; 600 frames on it stop the
  run as `unknown_mode_stuck`. Options that quit to the title are refused.
- Scrolling dialogue pages are stitched into one text; the context remembers what each person said and whether talking
  again is worth it; `new_text` is an objective predicate; the live view lists the dialogues read.

## Mode census

`bin/koholint census <run_dir> FRAME...` replays the run's journal to each frame (states cached in `tmp/census/states/`)
and, on throwaway copies, records every change of the mode tuple, a few watched bytes and a screen hash while it opens
and drives the inventory, the map, the save screen and the game-over screen (reached by draining health with a RAM write
in the copy only), and diffs RAM while moving their cursors. `census boot` records the boot modes idle and with a late
START. Reports are written to `tmp/census/*.json` and feed `data/modes.json` and `data/addresses.json` (two different
start states for `verified`).

## Live view

`bin/koholint watch <run_dir> [--port N] [--host H] [--from live|start] [--speed X] [--runs-root DIR]` prints
`watching http://127.0.0.1:PORT` and serves the run as video, status and feed from a read-only replay. It works on a
finished run or one being written; Ctrl-C stops it. It listens on 127.0.0.1 only; `--host 0.0.0.0` opens it to other
devices on the same network (no authentication: use it on a network you trust).

### Past runs

`watch` also explores the runs under `--runs-root DIR` (default: the watched run's parent directory when it holds other
runs, else `runs`). Routes besides `/`, `/frame.png` and `/state.json`:

| Route | What it does |
|---|---|
| `/runs`, `/runs.json` | Table of runs with a `summary.json`: sort by column; filter by minimum milestone, maximum dollars, tag, starred only; `$/call` and `free` (decisions not made by Claude); pick two runs to compare |
| `/run/<id>` | The live page as a read-only replay of that run, from boot; `/frame.png?run=<id>` and `/state.json?run=<id>` serve it |
| `/control?run=<id>&speed=1\|4\|16` and `&pause=0\|1` | Drive a replay |
| `/compare/<a>/<b>`, `/compare.json?a=&b=` | Summaries, usage and cost by skill side by side with differing fields marked, and the first frame at which each run reached each milestone and place |
| `POST /star?run=<id>` (form body `why=...`) | Same as `bin/koholint star`; the `Host` header must name the viewer itself and an `Origin` header, if sent, must match |

At most 3 replays are kept (least recently used evicted, idle ones dropped after 5 minutes). An evicted replay answers
410 until its page is reloaded; a run that cannot be replayed answers 404 or 422. Run ids are plain names directly
under the runs root (`[A-Za-z0-9_.-]`, no leading dot, no `..`); anything else is a 404.

## Run storage

Every finished run is kept in git as a light bundle under `runs/<id>/` (about 60 KB): `manifest.json` (with `tag`,
`harness_sha`, `prompts_sha`, `model`), `inputs.log`, `trace.jsonl.gz`, `world.json`, `suggestions.md`, `summary.json`
(written by the engine at every stop) and `star.json` when starred. `summary.json` (`v: 2`) also holds `cost_by_skill`
(model calls and dollars per skill), `decisions_by_agent` (free decisions included) and `usage` (goal changes, leads
by importance, rejected leads, objectives by kind, `because` uses, talks, talks to a known target, dialogues). `prompts/`, `keyframes/`, `save/`, `video/`,
`activity.json`, `run.lock` and the plain `trace.jsonl` are gitignored: saves and keyframes are derivable by replay.

| Command | Effect |
|---|---|
| `archive [--from DIR] [--root DIR] [--commit] [--full]` | Imports finished runs from `--from` (light bundle only, refreshed when the source changed, e.g. after a resume or a star; the source is never modified), gzips the trace, writes a missing or outdated (`v` below the current version) `summary.json`, regenerates `docs/runs/index.md`. `--commit` makes one commit (`Archive runs A..B`); `--full` also force-adds `prompts/`. Idempotent. Runs without a final `stop` event or with a live lock are skipped |
| `star <run_dir> "why"` | Marks a run worth keeping (`star.json`, `summary.json` `starred`); `prune-heavy` never deletes a starred run. Run `archive --commit` afterwards to record it in git |
| `prune-heavy [--keep N] [--yes]` | Deletes `prompts/` and `keyframes/` of unstarred runs older than the N most recent (default 5); without `--yes` it only lists them |

`resume` and `fork` on an archived run decompress the trace back to `trace.jsonl` (archive again after the stop);
`fork` rebuilds missing saves by replay, checked against their `sav_sha256`.
