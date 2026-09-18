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
| Rooms found | 27 labeled in `data/ram_registry.json`'s `room_labels` (17 "charted", 10 "glimpsed"/less). `163/0` clover_field promoted glimpsed -> charted September 17 2026 -- a SECOND route in was found (147/0's own south exit, never probed before), not the already-anti-patch-closed front_yard east approach; full survey found its south edge bridges into shop_screen (179/0) via 2 corridors flanking a central impassable clover-clump obstacle, resolving whether 147/0 and 179/0's yard are the same building (they are not; clover_field sits between them) -- no item/chest/NPC found. See Quest hypothesis below and `world_topology.clover_field_second_route_and_shop_connection`. `193/0` riverside_east_meadow, found September 17 2026 via `riverside_screen`'s (192/0) own EAST edge (a plain tap-through transition, not a wall), then FULLY SURVEYED a follow-up session the same day: its south edge is a real wall except at one column that loops back into already-charted `209/0`, and its own east edge (`x=155`, previously tap-false-negative) leads via a sustained hold into 2 MORE new rooms, `194/0` riverside_narrows (glimpsed) and `195/0` riverside_lake_cove (glimpsed, contains this cluster's real water/lake feature -- the earlier "lake in 193/0's south" VRAM-dump read is now believed to have been a HUD-row misread, see Quest hypothesis below) -- status promoted glimpsed -> charted for `193/0`; no chest/sign/NPC/item found in any of the 3 rooms, "Cave Flagello" still not located, see Quest hypothesis below. -- `208/0` riverside_south_room promoted glimpsed -> charted September 16 2026, its own last untested edge (WEST) confirmed a genuine hard wall via 3 independent y-bands, taps AND a 400-frame sustained hold each, no item/chest/NPC found -- see world_topology.riverside_south_room_survey's `west_edge_test` and Quest hypothesis below; `167/16` screen3_north_house_interior, NEW September 16 2026, found via screen3_north's own previously-unswept house door (world_topology.screen3_north_house_door_and_outdoor_telephone_search) while searching for a second outdoor telephone booth -- fully swept the same session (1 NPC dialogue, 1 mobile "dog" object, single door back out, no telephone/item found), status "charted"; `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, south/east of `riverside_south_room`, both further explored (224/0's scroll mechanism and "totem" identity resolved, 225/0's ground-accessible extent mapped plus its NE route now resolved into a real room transition); `209/0` riverside_east_room, found east of `riverside_south_room`'s south band (past the prior x=134,y=115 stop point), fully swept September 10-11 2026 (west/center then, east half via the D13 primitive) -- no bidule found anywhere in it; `179/0` shop_screen, first actually explored September 10 2026 -- turns out to be the shop's EXTERIOR yard, not its interior; see `world_topology.shop_screen_door_approach` and Next question below (SIXTH closed session September 16 2026, still no route to the door; SEVENTH session same day, non-live terrain/OAM read via `Koholint::AutonomousRecovery`, found part of the door band matches confirmed-wall signature and part has a previously uncatalogued static sprite on open-looking ground -- door itself still unreached, see Quest hypothesis below); `226/0` riverside_ne_cove, reached from `225/0`'s previously-abandoned NE route September 10 2026, fully swept September 11 2026 via the D13 primitive (status promoted glimpsed -> charted) -- no bidule found anywhere in it either, see Next question below; `227/0` riverside_se_grove, NEW September 16 2026 -- reached from `226/0`'s own SE point via a genuine sustained-hold push, correcting that point's earlier "hard wall" verdict (a tap-vs-hold false negative, not a dive-gated door -- see `world_topology.riverside_ne_cove_se_edge_sustained_hold_and_227_discovery`); fully swept the same day (status promoted glimpsed -> charted, see Quest hypothesis below) -- a small closed clearing, no bidule found). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with these rooms or this session's findings). D9 visual-catalog `visual_survey` now covers 6/20 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout + `well_platform`, `building_screen` rollout, fresh restart of an abandoned attempt, September 10 2026) -- see `DECISIONS.md`'s D9 entry. `146/0` north_corridor_room (still 20 total, was already labeled as an unreached stub) actually ENTERED for the first time September 16 2026, after the checkpoint mixup below cost a 4th anti-patch strike on the same wrong-checkpoint mistake as September 9's 3 -- see "What NOT to redo". First-survey only (D4): 3 of 4 directions open (`probe_all`), not swept. Its own `up` exit led to a new room, `130/0` (single-glance, a structure visible, see `room_labels['130/0']`); `right` led to `147/0` -- a "MAGASIN"-labeled building whose door turned out to be a real, walk-through transition into a 23rd room, `161/14` -- **the first shop interior ever reached in this project** (price-list HUD, counter, standing figure), see Quest hypothesis below. `130/0` FULLY SURVEYED September 16 2026 (follow-up session): a small, fully enclosed dead-end pocket -- a building facade with two dark door/window-shaped openings is visible but confirmed unreachable (2 independent 400-frame sustained-hold rechecks, both hard walls), no item/chest/NPC found, promoted glimpsed -> charted; `146/0`'s own last uncharacterized exit (`down`) live-tested the same session, confirmed the plain return to `front_yard` -- all 4 of its exits now characterized. See Quest hypothesis below. `178/0` overworld_screen2's "landmark" object turned out to BE the telephone booth (Sept 17 2026 correction, own real walk-through door found, leading to a 25th room, `203/16` telephone_booth_interior, glimpsed) -- see Quest hypothesis below. |
| Dialogues / readable text | 25 entries in `ram_registry.json`'s `dialogues` (`room167_toutou_greeting`, NEW September 16 2026 -- a generic pet-owner greeting in the newly-found `167/16`, not telephone-related, found while searching for the outdoor telephone booth; villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 8 books + 1 wall object, 9/9 tile objects resolved via OAM
(corrected September 11 2026 from an earlier, buggy "4 books" count -- see "What NOT to redo" below); house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a two-page signpost, "Attention aux oursins !" then "Se protéger avec un bouclier !" (2nd page found September 11 2026, needs a long `:a` hold to reveal), NOT a chest/item; `shop_screen_yard_npc` (179/0) -- a friendly yard NPC reciting the SAME save-tip line as room176's pair, first confirmed case of a reused dialogue asset, September 10 2026; `select_map_well_platform_place_name` (160/0) -- the SELECT box's 2-line place name ("Village des Mouettes"), September 12 2026, resolves the "2nd line" question as NOT a separate marker; `magasin_interior_shopkeeper_greeting` (161/14) -- a generic "Bienvenue! Apporte ici ce que tu veux acheter.", found September 16 2026, does not name any of the shop's 3 priced items (all hypothesis/verified_count 1). `starting_house_npc_bench`/`starting_house_npc_beds` promoted `hypothesis` -> `verified` (verified_count 2), September 16 2026 -- independently re-triggered live, both cycle to page 1 on a further `:a` press, the bench NPC is named Tarkin/Tarin in dialogue (`near_tarkin.dump`'s own first-meeting text, a new `world_topology.near_tarkin_first_meeting_live_retrigger` entry, not counted here), and the "`[nom vide/non rendu]`" name slot renders as `A`, not blank. `room203_pepe_phone_call` (203/16), found September 17 2026 earlier the same day -- see Quest hypothesis, now `verified`/`verified_count 2` (independently re-triggered live this session). `riverside_screen_signpost_cave_flagello` (192/0), NEW September 17 2026 -- a two-line signpost naming "Cave Flagello" and "Plage Coco", `verified`/`verified_count 2`; see Quest hypothesis below. |
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
- **Clue cross-referencing**: `lib/clue_cross_reference.rb` (`ruby lib/clue_cross_reference.rb`)
  cross-references `dialogues.*.text` against `select_map_screen.note`/`room_labels` place names;
  run it once per new dialogue or place-name fact captured (see `METAPLANNER.md#MP10`).

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
  **Follow-up, ANSWERED September 16 2026 (fresh cold-context session)**: swept the 2 remaining
  genuinely-unswept frontier edges on file -- `130/0` (`north_corridor_room`'s `up` exit, single-
  glance only before this session) and `146/0`'s own last uncharacterized exit (`down`). BOTH
  DEAD-END INTO ALREADY-KNOWN TERRITORY, no new lead: `130/0` is a small, fully enclosed pocket --
  a building facade with two dark door/window-shaped openings is VISIBLE but its `up`/`right` edges
  are both confirmed HARD WALLS via independent 400-frame sustained holds (zero drift, zero HP
  change, ruling out a tap-false-negative same as `227/0`'s own discovery method) -- no item,
  chest, sign, or NPC found, promoted glimpsed -> charted. `146/0`'s `down` exit, live-tested for
  the first time (previously only assumed by symmetry with its own entry route), is confirmed the
  plain return to `front_yard` (162/0) -- all 4 of `146/0`'s exits are now genuinely characterized,
  nothing left unswept in that room. Full detail: `room_labels['130/0']`,
  `world_topology.room130_survey_and_building_facade_dead_end`,
  `world_topology.north_corridor_room_exits`' `down_exit_addendum`. Screenshots:
  `data/screenshots/room130_building_facade.png`, `data/screenshots/room130_dead_end_pocket.png`,
  `data/screenshots/room146_down_to_front_yard.png`.
  **Next question**: rupee-sourcing and la Loupe both still read as blocked on the SAME missing
  A-slot item (no sword/cutting tool found anywhere in the registry). Both frontier edges known
  from `north_corridor_room`'s neighborhood are now closed with no A-slot lead -- the search needs
  to widen again, same lesson as the September 16 telephone-booth session: a genuinely new area
  (not a re-sweep of `130/0`/`146/0`/`147/0`/`161/14`/`179/0`/Plage Coco/`villager_screen`/
  `screen3_north`, all closed or exhausted) is the only kind of lead worth chasing next -- an NPC
  gift like the shield's, a chest, or a dungeon entrance nobody has found yet. Whether `179/0`
  connects to `147/0`/`161/14` by any route, or whether `130/0`'s building is enterable from some
  other, still-unknown room, is also still untested (out of scope for the edges swept this
  session).
  **`riverside_south_room` (208/0) WEST edge, ANSWERED September 16 2026 (fresh cold-context
  session, widening the search per this same paragraph's own instruction)**: the one edge in this
  room never tested from any direction (`world_topology.world_map_reconstruction`'s
  `frontier_untested_edges`) is a GENUINE HARD WALL, not a hidden door -- closed, not a new lead.
  From `lib_explorer_riverside_south.dump` (x=112,y=101, full HP), pushed west with ordinary taps
  to the room's actual boundary, x=20, reached and reproduced at 3 independent y-bands: y=90
  (north hedge-maze band), y=99 and y=123 (south open-grass band, upper and lower). All 3 read
  `probe_all` `left: :blocked`; per this project's own tap-vs-hold false-negative lesson (the
  method that found `227/0`), each was rechecked with a genuine continuous 400-frame `:left` hold
  via `mmu.joypad.key_state` -- zero real displacement (max 1px animation jitter), zero room
  change, zero HP change, all 3 times. No chest, NPC, sign, or new room found. `208/0` promoted
  glimpsed -> charted (all 4 edges now characterized; only the room's 2 wandering figures'
  interactivity remains genuinely unknown, a separate open item, not a blocked edge). Full detail:
  `world_topology.riverside_south_room_survey`'s `west_edge_test`. Screenshots:
  `data/screenshots/room208_west_edge_survey_start.png`,
  `data/screenshots/room208_west_edge_north_band.png`,
  `data/screenshots/room208_west_edge_south_band.png`,
  `data/screenshots/room208_west_edge_south_row_lower.png`.
  **`well_platform` (160/0) WEST front-notch strip, ANSWERED September 16 2026 (fresh
  cold-context session)**: the one untested fragment of 160/0's west edge (`y~40-75`) is ALSO a
  genuine river/hedge boundary, not a hidden door. `room160_entry.dump` (the only on-file
  checkpoint standing in 160/0) predates gemboy commit `d3278c7` and crashed on load with the
  already-documented `@current_period_div_accumulator` nil bug -- fixed the same throwaway-script
  way as `main.dump`/`front_yard_navigator.dump` before it (force each channel's period_divider
  accumulator to 0 post-load). Routing to the target band surfaced a NEW blocker not previously on
  file: the well/altar's 4 flanking pillar-shaped OAM decorations block a naive straight-west push
  at `y=74-114` (separate from the hedge, x=100-132 band) -- had to route south below them, west to
  the already-documented tree (x=68) and river wall (x=36), then north along the river bank into
  the flagged band. Reached 2 independent points squarely inside it, `x=36,y=58` and `x=36,y=74`
  (both at the corner where the hedge's west arm meets the river) -- both read `probe_all`
  `left: :blocked` (y=58 also `up: :blocked`), and per this project's tap-vs-hold false-negative
  lesson, each was rechecked with a genuine 380-frame sustained hold via `key_state`: zero
  displacement, zero HP change, zero room change, every time. No chest, NPC, sign, or new room
  found. `160/0`'s west edge is now fully characterized end to end (hedge base, pillar/well
  decoration band, tree, river wall at multiple rows) -- nothing left unswept on this edge. Full
  detail: `world_topology.room160_exits_and_content`'s `west_edge_notch_test`. Screenshots:
  `data/screenshots/room160_notch_band_x36_y58_4x.png`,
  `data/screenshots/room160_notch_band_y74_hold_4x.png`,
  `data/screenshots/room160_notch_sw_blocked_4x.png` (the new pillar-decoration blocker),
  `data/screenshots/room160_x68_y122_tree_4x.png`.
  **Next question, updated**: with `208/0` AND `160/0`'s WEST edge now both closed, the only
  still-genuinely-open frontier edge on file (per `world_topology.world_map_reconstruction`'s
  `frontier_untested_edges`) is `riverside_screen` (192/0) EAST's soft/undistinguished edge --
  untested, not yet closed either way. No A-slot item lead has surfaced across FIVE consecutive
  edge-closure sessions now (Plage Coco, the outdoor-telephone-booth neighborhood, `130/0`,
  `146/0`'s exits, `riverside_south_room`'s west edge, and now `160/0`'s own last strip) -- edge-by-
  edge spatial sweeping of already-glimpsed rooms is running out of untested edges to sweep at all,
  not just failing to find the item on the ones it tries. The search needs either a genuinely new
  area (an NPC gift, a chest, or a dungeon entrance nobody has found yet) or a different method
  entirely (e.g. re-reading the project's own collected dialogue for a missed clue) rather than
  another edge re-sweep of already-closed territory.
- **Combat-contact test, NINTH session (of this cluster), September 16 2026 (fresh cold-context
  session)**: per the "different method entirely" option above, tested a genuinely new kind of
  question instead of another edge sweep -- every prior session (D11/D13) built tactics to AVOID
  hostile creatures; nobody had tested what deliberate contact does to the CREATURE, shielded vs
  bare, not just to Link. From `lib_explorer_riverside_layout.dump` (208/0, hp=20, shield
  equipped), 2 independent script runs deliberately walked Link into the confirmed-hostile
  `riverside_south_tan_creature`: shielded (12-14 collision-seeking steps, closing to 8.1px) took
  **zero damage**; an identical bare control took 3 confirmed 4-HP hits (12 total) at comparable
  range. CLEAN NEGATIVE on the novel question: in neither condition did the creature's own OAM
  entry ever vanish, change to an unfamiliar tile, or leave behind any new sprite (checked via a
  full unfiltered OAM dump immediately after every damaging hit) -- contact has no observable
  effect on the attacking creature either way, no drop, no despawn, no A-slot/inventory/rupee
  change. Does NOT advance the sword/A-slot search. Genuinely NEW positive side-finding: this is
  the project's first live, damage-differential confirmation that the equipped shield actually
  functions as a combat mechanic (blocks contact damage entirely at this range), matching the
  manual's "repels most enemy attacks" -- previously only an inventory-flag hypothesis (D13's
  B-slot=4 read). Full method/result: `world_topology.riverside_south_room_combat_contact_test`,
  `visual_catalog.riverside_south_tan_creature`'s `combat_contact_tested` addendum. Screenshots:
  `data/screenshots/riverside_south_room_combat_contact_baseline.png`,
  `_shielded_no_damage.png`, `_bare_damage.png`. **Next question, updated again**: SIX consecutive
  sessions now (the five above plus this one) have found no A-slot lead -- both spatial edge-
  sweeping and this session's mechanic-level test are exhausted for now. The search needs a
  genuinely new area (an NPC gift, a chest, a dungeon entrance) or the one still-open spatial edge
  (`riverside_screen` 192/0 EAST, untested) rather than another combat/edge retest on
  already-covered ground.
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
- **Second building in villager_screen, SEARCHED September 17 2026 (Explorer session, owner-directed)**: owner's precise clue indicated a building east of Pépé's house in 177/0, distinct from Pépé's own house, that can be entered. Extensive exploration via east-west walks at Y levels 22, 32, 50, 60+; examined 5+ screenshots from different positions; inspected OAM sprites at checkpoint. Eastern boundary confirmed at x~148 (transitions to room 178/0). RESULT: no second, visually distinct building structure found. Registry description updated with search notation. Building may exist but was not located in this session -- possibility remains that it requires specific sub-tile alignment, interaction at specific location, or is in an unexplored region. Recommend future session continue search or try direct door-entry attempts at eastern region points.
- **Diagonal-hold mechanism, TESTED September 18 2026 (Explorer subagent, owner-directed: "invent a way to get past an obstacle" -- a genuinely new input mechanism, deliberate simultaneous 2-direction hold, never tried anywhere in this project before)**: tested at the Plage Coco cluster's 3 most rigorously-confirmed hard walls (`226/0`'s x=124,y=26, `209/0`'s x=140, `224/0`'s x=20), each with a real sustained hold (`mmu.joypad.key_state`, 120-150f) of blocked+perpendicular plus single-direction controls. CLOSED, negative on the mechanism itself: at all 3 points the blocked axis showed zero displacement identical to holding it alone (cleanest case: `209/0`'s right+down pinned x at exactly 140 while y moved freely); every case where a diagonal hold produced a room transition was reproduced identically by the perpendicular direction alone, proving no corner-slip, just an already-open (tap-vs-hold-false-negative) route doing the work. Full writeup: `world_topology.plage_coco_diagonal_hold_test`. Two unrelated side-findings from the control battery, still worth knowing: `209/0`'s north edge connects directly to already-charted `193/0` (was wrongly read as a wall from tap-only testing), and a **brand-new, previously uncharted room, `240/0`**, was found off `224/0`'s west-wall column via plain sustained `:down` -- entry-point only, unsurveyed, no item/chest/NPC looked for yet (`room_labels['240/0']`, `world_topology.room240_discovery_via_room224_west_wall`). Sword/A-slot search: still no lead. **What NOT to redo**: this specific mechanism (simultaneous 2-direction hold) at these 3 exact wall points is closed, don't re-test it there without new evidence; `240/0` is the next concrete unswept lead if the search returns to spatial sweeping.
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

**Outdoor telephone booth, TENTH session (of this cluster), September 16 2026 (fresh cold-context
session, owner-directed, two named leads)**: Question 1 (booth location) -- REFUTED for `178/0`
(`overworld_screen2`), the owner's own specific candidate ("one cell east of Pepe le Ramollo's
house"). A genuine dedicated D9-style survey (not just the prior session's south-edge-only test):
2 independent entry points (front_yard's south exit, and villager_screen's own confirmed east exit
per `world_topology.room177_exits` -- the exact route the clue names), full OAM census, full BG
tile-signature dump of the whole visible screen, all 4 edges pushed to their real boundary and
screenshotted. Confirmed `178/0` is a single static non-scrolling screen (SCX/SCY fixed at 0/128
throughout), so one full-room screenshot already shows its ENTIRE content -- no phone-booth-shaped
structure (BG or OAM) exists anywhere in it, only the already-catalogued hedge/creature landmark
(now confirmed to wander widely, explaining an apparent "2nd sprite" sighting) and 1-2 flying
companion sprites. East edge re-confirms (not newly finds) the already-on-file route into
`shop_screen` (179/0). Full detail: `world_topology.overworld_screen2_phone_booth_survey`,
`room_labels['178/0']`. **CORRECTED September 17 2026 (owner caught the error directly, sent the
same screenshot back saying "il existe un batiment sur cet ecran")**: the REFUTED verdict above was
wrong. The object this and every prior survey catalogued as a "round bush/tree-shaped landmark" IS
the telephone booth -- a dome with a phone icon and a dark doorway, only ever seen at low zoom
before. It has a real walk-through door (no `:a`): from `lib_overworld_screen2_via_villager.dump`,
8x `:down`, 8x `:right`, 6x `:left`, then push `:up` repeatedly (correcting with a `:down`+`:right`
step whenever it reads `:blocked`) -- the transition to a new room, `203/16`, happens on the exact
push that reads `:blocked` (the project's own documented "move! can report :blocked on the crossing
step itself" caveat). Reproduced live twice. Also found along the way: this room's SCX/SCY are NOT
literally fixed "throughout" as the REFUTED verdict claimed -- every on-file checkpoint happens to
settle at SCY=128, but a temporary SCY=0 poke on an unsaved loaded copy revealed a second,
tile-identical structure in the tilemap's rows 0-15, never shown by the normal camera (not the
booth itself, a separate methodological find -- see `world_topology.overworld_screen2_telephone_booth_door`).
**SOLVED, same day, follow-up pass**: the phone answers to a plain SHORT `:a` TAP, not a sustained
hold -- the inversion of this project's usual truncation lesson; a 200-frame hold at the exact same
spot produced nothing, a single `Navigator.tap_button(:a)` worked immediately. Full call transcribed
(`dialogues.room203_pepe_phone_call`): Pépé le Ramollo answers, says he knows the whole island and to
call him if lost -- a real, working hint mechanic, but THIS call is a generic intro line, not a
specific pointer to la Loupe or the A-slot item. Worth calling again after a story-flag-changing event
(a new room/item found) to see if the line changes, per `room176`'s own precedent for state-gated
dialogue. Full detail: `world_topology.overworld_screen2_telephone_booth_door`, `room_labels['178/0']`,
`room_labels['203/16']`, `dialogues.room203_pepe_phone_call`.
Question 2 (re-verify `starting_house_npc_bench`/`_beds`) -- BOTH promoted `hypothesis` ->
`verified`, `verified_count` 2, via genuinely independent fresh-session live re-triggers (sustained
~130f `:a` holds, one screenshot per page, not the prior sessions' shorter/single-checked runs).
Three concrete findings: (1) `near_tarkin.dump` (Sept 7 2026, previously only screenshot-inspected)
was LIVE re-triggered for the first time -- it's not a separate mystery greeting, it's the FULL,
original 10-page Tarkin/Tarin shield-acquisition dialogue (intro, the "it's engraved on the Shield"
name joke, the gift, the item-get message, the usage tip) -- see
`world_topology.near_tarkin_first_meeting_live_retrigger`. The bench NPC IS Tarkin/Tarin (same OAM
identity, tile=88/90 at x=120/128,y=80), not an unnamed generic NPC -- `near_tarkin.dump` is his
first meeting, `starting_house_npc_bench`'s "repeat" text is his later remark. (2) The
"`[nom vide/non rendu]`" blank-name-slot flag was a TRANSCRIPTION ARTIFACT from a screenshot-only
read, not a real rendering gap -- the name renders cleanly as `A` (the player's own chosen
file-creation letter) in both the bench NPC's repeat text and Tarkin's first-meeting text, confirmed
live in both. (3) Tested explicitly past where each prior session stopped: both NPCs' dialogues
CYCLE back to page 1 on a further `:a` press once closed (reproduced twice for the bench NPC, once
for the beds NPC) -- same pattern as the already-documented crate_room book re-trigger trap, not a
3rd/new page and not a no-op. `near_tarkin`'s OWN dialogue (the 10-page first-meeting text) behaves
DIFFERENTLY -- it does NOT reopen on further presses (tested 10 more times), a real distinction
between a one-time story dialogue and a repeating NPC-flavor line. Full detail:
`dialogues.starting_house_npc_bench`, `dialogues.starting_house_npc_beds`. Screenshots (9 total):
`data/screenshots/overworld_screen2_*.png` (7), `near_tarkin_live_retrigger_page0-10.png` (11),
`starting_house_npc_bench_*.png` (3), `starting_house_npc_beds_*.png` (3).

**Pépé phone call reproducibility + "Cave Flagello" found, ANSWERED September 17 2026 (fresh
cold-context session, two closely-related falsifiable questions per NEXT.md's own dispatch)**.
Question 1 (re-call Pépé after a state change): the SAME-checkpoint call IS reproducible
verbatim -- a fresh script reload of `lib_room203_16_entry.dump`, redoing the documented 3x-up/
1x-right approach and a full 13-tap page-through, reproduced the exact text (spot-checked pages 0,
5, 9, 13 against the recorded transcript, byte-for-byte) -- promotes
`dialogues.room203_pepe_phone_call` to `verified`/`verified_count 2`. The DIFFERENT-checkpoint half
was attempted, not forced: no on-file checkpoint sits closer to the booth than
`lib_overworld_screen2_via_villager.dump` with meaningfully different game-progress context (the
same-day shop/magasin visit's own checkpoints all sit deep inside `161/14`, requiring a fresh
multi-room route back out). Tried the literal documented route anyway as a first check (front_yard's
south exit lands in `178/0` at the same absolute in-room coordinates as the villager-entry route, so
the same tap sequence should transfer) -- it did NOT reproduce the booth crossing: a clean, fresh
replay of `overworld_screen2_telephone_booth_door`'s own "8 down, 8 right, 6 left, then up with
corrections" method walked 9 straight `:up` pushes with zero blocked reads, past the booth entirely,
into the room's own already-known north edge (`front_yard`/`162-0`) instead. This is a genuine
reproducibility gap in that entry's own tap-count description (now flagged there), not proof the
booth itself moved -- consistent with this project's own standing lesson that these routes are
live procedures, not fixed tap counts. Given the friction and per "don't force a route", did NOT
build a fresh 6-room reverse-navigation script this session. **Answer: SAME-checkpoint call
reproducible (confirmed); DIFFERENT-context re-call is genuinely OPEN, not answered either way** --
a future session with more budget could still attempt the shop-to-booth reverse route (147/0 west
into 146/0, south into front_yard, south into 178/0 at x=88,y=22, then live-recompute the door
approach rather than replaying fixed taps) if the re-call question is still live-interesting then.

Question 2 (the "decorative object" audit): checked the two candidates NEXT.md named first.
`shop_screen`'s (179/0) SW-pocket bush cluster had only ever been `:a`-tested with short taps
(terrain_collision's FIRST DIRECT CONTACT TEST) -- re-tested with a genuine ~130-140f sustained hold
from 3 approach angles (right/up/down, the pocket's 3 blocked sides): CONFIRMED STILL
NON-INTERACTIVE, closes the gap with a clean negative, no new lead. `riverside_screen`'s (192/0)
signpost -- logged since September 8 2026 as "tested negative for :a, not fully exhaustively", no
exact position/method ever recorded -- was the other candidate. Result: **POSITIVE, a genuine false
negative**. From `lib_route192_reached.dump`, nudged to x=68,y=40 (probe_all: up/left `:blocked`,
the sign itself), facing up, a single plain short `Navigator.tap_button(:a)` (no hold needed at
all, same as the telephone booth) opens a real 2-line message box: "→ Cave Flagello / ♦ Plage Coco".
Independently reconfirmed the same session via a fully separate script run (fresh reload, approach
re-derived from scratch) -- byte-identical result, `verified`/`verified_count 2`. A 2nd `:a` or a
`:b` both just close it, `:down` does nothing while open (tested via snapshot branches) -- a static
sign, not a selectable warp menu; no room/position/HP change on any branch. "Plage Coco" is already
well-known (the riverside cluster, exhaustively swept). **"Cave Flagello" is a brand-new name, never
seen anywhere else in this project** -- not yet located on the map. Full detail:
`dialogues.riverside_screen_signpost_cave_flagello`, `world_topology.riverside_screen_signpost_audit`,
`room_labels['192/0']`. Screenshots: `data/screenshots/room192_signpost_cave_flagello_message.png`,
`room192_signpost_approach_position.png`, `room179_shop_screen_bush_sustained_hold_test.png`.
**Next question, strongly updated**: after 6+ consecutive sessions finding no A-slot lead via edge
sweeps or mechanic tests, this audit -- a cheap, different method, exactly as NEXT.md's own
"different method entirely" option suggested -- found one. **Locating "Cave Flagello" is now the
single strongest next lead in this project**, ahead of another edge sweep (`riverside_screen`'s own
EAST edge is still the only untested spatial frontier edge on file) or another decorative-object
audit pass. Not chased this session (budget/scope -- this was the audit, not the search).

**`riverside_screen` (192/0) EAST edge tested, `193/0` found, "Cave Flagello" NOT located,
September 17 2026 (fresh cold-context session, same day, following up directly on the audit
above)**: the project's last genuinely-untested frontier edge (`world_topology.world_map_reconstruction`'s
`frontier_untested_edges`) is REFUTED as a wall -- it was never blocked at all. From
`lib_route192_reached.dump`, `Navigator.move!` pushed right x2 (to the previously-logged x=108,y=16
stop point), down x1, then right again crosses cleanly into a brand-new room, `193/0`
(`riverside_east_meadow`), on a plain ordinary tap -- no sustained hold ever needed (the earlier
"soft, undistinguished" read simply hadn't been pushed past that first stop point in this exact
sequence). Independently reproduced from a fresh reload with a different intermediate tap
breakdown, same result both times -- `verified_count 2`. Full method:
`world_topology.riverside_screen_east_edge_and_room193_discovery`.
`193/0` itself: only its north band (screen-relative y=16-32, x=0-155) was safely surveyed --
hazard-dense, same hostile creature family as Plage Coco (tile IDs 0x60-0x6a), costing real HP over
2 separate push attempts (24->4 HP, then 24->12 HP on a fresh retry), and a 3rd retreat attempt
reached HP=0, triggering this project's FIRST-EVER observed death/"PERDU!!" game-over screen (3
save/continue options, matching the already-known save mechanic's own menu) -- on a disposable
scratch checkpoint only, never `main.dump`, no save made from that screen; a genuinely new mechanic
confirmation, not previously observed anywhere in this project. No chest, sign, NPC, or item found
in the surveyed portion. A non-live raw 32x32 VRAM tilemap dump suggests a large lake-shaped feature
occupies much of the room's unswept southern portion -- NOT live-confirmed (the north hazard band
blocked every south-push attempt tried, each at real HP cost) -- the strongest concrete lead for a
follow-up session, not yet fact. A single unusual 2x2 BG signature spotted in the same raw dump
(world x=0-15,y=16-31) is NOT part of this room's reachable area (confirmed live: pushing further
west from the room's own entry leads straight back into 192/0) -- most likely stale VRAM from
192/0's own prior tilemap write, don't chase it as a hidden structure without a different, more
direct confirmation method. Also found: this room's camera is ACTIVELY tracked/re-locked every
frame (a diagnostic SCX=0 poke immediately reverted before the next render), unlike
`overworld_screen2`'s genuinely-fixed camera -- the "temporary SCX/SCY poke reveals hidden content"
technique that found that room's telephone booth dome does NOT apply here. Full detail:
`room_labels['193/0']`. Screenshots: `data/screenshots/room193_0_entry_from_192_east_edge.png`,
`room193_0_north_band_wider_view.png`, `room193_0_south_bush_wall_blocked.png`,
`room193_0_hp_zero_perdu_game_over.png`, `room192_0_east_edge_crossing_reconfirm.png`.
**Answer: the frontier edge itself is RESOLVED (open, not a wall) -- "Cave Flagello" is still NOT
located, genuinely OPEN not refuted**, since only part of the new room was safely reachable this
session. **Next question**: finish surveying `193/0` -- its unswept south (toward the inferred
lake) and full east extent past x=155 -- ideally with a fresh full-HP run that routes AROUND the
north band's 2 hostile creatures instead of through them (this session's 2 push attempts both cost
critical HP fighting through the same corner), or with `Navigator.avoid_hostiles_and_push!` retuned
for this room's density (the shipped 16px default did not prevent either near-death sequence here,
unretested at other radii in this specific room). Separately worth checking: whether `193/0`'s
south connects back to any already-charted room (`208/0`/`224/0`) rather than being fully isolated
territory.

**`193/0` fully surveyed, 2 MORE new rooms found (`194/0`, `195/0`), "Cave Flagello" STILL NOT
located, September 17 2026 (follow-up session, same day)**: closed both halves of the "Next
question" above, plus a methodological finding worth reusing. South: a real wall along most of
the room's width (x=4 through x=68 all stop between y=32-64, reproduced with zero HP cost via a
NON-MUTATING snapshot-probed sustained hold -- press+hold on a `Motherboard.load`'d throwaway
copy, read the result, discard it -- rather than a live mutating push), EXCEPT at the room's own
east column (x=135), where the same technique crosses into the ALREADY-CHARTED `209/0`
(riverside_east_room, Plage Coco cluster, no item) -- so 193/0's south boundary loops back into
known territory, it was never an isolated frontier. East: the x=155 edge previously read
`:blocked` by a short tap is ANOTHER tap-false-negative (same class as `227/0`'s own discovery) --
a genuine sustained hold (as short as 200 continuous frames, no release) crosses cleanly through
TWO more brand-new rooms in a row, `194/0` (riverside_narrows) and `195/0` (riverside_lake_cove) --
all 4 rooms in the `192`->`193`->`194`->`195` chain share the same fixed-camera single-screen
shape, so a long enough hold blows straight through more than one at once. `194/0`: a narrow,
hazard-dense (3 creatures) passage, partially swept -- a real south wall found at one column
(x=155,y=48, reproduced twice via a zero-cost probe), no chest/sign/NPC/item found, `status:
glimpsed`. `195/0`: the chain's east end, containing this cluster's actual water/lake feature (its
own south edge, screen-relative row 7) -- NOT the "0x7c/0x7e lake" the prior session inferred from
a raw VRAM dump in `193/0`, which this session found is almost certainly a MISREAD of the
bottommost screen row (row 8, native y=128-143): the same signature reappears at that exact row in
every room in this chain regardless of content, and no OAM sprite was ever observed at native
y>=122 in dozens of live samples -- consistent with row 8 being the HUD strip, not terrain (not
pixel-proven, but strong circumstantial evidence; see
`world_topology.room193_sustained_hold_south_and_east_survey`'s note). DIVE TEST at 195/0's real
water edge (per D14/the manual's "B to dive"): NEGATIVE, the project's 4th water body tested and
4th negative result (sustained B+down produced zero y-axis movement into the water, only an
x-axis wall-slide; a plain B tap alone did nothing) -- consistent with, not new proof of, Link
still lacking the Flippers/swim item. `195/0`'s east/west shore ends and its own east/right edge
(genuine hard wall, zero pixel movement under a 700-frame hold) are all now characterized -- no
chest, sign, or NPC found anywhere in either new room. Methodological finding, worth reusing in
any future hazard-dense room: a raw continuous sustained hold (no release) took noticeably less HP
damage crossing the same ground than `Navigator.avoid_hostiles_and_push!`'s tap-release-tap pattern
did earlier the same session (e.g. 0 HP cost holding south to `193/0`'s own y=64 wall, vs real
damage taken pushing the same room with the tap-based primitive) -- the idle settle window between
taps seems to give wandering hostiles repeated chances to land a hit that one fast continuous hold
skips past; D13's primitive is still the right choice when active hazard-avoidance/shield-state
logic is needed, but a plain sustained hold is worth trying first for reconnaissance (always via a
snapshot-probe, discarded after reading the result) and for a straight-line push once the probe
shows it's safe. HP floor of ~12 (the owner's stated safety priority this session) was respected
throughout on every checkpoint actually kept; one real (uncommitted, unsaved) exploratory branch
dipped to HP=8 before being abandoned -- flagged here transparently since it happened, though no
checkpoint file was ever overwritten with that state, so no persisted progress was put at risk. No
D12 HP-write exception was requested or used. Full detail:
`world_topology.room193_sustained_hold_south_and_east_survey`, `world_topology.room195_water_dive_test`,
`room_labels['193/0']` (promoted glimpsed -> charted), `room_labels['194/0']`, `room_labels['195/0']`.
Screenshots: `data/screenshots/room194_0_entry.png`, `data/screenshots/room195_0_entry_from_194.png`,
`data/screenshots/room195_0_south_water_edge.png`. **Next question**: "Cave Flagello" is still not
found anywhere in this whole 4-room riverside-east chain, which is now essentially exhausted (every
edge of `193/0`/`194/0`/`195/0` characterized, all loop back into either already-known territory or
a confirmed wall) -- the search needs a genuinely different area again, same pattern as every prior
"exhausted cluster" conclusion in this project (Plage Coco, the shop door, the telephone-booth
neighborhood). `194/0`'s own south/west portions are not 100% exhaustively swept (only one south
column tested), a minor gap worth a quick check before writing the room off entirely, but not
expected to change the room's overall "no item" verdict given its small, narrow, fully-hedge-bounded
shape. The dive-negative result is now a 4-for-4 pattern across this project's water bodies --
strong enough that a future session should treat "Link cannot enter deep water" as the working
assumption rather than a per-location open question, without a Flippers-equivalent item ever being
found first.

**`163/0` (clover_field) second route found, fully surveyed, "Cave Flagello" STILL NOT located,
September 17 2026 (fresh cold-context session, owner-directed -- this was the project's one
genuinely open frontier: `163/0` had only ever been glimpsed via front_yard's own east approach,
which was independently blocked-confirmed at 3 rows/2 methods and anti-patch-closed; the room
itself had never actually been entered)**. Used `world_topology.world_map_reconstruction`'s
tentative coordinate grid as a hypothesis generator, not ground truth: `north_corridor_room`
(146/0, at (0,-1)) has an own `right` exit into `147/0` (~(1,-1)); the grid tentatively placed
`clover_field` at (1,0) -- directly SOUTH of `147/0`. Cross-checked against a fact already on file
but never acted on: `room_labels['147/0']`'s own entry-point `probe_all` read `down: :ok`, but no
session had ever actually followed it (every prior 147/0 session went straight for the door north
into `161/14`). Live-verified: from `147/0`'s own entry checkpoint (x=85,y=121),
`cross_until_room_change!(:down)` crosses in 2 calls, zero HP cost, into `163/0` at x=85,y=23 --
reproduced identically on a fresh reload. **This is the second route the day's mandate asked
for -- confirmed, not the refused front_yard approach.** Full survey (live movement AND a non-live
`Terrain.signature_at` grid dump, D8's own non-invasive method, used to explain a puzzling result):
the room is a light-green grass frame around a solid, impassable 6x5 clover-clump block (confirmed
non-interactive under a 150-frame `:a` hold) -- a straight push south from the entry column dead-
ends at the clump's own north face (y=32), which is why the room initially looked sealed; 2 open
corridors flank the clump (columns 0-1 and 8) and, pushed to their far end (8 clean move! calls
each, zero HP cost), BOTH lead directly into `shop_screen` (179/0) -- **a previously unknown
adjacency**, resolving `room_labels['147/0']`'s own long-open question of whether 147/0 and 179/0's
yard are the same building (they are not; clover_field bridges 2 distinct areas, matching the
coordinate grid's (1,-1)/(1,0)/(1,1) column exactly, now confirmed by live traversal). East is a
genuine hard hedge wall (sustained-hold-confirmed); west (row 1) is a real transition back into
`front_yard`, at a different, previously-untested row than the one already refused. No chest, sign,
NPC, or item found anywhere in the room -- not Cave Flagello, not the A-slot item/sword. Status
promoted glimpsed -> charted. **Side finding worth a future session's attention, not chased here**:
the shop_screen crossing at x=138,y=16 sits outside every x-stop that room's own 8-session door
search ever sampled (topped out at x=122, see `world_topology.shop_screen_door_approach`) -- a
genuinely new, never-tried entry vector into a mechanism this project has otherwise closed under
anti-patch. Deliberately NOT turned into a fresh door-search attempt this session (that specific
mechanism needs explicit owner sign-off before a 9th session reopens it, per its own notes) -- flag
it, don't chase it, next time the sword/A-slot search revisits shop_screen. Full detail:
`world_topology.clover_field_second_route_and_shop_connection`, `room_labels['163/0']`,
`room_labels['147/0']`'s same-day addendum, `room_labels['179/0']`'s same-day addendum. Screenshots:
`data/screenshots/room147_0_before_south_push.png`, `room163_0_second_route_entry_from_147.png`,
`room163_0_entry_settled.png`, `room163_0_east_edge_hedge_wall.png`,
`room163_0_north_row_clover_wall.png`, `room163_0_south_corridor_into_shop_screen.png`,
`room179_0_new_entry_from_163_north.png`. **Next question**: the project's one identified genuinely
open frontier edge is now closed. No A-slot item/sword/"la Loupe"/Cave Flagello lead survives
anywhere currently mapped -- every named cluster (Plage Coco, the shop-door neighborhood via 3
separate approach families now, the telephone-booth neighborhood, `north_corridor_room`'s own
neighborhood, and the whole `192/0`-`195/0` riverside-east chain) is exhausted. A future session
needs either a genuinely new area (nothing charted currently borders unexplored territory the way
`163/0` did this morning -- would need a fresh long-range search, not another edge re-sweep) or a
mechanic/story trigger not yet tried (re-calling Pépé from a different game-state context, per the
still-open half of September 17's earlier Pépé-reproducibility question; or revisiting whether any
already-catalogued dialogue holds a missed clue, per NEXT.md's own "different method entirely"
precedent that found the Cave Flagello signpost in the first place).

## In-flight work (for resumability)

None currently. The `Koholint::AutonomousRecovery::ResearchTask` id `81da96f2cb8607eb` (shop_screen
door band, `.koholint/research_task.json`) reached `status: resolved` September 16 2026 (EIGHTH
session, 2nd independent supporting experiment) -- see "Quest hypothesis" above for the current
state of the underlying game goal (still blocked; a resolved *hypothesis* is not a reached door)
and `docs/archive/SESSION_LOG.md` for the full session writeup. A future session opening a new
blocker should create a fresh `ResearchTask` per `docs/AUTONOMOUS_RECOVERY.md`, not reuse this id.

## Next question

Session 4 (PLAN.md) is fully complete -- see the State section above. See "Quest hypothesis" above
for the live thread. The September 8-10 2026 topology/dialogue reference notes formerly here (early
Plage Coco routing, D11's hazard-classification pass, the open walkability-model architecture
question) were archived verbatim to `docs/archive/SESSION_LOG.md` September 17 2026 (already
resolved/superseded, `NEXT.md` one page over budget) -- every fact they contain is still reachable
from `data/ram_registry.json`'s `room_labels`/`world_topology`/`dialogues` entries, cited there.

## What NOT to redo

- `130/0` is a confirmed dead end (September 16 2026 follow-up session) -- both open `probe_all`
  edges from the pocket's own dead-end point (x=28,y=106) are hard walls under an independent
  400-frame sustained hold each, not tap-false-negatives. Don't re-approach the visible building
  facade from within this room expecting a hidden route; if it's ever reached, it'll be from a
  different, still-unknown room bordering its far side, not from `130/0`. `146/0`'s 4 exits are
  ALL characterized now (up/right/left/down) -- don't re-run `probe_all`/exit characterization on
  this room again, there's nothing left unswept in it.
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
  LONGER an open gap -- it's resolved into a real transition into `226/0`, see
  `world_topology.riverside_flower_clearing_ne_exit` (full write-up archived to
  `docs/archive/SESSION_LOG.md` September 17 2026) for the working strategy (hold the shield, and
  specifically drop to y~41, not y~26/34, to clear the flower-cluster wall around x=76) before
  attempting a straight re-push at the old y=26 band, which is a confirmed hard wall there. `lib_explorer_225_route7.dump` is a real but LOW-HEALTH (1 heart)
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
- `well_platform` (160/0)'s WEST edge is now fully characterized, including its last untested
  fragment (the front-notch strip, y~40-75) -- confirmed river/hedge boundary via 2 independent
  points, taps AND 380-frame sustained holds, September 16 2026. Don't re-walk this edge again
  without a new reason (e.g. a cutting item). `room160_entry.dump` (the only on-file checkpoint in
  this room) needs the same `@current_period_div_accumulator` post-load fix as `main.dump`/
  `front_yard_navigator.dump` before any input advances a frame -- see
  `world_topology.room160_exits_and_content`'s `west_edge_notch_test`. Also: the well/altar's 4
  pillar-shaped OAM decorations are a real, previously-uncatalogued blocker in the x=100-132/
  y=74-114 band, separate from the hedge -- don't assume a naive straight-west push from the entry
  checkpoint reaches the room's true west edge; route south below the pillars first.
- `riverside_south_room` (208/0)'s WEST edge is a confirmed hard wall at x=20 (September 16 2026)
  -- reproduced at 3 independent y-bands (north hedge-maze band, south open-grass band upper and
  lower) via both ordinary taps and a 400-frame sustained hold each, zero drift/HP change every
  time. Don't re-walk this edge expecting a hidden door without a new reason (e.g. a cutting item,
  if one is ever found); see `world_topology.riverside_south_room_survey`'s `west_edge_test`. All
  4 of `208/0`'s edges are now characterized -- don't re-run `probe_all`/edge characterization on
  this room again for the same reason `146/0` and `130/0` are already closed.
- Deliberate hostile-creature contact (shielded and bare) against `riverside_south_tan_creature`
  is confirmed to do NOTHING to the creature itself -- no despawn, no tile change outside its
  already-known animation set, no drop -- across 12-14 contact-seeking steps per condition,
  September 16 2026. Don't re-run this same test on the same creature/room expecting a different
  result without a new reason (an actual weapon to attack WITH, which this project doesn't have
  yet -- see `world_topology.riverside_south_room_combat_contact_test`). The shield fully blocking
  contact damage at this range IS newly confirmed and durable -- don't re-verify that in isolation
  either, it's now a live-tested fact, not a hypothesis to recheck.
- CORRECTED September 17 2026: the September 16 "no phone booth" verdict above was wrong -- don't
  cite `overworld_screen2_phone_booth_survey` as settled. The booth IS the room's "landmark" object;
  see `world_topology.overworld_screen2_telephone_booth_door` for the real door route into `203/16`.
  Don't trust a single screenshot as proof a room has "no structure" without zooming into every
  decorative-looking BG object first -- this is the second time in this project a real interactive
  object was dismissed as decoration at low zoom (crate_room's books were the first).
- `starting_house_npc_bench`/`starting_house_npc_beds` are both `verified`/`verified_count: 2` now
  (September 16 2026) -- don't re-run a basic re-trigger expecting new text. Both dialogues CYCLE
  back to page 1 on a further `:a` press once closed (confirmed independently for both); this is
  expected behavior, not a bug to re-investigate. `near_tarkin.dump`'s own dialogue (Tarkin's first
  meeting, `world_topology.near_tarkin_first_meeting_live_retrigger`) is the one exception in this
  room -- it does NOT reopen on further presses, confirmed via 10 additional sustained holds. The
  "`[nom vide/non rendu]`" name-slot question is CLOSED -- it renders as `A`, not blank; don't
  re-flag it as a rendering bug.
- `dialogues.room203_pepe_phone_call` is `verified`/`verified_count 2` now (September 17 2026) --
  don't re-run a basic same-checkpoint reproducibility check again, it's settled. The separate
  question of whether the call's TEXT changes after a story-flag/state change is still OPEN, not
  answered -- don't cite this session's work as having refuted or confirmed that, it only found
  routing friction reaching the booth from a different-context checkpoint, not a content result.
  `world_topology.overworld_screen2_telephone_booth_door`'s own "8 down, 8 right, 6 left, then
  up-with-corrections" tap-count description does NOT reliably replay -- a fresh literal replay
  walked straight past the booth into `front_yard` instead (September 17 2026 follow-up session).
  Treat that route as a live procedure only (push and check `room_id` after each, correct toward
  the door when blocked), same caveat this project already applies to every other multi-room route
  in `front_yard_to_room177`/Plage Coco -- don't assume the fixed tap counts are replayable as
  written.
- `shop_screen`'s (179/0) SW-pocket bush cluster (x~60-68,y=106-112) is now confirmed
  non-interactive under a genuine sustained `:a` hold from 3 approach angles too, not just short
  taps (September 17 2026) -- don't re-run this test on this object again without a new reason
  (e.g. a cutting item). This is a DIFFERENT object from `179/0`'s other bush at ~x=49-57,y=110
  (also already confirmed non-interactive, separately) -- don't conflate the two when reading this
  room's notes.
- `riverside_screen`'s (192/0) signpost is CORRECTED as of September 17 2026 -- it is NOT
  non-interactive. Don't cite the old "tested negative for :a, not fully exhaustively" line as
  current; a plain short `:a` tap from x=68,y=40 facing up opens a real message naming "Cave
  Flagello" and "Plage Coco" (`dialogues.riverside_screen_signpost_cave_flagello`,
  `verified_count 2`). It is a static sign (closes on a 2nd `:a` or `:b`, `:down` does nothing) --
  don't expect a selectable warp menu from it, that was tested and ruled out. "Cave Flagello" is
  not yet located -- don't assume it's reachable from this room without checking first.
- `riverside_screen`'s (192/0) EAST edge is CORRECTED as of September 17 2026 -- it is NOT a wall,
  don't re-test it as "the last untested frontier edge" again. It's a plain tap-through transition
  (`Navigator.move!` right x2, down x1, right x3+ from `lib_route192_reached.dump`) into a new room,
  `193/0` (`world_topology.riverside_screen_east_edge_and_room193_discovery`, `verified_count 2`).
  `193/0`'s own north band is a real hostile-creature encounter zone (same family as Plage Coco) --
  don't push through it carelessly expecting the low-damage results typical of a fresh, unexplored
  room; 2 independent sessions' worth of push attempts both cost 12-20 HP here, and one retreat
  attempt reached HP=0 (this project's first observed death/"PERDU!!" screen, harmless on a scratch
  checkpoint, but real time cost). Route around the 2 creatures near the entry corner rather than
  straight through, or retune `Navigator.avoid_hostiles_and_push!`'s radius for this room before
  trying again. The room's south portion (an inferred lake, from a non-live tilemap dump only) is
  still completely unconfirmed -- don't cite it as fact, and don't assume "Cave Flagello" is there
  without actually reaching it first.
- CORRECTED September 17 2026 (follow-up session, same day): `193/0` is now FULLY surveyed, don't
  re-run edge characterization on it again. The "inferred lake" from the paragraph above did NOT
  pan out on live visit -- it's most likely a misread of the bottommost screen row (HUD strip, not
  terrain, see `world_topology.room193_sustained_hold_south_and_east_survey`'s note), and the
  room's real south edge is a plain wall except at x=135, which loops into already-charted `209/0`.
  Its east edge (`x=155`) is ALSO a tap-false-negative, same as this room's own north-band lesson
  applies more broadly than just this one room -- a sustained hold there crosses into 2 more new
  rooms, `194/0` and `195/0` (both `glimpsed`, no item found in either). Don't assume a short-tap
  `:blocked` read is final anywhere in this project without at least considering a sustained-hold
  recheck first, especially near a screen's outer edge -- this is now the 3rd confirmed case
  project-wide (`227/0`, `193/0`'s own east edge, and now this same edge revealing 2 MORE rooms
  beyond it). A raw continuous sustained hold also measurably costs less HP than
  `Navigator.avoid_hostiles_and_push!`'s tap-release pattern when crossing a hazard-dense room in a
  straight line -- worth trying first (via a non-mutating snapshot probe) before the tap-based
  primitive in a room like this one. "Cave Flagello" is still not found anywhere in this 4-room
  chain (`192/0`/`193/0`/`194/0`/`195/0`) -- don't re-sweep any of their now-characterized edges
  again without a new reason; the search needs a different area entirely.
- `163/0` (clover_field) is fully charted now (September 17 2026) -- all 4 edges characterized,
  don't re-run `probe_all`/edge characterization on it again. Its route in is `147/0`'s own `down`
  exit (2 `cross_until_room_change!` calls from x=85,y=121), NOT `front_yard`'s east approach --
  that approach is separately, independently anti-patch-closed (`world_topology.front_yard_adjacent_rooms`)
  and still should not be retried a 4th time. The clover-clump block filling the room's center
  (tile-cell rows 2-6, cols 2-7) is confirmed non-interactive and confirmed impassable -- don't
  re-test it expecting a cutting mechanic without an actual cutting item in hand. Its south edge's
  2 corridors both lead into `shop_screen` (179/0), not new unexplored ground -- see
  `world_topology.clover_field_second_route_and_shop_connection`. The specific new shop_screen entry
  point this revealed (x=138,y=16) is a genuinely untried door-search vector, but don't turn it into
  an 8th+ door-search session without owner sign-off first -- that mechanism is separately
  anti-patch-closed (`world_topology.shop_screen_door_approach`).
