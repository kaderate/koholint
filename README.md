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

Tests: `rake test` (one process per file, ROM-heavy files one process per test, about 2 min; the first run builds an emulator state cache in `tmp/`); `rake test:fast` skips the ROM-heavy files (about 25 s);
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
`screens <run_dir>`, `watch <run_dir>`, `archive`, `star <run_dir> WHY`, `prune-heavy`, `census boot|<run_dir> FRAME...|entities <run_dir> FRAME...|ready <run_dir>`,
`npcs [--root DIR]`, `ab-plan <run_dir> --at-frame N`, `ab-report PREFIX`.

## Running

**Budgets.** `run`/`resume` accept `--frames N`, `--minutes N`, `--dollars X` (or `--max-dollars X`, default 1.5 with
`--agent`) and `--steps N` (finished objectives, only meaningful with `--agent`). Ctrl-C stops cleanly and cancels an
in-flight agent call. A run that hits the Claude subscription session limit stops as `agent_failures`; five
consecutive fallbacks stop a run the same way. An exception in the engine's own code before the agent is called is a free
fallback marked `engine_error` (class, message and origin in the justification); five in a row stop the run as `engine_errors`.

**Agent.** `--agent` uses `claude -p` (`--model`, default `sonnet`; `--claude-command PATH`). The engine writes what the
agent saw to `runs/<id>/prompts/<frame>-<decision_point>.txt` (and `.png` when an image was sent; gitignored, not part
of replay); the `decision` trace event carries its `prompt_sha`. `--tag NAME` labels a run.

**Autopilot.** `--autopilot on|off` (default `on`, agent runs only) is recorded in the manifest (`autopilot`); `resume`
keeps the recorded value and refuses a different one. With it on, an `explore` that stops at a new place, a known place, at its frame
budget or near an object never tried (`untried_object`) is followed by another `explore` with no direction that the harness issues itself (agent `delegated`, cost 0, the
`decision` event carries `autopilot: true`); the model decides again on any other stop or action, after a new lead or goal,
outside free play, after damage, at low health (a third of max hp or less), after damage with a creature within 3 cells, when the objective changes or is not `new_place`, `leave_place` or `new_text`, and after
6 such explores or 2400 frames since its last call. When such a chain reaches a place and achieves its objective, the harness also
starts the next objective itself (`new_place`, "Explore the nearest untried exits", `autopilot: true` on the `objective` and
`decision` events) instead of a paid `choose_objective`, under the same caps, as long as this place or a place routed to has untried exits.
An objective picked from the candidate menu (see Agent skills) is followed the same way: `explore` towards its exit, door or place, or one
`talk_to` of the person or sign here. Results chosen this way are marked `(autopilot)` in the model's context.

**A/B.** `ab-plan <run_dir> --at-frame N [--arms autopilot,off] [--forks 3] [--max-dollars 0.8] [--frames 3000] [--tag ab]
[--root tmp/ab/runs] [--model M]` checks the frame and writes `tmp/ab/plan.json` and `tmp/ab/run.sh`, the `fork` and
`resume --agent` commands of every arm and fork (tags `<tag>-<arm>-<k>`), and prints the script; it runs nothing.
`ab-report PREFIX [--root DIR]` reads the runs tagged `PREFIX-<arm>-<k>` and prints a table per arm measured from the fork
frame on (cost, paid calls, new places and new cells per 1000 frames, stalls: explore `stalled` stops and objectives
abandoned for stall or loop, autopilot decisions) with the pre-registered criterion: autopilot cost per 1000 frames at
most 50 % of `off` with places per 1000 frames at least 90 % of `off`.

**Pacing.** `--realtime` paces the engine at about 60 fps of wall time so the viewer can keep up; it never changes the
journal or the game state.

**Collision grid.** `--grid` reads the screen at each observation and probes unknown neighbour cells by walking. The
trace gains `screen` and `screen_changed`, `affordance` (walk evidence per tile appearance), `grid_contradiction`
(Link entered a cell believed blocked) and a `notable` of kind `grid_overlay_stuck` (over 600 frames of overlay in one
place, so the grid went dark). The live view has a grid toggle that overlays the believed passability.

