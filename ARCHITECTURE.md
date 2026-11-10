# Architecture

High-level map of Koholint v2. Keep it in sync with the code: change this file in the same commit as a change to
a layer, a data flow or a run artifact. The detailed design and its rationale are in
`docs/superpowers/specs/`; what remains to build is in `ROADMAP.md`; conventions are in `AGENTS.md`.

## Principle

A deterministic engine plays Link's Awakening DX through the emu-gb emulator. It calls an agent only at
**decision points** and executes what the agent chose with deterministic **skills**. The agent knows the game
manual, the genre and how the game is played (controls, menus, map, interactions), never a walkthrough: where to go is observed or read from in-game texts, and game facts are stored as typed data with provenance.
The engine owns the loop, the budgets, the files of a run and the trace; agents never touch them.

```
            ┌────────────────────────── Engine (engine.rb) ───────────────────────────┐
 emulator ─▶│ Perception ─▶ Vision (grid, beliefs) ─▶ Policy.decide(decision point) ─▶ │
 (emu-gb)   │      ▲                                        │ choice                  │
            │      │                                        ▼                         │
            │      └──────── frames ◀──── Skill execution (goto, talk_to, press…) ────┤
            └──── Run (journal, trace, keyframes, saves, summary) ◀── Budget ─────────┘
```

## Layers

**Emulator and replay** — `emulator.rb` wraps emu-gb (headless, paused between engine steps; the engine
decides when frames advance). `input_log.rb` is the append-only input journal; `replay.rb` rebuilds any
state by replaying the journal from boot; `keyframes.rb` and `canonical_save.rb` checkpoint it. The game is
deterministic, so *ROM + journal* is the whole run. Time is the frame; wall clock appears only in budgets,
pacing (`pacer.rb`) and observability.

**Perception** — `perception.rb`, `addresses.rb`, `game_state.rb`, `data/addresses.json`: a typed `GameState`
(position, room/map, HP, phase such as dialogue or locked, milestone, inventory cursor, menu option, A/B items, the 10 inventory slots, `shield_raised`) read from RAM. Every address carries
provenance and a `verified_count`; `verified` needs two independent checks. No RAM writes to gameplay state.
`items.rb` and `data/items.json` name item ids (with provenance; unmeasured names are shown with a `?`); the milestone is the best of `shield_level` and the `milestone` of the items held (`none`, `shield`, `sword`). The engine runs an `ItemWatch` on every frame and emits `item_gained` (`item`, `name`, `place`, `held`) the first time an item id appears among the held items after the first play frame (once per id per run, rebuilt from the trace on resume).
`GameState` also carries the readiness signals (`room_transition`, `link_airborne`, `link_z`, `link_knockback`,
measured by `probes/readiness_census.rb`, `bin/koholint census ready <run_dir>`). `entities.rb` reads the game's entity table (16 slots: status, type, x, y, state) into `{ slot, type, x, y, status, state,
cell, kind }` for the active slots; the kind per type id (`npc`, `enemy`, `object`, `creature`, `unknown`) comes from
`data/entities.json`, measured by `probes/entity_census.rb` (`bin/koholint census entities`): A pressed next to the
entity opens a dialogue that does not open with its slot cleared in a control copy (`npc`); contact damage against the
same control (`enemy`: types 9, 10 and 197 of the beach zone, measured with `EntityCensus.trajectory`, `motion_summary` and `hit_profile`: speed, contact gap, damage and whether the raised shield blocks it); neither, measured (`creature`: not a person, never a talk target, no danger);
an uncatalogued type is `unknown`. The engine passes `Entities.read` to the policy and
skills as the `entities` context entry. `Entities.objects` reads the room object table (`room_objects`, one id per cell)
and keeps the ids that `data/entities.json` lists with an `object` key and a kind (`sign`: shows a text when read with A,
`object`, `door`: walking up into it from the cell below enters a building) and the directions Link faced when it answered (`faces`, which restrict the standing cells of `talk_to`); it is
the `objects` context entry. `probes/object_census.rb` (`bin/koholint census objects`) measures them: in
a throwaway copy with every entity slot cleared, Link is put next to each cell, faces it by walking 6 frames and presses
A (a dialogue that also opens without A in a control copy is not the object's; the first page is saved as a PNG); each
object id is sampled 6 times unless it answered; `probes/door_census.rb` (`bin/koholint census doors`) puts Link
below up to 2 cells per object id in such a copy and walks up: an id is a door when Link walks into that cell by himself and
arrives in another place (226 at 5 house doors of map 0, 225 at one); `--crawl N` first crosses screen edges in copies to reach N screens of
the same map.

**Game modes** — `modes.rb`, `data/modes.json`: the catalogue of the game's screens (intro, file select, name entry,
loading, play, dialogue, locks, dying, game over, inventory, map, save screen). Each entry has a kind, the engine phase it
routes to, a `match` on the mode tuple (`game_mode`, `game_submode`, `dialog_state`, `motion_blocked`, `scene_state`,
`link_motion_state`, `game_over_stage`; values are an integer, a list, `nonzero` or `{"not": ...}`), an optional
`ready` (the settled submode), how to enter and leave it, its inputs, its cursor and options, and provenance
(`source`, `confidence`, `verified_count`). The validator refuses missing keys, `verified` below two checks and two
entries that match the same tuple unless one strictly refines the other (the most specific wins). `Modes.for(state)`
resolves the entry; `GameState#phase` is `boot` for anything outside play mode before the run first played, else the
entry's phase (`loading`, `playing`, `locked`, `dialogue`, `cutscene`, `menu`, `map`, `save`, `game_over`, `boot` for
the title screens) or `unknown`; the `ready` of `play` lists the readiness signals at rest (no screen scroll, not in the
air, no knockback, no door walk: `link_motion_state` not 2, 3 or 4); the engine emits a `notable` `unknown_mode` once per unknown tuple (rebuilt from the
trace on resume). `probes/mode_census.rb` (`bin/koholint census`; the probes are the only code allowed to write RAM, in throwaway copies, and are used by the CLI only) is the probe that measures them: from a replayed
state it plays scenarios on throwaway copies (START, SELECT, the four-button save combination, health drained to zero
by a RAM write in the copy only) and diffs RAM while moving cursors; reports go to `tmp/census/`.

