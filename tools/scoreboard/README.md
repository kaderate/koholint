# Koholint scoreboard

A scripted measurement of how far the agent gets and what it costs, kept in the repo. The goal it measures against is the eight instruments; until a run collects any, the leading indicators (key items, places seen, milestone) carry the signal. Run from the repository root; each command is one subcommand of `tools/scoreboard/scoreboard.rb`.

| command | what it does | spends |
|---|---|---|
| `ruby tools/scoreboard/scoreboard.rb measure RUN_DIR... [--json]` | the numbers below, from run folders | nothing |
| `ruby tools/scoreboard/scoreboard.rb run [--budget USD] [--from boot\|CHECKPOINT]...` | the standard daily run, appended to the history | up to `--budget` per run (default 4.00) |
| `ruby tools/scoreboard/scoreboard.rb debt [--window N] [--last N]` | the pit index | nothing |
| `ruby tools/scoreboard/scoreboard.rb alert` | exit 1 and the reasons when a guardrail trips | nothing |

`measure`, `debt` and `alert` read run folders under `--runs-root` (repeatable, globs allowed; default `~/.capy/work/atlas-root` and `~/.capy/work/runs/*`). They need no ROM, no emulator and no model. `test/scoreboard_test.rb` needs none either.

## measure

Per run, from `trace.jsonl` and `manifest.json` (and `summary.json` when it records instruments):

- **progress vector** (the whole run, inherited prefix included): `instruments` 0-8 (null: the engine records none yet), `dungeons` entered (null: `data/place_kinds.json` lists no dungeon map yet), `key_items` held at the end (id and name from `data/items.json`; a `?` marks a name not verified), `places_seen`, `highest_milestone`.
- **cost** (the run's own segment, frames from its fork frame on): `usd`, model `calls`, `calls_per_1000f`, `calls_at_one_heart` (8 hp or less).
- `deaths_per_1000f`, `new_places` (new to the run's own prefix) and `new_places_per_usd`.
- `stalls`: spans of 4000 frames or more with no new place, and the longest span.
- `rules`: how many decisions each harness rule family answered, by the decision's justification (`Measure::FAMILIES`; plain engine mechanics and the model's own choices are not counted).

## run

Plays `--from boot` (default) and any `--from CHECKPOINT` of `data/checkpoints.json` (repeatable; a checkpoint is forked from its run, found under the runs roots, then resumed). Every run gets `--max-dollars` of `--budget`, plays under `~/.capy/work/runs/scoreboard/` and runs with at most 2 emulator processes. A supervisor reads each trace as it grows and stops the run cleanly (SIGINT, as Ctrl-C) on 3 deaths (`--max-deaths`), on 4000 frames with no new place (`--stall`) or after 4 hours of wall time (`--max-seconds`), the rules of the held-out runs' supervisor. It appends one JSON line to `~/.capy/work/scoreboard/history.jsonl` (`--history FILE`; not the drive, not the repo): the date, flow, harness sha, decision-layer branch conditions, total dollars, the primary run's vector and rates, and every run's full measure. It spends real money: set `--budget` on purpose, and never above the day's allowance.

## debt

The pit index of the independent evaluation (KOHO-148), computed from git and the runs on disk: decision-layer branch conditions and their growth over the last `--window` flow versions (default 10, on `--ref`, default `origin/main`); the first gains of the paid runs of the window and the branch conditions added per gain; flow versions since the last paid run from boot; distinct fork points of the paid runs; new places per paid dollar; the rework rate (the share of function edits of the window that follow an earlier edit of the window); and the rule families that fired in none of the last `--last` scoreboard runs (empty until `run` has written the history). The alarm is branch conditions up 20% with no first gain in the window.

## alert

Exit 1, with a line per reason, when:

- the paid runs started today (run ids dated today) cost more than 20 USD;
- a paid run of today has `harness_dirty`;
- `deaths_per_1000f` or `calls_per_1000f` of the primary run rose more than 50% against the previous scoreboard line;
- branch conditions rose 20% over two batches while no component of the primary run's progress vector gained.

A run's own cost comes from its trace: a fork's `summary.json` dollars include its parent's.
