# Operating Koholint

Command reference for running, resuming and forking runs, the offline censuses, the viewer and run storage. For a first run see the [README](../README.md); for the agent-side skills see [AGENT_SKILLS.md](AGENT_SKILLS.md).

## Tests

`rake test` runs one process per file (ROM-heavy files one process per test, about 4 min on a busy Mac; the first run builds an emulator state cache in `tmp/`); `rake test:fast` skips the ROM-heavy files listed in `HEAVY` in the Rakefile (about 25 s with a warm cache, 110 s of CPU cold); every run counts what each file costs alone on a cold cache, in frames: the frames its processes and their Ruby subprocesses emulate, plus the frame depth of each distinct state the emulator cache hands it (once per process, hit or miss; building the state is not counted), so the count is the same cold or warm and whatever process built a state first; it fails when a file outside `HEAVY` counts more than `HEAVY_FRAMES` (6000, the heaviest light file counts 4245), so a test that replays a long journal goes into `HEAVY` instead of slowing `test:fast`; `rake test:ci` runs every file with the ROM hidden, so ROM tests skip (about 25 s). `SHARD=i/n rake test` runs every n-th job only, starting at the i-th. `bin/generate_start_fixture` regenerates `test/fixtures/start_game.expected.json` (read by `test/perception_test.rb`) after a boot script or perception change.

GitHub Actions (`.github/workflows/ci.yml`) runs `rake test:ci` on every pull request and push to `main`, and the whole suite with the ROM in 4 shards (`rom`, frame guard included), so nobody runs the full `rake test` on the Mac before a merge; locally, `rake test:fast` and targeted files are enough. Pull requests from forks get no secrets and run `test:ci` only. The shards keep only `tmp/test_times.json` in the Actions cache, so each run splits the jobs by their last durations; the rest of `tmp/` (emulator states derived from the ROM) is never cached. emu-gb is checked out from `kaderate/gemboy` at the commit pinned in `ci.yml` and `learn.yml` (bump both to take a new emu-gb), and third-party actions are pinned to commit SHAs.

### ROM in CI

The ROM is never in a repository. CI downloads `zelda_dx_rev1.gbc.age`, the ROM encrypted with age to an X25519 recipient, from the direct link in the Actions secret `ROM_URL`, decrypts it with the identity in the secret `ROM_AGE_KEY` into the runner's temp dir, checks it against `ROM_SHA256` and exports `KOHOLINT_ROM` (`.github/actions/rom`). `.github/actions/rom/rom.env` holds `ROM_SHA256` (the `rom_sha256` of the committed run manifests) and `ROM_CACHE_VERSION`. Only the ciphertext is kept in the Actions cache (key `rom-age-<sha>-v<ROM_CACHE_VERSION>`): the `fetch ROM` job downloads it on a cache miss and saves it only once it has decrypted and checked it, and the shards decrypt from the cache. Pushes to `main` keep the cache warm. A missing secret, a share page instead of a file, a wrong key or a wrong file each fail with their own message.

`bin/fetch_asset URL OUT` does the download: it follows redirects, retries network errors and server errors three times, and refuses web pages and empty answers; it prints the host, never the URL. `ROM_URL` must be a direct download link that needs no login, such as a Dropbox link ending in `dl=1`; a gofile.io `/d/` share page cannot be fetched by a script (its download token comes from gofile's browser code, and gofile's download API needs a premium account).

To re-encrypt (new key or new file): `age-keygen -o key.txt`, `age -r <public key> -o zelda_dx_rev1.gbc.age zelda_dx_rev1.gbc`, upload the file, put its link in `ROM_URL` and the identity line of `key.txt` in `ROM_AGE_KEY`, then bump `ROM_CACHE_VERSION`: a cache entry cannot be overwritten, so without the bump CI keeps decrypting the old ciphertext with the new key and fails.

`.github/workflows/rom-keepalive.yml` downloads and checks the file every Monday (and on demand). It is only needed when `ROM_URL` points at a host that deletes idle files (a free gofile file goes after about 10 days without a download, and CI rarely downloads thanks to the cache); with a permanent link it only tells early that the link died. It does not refresh the cache, which GitHub evicts after 7 days without use.

`.github/workflows/learn.yml` runs `koholint learn` on demand (Actions → learn → Run workflow): `run_url` is a direct link to a `.tar.gz` of one full run directory (`trace.jsonl`, `inputs.log`, `manifest.json`, `save/`; `tar -czf run.tar.gz -C runs <run id>`), with `limit` and `object` as in the command. It uploads `data/capabilities.json` and the log as an artifact, to be committed by hand. Expect about twice the Mac's time (about 1 h 45 for `--limit 10` on `0c64`).

## Running

**Budgets.** `run`/`resume` accept `--frames N`, `--minutes N`, `--dollars X` (or `--max-dollars X`, default 1.5 with
`--agent`) and `--steps N` (finished objectives, only meaningful with `--agent`). Ctrl-C stops cleanly and cancels an
in-flight agent call. A run that hits the Claude subscription session limit stops as `agent_failures`; five
consecutive fallbacks stop a run the same way. An exception in the engine's own code before the agent is called is a free
fallback marked `engine_error` (class, message and origin in the justification); five in a row stop the run as `engine_errors`.