**Readiness gate** — `readiness.rb`: in the `playing` and `loading` phases Link is ready when the `ready` signals of
the `play` mode hold for 2 consecutive frames (`Readiness::STABLE_FRAMES`: the last scroll write lands one frame after
`room_transition` clears; the census found the BG tile indices final by then after every scroll, door, jump and
knockback of run `20261024-184627-b97e`). The engine feeds it every frame it steps; at the start of each iteration,
before the perception event, the grid builder and the policy, it steps frames with no input (journalled, so replay,
verify and resume are unchanged; resume primes it with the frame before) until ready, records the wait on the
`perception` event (`not_ready_frames`) and as a diagnostic `notable` `not_ready_wait` `{frames, reason}` when over 5
frames, and stops the run with `not_ready_stuck` after 600 frames. Skills are never interrupted: one that ends mid-scroll
returns, and the next iteration waits. Other phases (boot, menu, map, save, game over, dialogue, locks, cutscenes) keep
their own handling. The grid builder only observes states whose signals are at rest; place screenshots wait for them too.
Measured: a screen scroll lasts 35-51 frames (vertical about 36, horizontal about 44), a ledge jump 20-27, a jump into a
screen change 53-66, a knockback 15-16, a door 62 (walk in, loading, walk out).

**Place cards** — `place_card.rb`: on the first ready observation in the `playing` phase of each visit of a place
(a new place since the last card; rebuilt from the trace on resume), after the grid builder, the engine scans the entity
table and the room objects and emits a `place_card` event: people (`npc` entities, verified or not), enemies, creatures, unknown
entities, signs, objects (`object` entities and room objects) with their cells, doors (room objects of kind `door`), and exits
(border cells believed walkable, by side). `world.json` `places` keeps per place the last card, the visits, the first and last card frames, the
place name the agent gave (`name`), the names and talk status of the people and whether each sign was read (from the talk log rebuilt from the trace). The
agent's context lists the doors of the screen with the cell to walk up from.