**Resume and fork.** `resume` continues a run with the same `flow_version` and ROM hash and rebuilds the ledger and
visited places from the trace; `fork` branches a run at a frame (the parent may be of an older flow; `--tag`, `--autopilot` and `--root` set the child's). Both work on an archived run, also on a fresh clone
(see Run storage).

## Agent skills (`flow-23`)

- Between decisions the engine waits, with no input, until Link is ready (no screen scroll, door walk, jump or
  knockback, then 2 settled frames): the screen is never mapped and the model never called mid-scroll or mid-jump
  (`notable` `not_ready_wait` for waits over 5 frames; the run stops with `not_ready_stuck` after 600 frames).
- `explore [direction]` (relaunched by the autopilot after benign stops, see Running) explores by itself: it walks to the nearest
  untried border exit (a side never left from this place) or untried door (walking up into it), else toward the nearest
  place it has taken an exit to that still has untried exits or doors, else to the nearest frontier (a known cell next to
  an unknown one) (`direction` prefers that side), steps out, re-plans, and returns to the model only at an event:
  `new_place`, `known_place` (a return to a place already seen), `dialogue`, `untried_object` (once per thing never talked to within 3 cells), `blocked`, `stalled` (3
  attempts in a row walked no new cell), `no_frontier` (with the exits already tried), `locked`, `damage` or `budget` (600 frames). What it walked, the walls it found, the
  exits it tried and the things it offered are kept per place and rebuilt from the trace on resume.
- `goto row col` walks to a cell of the known grid by a shortest path with the fewest turns (stops `done`, `blocked`,
  `no_path`, ...; a result carries `blocked_at` when a move hit a wall); `step direction pixels` moves a few pixels;
  `talk_to row col` walks next to a person, faces them and presses A, trying other sides on no response; the person is
  the entity at or next to the cell, followed when it walks away, and may cover several cells.
- A ledger counts blocked edges per place; an edge blocked twice is marked doubtful in the context, and an objective
  that keeps failing is abandoned as `unreachable`.
- Dialogue pages are advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once
  from page sheets.
- The agent writes a one-line `plan` that the next call sees; the live view shows its reasoning and plan under each
  decision.
- The agent sets its own long-term `goal`, restates or revises it at every objective (the context says when it was set) and, in the call that transcribes a text (dialogue, sign, object), extracts up
  to five leads (`quote`, `claim`, importance `high|normal|low|tip`, `tip` for how-to-play advice); a lead whose quote is not in that transcription is
  dropped. Both are trace events (`goal`, `lead`), shown in the context and the live view and written to `world.json`;
  an objective can cite the lead behind it (`because`). A lead may carry `where` (a place id such as `161-0` or a name the agent gave).
- At `choose_objective` the context lists candidate objectives with ids (`candidates.rb`): untried exits by side (`exit-up`) and doors
  (`door-R-C`) of this place, people (`person-tT`, listed first) and unread signs (`sign-R-C`) here worth a visit, known places with untried exits
  (`place-R-M`), people and unread signs of other known places (from their place cards) and places tied to a lead by its `where`
  (`lead-N`), nearest first by moves over exits explore took. The agent answers with `candidate` (or still a free title and predicate);
  the objective event carries `candidate` and its `target`, which the autopilot follows. While a person here is not
  exhausted, every candidate that leaves the place says `leaves unexhausted people here: ...`.
- The agent may name the current place (`place_name`, any call): a `place_name` trace event, shown in the context header,
  `world.json` `places` (`name`) and the viewer's map.
- Screens are modes of the catalogue `data/modes.json`: the context names the open screen, how to leave it, its inputs,
  cursor and options, and offers only the skills that work there. `open_menu`/`close_menu` (START), `menu_move slot`
  (inventory cursor 0-9), `menu_assign a|b` (swap the selected item with that button's item), `open_map`/`close_map`
  (SELECT, B), `choose_option option` (save and game-over screens); used elsewhere they stop with `wrong_mode`. An
  uncatalogued screen gets `press` and `wait` and a `notable` `unknown_mode` in the trace; 600 frames on it stop the
  run as `unknown_mode_stuck`. Options that quit to the title are refused. The game-over screen is answered by the harness, free: it
  continues with the first option that does not quit (`notable` `death`); a health drop emits a `notable` `damage` and
  the next prompt's health line shows the hearts lost since the last model call. At a third of max hp or less a `LOW HEALTH`
  line names the nearest known interior and a `shelter-<room>-<map>` candidate comes first; six fruitless results in one
  place without a new cell emit a `notable` `stuck` and a `STUCK` reset hint.
- The context header lists the items on A and B and in the inventory slots (`data/items.json` names; a `?` marks a name
  not measured yet). `use_item item [button] [frames]` uses a held item (assigning it through the START menu to `button`,
  default B, when it is on no button); `guard frames [direction]` raises the shield (Link walks at full speed and turns
  while guarding). A new item emits `item_gained` in the trace.
- Scrolling dialogue pages are stitched into one text; the context remembers what each person said and whether talking
  again is worth it; `new_text` is an objective predicate; the live view lists the dialogues read.
- People on screen come from the game's entity table in RAM (`entities.rb`): the context lists each entity with its cell,
  type id and measured kind (`data/entities.json`), sprites without an entity as a fallback, and the names people gave
  (`speaker`, asked in the transcription call); creatures (measured to give no dialogue) and unidentified entities are
  listed apart for information and are never offered as people to talk to. People are remembered by (place, entity type), so a person who moved
  keeps their memory.
- On arrival in a place, before the model is called, people and signs are engaged deterministically (`revisit.rb`, no
  model call to decide it): when a verified `npc` of the current place is not exhausted for the current world stamp
  (milestone, items held, number of high and normal leads; a place visited does not count) or a verified sign was never read, the policy issues `talk_to` itself (agent `delegated`,
  cost 0), lets the pages advance, and repeats until two conversations in a row are identical or give nothing new (a sign is read once), at
  most 6 rounds per person, 2 per sign, 1800 frames of free play per stamp and 2700 per visit (frames spent in
  dialogue pages or locked are not counted, so long dialogues never cut it short), 3 stamps per visit (counted by milestone and items, not leads), or 2 failed
  talks per visit; while one is due it replaces any choice, so no exit (model, autopilot, harness objective) happens first; never when hurt, hemmed, or near a hostile or moving unknown entity (a measured `creature` that gives no dialogue does not count); each round is
  a `notable` `revisit` event (`{npc|sign, round, outcome}`). Each new place also gets a `place_card` (people, enemies,
  creatures, signs, objects, exits) kept in `world.json` `places`. A conversation is identified by a signature of its pages' text pixels; a conversation
  already read is not sent to the model again (its stored text is reused, `dialogue` events with `cached: true`).

## Mode census

`bin/koholint census <run_dir> FRAME...` replays the run's journal to each frame (states cached in `tmp/census/states/`)
and, on throwaway copies, records every change of the mode tuple, a few watched bytes and a screen hash while it opens
and drives the inventory, the map, the save screen and the game-over screen (reached by draining health with a RAM write
in the copy only), and diffs RAM while moving their cursors. `census boot` records the boot modes idle and with a late
START. Reports are written to `tmp/census/*.json` and feed `data/modes.json` and `data/addresses.json` (two different
start states for `verified`).

## Entity census

`bin/koholint census entities <run_dir> FRAME...` replays the journal to each frame and, for every active slot of the
entity table, records its position, type and matching sprites, then in throwaway copies (RAM writes in the copy only):
places Link next to it on each side and presses A, with a control copy where the slot is cleared (a dialogue that also
opens in the control is not the entity's); pins Link on it for 90 frames and compares health with the control; watches
whether it moves; and talks to it twice and at a shifted frame to compare conversation signatures. Reports go to
`tmp/entities/*.json` and feed `data/entities.json` (kinds) and `data/addresses.json`.

## Object census

`bin/koholint census objects <run_dir> FRAME... [--crawl N]` replays the journal to each frame and reads the room object
table (one id per cell); in throwaway copies with every entity slot cleared it puts Link next to each cell, faces it by
walking and presses A, with a control copy without A. A cell whose dialogue opens only with A is readable; its first
page is saved under `tmp/objects/pages/`. Each object id is sampled 6 times unless it answered. `--crawl N` first crosses
screen edges in copies to reach N screens of the same map. Reports go to `tmp/objects/*.json` and feed the `object`
entries of `data/entities.json` (kind `sign` or `object`).

## Readiness census

`bin/koholint census ready <run_dir>` replays the whole journal frame by frame and writes `tmp/census/readiness-<run>.json`:
every span of play where Link is not ready (screen scroll, door, jump, knockback, forced walk) with its length and the
frames after it until the BG tile indices stop changing, the durations per kind, and the bytes of 0xC100-0xC1FF and
0xFF80-0xFFBF that are at rest in still play yet move in every screen change (how `room_transition` was found). It
feeds `data/addresses.json` and the `ready` of the `play` mode in `data/modes.json`. About 4 minutes per 25,000 frames.

## NPC catalogue

`bin/koholint npcs [--root DIR]` prints a markdown table of the people of all runs under `DIR` (default `runs`): per
place and person (entity type, or talk_to cell for older runs, or texts that opened by themselves), the names given, the
number of talks and of runs, and the distinct texts read with the milestone when each first appeared and in how many
runs. It writes nothing.

## Live view

`bin/koholint watch <run_dir> [--port N] [--host H] [--from live|start] [--speed X] [--runs-root DIR]` prints
`watching http://127.0.0.1:PORT` and serves the run as video, status and feed from a read-only replay. It works on a
finished run or one being written; Ctrl-C stops it. It listens on 127.0.0.1 only; `--host 0.0.0.0` opens it to other
devices on the same network (no authentication: use it on a network you trust).

Every page has the same top bar (Live, Runs, Compare once two runs are picked on `/runs`, the current run, a replay badge).
The live page and a replay share one layout, in equal columns on a desktop and one column on a phone: the game screen
with the mode badge (phase and mode name from the last perception; `unknown_mode` notables and `stuck_boot` or
`unknown_mode_stuck` stops raise a red alert), the activity banner and the grid toggle; the objective, goal and plan; the
reasoning and the event feed; the leads; the dialogues (with the person's state when the text came from a `talk_to`:
which talk it was, new text or not, and for the latest one exhausted or worth retrying); budget and agent stats
(cumulative dollars by frame, the previous run's curve in grey, cost split by skill, decisions paid and free and the
`summary.json` usage counters); a timeline of the whole run (places, objectives, agent calls coloured by skill,
dialogues, leads, explore stops, notables, stop; clustered past 300 markers; a click seeks a replay, or scrolls the
feed live); the world map of the places seen up to the shown frame (overworld screens on the 16-wide `room_id` grid,
interiors and other places in a lane below, under the overworld screen they were entered from, kinds from
`data/place_kinds.json`; visit order, exits taken, the current place, known cells, people and leads; a click shows
that place's belief grid, and its screenshot at 3x with a checkbox that overlays the belief grid; places with a screenshot show it as their node); and, folded at the bottom, the run header with a
notes box. The map, timeline and stats are derived from the trace and cached by the shown frame.

### Past runs

`watch` also explores the runs under `--runs-root DIR` (default: the watched run's parent directory when it holds other
runs, else `runs`). Routes besides `/`, `/frame.png` and `/state.json` (each JSON route takes `?run=<id>` for a past
run and serves the watched run without it):

| Route | What it does |
|---|---|
| `/runs`, `/runs.json` | Table of runs with a `summary.json`: sort by column; filter by minimum milestone, maximum dollars, tag, starred only; `$/call` and `free` (decisions not made by Claude); pick two runs to compare |
| `/run/<id>` | The live page as a read-only replay of that run, from boot; `/frame.png?run=<id>` and `/state.json?run=<id>` serve it |
| `/control?run=<id>&speed=1\|4\|16`, `&pause=0\|1` and `&seek=<frame>` | Drive a replay; `seek` restores the nearest keyframe at or before the frame (or replays from boot) and steps to it |
| `/screens/<room>-<map>.png[?run=<id>]` | The screenshot taken the first time the run played that place (`runs/<id>/screens/`; 404 when missing; cached 30 s) |
| `/map.json`, `/timeline.json`, `/stats.json`, `/cockpit.json`, `/header.json` | World map, run timeline, cost series and usage (with `reference`, the previous run's cost series), the cockpit data of the page (KPIs, health, HUD, objective and offered candidates, reasoning, symptoms, place card, interiors, leads, dialogues by person), run header and notes |
| `/compare/<a>/<b>`, `/compare.json?a=&b=` | Summaries, usage and cost by skill side by side with differing fields marked, and the first frame at which each run reached each milestone and place |
| `POST /star?run=<id>` (form body `why=...`) | Same as `bin/koholint star`; the `Host` header must name the viewer itself and an `Origin` header, if sent, must match |
| `POST /notes?run=<id>` (form body `text=...`) | Writes `runs/<id>/notes.md` (at most 8 KB, no control characters but newlines and tabs; empty text deletes it), same origin check; only for runs under the runs root |

At most 3 replays are kept (least recently used evicted, idle ones dropped after 5 minutes). An evicted replay answers
410 until its page is reloaded; a run that cannot be replayed answers 404 or 422. Run ids are plain names directly
under the runs root (`[A-Za-z0-9_.-]`, no leading dot, no `..`); anything else is a 404.

## Run storage

Every finished run is kept in git as a light bundle under `runs/<id>/` (about 60 KB): `manifest.json` (with `tag`,
`harness_sha`, `prompts_sha`, `model`), `inputs.log`, `trace.jsonl.gz`, `world.json`, `suggestions.md`, `summary.json`
(written by the engine at every stop), `star.json` when starred and `notes.md` when the owner wrote notes in the viewer, and `screens/<room>-<map>.png` (one 160x144 screenshot per place, about 3-8 KB each, taken by the engine 20 frames after the place became playable and ready). `bin/koholint screens <run_dir>` writes the missing ones for an older run by replaying its journal from boot (about one minute per 6000 frames; idempotent). `prune-heavy` keeps `screens/`. `summary.json` (`v: 3`) also holds `cost_by_skill`
(model calls and dollars per skill), `decisions_by_agent` (free decisions included) and `usage` (goal changes, leads
by importance, rejected leads, objectives by kind, `because` uses, talks, talks to a known target, dialogues, `not_ready_frames` waited by the readiness gate, `not_ready_waits` longer than 5 frames, `autopilot_decisions` and `chain_max`, the longest run of consecutive autopilot decisions); `v: 4` adds `autopilot` from the manifest; `v: 5` adds `usage.left_with_unexhausted_people` (place changes away from a place whose place card listed a verified person whose last talk verdict was not `exhausted`) and the matching `symptoms` entry with its evidence (`frame`, `place`, `people`). `v: 6` adds `usage.deaths` and `usage.damage_events` (counts of those notables); `v: 7` adds `usage.stuck_events`. `prompts/`, `keyframes/`, `save/`, `video/`,
`activity.json`, `run.lock` and the plain `trace.jsonl` are gitignored: saves and keyframes are derivable by replay.

| Command | Effect |
|---|---|
| `archive [--from DIR] [--root DIR] [--commit] [--full]` | Imports finished runs from `--from` (light bundle only, refreshed when the source changed, e.g. after a resume or a star; the source is never modified), gzips the trace, writes a missing or outdated (`v` below the current version) `summary.json`, regenerates `docs/runs/index.md`. `--commit` makes one commit (`Archive runs A..B`); `--full` also force-adds `prompts/`. Idempotent. Runs without a final `stop` event or with a live lock are skipped |
| `star <run_dir> "why"` | Marks a run worth keeping (`star.json`, `summary.json` `starred`); `prune-heavy` never deletes a starred run. Run `archive --commit` afterwards to record it in git |
| `prune-heavy [--keep N] [--yes]` | Deletes `prompts/` and `keyframes/` of unstarred runs older than the N most recent (default 5); without `--yes` it only lists them |

`resume` and `fork` on an archived run decompress the trace back to `trace.jsonl` (archive again after the stop);
`fork` rebuilds missing saves by replay, checked against their `sav_sha256`.
