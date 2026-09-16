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
| Rooms found | 24 labeled in `data/ram_registry.json`'s `room_labels` (10 "charted", 14 "glimpsed"/less -- `167/16` screen3_north_house_interior, NEW September 16 2026, found via screen3_north's own previously-unswept house door (world_topology.screen3_north_house_door_and_outdoor_telephone_search) while searching for a second outdoor telephone booth -- fully swept the same session (1 NPC dialogue, 1 mobile "dog" object, single door back out, no telephone/item found), status "charted"; `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, south/east of `riverside_south_room`, both further explored (224/0's scroll mechanism and "totem" identity resolved, 225/0's ground-accessible extent mapped plus its NE route now resolved into a real room transition); `209/0` riverside_east_room, found east of `riverside_south_room`'s south band (past the prior x=134,y=115 stop point), fully swept September 10-11 2026 (west/center then, east half via the D13 primitive) -- no bidule found anywhere in it; `179/0` shop_screen, first actually explored September 10 2026 -- turns out to be the shop's EXTERIOR yard, not its interior; see `world_topology.shop_screen_door_approach` and Next question below (SIXTH closed session September 16 2026, still no route to the door; SEVENTH session same day, non-live terrain/OAM read via `Koholint::AutonomousRecovery`, found part of the door band matches confirmed-wall signature and part has a previously uncatalogued static sprite on open-looking ground -- door itself still unreached, see Quest hypothesis below); `226/0` riverside_ne_cove, reached from `225/0`'s previously-abandoned NE route September 10 2026, fully swept September 11 2026 via the D13 primitive (status promoted glimpsed -> charted) -- no bidule found anywhere in it either, see Next question below; `227/0` riverside_se_grove, NEW September 16 2026 -- reached from `226/0`'s own SE point via a genuine sustained-hold push, correcting that point's earlier "hard wall" verdict (a tap-vs-hold false negative, not a dive-gated door -- see `world_topology.riverside_ne_cove_se_edge_sustained_hold_and_227_discovery`); fully swept the same day (status promoted glimpsed -> charted, see Quest hypothesis below) -- a small closed clearing, no bidule found). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with these rooms or this session's findings). D9 visual-catalog `visual_survey` now covers 6/20 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout + `well_platform`, `building_screen` rollout, fresh restart of an abandoned attempt, September 10 2026) -- see `DECISIONS.md`'s D9 entry. `146/0` north_corridor_room (still 20 total, was already labeled as an unreached stub) actually ENTERED for the first time September 16 2026, after the checkpoint mixup below cost a 4th anti-patch strike on the same wrong-checkpoint mistake as September 9's 3 -- see "What NOT to redo". First-survey only (D4): 3 of 4 directions open (`probe_all`), not swept. Its own `up` exit led to a new room, `130/0` (single-glance, a structure visible, see `room_labels['130/0']`); `right` led to `147/0` -- a "MAGASIN"-labeled building whose door turned out to be a real, walk-through transition into a 23rd room, `161/14` -- **the first shop interior ever reached in this project** (price-list HUD, counter, standing figure), see Quest hypothesis below. |
| Dialogues / readable text | 22 confirmed entries in `ram_registry.json`'s `dialogues` (`room167_toutou_greeting`, NEW September 16 2026 -- a generic pet-owner greeting in the newly-found `167/16`, not telephone-related, found while searching for the outdoor telephone booth; villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 8 books + 1 wall object, 9/9 tile objects resolved via OAM
(corrected September 11 2026 from an earlier, buggy "4 books" count -- see "What NOT to redo" below); house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a two-page signpost, "Attention aux oursins !" then "Se protéger avec un bouclier !" (2nd page found September 11 2026, needs a long `:a` hold to reveal), NOT a chest/item; `shop_screen_yard_npc` (179/0) -- a friendly yard NPC reciting the SAME save-tip line as room176's pair, first confirmed case of a reused dialogue asset, September 10 2026; `select_map_well_platform_place_name` (160/0) -- the SELECT box's 2-line place name ("Village des Mouettes"), September 12 2026, resolves the "2nd line" question as NOT a separate marker; `magasin_interior_shopkeeper_greeting` (161/14) -- a generic "Bienvenue! Apporte ici ce que tu veux acheter.", found September 16 2026, does not name any of the shop's 3 priced items (all hypothesis/verified_count 1). |
| Terrain / collision | D8 live: reads BG tilemap signatures from VRAM (`lib/terrain.rb`), 93.1%-validated against live-probe oracle. Primary method; live probing kept as fallback. |
| SELECT map (fog-of-war) | Widest-coverage checkpoint: `lib_explorer_225_fresh_entry.dump` (8 lit cells, superset of `main.dump`'s own 6). 6/8 cells now have a place name read from a checkpoint standing IN that exact cell's room ("Village des Mouettes", "Bibliothèque", "Sud du Village" x2 -- `176/0` and `192/0` share it, "Plage Coco" x2), `select_map_screen`'s SEVENTH + EIGHTH SESSION entries (`192/0` riverside_screen closed EIGHTH SESSION, new working route: nudge x to ~88 from `room176_entry_from_room160.dump`, then plain `:down` taps, no special alignment needed -- corrects the earlier "x=94, 8 calls" figure, which doesn't reproduce). Remaining 2 cells (the chain's earliest 2 rooms) confirmed NOT free-readable from any on-file checkpoint (checked EIGHTH SESSION) -- would need a from-boot replay. Scratchpad images ready for the Atlas (`select_map_full_*.png`), not yet pulled in. **NINTH SESSION, September 11 2026**: owner's game-manual-sourced `!?`/"message"-marker hypothesis tested directly -- REFUTED for the literal claim (no interior cell ever reuses the off-screen icon-legend block's own tile IDs, checked within-checkpoint across 7 checkpoints), but found a genuinely new fact: interior lit cells use 3 visually distinct glyphs, not one uniform "visited" dot -- a new glyph (`0xfd`) covers 4 rooms (`192/0`,`208/0`,`224/0`,`225/0`) at once, keyed to trail ROW not room content (reproduced across both coordinate-anchor families). Doesn't correlate cleanly with which rooms have confirmed dialogue, so likely decorative/distance-based, not a location hint -- see `select_map_screen`'s note for full detail, `hypothesis`/`verified_count: 1`. |
| Save/continue | Mechanically verified end-to-end: hold A+B+START+SELECT opens the real save menu, "SAUVEGARDER & QUITTER" writes a real `.sav` (MD5-diffed), "REVENIR AU JEU" continues at the room's own door. This is the durable-progress path -- see "Standing conventions" below. |
| Current position | `/tmp/zelda_checkpoints/main.dump` (continuous session state, not versioned -- see below), last saved September 8 17:05, around `riverside_south_room` (208/0) -- explored past the entrance September 9 2026 (world_topology.riverside_south_room_survey); its south exit into `224/0` and onward into `225/0` is now `verified`/`verified_count: 2` (world_topology.riverside_south_room_south_exit, September 10 2026, 2 independent Explorer sessions), but the route's exact tap count varies run to run (see 224/0's anomaly below) -- `main.dump` itself is untouched (Explorer scratchpad checkpoints only), so Link's real saved position is still right at the entrance. |

## Decisions in force

D1 ratified (HRAM, not OAM, for position/room). D2 obsolete (superseded by D1). D3 decided: DMG
hardware mode. D4 decided (September 8, 2026): exploration is on-demand, not exhaustive-per-screen.
D5-D7 ratified (see `DECISIONS.md`). D8 ratified (September 8, 2026): VRAM tilemap reads are the
terrain source of truth, live-probing kept as fallback. D9 ratified: per-room visual survey via
OAM mobility diffing + cross-room CHR pattern comparison (`visual_catalog`). D11 ratified
(September 10, 2026): before chasing a not-yet-classified mobile sprite for dialogue, run a cheap
contact/proximity test first (watch HUD hearts and Link's own position for the jump/knockback
signature) -- `visual_catalog` entries carry a `hazard_status` field (`friendly`/`hostile`/
`unknown`) for this. D12 ratified (September 10, 2026): RAM writes to gameplay state (HP via
`0xDB5A`, or any other writable mechanic found later) are for isolated tests only -- never to push
past a real in-game obstacle (e.g. topping HP up to continue exploring) without asking the owner
first, every time, never a standing blanket approval. D13 ratified (September 11, 2026): D11's
deferred hostile-avoidance `lib/navigator.rb` primitive is now being built -- the "recur a few
times first" condition was met (4 independent Explorer sessions hand-rolled the same
shield+push+HP-top-up tactic across `224/0`/`225/0`/`226/0`/`209/0`). Built and validated twice
(see `DECISIONS.md`'s D13 entry) -- `Navigator.avoid_hostiles_and_move!`/`avoid_hostiles_and_push!`
are the shipped primitive, not in-flight anymore. Full rationale for each: `DECISIONS.md`.

## Standing conventions

- **Language**: French with the owner, always. English in the repo (code, comments, commits,
  `data/`, `docs/`) -- always.
- **Push notifications**: send one whenever the owner's input is needed, on every meaningful
  finding, and on every Atlas update.
- **Screenshots in owner-facing reports**: the owner can't place a room from a `room_id/map_id`
  pair or a prose description alone (raised September 16, 2026). Any report to the owner that
  names a specific room -- a new find, a blocked door, a checkpoint's own vantage point -- must
  include a rendered PNG of it (`motherboard.ppu.export_framebuffer_png(path)`, same call
  `lib/validation/checkpoint_*.rb` scripts already use), sent via the file-delivery tool, not just
  described. Applies to the planner's own reports and to any Explorer subagent's final report
  back to the planner (the subagent should render and hand back PNG paths for its key
  checkpoints, not just prose).
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

## Quest hypothesis (current best guess + blocker)

Standing field: the single leading hypothesis for "what unblocks progress next" and what's
stopping it -- not a full quest log. Update in place when the leading guess changes; don't let
this section grow into a history (that belongs in `docs/archive/SESSION_LOG.md`).

**State as of September 11, 2026 (late)**: the sword hypothesis stands, but its most concrete
lead (Plage Coco -- `224/0`/`225/0`/`226/0`/`209/0`) is now EXHAUSTIVELY SWEPT with no item found,
and the literal "route du Sud" reading (`overworld_screen2`'s south edge) is REFUTED (real wall).
Full multi-session history of how this was established -- the Plage Coco push, D12/D13's HP-write
and avoidance-primitive decisions, the south-edge test -- is archived at
`docs/archive/SESSION_LOG.md` (look it up there, don't re-derive it from memory).

Two new NAMED leads surfaced tonight, from crate_room's library turning out to have 8 books, not
4 (owner-caught bug: 6 "hard negative" crates had only ever been tap-tested, never held for the
~110 frames a real dialogue needs -- see `dialogues.crate_room_book_e/f/g/h`):
- **"la Loupe" (magnifying glass)** -- `book_h` explicitly refuses to be read without it: "Il te
  faut la Loupe pour lire les petits caractères..." The first confirmed reference to a specific,
  named, not-yet-found item in this whole project. Not located anywhere yet. **September 12 2026
  dogfood session** (`experiment/autonomous-recovery-dogfood` branch, since deleted -- finding
  ported here and into `world_topology.front_yard_adjacent_rooms`'s dogfood addendum, the branch
  itself carried no other recoverable work): tested whether `clover_field` (163/0, glimpsed-only,
  east of `front_yard`) is reachable straight-east from `lib_front_yard.dump` (x=88,y=92) --
  REFUTED for that specific row: 16 real `Navigator.move!(:right)` calls advance x only to ~124
  then hit a real wall, room never changes. Does not refute the room's existence or the east
  transition itself, only this one row/approach. `north_corridor_room` (146/0, the other
  glimpsed-only lead) was not reached that session. **September 16 2026 follow-up (Explorer
  subagent, 3 bounded sub-attempts, anti-patch cap reached)**: retested with a genuine 400-frame
  continuous hold at y=92 (not a tap loop) -- REFUTED as a tap-timing artifact, reproduces the same
  x=124 wall (contrast with `227/0`, where the same technique did cross a tap-false wall). Also
  tried y=84 (partial, redirected into `starting_house`'s own door before reaching target) and
  y=108 -- both blocked too. **Anti-patch rule triggered**: 3 sub-attempts, no progress on any goal
  indicator, same mechanism (front_yard's east wall). Stopping here per `AGENTS.md`. Full detail:
  `world_topology.front_yard_adjacent_rooms`'s FOLLOW-UP note.
  **Paradigm to question, resolved by owner delegation, September 16 2026**: front_yard's east
  edge into `clover_field` is blocked-confirmed at 3 rows via 2 methods each -- consistent with an
  item gate (same shape as `shop_screen`'s door), not proven as one. Owner said "proceed
  autonomously per your guidelines" rather than picking between the 3 candidates listed here
  previously -- picked (b)'s `north_corridor_room` half (not the telephone-booth half): it has an
  already-confirmed route (front_yard's north corridor, column x<=24, `front_yard_adjacent_rooms`
  note above), so it's pure measurement on an established fact, no new judgment call about item
  gating or blind search -- the best fit for "autonomy executes, it does not design"
  (`AGENTS.md`). (a) needs a not-yet-known second edge to even attempt; (c) (Warp holes) has no
  known location anywhere, blind search. Not a paradigm change, no `DECISIONS.md` entry needed --
  ordinary next-question selection, same as every other "Next question proposed" pick.
  **This session's question, ANSWERED September 16 2026**: what's inside `north_corridor_room`
  (146/0)? Reached (after a checkpoint mixup, see "What NOT to redo"), first survey done. `up`
  leads to a genuinely new room, `room_id=130/map_id=0` (single-glance, see `room_labels['130/0']`).
  `right`'s initial "tan/brown object" sighting was a FALSE ALARM, resolved same session: it's
  Link's own OAM sprite self-sighted in a screenshot taken without a simultaneous OAM check, not a
  new object -- pushing further crosses cleanly into ANOTHER new room, `room_id=147/map_id=0`.
  Full detail: `room_labels['146/0']`, `world_topology.north_corridor_room_exits`.
  **MAJOR FINDING, same session**: `147/0`'s "MAGASIN"-labeled building's door IS a real, plain
  walk-through transition (no `:a` needed) -- reached from x=85,y=121, nudge x to ~72 (door column),
  push `up` 4 times. Leads to `room_id=161/map_id=14` -- **the first shop interior this project has
  ever reached**: a price-list HUD ("200"/"10"/"20" next to a tool-shaped icon, 3 hearts, and a
  shield icon), a counter, a standing figure. Full detail: `room_labels['147/0']`,
  `room_labels['161/14']`, `world_topology.magasin_door_and_shop_interior`. hypothesis/verified_count
  1, single session/method -- not yet re-confirmed independently. UNRESOLVED: whether `147/0` is the
  same physical building as `shop_screen`'s (179/0) yard seen from a different side, or a distinct
  building -- this route never touched 179/0's own geometry.
  **Follow-up, ANSWERED September 16 2026 (fresh cold-context session)**: the shopkeeper (counter
  sprite at (120,96)/(128,96)) IS interactive -- facing it and holding `:a` ~150 frames (not a
  short tap) triggers a real 2-page dialogue, `dialogues.magasin_interior_shopkeeper_greeting`:
  "Bienvenue! Apporte ici ce que tu veux acheter." A generic greeting, NOT item-specific -- no
  submenu/item-selection UI follows it (tested `:a`/directions while open, box just closes).
  Rupee count read from the HUD: **000** -- Link cannot afford any of the 3 items (200/10/20)
  regardless of identity, so purchase is untested (blocked by economy, not mechanic). The
  200-rupee icon's shape (4x crop) does NOT resemble a magnifying glass -- **not confirmed as "la
  Loupe"**, no in-game text has named any of the 3 items. Whether 179/0's yard connects to this
  interior is still untested. Full detail: `room_labels['161/14']`'s same-session addendum.
  **Follow-up, ANSWERED September 16 2026 (fresh cold-context session, owner-directed)**: checked
  Link's actual current equipped items first, per the owner's own suggestion, before any live test
  -- `wram_unmapped.equipped_b_item` already on file: B-slot (0xDB00)=4 (Shield), A-slot
  (0xDB01)=0 (empty) in every checkpoint ever sampled; `wram_unmapped.inventory` is "not found" --
  no sword anywhere in the registry. Then ran ONE bounded live test on the "cutting grass gives
  rupees" lead (owner-confirmed game-manual fact, flagged `terrain_collision` as "NOT YET
  INVESTIGATED" since September 9 2026): held `:a` for a genuine 150 frames (not a tap) while
  standing in plain open grass (`front_yard`, 162/0, `lib_front_yard.dump`), full `0xC000-0xDFFF`
  WRAM diff before/after, against a same-duration zero-input control to strip background-animation
  noise. RESULT: REFUTED for this location -- the `:a`-hold run and the idle control produced the
  byte-for-byte identical WRAM diff (same 88 addresses, all ordinary animation/counter noise);
  position, HP, room, both inventory slots, and the rendered framebuffer (HUD rupee counter still
  `000`, A-slot bracket still empty) are all unchanged. Holding `:a` in grass currently does
  NOTHING measurable -- consistent with (not new proof of) Link's empty A-slot being why no rupee
  source has been found anywhere in this project yet, the same underlying blocker as the sword
  hypothesis. Does NOT confirm grass-cutting is even this game's real rupee mechanism (still
  unobserved either way). hypothesis/verified_count 1, single location/direction (front_yard's
  base grass texture only, not a distinct tuft/bush object). Screenshots:
  `data/screenshots/front_yard_grass_a_test_before.png`,
  `data/screenshots/front_yard_hud_crop_4x_a_slot_empty_rupees_000.png`. Full detail:
  `world_topology.front_yard_grass_a_interaction_test`.
  **Next question**: rupee-sourcing and la Loupe both now read as blocked on the SAME missing
  A-slot item (no sword/cutting tool found anywhere in the registry) -- worth searching specifically
  for where an A-slot item could be obtained (an NPC gift like the shield's, a chest, a dungeon)
  rather than re-testing grass/bushes again with the current empty inventory. Whether 179/0
  connects to 147/0/161/14 by any route is also still untested.
- **shop_screen's (179/0) door, SEVENTH session finding, September 16 2026** (fresh cold-context
  session -- first real use of `Koholint::AutonomousRecovery` on a genuine blocker, per
  `docs/AUTONOMOUS_RECOVERY.md`/`.claude/skills/autonomous-recovery/SKILL.md`): rather than a 7th
  walking/push attempt (budget spent, see below), read the never-physically-probed door band
  (x=80-130,y=90-111) via `Koholint::Terrain.signature_at`/`Navigator.oam_sprites` on the on-file
  `lib_shop_screen.dump` checkpoint -- zero live movement, run for real through the recovery seam
  (`ExperimentRunner`, persisted `ResearchTask` id `81da96f2cb8607eb` at
  `.koholint/research_task.json`). Finding: part of the band (x=80-95,y=96-111) shares the EXACT
  BG signature as 2 already-confirmed real walls -- likely genuine structural wall, not a cuttable
  bush. Another part (x=96-111,y=80-95) reads plain open-grass BG signature but has a previously
  uncatalogued static OAM sprite (tile=94/0x5E) sitting directly on it -- the same
  "walkable-looking-tile-plus-invisible-sprite" pattern already proven to cause a real block
  elsewhere in this room (the SW pocket). Hypothesis `h_door_band_sprite_not_uniform_wall`: 1 of 3
  budgeted experiments used, outcome `supports`, still `open` (needs a 2nd independent experiment
  before the recovery flow calls it `supported`) -- **not yet promoted to a registry fact beyond
  hypothesis/verified_count 1**. Full detail: `world_topology.shop_screen_door_approach`'s SEVENTH
  SESSION note, `visual_catalog.shop_screen_door_band_object`.
  **EIGHTH session, ANSWERED (research-hypothesis level only) September 16 2026** (fresh
  cold-context session, resumed the same `ResearchTask` per its own instruction rather than
  starting a new one): live reconnaissance (west/south/east, not a formal experiment) found no new
  route toward the sprite cell -- reconfirms the SEVENTH session's "sealed from every side already
  reachable" reading, no new gap. The formal 2nd experiment, a CHR-byte crosscheck of the
  door-band sprite (tile=94/95) against the room's two already-confirmed-blocking bush sprites
  (tile=92/93, tile=88/89), ran for real through `ExperimentRunner`/`RecoveryCoordinator`: byte-
  distinct from both (not a mislabeled duplicate), and visually a small sparse tuft/paw-print mark
  (6/16 pixel rows inked) rather than a full bush silhouette (15/16) -- confirmed by a 6x
  framebuffer crop (`data/screenshots/shop_screen_door_band_crop_6x_eighth_session.png`). Outcome
  `supports` -- per the flow's own 2-supporting-experiment threshold, hypothesis
  `h_door_band_sprite_not_uniform_wall` is now `supported`, `ResearchTask` `status: resolved`.
  **Scope limit, stated plainly so this isn't overclaimed**: "supported" means only that a genuine,
  distinct, previously-uncatalogued static object sits in an otherwise-open-reading door-band cell,
  confirmed by 2 independent non-live methods -- it does NOT mean the object's movement-blocking
  behavior was live-tested (the cell is still physically unreached) and does NOT mean the door
  itself is any closer to being reached. **The door is still closed** -- 8 total sessions now, all
  3 open sides independently reconfirmed sealed at least twice each. Full detail:
  `world_topology.shop_screen_door_approach`'s EIGHTH SESSION note,
  `visual_catalog.shop_screen_door_band_object`'s same-session addendum. Given `147/0`'s MAGASIN
  building already leads to a real shop interior (`161/14`), the balance of evidence now favors
  reading `179/0`'s own door as unreachable background art from this side, not a live door gated
  by a missing item -- **recommend the owner confirm this reading before a 9th session repeats the
  same routing sweep a 3rd+ time** (anti-patch territory); no cutting item exists to test the
  alternative, and none is expected to change this specific reading since `161/14` already answers
  "where is the shop's real interior."
- **Warp holes** -- `book_f` describes teleporting between them ("il y a des trous Warp...").
  Never encountered/tested anywhere in this project. Could shortcut navigation if found.

Also newly known, not yet acted on: `book_e` mentions a laser-blocking shield variant beyond the
standard one (owned); `book_g` opens the real SELECT-map atlas directly from its own dialogue.
The owner-provided game manual (`docs/GAME_MANUAL_NOTES.md`, D14) flagged pushing (no item needed)
and diving (`B` in water) as untested mechanics. Both got a first real test September 12 2026 (see
below) and came back negative at the one spot each was tried -- Plage Coco's OTHER water strips
(`224/0`'s river, `226/0`'s water) are still untested for diving, and the door-approach bush cluster
specifically is still untested for pushing; worth trying there before calling either mechanic dead
for this cluster.

`shop_screen`'s door is CLOSED (anti-patch budget spent) -- bushes block its south approach, the
same conditional-terrain blocker as the sword hypothesis's core evidence. Worth a cheap retest
once any cutting item is found, not a routing problem.

**`house2_interior`'s telephone/Pépé discrepancy RESOLVED, September 11 2026** (the earlier
synthesis session's #1-ranked recommended action, run same day by a dedicated Explorer session --
full reasoning trail and outcome archived at `docs/archive/SESSION_LOG.md`). One-line answer:
it's BOTH two genuinely separate interactive objects (Pépé le Ramollo's own 4-page dialogue, and a
separate phone-on-the-table's 4-page wrong-number gag, proven simultaneously visible on screen at
once) AND Pépé's own sprite is a real, visible, solid, named NPC -- the registry had wrongly
called his sprite an "invisible trigger". Both `dialogues.house2_telephone_examine`/`_call` were
re-verified live with sustained `:a` holds: no hidden extra pages, no branch, in either. Corrected
in place in `data/ram_registry.json` (`room_labels['169/16']` and both dialogue entries), plus a
stale wrong cross-reference to `world_model.json`'s non-existent "building_screen (176/0)" entry.
**Outdoor telephone booth search, September 16 2026 (Explorer subagent)**: REFUTED for the
immediate neighborhood -- `villager_screen` (177/0) was already fully BFS-swept (83 cells) and
OAM-censused with no second building/phone-shaped object anywhere in it; `house2_interior` has a
single door, no second exit. The one genuinely unswept lead on file
(`world_topology.room161_exits_and_sprites`: screen3_north's own house structure "not probed for a
door") was run down live -- it IS a real door (plain `nudge_axis!(:y)` push north, no special
alignment), leading to a brand-new interior, `167/16` (`room_labels['167/16']`), fully explored
(1 NPC, 1 mobile "dog" object, 1 door back out) -- not a phone booth. Also read 2 SELECT-map place
names never confirmed from this checkpoint chain before: `villager_screen` = "Chez Pépé le
Ramollo" (re-confirms an EIGHTH-SESSION fact from a different checkpoint, now verified_count 2),
`screen3_north` = "Chez Mme Miaou Miaou" (new). Neither mentions a telephone. Full method:
`world_topology.screen3_north_house_door_and_outdoor_telephone_search`. Does NOT refute the
booth's existence elsewhere on the island -- Pépé's line only says "outside", not "outside this
room", and the manual confirms booths are a generic, presumably island-wide mechanic. No further
untested lead toward it is on file in this specific area; a future session should widen the search
radius rather than re-sweep villager_screen/screen3_north again.

**Three small bundled loose ends closed, September 12 2026** (Explorer session; full detail
archived at `docs/archive/SESSION_LOG.md`, one-line outcomes here): (1) the SELECT box's "never-read
2nd line" at `160/0` -- REFUTED as a separate owl/message line, it's just the same place name
("Village des Mouettes") word-wrapped onto 2 lines, confirmed stable up to 170f, nothing further
to find there (`dialogues.select_map_well_platform_place_name`). (2) `shop_screen`'s reachable bush
cluster under a genuine 400-frame sustained hold (not taps) -- CONFIRMED immovable, refutes "just
needed a real push" for that instance (`world_topology.shop_screen_door_approach`'s FIFTH SESSION
note); the exact unreached door-approach cluster is still untested. (3) `225/0`'s SW pocket under a
sustained direction+B hold (mirroring the manual's dive input) in both blocked directions --
CONFIRMED a hard wall, zero displacement/HP change/visual change either way, at least without
Flippers (`world_topology.riverside_flower_clearing_sw_pocket_dive_test`). None of the three opened
a new lead -- the sword search's two live named threads remain **"la Loupe"** and **Warp holes**
(below), plus the still-open outdoor-telephone-booth question above.

**Shop door SIXTH session (closed) + a new room via a sustained-hold correction, September 16
2026**: `shop_screen`'s door is STILL CLOSED -- a 6th session (3 new routing vectors, none opened
a gap; 2 fresh 400-frame sustained-hold pushes at the closest reachable points to the door's own
x=81-130 column, x=104,y=16 and x=122,y=32, both confirmed immovable, zero displacement/damage).
Exact geometry now pinned down on all 3 open sides: SW/bush wall at x=60,y=106 (already known),
roof-face wall at x=104-113,y=16-25 (new x-stops, same wall), NE/hedge wall at x=122,y=32 (now
hit from 2 independent entry vectors, same signature both times). No cutting item, no new lead --
still consistent with, not newly proof of, the "gated by an item Link doesn't have" hypothesis.
Full detail: `world_topology.shop_screen_door_approach`'s SIXTH SESSION note. **Separately, the
226/0 dive test (secondary mandate) found real new ground**: `226/0`'s own SE "cul-de-sac"
(x=154,y=58), previously read as a genuine 3-way wall under `Navigator.probe_all`'s short taps,
turned out to be a false negative -- a genuine 400f sustained hold toward `:right` (WITH OR
WITHOUT `:b`, a control run ruled out diving specifically) crosses into a brand-new room, **227/0
(`riverside_se_grove`)**. Not the sword/bidule (2 light-survey screenshots showed only more of the
already-known flower-creature/hazard family and hedge/sand terrain, no item, no connection to "la
Loupe"/Warp holes/the telephone booth), but a real methodological finding worth generalizing: at
least one cell in this project had been wrongly marked "blocked" because `move!`'s 2-frame taps
never held long enough to register a slow-committing transition -- see `room_labels['227/0']` and
`world_topology.riverside_ne_cove_se_edge_sustained_hold_and_227_discovery`. `227/0` itself is not
fully swept (budget) -- a future session should finish it before assuming it's a dead end, and
should consider whether other "hard wall" verdicts elsewhere in this project deserve the same
sustained-hold recheck rather than trusting the tap-based read alone.

**`227/0` fully swept, same day (dedicated Explorer session)**: CLOSED, not a dead end left open --
a small, fully self-contained clearing (x in [11,28], y in [58,80]), bounded on 3 sides by genuine
walls (each independently confirmed via its own 400f sustained hold: zero drift, zero HP change,
zero hazards_seen) and on the 4th by the already-known retreat into `226/0`. No item, chest, sign,
or NPC found; no connection to "la Loupe"/Warp holes/the telephone booth. Two things worth knowing
before touching this room again: (1) `lib_e227_entry.dump` was captured MID a one-time SCX camera-
scroll (144->224 over 20 frames, confirmed via a zero-input idle wait -- same mechanic class as
`224/0`'s SCY auto-scroll, horizontal instead of vertical), so any probe against it directly is
unreliable; use `lib_e227_entry_settled.dump` instead. (2) the discovery session's visual read of
the room's objects was wrong in two ways, corrected this session with a 4x framebuffer crop: the
"tan rock/building structure" is a PALM TREE (4 of them, one per corner, coincidentally sharing
tile IDs with an unrelated friendly NPC elsewhere), and the "2 flower-shaped plant creatures" are
BG-tilemap decoration, not OAM sprites (a genuine tile=0x60 hostile-family OAM entry does exist in
this room but reads hidden/off-screen in every settled sample taken). A small building-facade
visible in BG art beyond the north wall is a new, unreached, unchased visual lead. Full detail:
`room_labels['227/0']` (status promoted glimpsed -> charted), `world_topology.riverside_se_grove_full_sweep_and_scx_autoscroll`,
`visual_catalog.riverside_se_grove_features`.

## In-flight work (for resumability)

None currently. The `Koholint::AutonomousRecovery::ResearchTask` id `81da96f2cb8607eb` (shop_screen
door band, `.koholint/research_task.json`) reached `status: resolved` September 16 2026 (EIGHTH
session, 2nd independent supporting experiment) -- see "Quest hypothesis" above for the current
state of the underlying game goal (still blocked; a resolved *hypothesis* is not a reached door)
and `docs/archive/SESSION_LOG.md` for the full session writeup. A future session opening a new
blocker should create a fresh `ResearchTask` per `docs/AUTONOMOUS_RECOVERY.md`, not reuse this id.

## Next question

Session 4 (PLAN.md) is fully complete -- see the State section above. NOT currently paused (that
framing is stale from an earlier session); see "Quest hypothesis" above for the live thread, which
now also covers September 12 2026's three bundled closures (SELECT-box 2nd line, shop bush
sustained-hold push, 225/0 dive test) -- not repeated here. Most
of the detail below predates tonight's Plage Coco/crate_room/manual work (archived at
`docs/archive/SESSION_LOG.md`) and is kept here only for topology/dialogue reference, not as an
active question. SELECT-map fog-of-war, crate_room's
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
open gap for a future session. Full detail in `room_labels['224/0']`/`['225/0']`. `208/0`'s south
band east extent (from the original x=134,y=115 stop point) is now RESOLVED, same day: a real room
transition at x=149,y=115 into a new room, `209/0` riverside_east_room, single-glance only -- see
`world_topology.riverside_south_room_east_exit` and `room_labels['209/0']`, not chased deeper.
`shop_screen` (179/0) actually explored for the first time, same day: it's the shop's EXTERIOR
YARD, not the interior a prior session's Atlas note assumed -- a "MAGASIN" building facade ringed
by static flower-bush obstacles plus a hedge maze east side. The door itself was never reached
despite 8+ distinct routing attempts covering all 3 open sides (north over the roof, west and east
at ground level) -- every one hit a wall before the door's own column; see
`world_topology.shop_screen_door_approach` for the full attempt log and an open hypothesis (an
off-tile-grid trigger column, same shape as `house2_interior`'s door -- see D11 paragraph below).
Found and interaction-tested in the yard: a friendly NPC (tile=0x70/0x72) reciting the EXACT SAME
save-tip line as `room176_pair_a`/`room176_pair_b` -- first confirmed case in this registry of a
dialogue line reused verbatim across rooms (`dialogues.shop_screen_yard_npc`) -- and a decorative
plant/bush object, confirmed non-interactive. No shopkeeper, no buy/sell mechanic, no HUD/inventory
change -- because the interior was never reached, not because a shop mechanic was ruled out.

**`225/0`'s NE route RESOLVED, September 10 2026 (independent Explorer session)**: the "unexplained
diagonal slides" were never a real wall -- they were two stacked hazards along the route (an
invisible mobile hostile creature delivering contact knockback mid-tap, same pattern as `224/0`'s
totem and D11, plus ordinary blocking terrain: a sea-urchin OAM cluster and a flower-cluster BG
obstacle). Tactic tested per the owner's suggestion: holding B (the equipped shield) continuously
via `mmu.joypad.key_state` (not `Navigator.tap_button`, which releases every button between taps)
while pushing the route. Result: mixed but net positive -- one full clean run took zero damage
where the same route unshielded had cost 3 hearts, but a later shield-held attempt through the same
general area still lost a full heart with no OAM sprite visible adjacent in the snapshot, so the
shield mitigates the creature's knockback without eliminating all damage in the room. Working
strategy (not a fixed tap count, same caveat as every other route in this room cluster): from
`lib_explorer_225_fresh_entry.dump`, go down to y~42 before pushing east (avoids one hazard band),
back up to y~26 to continue east to x~76 where a flower cluster is a real wall, then -- the key
correction -- drop further south than instinct suggests, to y~41 (below the flower, above the
sea-urchin row), to clear it and continue east to x~124 (base of a second, NE-corner palm tree),
then south along the tree's east flank to y~65-68 and east again, which crosses room_id/map_id
from 225/0 into a brand-new room, **226/0 (`riverside_ne_cove`)**, at x=17,y=67, no damage on the
crossing itself. `226/0` itself: two palm trees, a differently-oriented hedge corner, more
sea-urchins, the same green amphibious sprite glimpsed in 225/0, and two more instances of the
tile=0x60/0x62 hostile-family creature (visually matching 224/0's "totem"). `probe_all` from the
entry point reads up/left/right all open, down blocked -- genuinely more room to explore, not a
dead end, but not pursued further this session (budget). The "bidule" item was NOT found in either
room this session. Full route, checkpoint chain, and every attempt (including the 2 that failed
and dead-ended back at x=76,y=26) are in `room_labels['225/0']`'s NE-route addendum and
`room_labels['226/0']`; the transition itself is also in
`world_topology.riverside_flower_clearing_ne_exit`. `224/0`'s own secondary sweep (also flagged as
open in its entry) was NOT attempted this session -- the NE route took far more sub-attempts than
budgeted, leaving no time for it; still open for a future session.

**D11 hazard-classification pass, September 10 2026 (Explorer session)**: `front_yard`'s creature
(D9's byte-identical CHR match to `villager_screen`'s confirmed-friendly NPC) got a 4th navigation
attempt using the adaptive live-OAM-tracking method D11 authorized -- still INCONCLUSIVE, not
refuted: 2 sub-attempts stayed in `front_yard` (avoiding the known door-column trap) but both got
wedged at a real obstacle, x=88,y=82-84 (a building-side wall, now independently reconfirmed by 2
sessions/2 different chase heuristics -- see `visual_catalog.villager_wandering_creature`'s
`interaction_tested['162/0']`). No `:a` was pressed; the creature's own interactivity is still
unknown. Separately, `hazard_status` was added across `visual_catalog` per D11:
`riverside_south_pale_creature` (tile=0x6c, never tested before) got 2 contact-test approaches --
both produced a knockback-shaped position jump on Link, but the creature wasn't confirmed on-screen
at the exact jump instant, so it's "unknown, suggestive of hostile" not a clean classification.
`riverside_east_room` (209/0)'s two sprites (tile=0x62 and 0x68/0x6a) turned out, via a 4-sample
idle animation log, to cycle through the SAME tile set (0x60/0x62/0x64/0x66/0x68/0x6a) as the
already-confirmed-hostile `riverside_south_tan_creature` and `riverside_south_river_room_sprite`
(224/0's totem) -- classified `hostile` mainly on that family match, plus one observed wrong-axis
13px jump while a family-tile creature was in close range. See `visual_catalog.riverside_east_room_creatures`,
`.riverside_south_pale_creature`, and `.villager_wandering_creature` for full detail. The
off-tile-grid-alignment hypothesis first confirmed for house2's door now has a SECOND candidate
case (`shop_screen`'s own unreached door, see above) -- still not a proven general rule, but worth
trying on any future "walled-off door" before assuming it's a genuine dead end. Also deferred, not
urgent: formalizing a navigation spec/format (raised by an external review, judged sound but not
blocking).

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

- Don't read an "unidentified object" off a single screenshot without an `oam_sprites` check at
  that exact position first -- a `north_corridor_room` sighting (September 16 2026) that looked
  like a new tan/brown object turned out to be Link's own 2-tile OAM sprite (tile 0/2, X-flip),
  confirmed only once a follow-up pass checked OAM at the same spot. Take the screenshot AND the
  OAM census from the same state, not a screenshot alone, before flagging a sighting as new.
- Don't start a `front_yard` (162/0) route from `lib_front_yard.dump` (x=88,y=92) when the
  documented route needs a different row -- `lib_front_yard.dump` sits in a mid-screen band
  (roughly y=56-96) that's blocked going west at x=52 (hut/bush obstacle, `probe_all` confirmed
  `left: blocked` at 4 sampled y's). The `north_corridor_room` (146/0) west-then-north route
  specifically needs `front_yard_navigator.dump` (x=88,y=131, near the south edge) instead -- this
  exact mistake cost anti-patch strikes twice (September 9 AND September 16 2026, 3+1 wasted
  attempts) before being caught. Check `room_labels`/`world_topology` for a checkpoint's *exact*
  starting position before assuming any `lib_*.dump` is interchangeable with an older one for the
  same room.
- A checkpoint dump saved before gemboy commit `d3278c7` (Sep 8 2026, APU::PeriodDivider
  accumulator fix) crashes on `Motherboard.load` the moment any input advances a frame
  (`NoMethodError` on a nil accumulator, since `Marshal` skips `#initialize`) -- confirmed a
  dump-age issue, not a code bug. If an old checkpoint crashes like this, don't fight it with a
  workaround script repeatedly; re-save a fresh checkpoint from a currently-working one instead.
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
- CORRECTED September 11 2026: crate_room's 6 "decorative" grid positions (top/bottom rows, cols
  2-4) are NOT decorative -- all 6 are real book stands, confirmed the same day via a sustained
  ~110-120 frame `:a` hold from a fresh approach. The prior "exhaustively confirmed negative"
  claim (including a side-approach and a 5x-tap retest) was itself the bug: short taps, even
  repeated ones with long settle waits between them, don't trigger these objects. Don't re-test
  them again expecting a negative -- see `dialogues.crate_room_book_a/b/e/f/g/h` and
  `world_topology.crate_room_and_riverside_content`'s correction paragraph for the full text and
  root cause. If a future session revisits this room, watch for the companion positioning trap
  found alongside this fix: an approach column off by more than ~5-6px from a crate's true
  ~8px-wide hitbox silently walks straight past it (every `move!` reads `:ok`) instead of
  blocking -- align x tightly before the final vertical approach, don't trust "reached the row"
  as "reached the crate."
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
  `interaction_tested['162/0']` for the full 3-attempt detail before trying a 4th route. UPDATE
  September 10 2026: a 4th attempt (adaptive live-OAM-tracking, D11-mandated) avoided the door
  column successfully but got wedged at x=88,y=82-84 instead -- a real building-side wall,
  independently reconfirmed by 2 sessions/2 methods now. Route AROUND it (clear x<80 or x>100
  before descending below y=84) rather than a straight-north dominant-axis chase; don't retry a
  5th straight-through attempt without that fix. Per the anti-patch rule this is now 3 distinct
  sub-attempts within D11's mandate alone (6 total project-wide) -- needs a genuinely different
  approach, not a 7th chase, if tried again.
