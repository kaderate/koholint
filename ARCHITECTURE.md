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
state by replaying the journal from boot; `keyframes.rb` and `canonical_save.rb` checkpoint it. The engine saves a
keyframe every 1800 frames, at the stop, and on the frame of every `item_gained` and every first ready play frame in a
place not seen in the run (`keyframe` then carries `reason`, `item_gained` or `new_place`, and the new place in `place`;
a resume rebuilds the places seen from perceptions and these keyframes); keyframes never feed perception or decisions,
so they do not change the play flow. `checkpoints.rb` and `data/checkpoints.json` name points of runs (`run`, `frame`, `flow`,
`source`) to branch from. The game is
deterministic, so *ROM + journal* is the whole run. Time is the frame; wall clock appears only in budgets,
pacing (`pacer.rb`) and observability.

**Perception** — `perception.rb`, `addresses.rb`, `game_state.rb`, `data/addresses.json`: a typed `GameState`
(position, room/map, HP, the rupee count (`rupees`: the BCD byte 0xDB5E for tens and units, verified, plus the hundreds byte 0xDB5D, a hypothesis), phase such as dialogue or locked, `link_frozen` (a scripted scene holds Link), milestone, inventory cursor, menu option, A/B items, the 10 inventory slots, `shield_raised`) read from RAM. Every address carries
provenance and a `verified_count`; `verified` needs two independent checks. No RAM writes to gameplay state.
`items.rb` and `data/items.json` name item ids (with provenance; unmeasured names are shown with a `?`); the milestone is the best of `shield_level` and the `milestone` of the items held (`none`, `shield`, `sword`). The engine runs an `ItemWatch` on every frame and emits `item_gained` (`item`, `name`, `place`, `held`) the first time an item id appears among the held items after the first play frame (once per id per run, rebuilt from the trace on resume).
`GameState` also carries the readiness signals (`room_transition`, `link_airborne`, `link_z`, `link_knockback`,
measured by `probes/readiness_census.rb`, `bin/koholint census ready <run_dir>`). `entities.rb` reads the game's entity table (16 slots: status, type, x, y, state, health) into `{ slot, type, x, y, status, state, health,
cell, kind }` for the active slots; the kind per type id (`npc`, `enemy`, `object`, `creature`, `unknown`) comes from
`data/entities.json`, measured by `probes/entity_census.rb` (`bin/koholint census entities`): A pressed next to the
entity opens a dialogue (or a scripted scene, flow-40, whose dialogue is then awaited up to 600 frames) that does not open with its slot cleared in a control copy (`npc`); contact damage against the
same control (`enemy`: types 9, 10 and 197 of the beach zone, measured for speed, contact gap, damage and whether the raised shield blocks it); neither, measured (`creature`: not a person, never a talk target, no danger);
an uncatalogued type is `unknown`. The engine passes `Entities.read` to the policy and
skills as the `entities` context entry. `Entities.objects` reads the room object table (`room_objects`, one id per cell)
and keeps the ids that `data/entities.json` lists with an `object` key and a kind (`sign`: shows a text when read with A,
`object`, `door`: walking up into it from the cell below enters a building, `chest`: a treasure chest that opens when Link walks up into it from the cell below and presses A; object 160 is closed and 161, flagged `open`, opened) and the directions Link faced when it answered (`faces`, which restrict the standing cells of `talk_to`); it is
the `objects` context entry. `probes/object_census.rb` (`bin/koholint census objects`) measures them: in
a throwaway copy with every entity slot cleared, Link is put next to each cell, faces it by walking 6 frames and presses
A (a dialogue that also opens without A in a control copy is not the object's; the first page is saved as a PNG); each
object id is sampled 6 times unless it answered; `probes/door_census.rb` (`bin/koholint census doors`) puts Link
below up to 2 cells per object id in such a copy and walks up: an id is a door when Link walks into that cell by himself and
arrives in another place (226 at 5 house doors of map 0, 225 at one); `--crawl N` first crosses screen edges in copies to reach N screens of
the same map.

**Game modes** — `modes.rb`, `data/modes.json`: the catalogue of the game's screens (intro, file select, name entry,
loading, play, dialogue, locks, scripted scenes, dying, game over, inventory, map, save screen). Each entry has a kind, the engine phase it
routes to, a `match` on the mode tuple (`game_mode`, `game_submode`, `dialog_state`, `motion_blocked`, `scene_state`,
`link_motion_state`, `game_over_stage`, `link_frozen`; values are an integer, a list, `nonzero` or `{"not": ...}`), an optional
`ready` (the settled submode), how to enter and leave it, its inputs, its cursor and options, and provenance
(`source`, `confidence`, `verified_count`). The validator refuses missing keys, `verified` below two checks and two
entries that match the same tuple unless one strictly refines the other (the most specific wins). `Modes.for(state)`
resolves the entry; `GameState#phase` is `boot` for anything outside play mode before the run first played, else the
entry's phase (`loading`, `playing`, `locked` (also the `frozen` entry, flow-40: `link_frozen` 0xC1A8 above 1, Link held by a scripted scene such as the owl arriving or the sword of 242/0 touched), `dialogue`, `cutscene`, `menu`, `map`, `save`, `game_over`, `boot` for
the title screens) or `unknown`; the `ready` of `play` lists the readiness signals at rest (no screen scroll, not in the
air, no knockback, no door walk: `link_motion_state` not 2, 3 or 4); the engine emits a `notable` `unknown_mode` once per unknown tuple (rebuilt from the
trace on resume). `probes/mode_census.rb` (`bin/koholint census`; the probes are the only code allowed to write RAM, in throwaway copies, and are used by the CLI only) is the probe that measures them: from a replayed
state it plays scenarios on throwaway copies (START, SELECT, the four-button save combination, health drained to zero
by a RAM write in the copy only) and diffs RAM while moving cursors; reports go to `tmp/census/`.