**Vision** (`vision/`) — what RAM does not give: `screen_vision` and `screen_snapshot` read the screen,
`grid_builder` probes neighbouring cells (the only place that snapshots and restores the emulator) and
builds a collision `grid`; `beliefs` and `world` accumulate per-place knowledge (observed free, blocked,
doubtful, contradicted); `capabilities` records what Link can do; `dialogue_shot` crops dialogue boxes for the
model. Unknown cells are unknown, not walls.

**Navigation and skills** — `geometry.rb` (cell grid, pixel offsets; x alignment uses the measured one-cell gap window `gap_entry`, -3..+4 px, for walk probes and the centring after a skill), `navigation/planner.rb` (shortest path Flow-24 danger and holes: the planner takes a `danger:` lambda (cells within the measured `contact_px` of `enemy` entities, `Entities.danger_cells`) and plans around them first, falling back to the plain route; a hole fall (`link_motion_state` 6, not ready for 93 frames) makes `Engine#await_ready` call `GridBuilder#note_fall`, which records a `fall` affordance (walk `no`, all directions) for the appearance of the cell Link fell from, so every hole cell of that look is impassable; the STUCK detector ignores results taken during a fall and the policy alerts on places where Link died. Flow-25 shield walk: `navigation/threat.rb` is the threat interface (position and `reach` per `enemy` entity, `within?` and `zone` take the caller's safety margin; a future combat skill lowers margins without touching navigation); `skills/shielded.rb` wraps walk, goto, explore and step in `Registry#start` and adds the shield button to every input that moves Link while a threat is within `reach` plus `shield_range` (data/geometry.json, 3 cells, hypothesis); direction is never touched, `guard` no longer takes a direction and stands still.
with the fewest turns over known cells), `skills/` (`walk`, `goto`, `step`, `talk_to`, `explore`, `press`,
`advance_dialogue`, `wait`, and the screen skills of `skills/screens.rb`: `open_menu`, `close_menu`, `menu_move`,
`menu_assign`, `open_map`, `close_map`, `choose_option`, which check the current mode from the catalogue, stop with
`wrong_mode` elsewhere and repeat a press the game ignored; and `skills/use_item.rb`: `use_item` and `guard`, which put the item on a button through those menu skills when it is on none, wait the 16 frames the game ignores A and B after the menu, then hold the button and report `raised_frames` from `shield_raised`; `refused` for an item not held) behind `skills/registry.rb`. `explore` chains goto legs by itself: it walks to the
nearest untried border exit (a side never left from this place) or untried door (it walks up from the cell below and waits,
with no input, through the walk-in and the loading); when the place has none, to the exit or door that leads, over the
places and exits it has taken (`explore_log.rb` route: breadth-first, the destination of each exit taken is recorded), to
the nearest place that still has some (or was never surveyed); only then to the nearest frontier (a known cell next to an
unknown one), except that untried exits or doors that no known path reaches yet send it to the frontier first, as does a place never surveyed before (flow-26: the first explore in a new place walks its frontier instead of leaving at once, and taking an exit also records the side of the new place it arrives by as left; flow-27, corrected in flow-29: a place change by a straight walk or step counts as an exit taken in the direction it was given; the first cut read the side from the cell the skill began on and recorded wrong edges, which sent explore to non-existent exits); flow-30: a survey from a call that left the place by a known or new place after fewer than 3 cells is provisional, so the place stays untried (and unsurveyed for the frontier-first rule) until a longer visit replaces it; flow-31: an exit records the cell it lands on, and an explore that walks no cell and finds no frontier on that cell while some place still has work marks the landing a closed pocket, which `route` no longer enters (room 192's bottom-right corner, entered from 208, led nowhere and sent explore up into it forty times); each
result's survey says whether the place still has such work (`pending`), which is what the route looks for; a place change
that does not cross the border is recorded as a door, and a step up from or into a door cell is never a frontier; it steps out, re-plans, and stops at
an event (`new_place` for a place never seen in the run, `known_place` for a return,
`dialogue`, `untried_object` once per thing never talked to nearby, `blocked`, `stalled` after 3
attempts that walked no new cell, `no_frontier`, `locked`, `budget` at 600 frames); `explore_log.rb` keeps per place the cells it walked or found walled, the exits
tried (left, or blocked twice) with their destination, the survey of each explored place (open border cells by side, doors, `pending`),
the places seen in any action and the things already offered, rebuilt from the `action` events on resume. A skill is a bounded, deterministic action with
validated parameters (the perpendicular settle of `goto` and the centring after a move give up once Link stops moving);
it reports how it stopped (`done`, `blocked`, `no_path`, `no_response`…). `ledger.rb`
counts blocked edges per place (doubtful edges), `triggers.rb` forbids inputs that re-fire a scripted event,
`talk_to` resolves the person to the entity at or next to the target cell
(an `npc`, else any non-enemy entity in that cell; never an entity type the census found mute, i.e. catalogued with a kind
other than `npc`: a target holding only such an entity stops `no_response` after one idle frame, with a cause): the cells its 16-pixel box covers by at least 4 pixels are the person
(a person between four cells is four cells), the standing cell is next to one of them, the walk re-plans when the entity
moves away (up to 6 times), Link aligns with the entity's pixel position and presses A at contact or once facing it
within the measured reach (`talk_reach` in `data/geometry.json`: 19 pixels facing up, 20 down, 15 left, 16 right), the
target is free only when the entity is gone or Link walked past it, a standing cell where Link stops out of reach
(furniture) or where the entity walks out of reach while A is pressed counts as no response, a
person who stays put wins over a walker on the same cells, and A is pressed again every 12 frames for 48 frames (the game ignores A for 24 frames after a
dialogue closes: `dialogue_cooldown`); without an entity it falls back on the grid. A catalogued room object (sign,
furniture, door) on the target cell is the target even with a sprite on or next to it (only an `npc` covering the cell
replaces it): Link presses toward it until he stops moving, since a sign answers only once he is pressed against it.
Its walk never goes up into or out of a door cell (that enters the building). `talk_log.rb` remembers which sides of a person gave no response and, per person (the entity type that `talk_to` faced when the
dialogue opened, reported in its result, else the last `talk_to` target cell), the key (letters
and digits only, as for `new_text`) of each stitched text read, its conversation signature and speaker name, and a world stamp (milestone, item ids held, count of `high` and `normal` leads; places visited do not count): the context says whether the last talk gave
new text, how many talks in a row gave nothing new, and `worth retrying` (the stamp changed or the last talk was new) or
`exhausted` (the last two talks repeated under the same stamp, by text or by signature, or both gave nothing new: a person cycling through older texts). It also keeps the page texts per
conversation signature. The listing of things on screen shows entities first (cell, type, kind, name), the sprite
objects that hold no entity as a fallback, and the signs with their reading status; `creature` and `unknown` entities are
not in it (nor among the candidates, the place card people or the revisit targets) but on a separate informational
`Creatures on screen` line.
`revisit.rb` is the deterministic revisit and arrival engagement: for the `npc` entities of a `verified` kind in the
current place that are not exhausted for the current stamp, and the `verified` `sign` room objects not read yet (a sign
is read once: a text remembered on its cell with no entity; `TalkLog#sign_status` is `never`, `tried` or `read`), it
gives the next `talk_to` (nearest target first, the same target until done, each person of a type shared by several
tried once per stamp), with caps counted in rounds and in frames of free play only (`Revisit#observe`, fed by the policy
at every iteration, adds the frames since the last state when that state was `playing`; dialogue pages and locked
scenes do not count): 2700 frames per visit of the place (`VISIT_FRAMES`, then one `visit_cap` note), 6 rounds per
person and stamp, 2 rounds per sign, 1800 frames per stamp, 3 stamps per visit (these caps key the stamp by milestone and items only, so a new lead reopens people without opening a new cycle) and 2 failed talks per target and visit (then unreachable); it never acts outside free play, with
health below the maximum minus one heart, within 300 frames of a hit, while hemmed, or with an `enemy` or a moving or
unmeasured `unknown` entity within 3 cells (a `creature` never gates it). Its talks are journaled like any decision (agent `delegated`, cost 0), are
not objective attempts and are hidden from the explore autopilot. It records one `notable` `revisit`
`{npc|sign, round, outcome}` per round.
`vision/dialogue_shot.rb` also reduces a captured page to the text pixel rows of its dialogue box; a conversation's
signature hashes the rows that are not the partial form of a longer row (pages are captured mid-typing at a phase that
varies, so raw page hashes are not stable; the signature was measured identical across phases and runs).
`dialogues.rb` groups `dialogue` events (same frame and place) into one dialogue and stitches the overlapping pages of a
scrolling text box into the full text without losing a word; the stored events stay raw.

**Decision points and policies** — `decision.rb` defines the points (`choose_objective`, `choose_skill`,
`move`, macros) with their output schema and validation. A policy answers them: `policies/delegated.rb`
(agent-driven; owns the context, plan memory, automatic dialogue pages, lock/hemmed handling, and before asking the model
the revisit of people and signs (its `prepare(context)` gets the entity and object readers before `decision_point_for`, so
the first decision of a visit or a run engages too) and the reuse of conversations already read: a dialogue closed when read (dialog state back to 0) whose signature (at least 2 full rows) is known is not sent
as sheets, its stored text is emitted again with `cached: true`; when a revisit is due it replaces the model's skill choice,
also right after a sheet reading; and the explore autopilot, `autopilot.rb`: after an `explore` that stopped with
`new_place`, `known_place` (not counted in the 6-explore chain; a third return to the same place goes back to the
model), `budget` or `untried_object`, the policy issues the next `explore` with no direction itself (agent `delegated`, cost 0,
`decision` event with `autopilot: true`), after the revisit, the hemmed wait and pending dialogue pages; the model is called again
on any other stop or action, a new lead or goal from the last call, a phase other than `playing`, health lower than at the
last call, low health (hp at most a third of max hp; only a `shelter` target is still followed), damage in the last 300 frames with a
creature, unknown or enemy entity within 3 cells, an objective that changed or whose kind is not `new_place`, `leave_place` or `new_text` (unless it has a target), and after 6 autopilot
explores or 2400 frames since the last call. An objective with a `target` (picked from the candidate menu) is followed from the first
skill decision after the model's call: `explore` with the exit's direction, or with an `aim` in the skill context (a door to enter first,
a place to route to through `ExploreLog#route(goal:)`), or one `talk_to` of a person or sign of the current place (a `new_text` target left behind is not routed back to; a door Link stands on or just below is not a candidate); a new goal
from that call does not hold it. When a chain stopped `new_place` or `known_place` and achieved the model's objective, the next
`choose_objective` is answered by the policy (`new_place`, `autopilot: true` on the objective) while the place or a routed place has
untried exits and the caps allow it. Results of autopilot decisions are marked `(autopilot)` in the context's results and attempts. Autopilot explores are objective attempts like any other (loop and stall
abandonment still apply) and leave the engine's consecutive failure and refusal counters untouched; `--autopilot off`
(manifest `autopilot`) disables it),
`policies/walk_and_talk.rb` and `start_game.rb` (deterministic baselines and the intro), `with_fallback.rb`
(an invalid answer falls back deterministically, 5 consecutive fallbacks stop the run; an engine exception before the
agent call is an `engine_error` fallback counted apart and stops as `engine_errors`). Phases come from the mode
catalogue (see Game modes): the boot script owns `boot` and `loading`; once the run has played (a `perception` in play
mode, rebuilt from the trace on resume) the screens go to the agent with their own skills only (`menu`: `menu_move`,
`menu_assign`, `close_menu`; `map`: `close_map`; `save`: `choose_option`; `unknown`: `press` and `wait`;
all with `press` and `wait`), after a deterministic wait while the screen is still opening; `cutscene` (the dying
animation included) waits like `locked`. The game-over screen is never sent to the model: the policy picks its first
catalogue option not flagged `quits` with `choose_option` (agent `delegated`, no prompt) and emits one `notable` `death`
per screen. A drop of `hp` between two observations emits a `notable` `damage` (`hp 16 -> 12`), and the next prompt's
health line adds the hearts lost (and a death) since the last model call. At low health the header adds a `LOW HEALTH` line
with the nearest known interior and `choose_objective` lists a `shelter-<room>-<map>` candidate first (target `shelter`, followed
like a place). Six `no_frontier`, `no_path`, `blocked` or `stalled` results in one place without reaching a new cell emit a
`notable` `stuck` and add a `STUCK` reset hint to the header until Link reaches a new cell or leaves. The play skill set has no screen-only skill. The engine stops the run with
`stuck_boot` when the boot script decides for over 900 consecutive frames in a non-play mode past boot, or 3600 in any case. It stops
with `unknown_mode_stuck` after 600 consecutive frames on an uncatalogued screen, and with `not_ready_stuck` after 600
frames waited for readiness. `choose_option` refuses (`refused`) the
catalogue options flagged `quits` (save and quit to the title), and the context lists only the other options.

**Candidates** — `candidates.rb` builds the `choose_objective` menu: people here first (`npc`, status never/new/changed/repeat),
unread signs here, untried exits by side and untried doors of the place (every candidate that leaves the place is labelled
`leaves unexhausted people here` while such a person is listed), known places with untried exits, people (never/new) and unread signs of
other places from their last place card (`PlaceCard.latest`, kept current by the policy), and places a lead's `where` resolves to (a
place id or a place name); remote ones are nearest first by `ExploreLog#hops`, 4 per kind. Each candidate carries an id, a label, a
title, a predicate and a `target` (`exit`, `door`, `person`, `sign`, `place`, `lead`); an unknown id is a refusal. Place names (`place_name`
events) live in `leads.rb` with the leads and resolve `where`.