- Tile IDs 0x60/0x62/0x64/0x66/0x68/0x6a are NOT distinct creature species -- confirmed September
  10 2026 via a 4-sample idle animation log in `riverside_east_room` (209/0): both of that room's
  sprites cycle through the whole set frame to frame. Treat any single tile ID in this range as one
  animation/directional frame of the same creature family (already confirmed hostile via
  `riverside_south_tan_creature` and `riverside_south_river_room_sprite`/224's totem), not a new
  species to re-catalog from scratch. See `visual_catalog.riverside_east_room_creatures`.
- `screen3_north`'s OAM survey found up to 6 distinct moving patterns, not the room's 3-creature
  narrative count -- don't assume a 1:1 mapping without re-deriving it (unresolved, low priority).
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
- `225/0`'s signpost (the room's only known interactive object) is resolved -- don't re-approach it
  expecting an item; it's a hazard warning, not a chest, and produces no HUD/inventory change.
  CORRECTED September 11 2026: it's a TWO-page dialogue ("Attention aux oursins!" then "Se protéger
  avec un bouclier!"), not single-page -- a quick default-length 2nd `:a` tap dismisses it before
  page 2 renders; a ~110-frame hold on the 2nd `:a` is needed to see it (see
  `dialogues.riverside_flower_clearing_sign`). Don't re-read the single-page version as the full
  text. `225/0` does not scroll (single fixed screen) and its SW
  ground pocket dead-ends at a hedge/water boundary (`probe_all` blocked both down and right
  there) -- don't re-walk that pocket expecting a new exit. The NE route past the sign is NO
  LONGER an open gap -- it's resolved into a real transition into `226/0`, see "Next question" for
  the working strategy (hold the shield, and specifically drop to y~41, not y~26/34, to clear the
  flower-cluster wall around x=76) before attempting a straight re-push at the old y=26 band, which
  is a confirmed hard wall there. `lib_explorer_225_route7.dump` is a real but LOW-HEALTH (1 heart)
  checkpoint -- resume from `lib_explorer_225_fresh_entry.dump` (full health) instead unless
  deliberately continuing from the dead end. The exact per-leg tap counts on the NE route are not
  reproducible at a fixed count (same caveat as every other route in this room cluster) -- treat
  only the y-band strategy as durable, re-derive the taps live via `probe_all`/room_id checks.