**Agent.** `--agent` uses `claude -p` (`--model`, default `sonnet`; `--claude-command PATH`, else `CLAUDE_COMMAND` from the environment or `.env`, else `claude` on `PATH`). The engine writes what the
agent saw to `runs/<id>/prompts/<frame>-<decision_point>.txt` (and `.png` when an image was sent; gitignored, not part
of replay); the `decision` trace event carries its `prompt_sha`. `--tag NAME` labels a run.

**Autopilot.** `--autopilot on|off` (default `on`, agent runs only) is recorded in the manifest (`autopilot`); `resume`
keeps the recorded value and refuses a different one. With it on, an `explore` that stops at a new place, a known place, at its frame
budget or near an object never tried (`untried_object`) is followed by another `explore` with no direction that the harness issues itself (agent `delegated`, cost 0, the
`decision` event carries `autopilot: true`); the model decides again on any other stop or action, after a new lead or goal,
outside free play, after damage, when the objective changes or is not `new_place`, `leave_place` or `new_text`, and after
6 such explores or 2400 frames since its last call. When such a chain reaches a place and achieves its objective, the harness also
starts the next objective itself (`new_place`, "Explore the nearest untried exits", `autopilot: true` on the `objective` and
`decision` events) instead of a paid `choose_objective`, under the same caps, as long as this place or a place routed to has untried exits and (flow-52) no person on screen was never tried.
An objective picked from the candidate menu (see [AGENT_SKILLS.md](AGENT_SKILLS.md)) is followed the same way: `explore` towards its exit, door or place, or one
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
(see Run storage). `branch <run_dir> --at FRAME|CHECKPOINT` forks, starts `watch` on the child (`--port`, `--host`,
`--speed`) and resumes it with the `resume` options (`--agent`, budgets) in one command, then stops the viewer and exits;
`--keep-viewer` keeps it serving after the stop until Ctrl-C (if it could not start, for example on a busy port, `branch` says so and still plays). A checkpoint is a name from `data/checkpoints.json` (`name`, `run`, `frame`, `flow`, `source`),
checked against the run id and its flow, e.g. `bin/koholint branch runs/20261111-194737-9ba1 --at sword-obtained --frames 3000`.

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

Every finished run is kept in git as a light bundle under `runs/<id>/` (tens to a few hundred KB): `manifest.json` (with `tag`,
`harness_sha`, `prompts_sha`, `model`), `inputs.log`, `trace.jsonl.gz`, `world.json`, `suggestions.md`, `summary.json`
(written by the engine at every stop), `star.json` when starred and `notes.md` when the owner wrote notes in the viewer, and `screens/<room>-<map>.png` (one 160x144 screenshot per place, about 3-8 KB each, taken by the engine 20 frames after the place became playable and ready). `bin/koholint screens <run_dir>` writes the missing ones for an older run by replaying its journal from boot (about one minute per 6000 frames; idempotent). `prune-heavy` keeps `screens/`. `summary.json` (`v: 3`) also holds `cost_by_skill`
(model calls and dollars per skill), `decisions_by_agent` (free decisions included) and `usage` (goal changes, leads
by importance, rejected leads, objectives by kind, `because` uses, talks, talks to a known target, dialogues, `not_ready_frames` waited by the readiness gate, `not_ready_waits` longer than 5 frames, `autopilot_decisions` and `chain_max`, the longest run of consecutive autopilot decisions); `v: 4` adds `autopilot` from the manifest; `v: 5` adds `usage.left_with_unexhausted_people` (place changes away from a place whose place card listed a verified person whose last talk verdict was not `exhausted`) and the matching `symptoms` entry with its evidence (`frame`, `place`, `people`). `v: 6` adds `usage.deaths` and `usage.damage_events` (counts of those notables); `v: 7` adds `usage.stuck_events`. `prompts/`, `keyframes/`, `save/`, `video/`,
`activity.json`, `run.lock` and the plain `trace.jsonl` are gitignored: saves and keyframes are derivable by replay.

| Command | Effect |
|---|---|
| `archive [--from DIR] [--root DIR] [--commit] [--full]` | Imports finished runs from `--from` (light bundle only, refreshed when the source changed, e.g. after a resume or a star; the source is never modified), gzips the trace, writes a missing or outdated (`v` below the current version) `summary.json`, regenerates `docs/runs/index.md`. `--commit` makes one commit (`Archive runs A..B`); `--full` also force-adds `prompts/`. Idempotent. Runs without a final `stop` event or with a live lock are skipped |
| `star <run_dir> "why"` | Marks a run worth keeping (`star.json`, `summary.json` `starred`); `prune-heavy` never deletes a starred run. Run `archive --commit` afterwards to record it in git |
| `check-leads <run_dir>...` | Validator over the `lead` events of each run (`lead_check.rb`): lists every lead whose claim or `where` names a catalogued item (`data/items.json`, name or `aliases`) that no text read so far (dialogue texts and the lead's quote) names and that Link did not hold by then (A, B, inventory, or the item's milestone), i.e. a name taken from general knowledge of the game; exits 1 when it finds any. `test/lead_check_test.rb` runs it on the committed bundle `runs/20261111-194737-9ba1` |
| `prune-heavy [--keep N] [--yes]` | Deletes `prompts/` and `keyframes/` of unstarred runs older than the N most recent (default 5); without `--yes` it only lists them |

`resume` and `fork` on an archived run decompress the trace back to `trace.jsonl` (archive again after the stop);
`fork` rebuilds missing saves by replay, checked against their `sav_sha256`.