**Readiness gate** — `readiness.rb`: in the `playing` and `loading` phases Link is ready when the `ready` signals of
the `play` mode hold for 2 consecutive frames (`Readiness::STABLE_FRAMES`: the last scroll write lands one frame after
`room_transition` clears; the census found the BG tile indices final by then after every scroll, door, jump and
knockback of run `20261024-184627-b97e`). flow-60: `pending_heal` (0xDB93, health still to add) is a `ready` signal too, and
the delegated policy (`waits.rb`) treats locks less than 30 frames apart as one scene, so each release waits as long as the
scene so far (up to 30 frames), with a settle wait that ends when Link is held again. After its dialogue, the healing scene of
83/0 holds Link for about 370 frames: the lock flickers (free 1 to 12 frames at a time) and leaves an 87-frame gap that only
the heal covers, since it reads 4 and 0 on alternate frames and never settles. The engine feeds it every frame it steps; at the start of each iteration,
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
entities, signs, objects (`object` entities and room objects) with their cells, doors (room objects of kind `door`), chests (`{cell, open}`, room objects of kind `chest`; `PlaceCard.latest` gives the policy the closed ones not opened since, so a resume keeps away chests), and exits
(border cells believed walkable, by side). `world.json` `places` keeps per place the last card, the visits, the first and last card frames, the
place name the agent gave (`name`), the names and talk status of the people and whether each sign was read (from the talk log rebuilt from the trace); flow-79: `unknown_types` gives, once per unknown type of the last card, `tries` (talk_to results aimed at that type there, `target_type` or `entity`), `answered` (those that opened a dialogue) and `moved` (talk_to had to chase it, `tracked`), and the place has `items_gained` (its `item_gained` events). The
agent's context lists the doors of the screen with the cell to walk up from.

**Vision** (`vision/`) — what RAM does not give: `screen_vision` and `screen_snapshot` read the screen,
`grid_builder` probes neighbouring cells (the only place that snapshots and restores the emulator) and
builds a collision `grid`; `beliefs` and `world` accumulate per-place knowledge (observed free, blocked,
doubtful, contradicted); `capabilities` records what Link can do; `dialogue_shot` crops dialogue boxes for the
model. Unknown cells are unknown, not walls.