- `160/0`'s SELECT-box "2nd line" is NOT a separate owl/message marker -- confirmed September 12
  2026 (hold SELECT+A up to 170f, pixel-stable from 110f on) it's just the room's own place name
  ("Village des Mouettes") word-wrapped onto 2 lines because it's longer than this project's other
  single-line place names. Don't re-investigate it as a distinct mechanic; see
  `dialogues.select_map_well_platform_place_name`.
- `shop_screen`'s reachable SW-corner bush cluster (near `lib_shop_wide3.dump`, NOT the still-
  unreached door-approach cluster) is confirmed immovable under a genuine 400-frame continuous hold
  (September 12 2026), not just the earlier raw-tap test -- don't re-run a "maybe it just needed a
  real push" retest on this same reachable cluster; see `world_topology.shop_screen_door_approach`'s
  FIFTH SESSION note. The exact door-approach cluster (x=81-94/96-130,y=96-111) is still untested by
  any push method, reachable or not.
- `225/0`'s SW pocket is confirmed a hard wall under a sustained direction+B hold too (both `down`
  and `right`, 400 frames each, September 12 2026), not just ordinary movement -- don't re-test
  "maybe diving does something" here without a cutting/swimming item Link doesn't have yet
  (Flippers); see `world_topology.riverside_flower_clearing_sw_pocket_dive_test`.
