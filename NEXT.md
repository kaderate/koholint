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
| Rooms found | 16 labeled in `data/ram_registry.json`'s `room_labels` (8 "charted", 8 "glimpsed"/less -- adds `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, September 10 2026, south/east of `riverside_south_room`). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with the 2 new rooms). D9 visual-catalog `visual_survey` now covers 4/16 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout, same day, autonomous session) -- see `DECISIONS.md`'s D9 entry. |
| Dialogues / readable text | 12 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 4 books + 1 wall object, 9/9 tile objects resolved via OAM; house2_interior's 2 OAM-verified telephone objects, both hypothesis/verified_count 1, September 9 2026). |
| Terrain / collision | D8 live: reads BG tilemap signatures from VRAM (`lib/terrain.rb`), 93.1%-validated against live-probe oracle. Primary method; live probing kept as fallback. |
| Save/continue | Mechanically verified end-to-end: hold A+B+START+SELECT opens the real save menu, "SAUVEGARDER & QUITTER" writes a real `.sav` (MD5-diffed), "REVENIR AU JEU" continues at the room's own door. This is the durable-progress path -- see "Standing conventions" below. |
| Current position | `/tmp/zelda_checkpoints/main.dump` (continuous session state, not versioned -- see below), last saved September 8 17:05, around `riverside_south_room` (208/0) -- explored past the entrance September 9 2026 (world_topology.riverside_south_room_survey) and its real south exit found September 10 2026 (world_topology.riverside_south_room_south_exit, leads to `224/0`), but `main.dump` itself is untouched (Explorer scratchpad checkpoints only), so Link's real saved position is still right at the entrance. |

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

## Paradigm to question (anti-patch, house2_interior) -- RESOLVED September 9 2026

house2_interior's door is FOUND and CONFIRMED (candidate (a) above, sub-pixel/alignment, was the
right one). Full evidence in `data/ram_registry.json`'s `world_topology.room177_exits` (search
"DOOR FOUND AND CONFIRMED"). Summary: the row directly south of the door (row5, y=80..95) is a
false floor -- blocked by the building's own footprint at x=100,y=82 (a genuine wall, 0px progress
across 38 raw taps). The real approach detours one row further south (row6, y~106, already known
open) before turning toward the door's column and pushing up. Once aligned, the transition takes
as few as 6 raw taps / 2 `Navigator.move!` calls -- `Navigator.move!`'s `MAX_TAPS = 8` was NEVER
the bottleneck; do not raise it on the strength of this. The real constraint: the door's trigger
column is only ~8px wide (x=72/76 worked; x=64/68/80/88, each just 4-8px off, did not), narrower
than the 16px tile grid `Navigator`/`Terrain::RoomClassifier` currently reason in -- which is
exactly why the earlier BFS (cell-snapped to 16px) never found it. New room reached: `169/16`
(`house2_interior` in `room_labels`), a house interior (bed, table with pots), not yet explored
beyond the entry glance. Explorer checkpoint (not the canonical Builder one):
`/tmp/zelda_checkpoints/lib_house2_interior_explorer.dump`.

## Next question

Paused, awaiting the owner's go-ahead (explicit "arrête-toi et ping moi" checkpoint). Session 4
(PLAN.md) is now fully complete -- see the State section above. SELECT-map fog-of-war is CONFIRMED
and d-pad-cursor-while-box-open is tested negative (32 combinations; double-A/`:b`/select-release/
pre-existing-hold untested but not a priority) -- both resolved, no longer open questions. Crate_room's
library is fully read, 9/9 objects (September 9 2026) -- also resolved, see "What NOT to redo".
`house2_interior` (169/16) explored past the entry glance, same day: no NPCs or items, but 2
OAM-verified interactive objects (a telephone giving a hint-flavored monologue, and the phone
itself ringing into a comedic wrong-number call) -- see `dialogues.house2_telephone_examine`/
`house2_telephone_call` -- also resolved. `riverside_south_room` (208/0) also explored past the
entrance, same day: its two entrance figures turned out to be mobile/wandering (not static), and
4 interaction attempts across the session found no dialogue but never confirmed genuine
adjacency at the press -- INCONCLUSIVE, not negative, same call already made once for
front_yard's wandering creature; see `world_topology.riverside_south_room_survey`. Its south band
(an S-curved paved path) has its south exit FOUND September 10 2026 -- a single move south crosses
into `224/0` (riverside_south_river_room, see `world_topology.riverside_south_room_south_exit`),
which itself has an unresolved anomaly (visually distinct 2nd screen under the SAME room_id, plus
idle-frame position drift with no input held -- not explained, not a priority to chase alone) and
leads on to a 3rd room glimpsed only (`225/0`). The south band's east extent from the original
x=134,y=115 stop point is still unprobed. Candidates once
resumed: a dedicated multi-sample OAM-tracking session for riverside_south_room's 2 wandering
figures (continuous per-frame position log rather than isolated snapshots, to actually catch
genuine adjacency before pressing :a); retest `riverside_screen`'s signpost with a positive
control. Also deferred, not urgent: formalizing a
navigation spec/format (raised by an external review, judged sound but not blocking); whether other
already-"refuted" doors in this project deserve a re-look under the same off-tile-grid-alignment
hypothesis now confirmed for house2 (not yet tested elsewhere -- one confirmed case, not yet a
proven general rule); the book_a/book_b vs. OAM discrepancy flagged in
`world_topology.crate_room_and_riverside_content` (their notes claim "BG object, not OAM sprite",
but this session's full-room OAM read accounts for all 9 `tile=0x58` objects with none left over --
unresolved, orthogonal to the content itself, not worth a dedicated round right now).

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
  see "Paradigm to question" above, the mechanism itself was exhausted, not one attempt short.
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
  (riverside_south_river_room) visually renders as 2 distinct screens under that one room_id, and
  a single `Navigator.move!` step between them jumped ~94px in one axis (see
  `room_labels['224/0']`). Check the screenshot, not just the room key, before concluding nothing
  moved. Also unresolved there: position drifted over idle frames with zero input held -- don't
  read that as a script bug before checking the room's own footage.
