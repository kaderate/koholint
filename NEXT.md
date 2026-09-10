# NEXT

Entry point for any resumption. One page, no more. Full chronological history (every session's
question/answer/decisions) lives in `docs/archive/SESSION_LOG.md` -- read it to look up a past
finding, not to resume the project.

Before adding anything here, apply `AGENTS.md`'s scope test (Process section): would this line
still be true and worth knowing once the current question is answered and forgotten? If yes, it's a
durable convention -- it belongs in `AGENTS.md`, not here.

## State as of September 9, 2026 (PLAN.md Session 4 complete)

All 7 PLAN.md Session 4 checkpoints (`after_shield_interior`, `front_yard`, `overworld_screen2`,
`villager_screen`, `shop_screen`, `screen3_north`, `house2_interior`) are regenerated and traversed
via `lib/` alone, no `legacy/` file. `house2_interior` (the 7th) was REFUTED via BFS, then FOUND
AND CONFIRMED by an Explorer session the same day via a narrower-than-one-tile alignment the BFS's
16px cell grid couldn't land on, then a follow-up Builder session rewrote
`lib/validation/checkpoint_house2_interior.rb` around that route (`Koholint::CheckpointSupport`'s
`nudge_axis!`/`cross_until_room_change!`, same pattern as the other 6 scripts) and independently
re-confirmed it -- 2 fresh runs from `villager_screen`'s checkpoint, deterministic, both landing in
21 `Navigator.move!` calls, room_id/map_id read as 169/16 each time, screenshot re-matches the bed
+ table-with-pots interior. One correction found and fixed along the way: the earlier note's
`y=106` target for the approach row isn't itself reachable (move! advances in ~8px steps from this
room's spawn parity) and a default `nudge_axis!` tolerance lands at `y=102`, which is STILL inside
the row5 false-wall band -- `y=110` is the actual clear value. Full detail and the corrected route
in `data/ram_registry.json`'s `world_topology.room177_exits` and `room_labels['169/16']`. D5's
parity condition (all 7 checkpoints passing via `lib/` alone) is met -- **`legacy/` removed**,
same commit, along with `lib/validation/oracle_grid_check.rb` and `terrain_predictor_check.rb`
(their one-time purpose -- validating `lib/`'s navigation/terrain tools against `legacy/`'s oracle
grids -- already fulfilled and recorded under D8 in `DECISIONS.md`; no other file depended on
`legacy/`).

**Indicators**