**Objectives** — `objectives.rb`: a short goal with a predicate the harness checks from memory
(`leave_place`, `reach_place`, `reach_cell`, `dialogue_closed`, `new_place`, `new_text`: a text not read before in
the run, compared whitespace-insensitively on the stitched text, the read texts rebuilt from `dialogue` events on resume); the engine emits started and
achieved/abandoned/failed events; a `started` event may carry `because`, the id of the lead that motivated it, `candidate` and `target`, and `autopilot`. The
long-term direction is the agent's own `goal` (a short text it restates or revises at every objective; the context shows
when it was set). `leads.rb` holds the leads: claims the
agent extracts from texts it read (dialogue, signs, objects), each with a verbatim `quote`, a `claim` and an importance
(`high`, `normal`, `low`, or `tip` for how-to-play advice; the context shows all high leads, the normal ones of the
place and the 4 newest tips). A lead whose quote is not in the transcription of the same call is dropped (`notable`
`lead_rejected`), duplicates are dropped by quote. Goal and leads are rebuilt from the `goal` and `lead` trace events on
resume.

**Agents** (`agents/`) — `context.rb` renders state for the model (grid map, neighbours, entities and objects on screen, people's names,
goal, leads — every `high` one, `normal` ones of the current place, never `low` ones —, recent results, plan), `prompts.rb` holds the system prompts, `claude_cli.rb` calls `claude -p` with a JSON
schema and reports cost and latency. Jev (tactical choices) is planned, not wired.