**Navigation and skills** — `geometry.rb` (cell grid, pixel offsets; x alignment uses the measured one-cell gap window `gap_entry`, -3..+4 px, for walk probes and the centring after a skill), `navigation/planner.rb` (shortest path Flow-24 danger and holes: the planner takes a `danger:` lambda (cells within the measured `contact_px` of `enemy` entities, `Entities.danger_cells`) and plans around them first, falling back to the plain route; a hole fall (`link_motion_state` 6, not ready for 93 frames) makes `Engine#await_ready` call `GridBuilder#note_fall`, which records a `fall` affordance (walk `no`, all directions) for the appearance of the cell Link fell from, so every hole cell of that look is impassable; flow-67: `Beliefs#hole?` reads a look as a hole while Link fell through it on more frames than he walked onto it safely (`yes` walk records, counted in frames), so a look later walked safely is unlearned; `Grid#hole_margin` (the cells beside a hole, memoised per grid) is routed around by the planner like a danger zone except at the goal, crossed only by a last tier that drops it while the hole cells stay `no` (flow-70: never on the way to a frontier or a clearable object, only to exits, doors and named goals; run `20261118-145240-e9bd`, frame 90719: that tier took explore past a hole in 115/0 toward a frontier and Link fell in), and explore takes no frontier from or into it, because a hole pulls Link in from the cell beside it (run `20261114-093702-a0dc`: explore walked to the cell above a look recorded as a fall 3 times and Link fell at frame 84402, the checkpoint death of every post-65 fork); the STUCK detector ignores results taken during a fall and the policy alerts on places where Link died. Flow-25 shield walk: `navigation/threat.rb` is the threat interface (position and `reach` per `enemy` entity, `within?` and `zone` take the caller's safety margin; a future combat skill lowers margins without touching navigation); `skills/shielded.rb` wraps walk, goto, ex... (line truncated to 2000 chars)
with the fewest turns over known cells), `skills/` (`walk`, `goto`, `step`, `talk_to`, `attack`, `explore`, `press`,
`advance_dialogue`, `wait`, and the screen skills of `skills/screens.rb`: `open_menu`, `close_menu`, `menu_move`,
`menu_assign`, `open_map`, `close_map`, `choose_option`, which check the current mode from the catalogue, stop with
`wrong_mode` elsewhere and repeat a press the game ignored; and `skills/use_item.rb`: `use_item` and `guard`, which put the item on a button through those menu skills when it is on none, wait the 16 frames the game ignores A and B after the menu, then hold the button and report `raised_frames` from `shield_raised`; `refused` for an item not held) behind `skills/registry.rb`. `explore` chains goto legs by itself: it walks to the
nearest untried border exit (a side never left from this place) or untried door (it walks up from the cell below and waits,
with no input, through the walk-in and the loading); when the place has none, to the exit or door that leads, over the
places and exits it has taken (`explore_log.rb` route: breadth-first, the destination of each exit taken is recorded), to
the nearest place that still has some (or was never surveyed; flow-66: the flow-62 ranking of places by kind of work is gone,
since its A/B found fewer new places per dollar; a cell whose upward step crosses a door Link has walked through, door object
or not, is no frontier, `ExploreLog#door_edge?`, and a route hop through such a door is walked like a door object's); only then to the nearest frontier (a known cell next to an
unknown one), except that untried exits or doors that no known path reaches yet send it to the frontier first, as does a place never surveyed before (flow-26: the first explore in a new place walks its frontier instead of leaving at once, and taking an exit also records the side of the new place it arrives by as left; flow-27, corrected in flow-29: a place change by a straight walk or step counts as an exit taken in the direction it was given; the first cut read the side from the cell the skill began on and recorded wrong edges, which sent explore to non-existent exits); flow-30: a survey from a call that left the place by a known or new place after fewer than 3 cells is provisional, so the place stays untried (and unsurveyed for the frontier-first rule) until a longer visit replaces it; flow-31: an exit records the cell it lands on, and an explore that walks no cell and finds no frontier on that cell while some place still has work marks the landing a closed pocket, which `route` no longer enters (room 192's bottom-right corner, entered from 208, led nowhere and sent explore up into it forty times); flow-33: entity type 14 (sea-urchin-like, patrols slowly) is an `enemy` with `contact_px` 9; walking into it with the shield raised, which `Shielded` already does near enemies, pushes it 15 to 20 px away without damage, so no separate pushable handling exists (room object 0x5C is a solid obstacle, not pushable by that probe); flow-35: a stationary enemy (type 197, the sea urchins whose sprites make their cells look like objects) is a last-resort route in `Planner` (`pushable:`) and a frontier in explore, because walking into it with the shield raised pushes it ahead of Link (probe: `walk down 3` through the urchin gap of room 225 passed it with no damage in 222 frames); flow-36: a `wait` or `guard` chosen while an enemy is within its reach plus two cells is replaced by `explore` (`keep_moving` in the delegated policy), so Link never stands still beside a hostile creatur... (line truncated to 2000 chars)
result's survey says whether the place still has such work (`pending`), which is what the route looks for; a place change
that does not cross the border is recorded as a door, and a step up from or into a door cell is never a frontier; it steps out, re-plans, and stops at
an event (`new_place` for a place never seen in the run, `known_place` for a return,
`dialogue`, `untried_object` once per thing never talked to nearby, `blocked`, `stalled` after 3
attempts that walked no new cell, `no_frontier`, `locked`, `budget` at 600 frames); `explore_log.rb` keeps per place the cells it walked or found walled, the exits
tried (left, or blocked twice) with their destination, the survey of each explored place (open border cells by side, doors, `pending`),
the places seen in any action and the things already offered, rebuilt from the `action` events on resume. flow-55: it also keeps
each place's latest `screen` grid (tile appearances, from the trace on resume) and the tile of every cell a capability cleared (`look`,
recorded by `Clearing` on each use, or read from the screen grid for older traces), with the clears of that tile that worked and failed.
In a place last explored before the first clear (in trace order), a cell Link never entered with any skill, next to one he did, whose
tile cleared more often than it failed and that is not a failed clear itself, is an inferred clearable cell
(`ExploreLog#inferred_clearable`: cell, tile, the place and cell of the tile's first clear, its wins and losses); such a place counts
as untried, so explore's route goes there (the route's `clearable` lists them), and once there the live clearing path takes over. flow-78: a side known only as an assumed way back is no crossing (`ExploreLog#side_crossed?`; `side_left?` still routes through it), so explore, the place's `untried` state and the exit candidates treat it as an untried side; a cell Link stood in with any skill is no frontier on a later visit; and a clearable object cell is a frontier only when cutting leads on: across the patch of objects and the known cells no path reaches without cutting, an untried border exit, an untried door above a cell of the patch, or an unknown cell that is not an object (`Explore#leads_on?`); otherwise objects are never a frontier (scripted forks from b628 at frame 97200: 163/0 cost 1,803 frames over 2 visits, 1,454 of them explore budget stops cutting objects, and 302 frames after). A way an explore found unreachable from the side Link entered the place by, on two visits, is cut off from that side (`ExploreLog#cut_off`) until a crossing from that side takes it, a new context (item or milestone, `in_context`, replayed from the decisions on rebuild) clears every cut, or `CUT_VISITS` (4) further visits of the place pass; `route` searches each place once per side it is entered by, starting from the side Link entered the current place by, and never takes a cut way (scripted always-explore forks from forest-144-full-health, 15k frames: 226/0 and 242/0 each routed to 227/0 through the other, 10k frames of shuttling on main, gone with the cut). flow-80: a search for work (no goal) that finds none under the cuts ignores the live cuts one at a time, oldest first, and returns the first route found (`route` marks it `lifted`); a lifted cut is tried once per cut episode: found unreachable again while still cut, it is spent (`@spent_cuts`), no route lifts it again, and a new context or a crossing from that side clears it, so with two cuts and no other work Link tries each o... (line truncated to 2000 chars)
validated parameters (the perpendicular settle of `goto` and the centring after a move give up once Link stops moving);
it reports how it stopped (`done`, `blocked`, `no_path`, `no_response`…). flow-51: a `goto` stopped by an edge its grid believed
open avoids that edge and plans again from where Link stands, up to `Goto::REPLANS` (3) times, before it reports `blocked` (the result
counts `replans` and lists the edges it went around in `avoided`, which `Ledger.edges_of` reads with `blocked_at`, so the delegated
ledger and learn record them too); explore's legs and `talk_to` keep their own replanning (explore blocks the edge and picks its next target, `talk_to`
its next standing cell). flow-54: before that, a goto blocked off-centre backs off to the cell's centre along its move,
centres exactly across it and tries the same edge once more with no tolerance, since stairs and one-cell gaps take Link only when
exactly centred (208/0's stairs refuse him 3 px off). The retry happens once per cell and heading, never in a direction the
triggers forbid, and the zero tolerance ends at the next cell or replan; talk_to's and attack's walks share it, as do explore's legs.
flow-56: when the game opens a dialogue by itself during an explore leg or outward step, explore blocks the edge Link pushed before it
stops `dialogue`, but only when the push is evidenced. Link must still stand in the cell he last entered, his position must be unchanged
on that frame, and he must be flush against the cell's edge in his heading (`link_footprint`: half its width across, its row band along).
A call-out, a scene or a talking door elsewhere bars nothing. The survey's `pending` then counts only work reachable without that edge.
In the 21b0 forks, 69/0's door and exits lay behind a rock the grid reads as open. Triggers and the ledger forget the rock when Link
leaves, so the place stayed untried, and explore came back from 68/0 to push it up to 13 times per fork, loop breaks included. `ledger.rb`
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
Flow-40: a person that gives nothing after the 48 frames at talk reach gets one more try pressed against it (the sword of 242/0
answers at 14 px, not at 19); a scripted scene that starts during any skill (`GameState#scene?`) stops it with `scene`, and for
`talk_to` that counts as the target's answer once Link faces it (`talked`, with the faced `entity`; a scene met on the way is not attributed).
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
current place that are not exhausted for the current stamp (flow-62: a person of another place whose last talk was under
other held items or another milestone, `TalkLog#stale?`, is a `person-R-M-tT` candidate again until Link talks to them), and the `verified` `sign` room objects not read yet and the closed `chest` objects a route on the current grid reaches from the cell below (flow-81: `objects_for` marks each closed chest `reachable` by the default planner, which counts unknown cells as walkable; a `talk_to` at a chest that drew no response keeps it unreachable for the rest of that visit of the place, and any `talk_to` at it drops it from the away cards; an opened one is no work; 2 rounds per chest, its close note says `opened` or `not_opened` from the object read after the dialogue; a `chest` objective ends when its chest is seen open, whatever its text) (a sign
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

**Exit graph and puzzles** (flow-74, `explore_log.rb`) — every crossing is an observation of `(place, way) -> place`, the way a side or the door cell, kept with its count and frames; a way never forgets an earlier destination. The first crossing of a way is compared with a hypothesis: the way back assumed across an earlier crossing on the same map (`reverse`; a way back from another map is still routed but predicts nothing, a door lands on its own cell), else the screen next to it on the map (`neighbour`, `Geometry.neighbour`: an overworld room is 16 wide, `overworld_neighbour` in `data/geometry.json`, a hypothesis from one census of 36,147 crossings; map 0 only, interiors have none). A first destination other than its hypothesis is a puzzle (`unexpected_arrival`, or `refuted` for an assumed way back), and a second destination through the same way is a `contradiction`; a crossing that raises a puzzle assumes no way back (run `20261118-142325-20ea`: the top of 81/0 leads to 99/0, and the invented way from 99 down to 81 sent explore to an exit that does not exist). Routes take ways that led to one place first and a contradicted way, toward its most observed destination, only when nothing else reaches the goal. The delegated policy hands new puzzles to the engine at the next decision, with the landing cell when Link is still in the arrival place, and the engine traces them as `puzzle` events (`{id, kind, place, way, expected: {to, source}, observed: {to, landing}, frames}`); a rebuilt log emits only those whose event a fork cut off. The prompt states the last two puzzles of the place as observed facts, once per visit. Puzzles are evidence for the exit bench below; play never resolves one by itself.

**Exit bench** (offline, flow-75, `bench.rb`, `exits.rb`, `data/exits.json`) — `koholint bench exits <run_dir> [--place R/M --at-frame N]` measures a puzzle place's ways with zero model calls. For each visit of the place (its first keyframe; `--at-frame` maps to the first frame of the visit around it, so two frames of one visit are one visit) and each side (and each door of its place card), it forks the run under `tmp/bench/runs` and resumes it with a `Bench::ExitTrial` policy: advance dialogue or wait until play, `goto` a border stand of the side, `walk` 2 cells out, `walk` back. The arrival is a trial of `(place, way, context) -> to`, and the walk back one of the reverse way (`via` the forward way; a door's reverse is the `down` side, the key ExploreLog gives a walk out of an interior); a walk back that stays in the arrival place records nothing. A trial is `unreached` when no stand was reached, and discarded, recording nothing, when Link loses health or the game is over; a side crossing that lands off the opposite border (a fall, a warp) is recorded with `off_border` and no walk back. The context is the milestone and the held item ids (`Exits.context`). Each trial carries its `lineage`, the oldest ancestor found beside the run or among the archived runs (`Bench.lineage_root`); an edge is `verified` when agreeing trials come from 2 root lineages (`Exits::VERIFIED_AT`, enforced by `Exits.validate!`), `observed` with one, `contradicted` with two destinations, and lists the hypotheses it `refutes` (`neighbour`, `reverse`); a rerun from the same parent, frame and forward way adds nothing. Each bench records, per place and context, every way's destination, the places new to the run it reached and its status: `leads_on` when it reached one, `incomplete` while a way stays unreached, and only with every way reached and none new `depends_on_context`, with the place's `lead` events (by id) and `dialogue` texts (by frame) read before the keyframe as candidate hypotheses, nev... (line truncated to 2000 chars)

**Capability learning** (offline, `learn.rb`, `capabilities.rb`, `skills/composite.rb`, `data/capabilities.json`; design: `docs/superpowers/specs/2026-11-12-capability-learning-slice.md`) — `koholint learn <run_dir>` takes each item held from the run's own first frame on (read from perceptions, since a fork drops the `item_gained` of its fork frame; so a fork also learns from an item an ancestor gained, over the places it sees after the fork frame, and its hypothesis records the frame the item was first held in the lineage with `held_from`, the fork frame), replays to the first ready play frame of every place seen after it (`Replay.to`), reads the raw room object table there (`Entities.room_objects`, also the engine's read-only `room_objects` context entry) and proposes the uncatalogued object ids Link never stood on, counting only stands from the frame of that run's sighting of the place on, a proxy for the sighting's grid being what lay under Link (an earlier stand, such as one by an ancestor before the item, may have been on another object) and not a cell he entered only after a capability changed its object (`--limit`, default 10, about 50 minutes on `0c64`; `--object ID` picks one). Ids are ranked first by blocking evidence pooled over the run's lineage (`Learn.lineage`: the run's oldest ancestor under the same root directory and every run descending from it). That evidence is the cells that stopped Link: the cell ahead of a blocked move or edge, explore's walls, and the target of a capability use whose step into it was blocked. Ties go to the id seen in the most places. A pair already in the file is retried only while it is `inconclusive` and some (place, cell, standing cell) among its first places and cells is still untried. A triple already in its evidence is never tried again, and unreached trials count separately from failures, since they are goto problems. flow-51: an unreached trial records the edges that stopped its goto (`blocked_edges`: its `blocked_a... (line truncated to 2000 chars)