| Indicator | Value |
|---|---|
| Rooms found | 16 labeled in `data/ram_registry.json`'s `room_labels` (8 "charted", 8 "glimpsed"/less -- `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, south/east of `riverside_south_room`, both now further explored: 224/0's scroll mechanism and "totem" identity resolved, 225/0's ground-accessible extent mapped to a dead-end pocket, September 10 2026 -- no 17th room found yet). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with the 2 rooms or this session's findings). D9 visual-catalog `visual_survey` now covers 4/16 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout, same day, autonomous session) -- see `DECISIONS.md`'s D9 entry. |
| Dialogues / readable text | 13 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 4 books + 1 wall object, 9/9 tile objects resolved via OAM; house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a signpost reading "Attention aux oursins !", NOT a chest/item, added September 10 2026 -- all hypothesis/verified_count 1). |
| Terrain / collision | D8 live: reads BG tilemap signatures from VRAM (`lib/terrain.rb`), 93.1%-validated against live-probe oracle. Primary method; live probing kept as fallback. |
| SELECT map (fog-of-war) | Widest-coverage checkpoint found: `lib_explorer_225_fresh_entry.dump` (8 lit cells, superset of `main.dump`'s own 6). Clean grid PNG + 5/8 lit-cell place names read (French, in-game text -- "Village des Mouettes", "Bibliothèque", "Sud du Village", "Plage Coco" x2) September 10 2026, `select_map_screen`'s SEVENTH SESSION entry; 3 cells (the chain's earliest 2 rooms + `192/0` riverside_screen) flagged not-yet-read, not guessed. Scratchpad images ready for the Atlas (`select_map_full_*.png`), not yet pulled in. |
| Save/continue | Mechanically verified end-to-end: hold A+B+START+SELECT opens the real save menu, "SAUVEGARDER & QUITTER" writes a real `.sav` (MD5-diffed), "REVENIR AU JEU" continues at the room's own door. This is the durable-progress path -- see "Standing conventions" below. |
| Current position | `/tmp/zelda_checkpoints/main.dump` (continuous session state, not versioned -- see below), last saved September 8 17:05, around `riverside_south_room` (208/0) -- explored past the entrance September 9 2026 (world_topology.riverside_south_room_survey); its south exit into `224/0` and onward into `225/0` is now `verified`/`verified_count: 2` (world_topology.riverside_south_room_south_exit, September 10 2026, 2 independent Explorer sessions), but the route's exact tap count varies run to run (see 224/0's anomaly below) -- `main.dump` itself is untouched (Explorer scratchpad checkpoints only), so Link's real saved position is still right at the entrance. |

## Decisions in force

D1 ratified (HRAM, not OAM, for position/room). D2 obsolete (superseded by D1). D3 decided: DMG
hardware mode. D4 decided (September 8, 2026): exploration is on-demand, not exhaustive-per-screen.
D5-D7 ratified (see `DECISIONS.md`). D8 ratified (September 8, 2026): VRAM tilemap reads are the
terrain source of truth, live-probing kept as fallback. Full rationale for each: `DECISIONS.md`.

## Standing conventions

- **Language**: French with the owner, always. English in the repo (code, comments, commits,
  `data/`, `docs/`) -- always.
- **Push notifications**: send one whenever the owner's input is needed, on every meaningful
  finding, and on every Atlas update.
- **Continuous save model**: `/tmp/zelda_checkpoints/main.dump` is the single canonical
  in-progress state, overwritten in place after each session (previous version backed up to
  `/tmp/zelda_checkpoints/backups/main_<timestamp>.dump` first). Never branch from a fixed
  checkpoint per session. **Never commit a `Motherboard#dump`/`.marshal` file** -- Marshal
  serialization embeds the full copyrighted ROM binary (`MBC1#@rom`). The game's own `.sav` file
  is the safe, committable alternative (pure save data, no ROM content, ~32KB) once we're ready
  to persist progress in git.
- **Room labeling**: every newly-reached screen gets a one-word-ish English label plus a short
  visual-only description, recorded in `ram_registry.json`'s `room_labels`, keyed
  `"room_id/map_id"`.
- **Atlas**: `https://claude.ai/code/artifact/e67f636d-0b55-4762-976a-21b7cd5fc5bb`, updated after
  meaningful exploration progress, rebuilt via the scratchpad's `build_atlas.py`. Ping the owner
  on every update.
- **Explorer subagents**: dispatch world-exploration work to isolated `Agent` subagents (role
  separation per `AGENTS.md`) with a self-contained prompt (context, tools, lessons learned,
  budget, exact report format). Never use `run_in_background`/Monitor inside an Explorer's own
  script -- run everything foreground/synchronous, it has gotten subagents stuck twice.

## Paradigm to question (anti-patch, mobile-sprite interaction testing) -- OPEN September 10 2026

Three separate sessions across three different rooms have now failed to confirm interaction with
a mobile creature, each for the same underlying reason: `Navigator`'s chase/approach helpers
(`move!`, `nudge_axis!`) are built for static-target navigation and can't reliably land Link
adjacent to something that's also moving before pressing `:a` -- `front_yard`'s wandering
creature (September 9), `riverside_south_room`'s pale and tan figures (September 9-10, 4 attempts),
and `224/0`'s "totem" -- actually a mobile enemy sprite, tile=0x60 (September 10). All three are
recorded `interaction: inconclusive, not negative` -- never a confirmed refutation, just a
navigation-access gap, every time. Per `AGENTS.md`'s anti-patch rule, this is the mandatory stop:
the fourth room won't fix it either. **Owner must decide**: is it worth building a real
intercept/chase primitive for `Navigator` (tracks the target's OAM position live, adjusts approach
each step, not a single dead-reckoned move) -- a genuine new capability, out of autonomous scope
per "Autonomy executes, it does not design" -- or is chasing mobile-sprite dialogue not worth the
investment right now given everything reachable so far this way has been a hazard warning, not
plot-critical content? Also worth noting as a data point: two of these sessions (`224/0`, `225/0`)
saw Link's HUD hearts drop (3->1 in one case) with no OAM sprite adjacent in either snapshot around
the hit -- consistent with contact damage from the same fast-moving creatures, unconfirmed, and a
reason NOT to keep probing this area ad hoc in scratchpad checkpoints without the tooling fixed
first (no real save is at risk -- `main.dump` is untouched -- but it's a sign this area has real
combat, not just dialogue, and blind chasing risks a checkpoint "death" state nobody's checked the
game's handling of yet).

## Next question

Paused, awaiting the owner's go-ahead (explicit "arrête-toi et ping moi" checkpoint). Session 4
(PLAN.md) is now fully complete -- see the State section above. SELECT-map fog-of-war, crate_room's
library (9/9 objects), and `house2_interior`'s 2 telephone objects are all resolved -- see "What
NOT to redo" and `dialogues.*` for detail, not repeated here. `riverside_south_room` (208/0)'s two
entrance figures are mobile/wandering; 4 interaction attempts found no dialogue but never confirmed
genuine adjacency at the press -- INCONCLUSIVE, not negative (see
`world_topology.riverside_south_room_survey`). Its south exit into `224/0`
(riverside_south_river_room) and onward into `225/0` (riverside_flower_clearing) is now
`verified`/`verified_count: 2` (2 independent Explorer sessions, September 10 2026) -- reliable as
a procedure ("keep tapping `:right`, check room_id after each"), NOT at a fixed tap count (see
`world_topology.riverside_south_room_south_exit`). `225/0`'s previously glimpsed-only "chest-like
object" is RESOLVED, same day: it's a signpost ("Attention aux oursins !" -- a hazard warning, not
an item; see `dialogues.riverside_flower_clearing_sign`), no HUD/inventory change. `224/0`'s scroll
mechanism and "totem" identity are FULLY RESOLVED (time-based scripted scroll, totem = a mobile
contact-damage enemy sprite) -- archived to `docs/archive/SESSION_LOG.md`, full detail still in
`room_labels['224/0']`. `225/0` was explored past the signpost, same session: it does NOT scroll (fixed single
screen, confirmed), and its ground-accessible area is small and enclosed -- hedges north/west, a
water strip south/east that was never actually entered (swim-gated hypothesis, Link has no Flippers
yet, unconfirmed) -- `Navigator.probe_all` dead-ends at `down: blocked, right: blocked` in the SW
pocket. No new room transition found in 225/0. One route (hugging the top row east past the sign
toward the NE bush cluster) produced only unexplained diagonal slides, never reaching that area --
open gap for a future session. Full detail in `room_labels['224/0']`/`['225/0']`. The south band's
east extent from the original x=134,y=115 stop point (within 208/0 itself) is still unprobed.
Candidates once resumed: a dedicated multi-sample OAM-tracking session for riverside_south_room's
2 wandering figures (continuous per-frame position log, to actually catch genuine adjacency before
pressing :a) -- the same technique would also settle `224/0`'s totem-creature and `225/0`'s NE-route
question above; whether `225/0`'s water strip is genuinely Flippers-gated (untested, only inferred);
whether other already-"refuted" doors in this project deserve a re-look under the same
off-tile-grid-alignment hypothesis now confirmed for house2 (one confirmed case, not yet a proven
general rule). Also deferred, not urgent: formalizing a navigation spec/format (raised by an
external review, judged sound but not blocking).

**Real architecture question, owner-raised September 9 2026, not yet designed**: the current
walkability model (D8's `Terrain::RoomClassifier`, `walkable`/`blocked` per tile signature) is a
static snapshot that conflates several genuinely different things -- see
`terrain_collision.background_tilemap_predicts_walkability`'s three newest caveats: (1) the bottom
HUD row reads as a normal 'blocked' cell despite not being world terrain at all, (2) the same
visual object (e.g. a tree) can carry different signatures per room, by design, but nothing
currently states this explicitly for a reader reasoning about the data, (3) at least one class of
terrain (bushes) is CONDITIONALLY blocked -- passable once cut, presumably with an item Link
doesn't have yet -- and the model has no way to represent "blocked now, for a reason that could
change" versus "permanently blocked." Owner's framing: how do we build a world-model
representation that's good enough to act on now but can evolve as more is learned, and --
explicitly -- how much of getting this right is on-session judgment (mine, this conversation) vs.
something that belongs in the durable, cold-readable parts of this project (schemas, `AGENTS.md`
process rules, `DECISIONS.md`) so it doesn't depend on any one session remembering it. Needs a
real design pass, not a quick patch -- likely a Builder-role decision once scoped (changes D8's
own data model), not something to implement ad hoc.

## What NOT to redo

- Don't infer room identity from `move!`'s return value alone near a screen edge -- it can return
  `:blocked` on the exact step that actually crosses into a new room, because `position()` rebases
  once the new screen loads. Check `room_id`/`map_id` explicitly.
- Don't treat `room_id` alone as a unique room key -- `map_id` matters too (confirmed collision:
  room_id 163 is both `starting_house` (map 16) and a different outdoor room (map 0)).
- Don't look for dialogue state in a memory flag -- `0xD0-0xDF`/`0xE0-0xEF` are tilemap IDs, not
  dialogue-state bytes (confirmed all-zero during open dialogue). Render the framebuffer and read
  it visually.
- Don't assume the SELECT map screen is a stable held-open state -- it auto-cycles on its own
  timer (~96 frames: 20f delay, 36f open, 60f closed), confirmed via full-tilemap MD5 hashing.
  Panning and per-room discovery-status encoding on it were both tested and refuted.
- Don't run any save/battery-RAM script from outside `gemboy/`'s own directory --
  `battery_ram_path` is relative to cwd and silently resolves to the wrong place otherwise.
- Don't rebuild `Terrain::RoomClassifier` per-cell -- classify per signature (2x2 tile-ID block)
  and cache; that's what makes D8 cheap.
- Don't chase `starting_house`'s remaining terrain-classifier disagreements -- diminishing
  returns already measured at 93.1% agreement; not worth further tuning right now.
- Don't trust a subagent's screenshot reference after the fact without checking it's still on
  disk -- reproduce the scene directly from the relevant checkpoint if it's gone.
- Don't trust a `Terrain::RoomClassifier`-cached verdict alone to rule out a door on a given edge
  -- a shared BG-tile signature can mask a real transition behind an already-cached "blocked"
  wall from elsewhere in the room (confirmed live: room177's own known east exit was missed by a
  cache-respecting-only sweep). Check real room identity after every edge's actual move, not only
  on a classifier cache miss.
- Don't re-run another BFS/walkability-map sweep on villager_screen looking for house2's door --
  already found and confirmed (see the State section above and `data/ram_registry.json`'s
  `world_topology.room177_exits`); the BFS's 16px grid couldn't land on the actual ~8px trigger
  column, not a case of the mechanism needing one more attempt.
- Don't re-scan the BG tilemap looking for crate_room's objects -- confirmed dead end, it only
  holds floor decoration + the dialogue scratch-tile range while text is open. Its 9 objects
  (`tile=0x58`) are OAM sprites: 8 in the visible 2x4 floor grid (OAM y=48/96, x=28/60/108/140) +
  1 embedded in the north wall (OAM y=14, x=84, attrs=0x2). Read OAM (`0xFE00-0xFE9F`) directly.
- Don't re-test crate_room's 6 decorative grid positions (top/bottom rows, cols 2-4) -- exhaustively
  confirmed negative, including a side-approach and a 5x-tap deep retest on one of them.
- Don't trust a `nudge_axis!` tolerance without checking where it actually lands -- `move!`
  advances in consistent ~8px steps from a given spawn parity, so a target that isn't itself on
  that step sequence (e.g. `y=106` from villager_screen's spawn parity) resolves to whichever
  step first falls within tolerance, which can be inside a false-wall band one step short of the
  real target (confirmed: `y=102` reads as "close enough" to `106` at `tolerance: 4` but is still
  blocked; `y=110` is the real clear value). Print the landed position, don't assume the target
  was reached because the call returned.
- Don't blindly chase `front_yard`'s wandering creature (CHR-matches `villager_screen`'s
  interactive NPC, per D9) straight north from spawn -- the door column (x~80-96) is right there
  and 2 independent chase attempts walked back into `starting_house` through it by accident,
  September 9 2026. A 3rd attempt routed via `scratchpad/walkability/front_yard.json`'s own
  precomputed D8 walkability grid also failed: `Navigator.move!` reported `:blocked` twice in a
  row at the exact (row5,col3)->(row4,col3) step that grid calls walkable (x=72, pushing from
  y=92 to y=90 and no further) -- not resolved which of the grid being stale or the creature/its
  shadow transiently occupying that cell is the cause; the creature's actual interactivity is
  still genuinely unknown, not refuted. See `visual_catalog.villager_wandering_creature`'s
  `interaction_tested['162/0']` for the full 3-attempt detail before trying a 4th route.
- `screen3_north`'s tile-level OAM survey (D9 rollout, September 9 2026) found up to 6 distinct
  moving patterns, not the room's existing 3-creature narrative count -- don't assume a 1:1
  mapping between the two without re-deriving it; which tile group is which pre-tested creature
  is unresolved.
- Don't assume a stable `room_id`/`map_id` means "same screen" -- `224/0`
  (riverside_south_river_room) visually renders as 2 distinct screens under that one room_id via a
  genuine SCY hardware scroll (0->128 over ~40-60f). It is PURELY TIME-BASED, confirmed by a plain
  zero-input idle-wait reproducing it identically -- don't describe it as input-triggered, that
  theory is superseded (see `room_labels['224/0']`). Don't expect a fixed `Navigator.move!` tap
  count for 208/0->224/0->225/0 either -- runs have crossed into 225/0 after 3-7 total `:right`
  taps; the reliable procedure is "keep tapping and check room_id after each." The post-scroll idle
  drift (position changes over hundreds of frames with confirmed zero input) is stepwise, not a
  smooth current, and Link's own OAM sprite is sometimes hidden (y=244) during it -- don't read a
  visible, moving Link sprite into this without checking OAM directly; why OAM visibility differs
  between reproductions is still unresolved, not chased further (anti-patch rule, 3+ probes spent
  across 2 sessions). `224/0`'s "totem/statue" is the mobile tile=0x60 creature family, not static
  BG art -- don't expect a clean dialogue test on it without solving the same wandering-target
  chase problem already open for riverside_south_room's figures.
- `225/0`'s signpost (the room's only known interactive object, "Attention aux oursins !") is
  resolved -- don't re-approach it expecting an item; it's a hazard warning, not a chest, and
  produces no HUD/inventory change. `225/0` does not scroll (single fixed screen) and its ground-
  accessible area dead-ends at a hedge/water pocket SE of the sign (`probe_all` blocked both
  down and right there) -- don't re-walk that same SW pocket expecting a new exit; the open gap is
  the untried NE route past the sign instead (see "Next question"). `lib_explorer_225_route7.dump`
  is a real but LOW-HEALTH (1 heart) checkpoint -- resume from `lib_explorer_225_fresh_entry.dump`
  (full health) instead unless deliberately continuing from the dead end.