**Run storage** — `run.rb`: `runs/<id>/` with `manifest.json` (flow version, ROM hash, tag, harness/prompts
sha, model, `autopilot` for agent runs; `resume` keeps it), `inputs.log`, `trace.jsonl` (events validated by `trace.rb`), `keyframes/`, `save/`, `prompts/`, `screens/` (one PNG per place, written by `place_shots.rb`:
observability only, no trace event, the set of captured places is rebuilt from the directory; `screens <run_dir>` backfills older runs by replay),
`world.json` (`{ goal, leads, places }`, rewritten from the trace at every stop), `summary.json` (written at every stop by
`summary.rb` from the trace only, versioned by `Summary::VERSION`: totals, cost by skill, decisions by agent and
feature usage, with `autopilot_decisions`, `chain_max`, `deaths`, `damage_events` and `stuck_events`, and `symptoms`: `left_with_unexhausted_people`, place changes
away from a place whose last place card listed a verified person whose `TalkLog#last_status` was not `exhausted`; `archive` rewrites an outdated one), `star.json`, `notes.md` (owner notes from the viewer). Trace events (`dialogue` may carry `speaker`, `conversation` and `cached`; a `talk_to` result may carry `entity`; a `perception` may carry `not_ready_frames`; a `decision` may carry `autopilot`; a `choose_objective` decision lists the offered candidates in `options` as `{id, label, leaves_unexhausted, picked}`): `perception`, `decision`, `action`, `objective`, `dialogue`, `lead`, `goal`,
`notable`, `place_card`, `place_name`, `item_gained`, `screen`, `screen_changed`, `affordance`, `grid_contradiction`, `keyframe`, `save`, `budget_stop`, `stop`. `budget.rb` enforces frames,
minutes, dollars and objective steps. `archive.rb` keeps a light bundle per run in git (trace gzipped, `screens/` included);
heavy artifacts stay local. A run resumes only with the same `flow_version` and ROM hash; a change to the
play flow means a new `flow_version`.