**Decision points and policies** — `decision.rb` defines the points (`choose_objective`, `choose_skill`,
`move`, macros) with their output schema and validation. A policy answers them: `policies/delegated.rb`
(agent-driven, with its concerns mixed in from `policies/delegated/`: `dialogue.rb`, `waits.rb`, `outcomes.rb`, `guidance.rb`; owns the context, plan memory, automatic dialogue pages, lock/hemmed handling, and before asking the model
the revisit of people and signs (its `prepare(context)` gets the entity and object readers before `decision_point_for`, so
the first decision of a visit or a run engages too) and the reuse of conversations already read: a dialogue closed when read (dialog state back to 0) whose signature (at least 2 full rows) is known is not sent
as sheets, its stored text is emitted again with `cached: true`; when a revisit is due it replaces the model's skill choice,
also right after a sheet reading; and the explore autopilot, `autopilot.rb`: after an `explore` that stopped with
`new_place`, `known_place` (not counted in the 6-explore chain; a third return to the same place goes back to the
model), `budget` or `untried_object`, the policy issues the next `explore` with no direction itself (agent `delegated`, cost 0,
`decision` event with `autopilot: true`); flow-79: before that explore, and also after an autopilot try (stop `tried`), it issues one `talk_to` (`Autopilot#try_choice`) at the nearest thing never tried on screen: a cell the last `untried_object` stop named, or an `unknown` entity whose type no talk_to aimed at in this place (`ExploreLog#met?`, from the talk_to results' `target_type`, the type `talk_to` aimed at, or `entity`), skipping types struck this visit and types it already aimed at in that place (kept in the autopilot itself); a try costs no call and does not count in the chain, the chain and frame caps do not hold it but `TRY_LIMIT` (6 per visit, reset by a model call or a place change) does, and the other holds do (the val78 lineage: 27 of 29 `untried_object` stops were followed by another autopilot decision, and 26 of 34 places holding an unknown entity never had a talk_to); and the engine passes each place card to the policy (`note_card`), so `ExploreLog` keeps the uncatalogued types of each place's last card (`card`, rebuilt from the `place_card` events), and `route` aims at a place with such a type never aimed at (`work?`) as at a place with untried exits; after the revisit, the hemmed wait (flow-63: each 120-frame wait is followed by a 2-pixel
`step` probe, and a probe that moves Link ends the latch) and pending dialogue pages (flow-65: after an
`attack` that stopped `done` or `target_gone`, it strikes the nearest `enemy`, or unidentified type already struck in this visit
(forgotten when Link leaves the place), within 2 cells and never in the slot just struck, the same way, until none is left,
health is below 2 hearts or a heart below the last call, an attack stops any other way (`room_change` included), or 8
attacks or 900 frames have passed since the model's last call); the model is called again
on any other stop or action, a new lead or goal from the last call, a phase other than `playing`, health lower than at the
last call, an objective that changed or whose kind is not `new_place`, `leave_place` or `new_text` (unless it has a target), and after 6 autopilot
explores or 2400 frames since the last call. flow-80 (val78: 73 of 146 model skill calls answered `explore`): the end of a dialogue the model asked for (a model-chosen `talk_to` stopped `done` or `no_response`, through the `advance_dialogue` and waits after it; an autopilot try stays `tried` whatever it met, through its dialogue) continues the chain like a benign stop unless the last call brought a lead or goal (a dialogue with new text is still read by the model, since a pending sequence or reading holds the autopilot; 29 calls, $0.67 after dialogues that gave none); an arrival (`new_place`, `known_place`) or a dialogue end no longer holds for a target that cannot be followed from here (fork 0795: 19 calls held so while a person target stayed in 146/0), while an autopilot try never fires under an objective with a target; and after a `goto` stopped `done` on the cell right below a door object, `Autopilot#door_choice` walks up 2 cells once, when none of the common holds (new lead or goal, explore loop, phase, hp drop, low health) applies (the model's goto, walk up, walk up pattern in all three forks). An objective with a `target` (picked from the candidate menu) is followed from the first
skill decision after the model's call: `explore` with the exit's direction, or with an `aim` in the skill context (a door to enter first,
a place to route to through `ExploreLog#route(goal:)`; a model `explore` with no direction gets the same aim, or the objective's place, and the prompt shows the known route to that place, `ExploreLog#path`), or one `talk_to` of a person or sign of the current place (a `new_text` target left behind is not routed back to, except a sign offered from another place, `remote` on its target, which is routed to and ends only when that sign's text is read, `Objectives#note_sign_read` (flow-69); a door Link stands on or just below is not a candidate); a new goal
from that call does not hold it. When a chain stopped `new_place` or `known_place` and achieved the model's objective, the next
`choose_objective` is answered by the policy (`new_place`, `autopilot: true` on the objective) while the place or a routed place has
untried exits and the caps allow it, and (flow-52) no person on screen was never tried (no talk attempt with its type here): such a person is the first candidate of the model's objective choice (run `20261113-160556-fef5` kept exploring past the never-tried type 49 at (5,5) of 242/0 and left). Results of autopilot decisions are marked `(autopilot)` in the context's results and attempts. Autopilot explores are objective attempts like any other (loop and stall
abandonment still apply) and leave the engine's consecutive failure and refusal counters untouched; `--autopilot off`
(manifest `autopilot`) disables it),
`policies/walk_and_talk.rb` and `start_game.rb` (deterministic baselines and the intro). In `delegated.rb` an invalid
answer falls back deterministically, 5 consecutive fallbacks stop the run; an engine exception before the
agent call is an `engine_error` fallback counted apart and stops as `engine_errors`. Phases come from the mode
catalogue (see Game modes): the boot script owns `boot` and `loading`; once the run has played (a `perception` in play
mode, rebuilt from the trace on resume) the screens go to the agent with their own skills only (`menu`: `menu_move`,
`menu_assign`, `close_menu`; `map`: `close_map`; `save`: `choose_option`; `unknown`: `press` and `wait`;
all with `press` and `wait`), after a deterministic wait while the screen is still opening; `cutscene` (the dying
animation included) waits like `locked`, in waits that end the frame Link is free (flow-50); a lock is followed by a wait as long
as itself, up to 30 frames, before the model is asked (flow-40: the sword scene released Link for 3 frames between two locks;
flow-50: the owl of 128/0 for 1); a lock that outlasts the 900-frame wait cap emits one
`notable` `lock_cap` and the model decides from then on. A dialogue sequence that reaches its page or frame cap is
sent as sheets once and the advance goes on (the model's choice is replaced while the box is open); only a second cap of the same
dialogue hands the pages to the model (the owl and sword texts together run over 40 pages); a dialogue that opens with no current
objective is advanced before a new objective is asked for. The game-over screen is never sent to the model: the policy picks its first
catalogue option not flagged `quits` with `choose_option` (agent `delegated`, no prompt) and emits one `notable` `death`
per screen. A drop of `hp` between two observations emits a `notable` `damage` (`hp 16 -> 12`), and the next prompt's
health line adds the hearts lost (and a death) since the last model call. flow-68 brings back one low-health rule (flow-34 had removed them all): at one heart or less (`health <= HP_PER_HEART`) the autopilot holds (`low health`), so the model takes every decision, and walk, goto and explore grow every enemy contact zone by a cell (`Execution#danger_of`). The planner crosses that ring only as a last tier and never the contact zone itself (`contact:`), a goal inside a zone is still reached, and from inside a zone Link may take any step that does not bring him closer to an enemy (`closeness:`, `Entities.threat_distance`); walk stops `danger` before a zone cell under the same rule, and a goto with no route outside the contact zones names them in its `no_path` cause. In the 9 post-57/61/65 forks, 5 of 15 deaths were enemy contact at one heart or less (4 at half a heart). There is still no retreat and no shelter candidate: flow-34 removed rules whose thresholds were never measured, and this one rests on those death counts. flow-73 (66/0, per-frame probes of run `20261118-155549-c9c4` at frames 87880 and 88140 with every other entity cleared): type 27 hurts at an axis gap of 8 px or less on 7 of 8 sides (11 px above it in one state, so `contact_px` 11) and barely moves (0.07 to 0.23 px/frame); one sword hit turns it into two type 28, which chase Link (0.4 to 1.0 px/frame) but never hurt him (0 hp in 4 of 4 placed contacts); 28 stays `unknown` until a second independent check, a moving contact included. `Attack#closest` now uses the default reach (9 px) when a type has no `contact_px`, so the lineup no longer strikes from inside contact (it did at 2 px, and those strikes missed), and a back-off into a wall switches to the other axis (`BACKOFF_STILL`). The away rule for zones (`Execution#away_of`) is a direction test from Link's own position against the enemies within a cell of their touch, because comparing cell centres let him walk down into a 27 sharing his cell. At one heart or less with such an enemy near, `Autopilot#disengage_choice` walks one cell in the direction with no enemy ahead that ends farthest from them, skipping directions a walk found blocked (or refused at once for danger) since the last model call and cells on or beside a learned hole, up to `DISENGAGE_LIMIT` (3) times per model call; the model decides after. Continuing the attack chain after a `damage` stop was tried and dropped: in replays the next attack re-entered contact and lost another half heart. Six `no_frontier`, `no_path`, `blocked` or `stalled` results in one place without reaching a new cell emit a
`notable` `stuck` and add a `STUCK` reset hint to the header until Link reaches a new cell or leaves. `loop_watch.rb` (`LoopWatch`, fed by the policy with every play-mode observation and rebuilt from the `perception` events on resume) catches the loops across places that this per-place count misses: a known place entered for the 4th time within 3600 frames with no place new to the run in between emits a `notable` `stuck` (`loop: ...`) and a `LOOP` hint in the header until Link reaches a new place (thresholds measured on run `20261111-232729-4ec5`, where it fires at frames 63755 and 65331). flow-44: the detection also changes behaviour. At the next skill or objective decision, once per detection (`LoopWatch#act!`, rebuilt from the trace on resume), `Delegated#loop_break` abandons the current objective (reason `loop`) and starts the harness's new-place objective. It then explores toward the nearest place with untried work outside the loop (flow-66: `route(skip:)`) (`ExploreLog#route`), or explores here when this place still has some. flow-47: when no known place has untried work, it starts a `reach_place` objective (target kind `place`) toward the reachable place entered least outside the loop's places, nearest first (`ExploreLog#least_visited`, from the explore log's visit counts), and explores toward it; every later detection acts again (run `20261113-101324-216d`: the 178/0 ↔ 203/16 phone-booth loop was detected 4 more times while every known place read as exhausted, so the break never acted). Explore also takes a clearable object's frontier in the current place before an aimed route, and counts it as untried work in its survey. A capability that ran on an object without clearing it is recorded in the explore log (`failed_clears`), and that cell is no longer a frontier there. NPC revisits wait while a surveyed place still has untried work. A skill that ends its move with Link off the grid (a border crossing whose room id changes only after the scroll) waits up to `EDGE_FRAMES` for the room change. flow-45: after `ZERO_LIMIT` (3) identical results of at most one frame in the same place (same skill and stop), `Delegated#zero_cap` answers the next skill decision itself with a `stuck` notable. The streak is counted by `zero_watch.rb` (`ZeroWatch`, rebuilt from the trace's actions and the harness's own decisions on resume). The harness explores toward the nearest place with untried work when there is one, unless its explore already came back instantly in this streak; otherwise it waits 120 frames. Its own answer keeps the count, so each further instant repeat costs one model call per wait, until a result takes more than a frame or the place changes. flow-80: explores that stop `no_frontier` or `stalled` with no cell walked (or in a frame) are also counted over one visit of a place, whatever moves run between them, reset by an explore that walked, by leaving, by a new context (item or milestone), a lead or goal (the `lead` and `goal` events on rebuild), or a skill other than a move (explore, goto, walk, step, wait) that took more than 8 frames; the third such result gets the same harness answer (`walking no cell` in its justification and `no cell walked` in the notable), and when no place has untried work the harness explores toward the reachable place entered least (`least_visited`) before waiting. flow-57: a hit sets `pending_damage` (0xDB94) to its whole loss and the game then lowers `hp` one unit every 2 frames (per-frame replays in two run lineages), so every skill started during that drain stopped `damage` within 2 frames and cost a model call per unit (24 calls, 0.46 USD in the 3 post-56 forks). `GameState#health` (hp minus the pending damage) is what every damage check compares: the skills (and so composites and learn trials), the autopilot hold and the damage notable. A hit now stops a skill once, on its own frame. flow-46: `attack` takes an unknown or creature (`Entities.creature?`) at or next to the cell when no `enemy` is there, never a person nor any other kind (run `20261113-090835-21b0`: types 11 and 27 of the northern places hurt Link 18 times while all 9 attacks on them stopped `no_target`); both types are catalogued as `enemy` hypotheses. The play skill set has no screen-only skill. The engine stops the run with
`stuck_boot` when the boot script decides for over 900 consecutive frames in a non-play mode past boot, or 3600 in any case. It stops
with `unknown_mode_stuck` after 600 consecutive frames on an uncatalogued screen, and with `not_ready_stuck` after 600
frames waited for readiness. `choose_option` refuses (`refused`) the
catalogue options flagged `quits` (save and quit to the title), and the context lists only the other options.

**Candidates** — `candidates.rb` builds the `choose_objective` menu: people here first (`npc`, status never/new/changed/repeat),
unread signs here, unidentified things here (flow-40: `unknown` entities and sprites holding no entity never talked to, nearest 4,
`examine-ROW-COL`, followed by one `talk_to`), untried exits by side and untried doors of the place (every candidate that leaves the place is labelled
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
resume. flow-48: each lead has a status derived from the objectives that followed it (`because`, or a `lead` candidate's target), read from the finished
objectives (`Leads#note_objective`, fed with `Objectives#history` before each prompt and rebuilt from the `objective` events on resume): `open` until one
follows it, `tested` once one is achieved, `refuted` after `REFUTE_AT` (2) that failed, or were abandoned for a reason other than `loop`, `stall`, `unreachable`
or `resume` (navigation and restarts say nothing of the claim). The evidence is those objectives (id, title, outcome, place, frame, reason).
The context tags a followed lead with its status and its last 3 objectives and lists open leads first; a lead stops being a `lead-N` candidate once refuted
or once an achieved objective reached the place it points to (a loosely cited `tested` keeps it), and
`world.json` carries `status` and `evidence` per lead. flow-58: when a skill opens a text without pressing A (`Triggers.scripted?`, the barred edge), the policy
notes what is in the cell ahead in the `trigger_input` direction (an `npc` entity's type, else the `room_objects` id unless that id lies under Link or under a
cell the explore log walked in that place or fills at least 10% of the room's cells, since the table holds an id in every cell) in the dialogue sequence, and the call that reads that text adds
`Leads#contact`: a `normal` lead with the text as quote, the place as `where`, the cell as `source` and `contact` (`row`, `col`, `object` or `entity`), claiming
only that contact opened the text; one per thing and text (a quote overlapping one about the same thing, or any lead's quote in that place, model leads
included, counts once), `LIMIT` per place, restored from its `lead` event like the others; its `where` is its own place, so it never becomes a goto candidate. `Dialogues.leads_count` leaves contact leads out, so they never change the stamp that reopens people.
flow-59: `lead_check.rb` holds the walkthrough rule on leads: a claim or `where`
naming a catalogued item (under its name or an `aliases` entry of `data/items.json`) that the text read does not name and that Link does not hold
(`Items.held_ids`: A, B, inventory, milestone) is general knowledge, not something read. `Leads#absorb` drops such a lead at runtime with the same inputs as the offline
check: every text the run has read (`note_read`, from the policy and from `dialogue` events on resume), the current transcription and earlier lead quotes,
and the items ever held (`note_held`, cumulative, so a used-up item still counts); the engine traces a `lead_leak` notable and `koholint check-leads` reports them in traces. It also checks that every sentence read (3 words or more, once per run) is quoted by a lead or dismissed by a low lead quoting it, and lists the dropped ones (`LeadCheck.sentences`; a quote cut inside a sentence covers nothing).

**Agents** (`agents/`) — `context.rb` renders state for the model (grid map, neighbours, entities and objects on screen, people's names,
goal, leads — every `high` one, `normal` ones of the current place, never `low` ones —, recent results, plan), `prompts.rb` holds the system prompts, `claude_cli.rb` calls `claude -p` with a JSON
schema and reports cost and latency. Jev (tactical choices) is planned, not wired.

**Run storage** — `run.rb`: `runs/<id>/` with `manifest.json` (flow version, ROM hash, tag, harness/prompts
sha, model, `autopilot` for agent runs; `resume` keeps it, `capabilities`: the digest of the operational capabilities at creation, `exits`: the digest of the exit bench data (`false` for a run without it), or `false` for an A/B arm without them; a fork takes the current digest unless it or its parent is `false`), `inputs.log`, `trace.jsonl` (events validated by `trace.rb`), `keyframes/`, `save/`, `prompts/`, `screens/` (one PNG per place, written by `place_shots.rb`:
observability only, no trace event, the set of captured places is rebuilt from the directory; written after 20 playable frames in the place, or at once when the engine reads it settled before a decision, so a place left within those frames still has one),
`world.json` (`{ goal, leads, places }`, rewritten from the trace at every stop), `summary.json` (written at every stop by
`summary.rb` from the trace only, versioned by `Summary::VERSION`: totals, cost by skill, decisions by agent and
feature usage, with `autopilot_decisions`, `chain_max`, `deaths`, `damage_events`, `stuck_events`, `chests_opened` and `rupees` (the last perceived count), `puzzles` (`{open, by_place}`: the `puzzle` events counted once per id, per place and kind), and `symptoms`: `left_with_unexhausted_people`, place changes
away from a place whose last place card listed a verified person whose `TalkLog#last_status` was not `exhausted`; `archive` rewrites an outdated one), `star.json`, `notes.md` (owner notes from the viewer). Trace events (`dialogue` may carry `speaker`, `conversation` and `cached`; a `talk_to` result may carry `entity`; a `perception` may carry `not_ready_frames`; a `decision` may carry `autopilot`; a `keyframe` may carry `reason` and `place`; a `choose_objective` decision lists the offered candidates in `options` as `{id, label, leaves_unexhausted, picked}`): `perception`, `decision`, `action`, `objective`, `dialogue`, `lead`, `goal`,
`notable`, `place_card`, `place_name`, `item_gained`, `chest_opened` (`place`, `cell`: a chest closed at the last ready look at the place and open now, emitted by the engine), `puzzle`, `screen`, `screen_changed`, `affordance`, `keyframe`, `save`, `budget_stop`, `stop`. `budget.rb` enforces frames,
minutes, dollars and objective steps. `archive.rb` keeps a light bundle per run in git (trace gzipped, `screens/` included);
heavy artifacts stay local. A run resumes only with the same `flow_version`, ROM hash, capabilities digest and exits digest (`Run#check_exits!`)
(`Run#check_capabilities!` in `Engine.resume`: a manifest without the key is the empty digest, `false` always resumes, a
mismatch names both digests and the `fork` command to continue with the current set); a change to the play flow in code means
a new `flow_version`, publishing or retiring a capability changes only the digest.

**Atlas** (`atlas.rb`) — what every run under one or more roots observed, merged per place, read only from what the engine
wrote (`manifest.json`, the trace, `screens/`). A run whose parent is among the runs read counts its places from the fork frame on,
so a shared prefix counts once; without its parent, the prefix's places count, since nothing else holds them. Frames, dollars and
model calls always count each fork from its fork frame (as `Summary`'s `cost_usd`). Per place: label (overworld screens by map
label, column A-P = `room % 16`, row `room / 16 + 1`; other places `room/map`), first visit (run and frame), visits and runs,
deaths, the stitched texts read there (`Dialogues`, with speaker, run and frame), entity types seen on its place cards, the
`talk_to` tries and answers per type (`PlaceCard.tries`), the people types with no try at all (`untried`) and, apart, the unknown
types with no try that no card saw as an enemy or creature (`unknown_untried`), signs and doors, ways taken to neighbour screens
(same row for left and right) or through a door, never the first place change after a death (a respawn), the overworld screen an
interior opens from, items gained, puzzles, and the latest run with its screenshot (a visited screen without one is drawn hatched, "vu, sans capture"). A `place_name` is kept only with a text read at
that place, at or before it, that carries one of its words of 4 letters or more (accents and case folded); the others are counted as
withheld, since the model writes names. Leads: one per quote (`Dialogues.key`), with the claim, importance and place label of its
first reading, the runs that read it (a fork reads only its own segment's leads when its parent is read), the objectives that
followed it and those achieved, and its best status over the runs (`Leads#status`: tested, then refuted, then open). Flows: per
`flow_version`, the runs, own frames, dollars and calls, and the screens, interiors, texts, leads and items those runs reached first
among the runs read (by run id, which is chronological), from each fork frame; what a fork whose parent is not read reached before
its fork frame goes to an `inherited` row with no cost. Contact leads carry the engine's claim, not the model's. Facts (`Atlas.facts`):
one row per entry of the typed files of `data/` (addresses, entities, items, modes, place kinds, geometry, exit edges and benches,
capabilities, checkpoints) with its status, check count, provenance and note as written there, and the nested confidences of an
entry (an entity's `sword_hits`) beside its status; a capability's check count is derived, its success places
(`Capabilities.success_places`). A file that does not parse or has another shape is listed with its error, and other JSON files of
`data/` as skipped. Totals: runs, unreadable runs, frames, dollars, model calls, screens, interiors, distinct
texts, deaths, items, puzzles. `koholint atlas [--root DIR]...` writes `tmp/atlas.json` (default root `runs`; a root with no run is
an error); the viewer's `/atlas` page and `/atlas.json` read the runs root and keep one digest of plain data per run directory,
rebuilt when its trace's size or mtime changes.

**Viewer** (`viewer.rb`, `viewer/`) — a small HTTP server. A `Follower` replays the journal of the watched
run and seeks by restoring the nearest keyframe; `Feed` derives status, mode and alerts, feed, reasoning, objectives,
goal, leads and the stitched dialogue history (newest first, with the person talked to and their state) from the trace
up to the shown frame, and `Insights` the world map (places on the overworld grid or attached to the screen they were
entered from, kinds from `data/place_kinds.json` via `place_kinds.rb`; exits taken, belief grids, people, leads, and a `screenshot` flag per place served by `/screens/<room>-<map>.png`), the timeline
markers, cached by trace and shown frame, and the `cockpit` (KPIs against the manifest budget, the health band, HUD, current objective with its offered candidates, reasoning, symptoms, the place card of the current place, interiors with their entry door, leads and the dialogues grouped by person) that feeds the page: a top bar, a sticky chronological strip, three columns (screen with people, sign and door overlays, HUD and reasoning; objective and dialogues; symptoms, place card, leads) and, below, the world map in an exterior and an interiors tab, the complete inventory and the dialogue history. `Explorer` and `Registry` serve past runs (list,
read-only replays with pacing and seek, comparison via `run_compare.rb`, star, the run header and `notes.md`) and the
atlas (`/atlas`, above). It never writes game state; the only files it writes are `star.json`, `summary.json`'s `starred` and `notes.md`.

**CLI** — `cli.rb`, `bin/koholint`: `run`, `resume`, `fork`, `branch` (fork at a frame or a checkpoint of
`data/checkpoints.json`, spawn `watch` on the child, resume it, then stop the viewer and exit, or with `--keep-viewer` wait for it; say when it did not start), `verify`, `summary` (a fork's `cost_usd` counts its own decisions only, `inherited_cost_usd` the parent's; the viewer's spent figure does the same), `watch`, `archive`, `star`,
`prune-heavy`, `atlas` (above), `census` (modes, `census entities`, `census objects`, `census doors`, `census sword` or `census ready`), `ab-plan` and
`ab-report` (`ab.rb`: the fork and resume commands of an A/B between autopilot arms, or with `--arms capabilities,no-capabilities` between forks with and without the operational capabilities (`--capabilities on|off`), from one frame of a run, written to
`tmp/ab/plan.json` and `tmp/ab/run.sh`; then a table per arm measured from the fork frame on: cost, paid calls, new places and
new cells per 1000 frames, stalls, autopilot decisions, and the pre-registered criterion), `learn` and `capability list|publish|retire` (capability learning above), `bench exits` (the exit bench above; the capability arms of `ab-report` add progress, new places plus items gained plus milestone steps, per 1000 frames and per dollar, capability uses and cleared objects, a use-based criterion and a per-fork table; a new place is one no ancestor run reached, before or after the fork frame). `fork` opens a parent of any flow
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
  `data/modes.json`, `data/entities.json` and a run's `world.json`, with provenance; named branch points live in
  `data/checkpoints.json`.
- A rule a script can check is a validator, not a paragraph.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`.

## Where things are

| Need | Look at |
|---|---|
| Design rationale | `docs/superpowers/specs/` |
| Measurements of agent runs | `docs/runs/` (`index.md` lists every archived run) |
| What all runs observed, per place, lead and flow | `koholint atlas`, the viewer's `/atlas` |
| What remains | `ROADMAP.md` |
| Conventions | `AGENTS.md` |
| Commands, censuses, viewer and run storage | `docs/OPERATING.md` |
| Agent skills and harness behaviour (per flow) | `docs/AGENT_SKILLS.md` |
| Game manual digest given to the agent | `docs/AGENT_MANUAL.md` |