- `shop_screen`'s door is closed on all 3 open sides now with a 6th session's worth of evidence,
  including 2 fresh 400-frame sustained-hold pushes (September 16 2026) at the closest reachable
  points to the door's own column (x=104,y=16 and x=122,y=32, both confirmed immovable) -- don't
  re-sweep any of the 3 known walls (x=60,y=106 SW/bush, x=104-113,y=16-25 roof-face, x=122,y=32
  NE/hedge) again without either a cutting item or a genuinely different method (e.g. a
  `lib/terrain.rb` signature read of the door's own cell, no live probing); see
  `world_topology.shop_screen_door_approach`'s SIXTH SESSION note.
- `Navigator.probe_all`/`move!`'s short 2-frame taps produced at least one confirmed false
  "blocked" negative (226/0's SE point, x=154,y=58 -- see
  `world_topology.riverside_ne_cove_se_edge_sustained_hold_and_227_discovery`): a genuine 400f
  sustained hold crossed cleanly into a new room where taps always read all-3-directions-blocked.
  Don't trust a tap-based "hard wall" verdict anywhere in this project as final without at least
  considering a sustained-hold recheck, especially near water/scroll terrain -- the gap was NOT
  diving-specific (a no-B control crossed identically), so this isn't only a water-mechanic
  caveat.
- Don't re-test grass-cutting-for-rupees with Link's current inventory expecting a different
  result -- a genuine 150-frame `:a` hold in open grass (`front_yard`) produced a WRAM diff
  byte-for-byte identical to a same-duration zero-input control, September 16 2026 (A-slot is
  empty, 0xDB01=0). Confirmed nothing measurable happens, not a timing/hold-length artifact; see
  `world_topology.front_yard_grass_a_interaction_test`. An A-slot item would be a genuinely
  different, decisive retest -- the empty-handed case doesn't need repeating.
- `CheckpointSupport.nudge_axis!` burns its whole `max_steps` budget without noticing if the
  target axis is on the far side of a real obstacle (confirmed September 16 2026, `161/14`
  magasin_interior: nudging x toward the counter's column hit `Navigator.move!(:right): :blocked`
  8 times in a row, `max_steps` exhausted, landing well short of the intended target with zero
  useful progress after the first hit) -- same class of gap as D13's own documented one for
  `avoid_hostiles_and_push!` (`world_topology.shop_screen_door_approach`'s D13 addendum: neither
  helper detects "the last N calls all hit the same wall" and stops itself). Don't assume
  `nudge_axis!`'s returned position is close to the requested target just because it returned --
  print the landed position and compare, and don't re-issue it blindly toward a target that's
  behind a sprite/furniture object already known (or suspected) to block that direction.