**Viewer** (`viewer.rb`, `viewer/`) — a small HTTP server. A `Follower` replays the journal of the watched
run and seeks by restoring the nearest keyframe; `Feed` derives status, mode and alerts, feed, reasoning, objectives,
goal, leads and the stitched dialogue history (newest first, with the person talked to and their state) from the trace
up to the shown frame, and `Insights` the world map (places on the overworld grid or attached to the screen they were
entered from, kinds from `data/place_kinds.json` via `place_kinds.rb`; exits taken, belief grids, people, leads, and a `screenshot` flag per place served by `/screens/<room>-<map>.png`), the timeline
markers and the cost series, cached by trace and shown frame, and the `cockpit` (KPIs against the manifest budget, the health band, HUD, current objective with its offered candidates, reasoning, symptoms, the place card of the current place, interiors with their entry door, leads and the dialogues grouped by person) that feeds the page: a top bar, a sticky chronological strip, three columns (screen with people, sign and door overlays, HUD and reasoning; objective and dialogues; symptoms, place card, leads) and, below, the world map in an exterior and an interiors tab, the complete inventory and the dialogue history. `Explorer` and `Registry` serve past runs (list,
read-only replays with pacing and seek, comparison via `run_compare.rb`, star, the run header and `notes.md`). It
never writes game state; the only files it writes are `star.json`, `summary.json`'s `starred` and `notes.md`.

**CLI** — `cli.rb`, `bin/koholint`: `run`, `resume`, `fork`, `verify`, `summary`, `screens`, `watch`, `archive`, `star`,
`prune-heavy`, `census` (modes, `census entities`, `census objects` or `census ready`), `npcs` (`npc_catalogue.rb`: a markdown table of the people of all
runs, their names and the distinct texts read with the milestone and the number of runs; writes nothing), `ab-plan` and
`ab-report` (`ab.rb`: the fork and resume commands of an A/B between autopilot arms from one frame of a run, written to
`tmp/ab/plan.json` and `tmp/ab/run.sh`; then a table per arm measured from the fork frame on: cost, paid calls, new places and
new cells per 1000 frames, stalls, autopilot decisions, and the pre-registered criterion). `fork` opens a parent of any flow
version, and may set the child's `--tag`, `--autopilot` and `--root`.

## Data flow of one decision

1. The engine waits for readiness (see Readiness gate), reads `GameState` and emits a `perception` event; vision updates the grid and beliefs;
   on a new place the engine emits its `place_card`.
2. The policy gets a decision point and a context. For an agent policy: render context, call the model, validate
   the answer against the schema; invalid twice means deterministic fallback.
3. The engine emits a `decision` event (choice, justification, confidence, cost, latency, prompt sha) and runs
   the chosen skill frame by frame, appending every input to the journal.
4. The skill result becomes an `action` event and feeds the next context; objectives are re-evaluated.
5. The budget is checked after every frame; at stop the engine saves, checkpoints, emits `stop` and writes
   `summary.json`.

## Invariants

- Only the engine writes `trace.jsonl`, `inputs.log` and `save/`; `verify` replays the journal and compares hashes.
- Determinism: the same journal on the same ROM gives the same states. Agents are never called in replay.
- No walkthrough in code or prompts (how-to-play knowledge is allowed, see `AGENTS.md`); facts live in `data/addresses.json`,
  `data/modes.json`, `data/entities.json` and a run's `world.json`, with provenance.
- A rule a script can check is a validator, not a paragraph.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`.

## Where things are

| Need | Look at |
|---|---|
| Design rationale | `docs/superpowers/specs/` |
| Plans of past work | `docs/superpowers/plans/` |
| Measurements of agent runs | `docs/runs/` (`index.md` lists every archived run) |
| What remains | `ROADMAP.md` |
| Conventions | `AGENTS.md` |
| Run storage and viewer usage | `README.md` |
| Game manual digest given to the agent | `docs/AGENT_MANUAL.md` |
