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
| Rooms found | 19 labeled in `data/ram_registry.json`'s `room_labels` (8 "charted", 11 "glimpsed"/less -- `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, south/east of `riverside_south_room`, both further explored (224/0's scroll mechanism and "totem" identity resolved, 225/0's ground-accessible extent mapped plus its NE route now resolved into a real room transition); `209/0` riverside_east_room, found east of `riverside_south_room`'s south band (past the prior x=134,y=115 stop point), fully swept September 10-11 2026 (west/center then, east half via the D13 primitive) -- no bidule found anywhere in it; `179/0` shop_screen, first actually explored September 10 2026 -- turns out to be the shop's EXTERIOR yard, not its interior; see `world_topology.shop_screen_door_approach` and Next question below; `226/0` riverside_ne_cove, reached from `225/0`'s previously-abandoned NE route September 10 2026, fully swept September 11 2026 via the D13 primitive (status promoted glimpsed -> charted) -- no bidule found anywhere in it either, see Next question below). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with these rooms or this session's findings). D9 visual-catalog `visual_survey` now covers 6/19 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout + `well_platform`, `building_screen` rollout, fresh restart of an abandoned attempt, September 10 2026) -- see `DECISIONS.md`'s D9 entry. |
| Dialogues / readable text | 14 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 4 books + 1 wall object, 9/9 tile objects resolved via OAM; house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a two-page signpost, "Attention aux oursins !" then "Se protéger avec un bouclier !" (2nd page found September 11 2026, needs a long `:a` hold to reveal), NOT a chest/item; `shop_screen_yard_npc` (179/0) -- a friendly yard NPC reciting the SAME save-tip line as room176's pair, first confirmed case of a reused dialogue asset, September 10 2026 -- all hypothesis/verified_count 1). |
| Terrain / collision | D8 live: reads BG tilemap signatures from VRAM (`lib/terrain.rb`), 93.1%-validated against live-probe oracle. Primary method; live probing kept as fallback. |
| SELECT map (fog-of-war) | Widest-coverage checkpoint: `lib_explorer_225_fresh_entry.dump` (8 lit cells, superset of `main.dump`'s own 6). 6/8 cells now have a place name read from a checkpoint standing IN that exact cell's room ("Village des Mouettes", "Bibliothèque", "Sud du Village" x2 -- `176/0` and `192/0` share it, "Plage Coco" x2), `select_map_screen`'s SEVENTH + EIGHTH SESSION entries (`192/0` riverside_screen closed EIGHTH SESSION, new working route: nudge x to ~88 from `room176_entry_from_room160.dump`, then plain `:down` taps, no special alignment needed -- corrects the earlier "x=94, 8 calls" figure, which doesn't reproduce). Remaining 2 cells (the chain's earliest 2 rooms) confirmed NOT free-readable from any on-file checkpoint (checked EIGHTH SESSION) -- would need a from-boot replay. Scratchpad images ready for the Atlas (`select_map_full_*.png`), not yet pulled in. |
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
shield+push+HP-top-up tactic across `224/0`/`225/0`/`226/0`/`209/0`). A Builder task is in flight,
see In-flight work below. Full rationale for each: `DECISIONS.md`.

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

## Quest hypothesis (current best guess + blocker)

Standing field: the single leading hypothesis for "what unblocks progress next" and what's
stopping it -- not a full quest log. Update in place when the leading guess changes; don't let
this section grow into a history (that belongs in `docs/archive/SESSION_LOG.md`).

**Current hypothesis (September 10, 2026, UPDATED same day)**: the next real objective is
finding/obtaining a sword, and there's now a concrete place to look for it. Evidence: (1) bushes
are CONDITIONALLY-blocked terrain (cuttable, not permanently blocked scenery) per the
architecture question above; (2) two crate_room hint books already read describe sword mechanics
-- `dialogues.crate_room_book_b` (a charge-and-release spin-attack technique) and
`dialogues.crate_room_book_c` (items that can replace the sword slot in combat); (3) no sword is
confirmed obtained (inferred, not directly probed); (4) **NEW**: `starting_house` (163/16) turned
out to hold 2 never-before-interacted OAM NPCs (owner-prompted re-visit, September 10 2026 --
see `dialogues.starting_house_npc_bench`/`starting_house_npc_beds`) -- both independently point
south to "la plage" (the beach where Link washed up) and warn of monsters there; NPC A explicitly
names "un autre bidule qui est resté sur la plage" (another unspecified thingy left on the
beach). Neither mentions a sword by name, but an unidentified item at a specific, nameable
location is the most concrete lead this project has had for the sword hypothesis so far.

**Blocker (CORRECTED A THIRD TIME, same day -- see `world_topology.world_map_reconstruction`; the
owner caught each of the first two mistakes by asking "are you sure?" instead of trusting the
claim, which is exactly the discipline to keep applying here)**: the beach is very likely NOT an
unexplored edge at all -- it's almost certainly already reached. `select_map_screen`'s own in-game
place-name reads name BOTH `riverside_south_river_room` (224/0) AND `riverside_flower_clearing`
(225/0) "Plage Coco" (Coco Beach), and `225/0`'s own signpost reads "Attention aux oursins !"
(watch out for sea urchins -- a beach detail, not a river one). Both rooms are already charted,
reached via `well_platform` -> `building_screen` -> `riverside_screen` -> `riverside_south_room`
(west then south from front_yard, NOT south from `overworld_screen2` -- that edge is still a
genuine frontier per `world_map_reconstruction` but is a different, unconnected direction on the
grid and has no naming evidence tying it to "la plage"). The real gap: `225/0` has a known,
never-resolved NE route past the signpost, abandoned at the time because it produced "unexplained
diagonal slides" -- which D11's later contact-knockback finding (see Decisions in force above)
now explains as probable enemy-collision knockback, not a real wall never actually blocking
progress. `224/0` is also flagged in its own entry as "not fully explored past its entry+drift
probe". The "bidule" NPC A mentioned is most plausibly sitting somewhere in one of these two
already-reached rooms, unfound because earlier sessions had no reason to search this hard or to
route around the knockback. Link's equipped-item/inventory RAM location is still not identified
either, so even finding an item there won't let us confirm it's a sword without visual/dialogue
confirmation.

**UPDATE, September 10 2026 (same day, Explorer session)**: `225/0`'s NE route IS resolved now --
it was never a wall, just two stacked hazards (an invisible knockback creature plus ordinary
sea-urchin/flower terrain) that a held shield mostly gets past (see Next question below for full
detail). It leads to a brand-new room, `226/0` riverside_ne_cove -- but the "bidule" was NOT found
there, or anywhere else this session; only the room's entry point was glimpsed (budget went
entirely to solving the route).

**UPDATE 2, September 10 2026 (same day, follow-up Explorer session)**: `226/0`'s 3 open
directions and 2 new directions in `224/0` were swept -- still NO "bidule" found anywhere, and a
real new blocker surfaced: both rooms are dominated by the same hostile tile=0x60-family
creature, the shield-hold tactic only mitigates (not eliminates) damage, and every route pushed
this session ended with Link at ~1 heart (of an as-yet-unpinned max) -- see
`room_labels["226/0"]`/`["224/0"]`'s latest addenda for the exact routes/damage log. **No healing
mechanism is confirmed anywhere in this project yet** -- that's now the practical blocker on
pushing this specific thread further, not navigation. A follow-up session is testing whether
`house2_interior`'s beds restore HP (see In-flight work below) before any 3rd push into this
hostile territory.

**UPDATE 3, September 10 2026 (same day)**: beds do NOT heal -- tested cleanly with genuine
below-max HP (via `wram_unmapped.link_health`'s newly-found RAM byte, see below), zero HP change
across contact/`:a`/150-frame-idle at both reachable approach angles. No healing mechanism is
confirmed ANYWHERE in this project as of now. Real side-finding, though: `link_health` is now
RESOLVED (`wram_unmapped.link_health`, promoted `verified`/`verified_count: 2`) -- current HP is
`0xDB5A` (eighth-heart units, 8 per heart), max/containers is `0xDB5B` (reads 3 everywhere
checked so far). Important caveat on file: a direct `mmu.write` to `0xDB5A` does NOT refresh the
visible HUD heart icons (they only redraw via the game's own damage-handling code) -- read this
byte directly, don't trust the on-screen hearts after a manual write.

**RESOLVED, September 10 2026 (owner decision, D12 in `DECISIONS.md`)**: RAM writes to HP are
case-by-case by default. **AMENDED same day**: the owner then granted a SCOPED standing approval
specifically for this thread ("Oui pour toute poussée nécessaire à la découverte de l'épée, sur la
plage coco") -- HP writes on scratch checkpoints no longer need a fresh ask for each individual
Plage Coco push, though every other room/purpose still does. IMPORTANT: don't read "Plage Coco
paused" as "abandoned" in any future summary -- this remains the project's single strongest lead
(both starting_house NPCs, the game's own place name, the signpost). A prior status report
conflated "paused pending a specific ask" with "closed/exhausted" and the owner caught it --
logged as `METAPLANNER_ESCALATIONS.md`'s ESC7.

**UPDATE 4, September 10 2026 (same day, follow-up Explorer session, using the new HP-write
permission)**: the "bidule" is STILL NOT FOUND, and this push closes out both rooms' remaining
unswept ground rather than leaving it open. `224/0`'s area past x=68,y=48 (`up` and `left`, both
previously untried) and `226/0`'s NW cul-de-sac `up` wall (previously only probed, never pushed
to an exhausted/HP-safe conclusion) were both fully resolved this session: every route either
led into already-fully-explored territory via a newly-found room connection (`224/0` now has a
second door into `225/0` at its north edge, and a second door into `208/0` at its NW corner,
neither opening new ground) or hit a real, reproduced dead-end wall (`224/0`'s west edge;
`226/0`'s north wall, confirmed blocked at 2 different columns after repeated identical hits).
**This significantly weakens the "bidule is hiding in an unswept corner of Plage Coco" reading**
-- the cluster's three rooms (`224/0`, `225/0`, `226/0`) now have no known unexplored ground left
except `226/0`'s own east/south side past x=46,y=26 (right/down still read `:ok` there, never
pushed). The sword-hypothesis lead itself (the starting_house NPCs' dialogue, the "Plage Coco"
place name) is NOT invalidated by this -- only the specific guess that the item sits in one of
these three rooms' already-glimpsed corners is looking weaker. Full route detail: `room_labels`'s
"THIRD PUSH"/"FOURTH PUSH" addenda and "In-flight work" below.

**UPDATE 5, September 10 2026 (same day, follow-up Explorer session, `riverside_east_room`/209/0's
first full sweep)**: still NO "bidule" found. This was the last untested ground in Plage Coco (the
rest of the cluster was exhaustively swept per UPDATE 4) -- roughly its west half and center are
now swept clean too (only the hostile creature family, a non-interactive flower wall, hedge, and
unentered water found), but its east half and north-of-hedge area remain genuinely unreached, not
ruled out: a 2-creature pocket in the room's center blocked every push this session (6+ distinct
attempts, closed under the anti-patch rule). **This continues to weaken, without fully closing, the
"bidule is in an already-glimpsed corner of Plage Coco" reading** -- the cluster's ground truly
still unswept is now down to just two small pockets: `226/0`'s east/south side past x=46,y=26, and
`209/0`'s east half past its center creature pocket. The sword-hypothesis lead itself is still not
invalidated. Full detail: `room_labels['209/0']` and "In-flight work" below.

**UPDATE 6, September 11 2026 (D13 primitive sweeps, both remaining pockets)**: both of the two
pockets UPDATE 5 named are now closed -- `209/0`'s east half (via D13's own validation retest,
reaching a real east wall at x=140) and `226/0`'s east/south side (via a follow-up Explorer
session using the same primitive as its primary method, reaching a real wall at x=124,y=26 and a
water-bounded cul-de-sac at x=154,y=58). **The entire Plage Coco cluster (`224/0`, `225/0`,
`226/0`, `209/0`) is now believed EXHAUSTIVELY swept -- no known unexplored ground left anywhere
in it, not just "no gap currently open".** No "bidule" was found anywhere in any of the four
rooms across this whole multi-session search. This substantially weakens the "bidule is
somewhere in Plage Coco" reading that has driven this thread since `starting_house`'s NPCs were
first read -- worth an explicit owner decision on whether to keep treating Plage Coco as the
leading sword-hypothesis location, or reconsider the lead itself (e.g. the NPCs' "la plage"
reference might point somewhere not yet reached, not necessarily this specific cluster). Full
detail: `room_labels['226/0']`'s newest addendum and "In-flight work" below.

**UPDATE 7, September 11 2026 (pivot, then RESOLVED same day, Explorer session)**: the lead moved
to `overworld_screen2`'s (178/0) SOUTH edge -- never tested, despite being the single most literal
reading of `starting_house_npc_beds`'s "suis la route du Sud" (Plage Coco was reached via WEST then
south, a different geometric direction from `front_yard`). Flagged hours ago in
`world_map_reconstruction.frontier_untested_edges` as "the single most on-narrative untested edge
in the whole known map" but never actually pursued until now. **Result: REFUTED as a route to
anything new.** 5 x-columns swept (x=40, 60, 102 [directly under the room's central hedge
landmark, on the theory a hidden door would sit under the room's one distinctive object -- same
instinct as `house2_interior`'s real door], 120, 136 -- nearly the room's full visible width), all
`Navigator.move!(:down)` reporting `:blocked` at the identical y=112, and `Terrain.signature_at`
confirms one continuous BG tile signature ({22,23,32,33}/{20,21,30,31} alternating) across the
whole row, directly against the HUD row below -- no door-shaped signature break anywhere in it
(unlike a real door elsewhere in this project, which shows up as exactly such a break in an
otherwise-uniform wall row). No hostile/unknown-hazard OAM sprite was present in the room during
the sweep (only Link, the central hedge creature, and the D9-confirmed-friendly
villager_wandering_creature companion tile), so D13's avoidance primitive wasn't needed and no HP
was spent. No item, chest, signpost, or beach/water visual in any of the 5 route screenshots. This
refutes the LITERAL "due south of front_yard" reading of the NPCs' clue specifically -- it does
NOT refute the clue itself or the sword hypothesis. Plage Coco (UPDATE 6, exhaustively swept) and
this edge were the two most concrete "south" candidates on file and both are now closed with no
bidule found; the remaining untested edges in `world_map_reconstruction.frontier_untested_edges`
(e.g. `riverside_south_room` WEST, `163/0` clover_field, `north_corridor_room`) are the next places
to look, and/or the "la plage" reference may point somewhere not yet reached at all -- an explicit
owner call on where to look next is warranted rather than another self-directed pivot. Full detail:
`world_topology.overworld_screen2_south_edge`, `room_labels['178/0']`.

`shop_screen`'s door, retry 3 is DONE (September 10 2026) -- CLOSED, anti-patch budget spent, do
not attempt a 4th routing try. Both the NPC-east/NE route and the hedge-maze route failed cleanly
(hedge maze turns out to be `shop_screen`'s own north boundary, connecting to the already-known
`clover_field`/163-0 -- new topology fact, appended to `world_topology.shop_screen_door_approach`,
not yet reflected in the coordinate grid/graph). Real finding via pixel analysis: the door's south
approach band splits in two -- part is open ground nothing reaches, part (y~96-110, right under
the door) is covered by 2 bush clusters. Consistent with, and new live evidence for, this
project's standing "bushes are conditionally-blocked, need a cutting item" hypothesis
(`hypothesis`/`verified_count: 1`, no direct cut test performed). **This is the SAME blocker type
as the sword hypothesis's core evidence** -- a second, independent location (this door) is gated
by the identical conditional terrain as the crate_room hint books predicted. Not re-tested against
an actual cutting item (Link has none yet) -- if/when one is found, this door is worth a cheap
retest before assuming it needs a whole new route.

## In-flight work (for resumability)

**Owner provided the official game manual, September 11 2026** -- read in full, distilled into
`docs/GAME_MANUAL_NOTES.md` (paraphrased mechanics only, original PDF NOT committed, copyright --
see `DECISIONS.md`'s D14). Best lead: the SELECT map has a `!?` marker ("important locations you
need to visit") and a separate "message" marker (re-playable important dialogue), both previously
assumed to be a fixed legend only, never checked as real per-cell markers. Dispatched below.
Also flagged, not yet dispatched: pushing (no item needed, distinct from pulling) and diving (`B`
in water) are both untested mechanics in this project -- Plage Coco's water strips were always
treated as boundaries, never actually dived into.

**Owner correction, September 11 2026**: "Il y a 8 livres et pas 4 dans la bibliothèque" --
crate_room's 6 "confirmed hard negative" grid crates were tested with repeated short `:a` taps,
never one sustained ~110-frame hold -- the exact same bug class that hid `225/0`'s signpost 2nd
page. Re-testing all 6 with a proper hold now, see below.

As of September 11, 2026, ~01:35 UTC, one subagent remains dispatched -- check `ListAgents`
before assuming it is idle or before re-dispatching a duplicate:
- **`overworld_screen2`'s (178/0) untested SOUTH edge** -- with Plage Coco now believed
  exhaustively swept (no bidule), this is the pivot: the literal, most direct "south road" reading
  of the starting_house NPCs' clue, never actually pursued (attention went to Plage Coco instead).
  See `world_topology.world_map_reconstruction.frontier_untested_edges` for why this was always
  flagged as "the single most on-narrative untested edge" but never tested. Clue-directed, has
  access to D13's new avoidance primitive if needed; does NOT have D12's Plage-Coco HP-write scope
  (new room/purpose, would need a fresh ask).

**`226/0`'s last unswept pocket is DONE, September 11 2026 (independent Explorer subagent, D13's
second validation data point)** -- still NO "bidule" found, and this closes out the ENTIRE Plage
Coco cluster's remaining unswept ground (both `226/0`'s own pocket and, combined with the prior
209/0 sweep, the whole cluster). Using `Navigator.avoid_hostiles_and_push!` (radius:16 shipped
default, no retuning needed) as the PRIMARY method throughout: resumed from
`lib_226_session_end.dump` (x=46,y=26), pushed east to a real, reconfirmed wall at x=124,y=26 (10
consecutive `:blocked` results, zero position drift), pivoted south to x=119,y=59 (real progress),
then further east to a genuine 3-way water-bounded cul-de-sac at x=154,y=58, and separately
confirmed the area's only other open branch (`up` from x=119,y=59) loops back to the exact same
x=124,y=26 wall rather than opening new ground -- the whole area is one contiguous, now fully
bounded pocket. No item/chest/signpost/dialogue trigger in any of 7 screenshots taken along the
route (pixel-diffed and color-histogrammed to rule out a stale render or an out-of-palette icon
being missed). `226/0`'s `room_labels` status promoted `glimpsed` -> `charted`. D13 SECOND
VALIDATION DATA POINT: the shipped `radius:16` default (already retuned once, in 209/0) worked
here with NO further retuning -- correctly separated genuine walls from hazard-blocked pushes,
reached real new ground twice (south, then further east). One usability caveat found and logged:
the primitive doesn't itself detect "hit the same wall again" and stop early -- that judgment is
still on the caller. 3 HP-writes, all scratch checkpoints (`e226_*.dump`), never `main.dump`, all
logged. Full detail: `room_labels['226/0']`'s newest addendum and `DECISIONS.md`'s D13 entry (a
3rd addendum may be worth adding there summarizing both validation retests together). See "Quest
hypothesis" below for what this means for the sword lead -- the cluster is now believed
EXHAUSTIVELY swept, not just "no known gap left".

**D13 Builder task DONE, September 11, 2026** -- `lib/navigator.rb` gained
`Navigator.avoid_hostiles_and_move!`/`avoid_hostiles_and_push!` (OAM-hazard-biased, auto-shield-hold
via a new `Navigator.shield_equipped?`/`move_holding!` pair), validated live against `209/0`'s east
bottleneck (the pocket the ad-hoc tactic left CLOSED under the anti-patch rule, see below). VERDICT:
measurably helped, but only after a live-found correction -- the first-guess default
(`HAZARD_PROXIMITY_PX=40`) performed WORSE than the ad-hoc tactic (walked Link backward into the
room's own west dead-end, 28 damage for zero progress); retuned to `16` based on that same retest,
which then reached x=140 (past the x>95 boundary the ad-hoc session never crossed) for 56 damage
across 22 calls. No bidule found in the newly-reached ground. Side finding: the B-slot equipped-item
byte, previously unlocated, is now `0xDB00` (hypothesis, `verified_count: 1`) --
`data/ram_registry.json`'s `wram_unmapped.equipped_b_item`. Full detail: `DECISIONS.md`'s D13 entry
(2 addenda: API choice, validation retest) and `room_labels['209/0']`'s own addendum.

**`riverside_east_room` (209/0) full exploration is DONE (September 10 2026, clean redispatch after
the earlier container-restart loss noted below)** -- still NO "bidule" found, but the room now has
a full `room_labels['209/0']` entry (previously none at all) and its connection to `208/0` is
pinned down precisely: a plain horizontal transition on the shared y=115 row, confirmed BOTH
directions now (`world_topology.riverside_south_room_east_exit` promoted to `verified`,
`verified_count: 2`). Swept roughly the room's west half and center (entry column, the west
river-edge dead-end pocket, and a creature-infested center pocket up to about x=94,y=74) -- found
only environmental hazards (2+ instances of the same tile=0x60-family hostile creature already
known from the rest of Plage Coco), a non-interactive flower-cluster wall (`:a` tested, no effect),
hedge, and unentered water. The room's east half (past x~95, including the hedge-bounded north
area) is CLOSED for this session under the anti-patch rule -- 6+ distinct attempts to push past the
2-creature center pocket all oscillated without net progress; a future session wanting the rest of
this room needs a genuinely different tactic (e.g. a real intercept/avoidance primitive, per
`world_topology.riverside_south_room_adaptive_chase_experiment`'s assessment), not another straight
push. HP-write permission (D12 Plage Coco amendment) used twice (`0xDB5A` 8->24 each time, both on
scratch checkpoints, both logged with cause) plus one no-op call (already at max, logged anyway for
transparency). Full detail in `room_labels['209/0']`. See "Quest hypothesis" below for what this
means for the sword lead.
**UPDATE, September 11 2026 (D13 Builder validation)**: the "genuinely different tactic" this note
asked for now exists and closed the rest of this room -- see "In-flight work"'s D13 entry above.
East half swept to the room's real x=140 east wall and a real north wall further up; still no
bidule anywhere in the room.

**Container restart, September 10 2026, ~20:15 UTC**: this session's container restarted, killing
all in-flight subagents with no loss to git (last commit `0856ffe` survived) or to
`/tmp/zelda_checkpoints/` (survived intact, 278 files). Lost work: the first 209/0 dispatch above
(no progress had been saved) and the already-considered-abandoned D9-rollout zombie
**CORRECTION (September 10 2026, this session's redispatch)**: "no progress had been saved" was
not quite right -- 8 stray `lib_e209_*.dump`/1 `.png` checkpoints timestamped 22:05-22:19 (just
before the restart) survived in `/tmp/zelda_checkpoints/` from that lost dispatch, reaching the
same west dead-end pocket (x=4-6,y=90-112) this session independently reached too. Not treated as
authoritative (per this session's "clean fresh start" mandate, everything in `room_labels['209/0']`
was independently re-derived), but inspected for orientation and cross-checked: no item visible in
any of them either, consistent with this session's own findings. Worth noting for a future cold
reviewer so "no progress saved" isn't taken as literally zero trace on disk.
(`a1ace155a0a80c4b1`, moot -- superseded by its own fresh restart hours earlier, `53afb77`).
Also lost: two unrecognized background shell watchers referencing task ids `be9wylr1b`/`b7uea137o`
("wait until the backgrounded NE-push script's ruby process exits" / a `cat`-on-output loop) that
this planner did not knowingly create -- these look like a subagent using `run_in_background`
internally despite the standing rule against it (`AGENTS.md`'s "Explorer subagents" convention,
"it has gotten subagents stuck twice" -- possibly a third instance, and possibly a contributing
factor to this restart, though not confirmed). No specific subagent was identified as the source
since the session that ran it is gone. Flagged here rather than chased further; worth an
escalation if the pattern recurs.

**Plage Coco push with HP-write permission is DONE (September 10 2026, Explorer session, D12
amendment scope)** -- still NO "bidule" found anywhere. `224/0`'s area past x=68,y=48 (both `up`
and `left`) and `226/0`'s NW cul-de-sac `up` wall were both pushed to a clean conclusion rather
than another early safety-stop: every direction either resolved into a confirmed room transition
into already-fully-explored territory (`224/0` gained a SECOND, previously-unknown connection
each to `225/0`, along the north edge at y=26, and to `208/0`, at its NW corner -- both new doors
between already-charted rooms, not new ground) or a genuine, reproduced dead-end wall (`224/0`'s
west edge at x=20; `226/0`'s north wall, reconfirmed blocked at 2 different x columns after 3
consecutive identical hits, closing it under the anti-patch rule). No item, chest, signpost, or
dialogue trigger appeared in any screenshot taken this session. HP-write permission (D12's
September 10 amendment) was used 5 times, all `mmu.write(0xDB5A, 24)` on scratch checkpoints only
(never `main.dump`): 2 resumes from a prior session's ~1-heart safety-stop point (one per room),
2 top-ups before pushing into fresh ground at 1.5-2 hearts remaining, and 1 top-up at 5/6 health
that was earlier than the "safety net, not habit" guidance intends (worth flagging honestly, not
a case of ignoring the creature -- just one write issued a bit ahead of the actual risk). Full
route-by-route detail, exact checkpoint chain, and HP figures in `room_labels["224/0"]`/`["226/0"]`'s
newest addenda ("THIRD PUSH"/"FOURTH PUSH"). See "Quest hypothesis" below for what this means for
the sword lead.

**Bush contact/`:a` test is DONE (September 10 2026, Explorer session)** -- first-ever direct
interaction test on a bush, not another door-routing attempt. From `lib_shop_wide3.dump`
(`shop_screen`/179-0, full HP), reached a reachable bush cluster in the yard's SW area (visually
confirmed adjacent in the rendered framebuffer; not the exact x=81-94 door cluster, which is still
unreached -- reaching it would be a 4th door-routing attempt, already closed off). Result: plain
contact is indistinguishable from a wall -- 10 raw `Navigator.tap(:right)` calls all produced
zero net displacement, no partial slide. HP unchanged (24/24 throughout). `:a`-while-facing
produced no dialogue box or any UI change (3 presses + 120 idle frames, framebuffers compared
pixel-by-pixel against a known real dialogue box from the same room -- no match, only unrelated
ambient animation). Movement worked normally afterward (no soft-lock). Answers this session's
falsifiable question: option (a), plain-wall behavior, confirmed; (b)/(c) refuted for this
cluster. Does not confirm what a cutting item would do (Link has none). Full method/result in
`terrain_collision.background_tilemap_predicts_walkability`'s newest caveat and
`world_topology.shop_screen_door_approach`'s FOURTH SESSION note. `verified_count: 1` (single
session) -- a retest at the exact door cluster, or with a cutting item once found, would be a
genuinely independent check.

**D9 rollout on `well_platform` + `building_screen` is DONE (September 10 2026, fresh restart, ~20
minutes, well inside budget)** -- the earlier 6h+ abandoned attempt is superseded, not resumed.
Both rooms surveyed (4 OAM samples ~2s apart, no input, no reload, LCDC 8x16 mode confirmed and
both top+bottom tiles read per DECISIONS.md's D9 pitfall). No genuinely new sprite found in either
room beyond what prior sessions' descriptions already listed. Findings: (1) `villager_wandering_creature`'s
companion tile (94/95, `visual_catalog.villager_screen_companion_sprite`) now confirmed
byte-identical (full top+bottom composite, re-derived fresh from 4 separate checkpoints) in
well_platform (3 mobile instances) and building_screen (2 mobile instances) too, alongside its
already-known villager_screen/screen3_north appearances. (2) building_screen's 2 static,
already dialogue-confirmed NPCs (`dialogues.room176_pair_a`/`room176_pair_b`) got a formal
`visual_catalog` entry (`building_screen_humanoid_npc_pair`) -- new finding: both share the exact
same CHR tile data, pair_b is pair_a's sprite rendered X-flipped as a whole, not two distinct
character designs. (3) building_screen's fast intermittent single-tile object got its own entry
(`building_screen_flutter_object`) -- no cross-room CHR match, mobility under-sampled by this
method's ~2s grain (consistent with, not contradicting, its already-known fast/erratic behavior).
Full detail in `room_labels['160/0']`/`['176/0']`'s new `visual_survey` sub-objects and the 2 new
+ 1 extended `visual_catalog` entries.

`house2_interior`'s bed-healing test is DONE (September 10 2026) -- beds do NOT heal, tested
cleanly; see "Quest hypothesis" UPDATE 3 above for the full result and the open
save-editing-vs-legitimate-play question it raised, still awaiting the owner's call.

`226/0`/`224/0`'s sweep for the "bidule" is DONE for this round (September 10 2026) -- not found,
both rooms confirmed to cost real health with no healing mechanism on file -- see "Quest
hypothesis" above for the full finding and why the next step is the bed test, not a 3rd push.

`225/0`'s NE re-push is DONE (September 10 2026) -- resolved into a real room transition into
`226/0` riverside_ne_cove. `224/0`'s secondary sweep was NOT done this session (budget went
entirely to the NE route, which took far more sub-attempts than expected) -- still open, see
"Not yet tried" above. See Next question below for the full route/finding detail.

`shop_screen`'s door, retry 2 is DONE (September 10 2026) -- clean null result, NOT a repeat of
the same failure mode: swept off-grid tap offsets at the 3 already-known approach points
(north/west-corner/mid-row), all uniformly blocked across 6-12px with zero exceptions -- the
OPPOSITE signature from `house2_interior`'s real door (a narrow ~8px gap flanked by `:ok`
neighbors). Rules out a narrow-parity-trigger door at these 3 specific points, not the door
itself. Real gap now precisely identified: no checkpoint has ever stood directly south of the
door's own x=86-104 column (y=90-110) -- the west dead-corner blocks reaching that exact cell
from the tested side. Next attempt (not yet dispatched) needs a genuinely different route into
that cell -- through the hedge maze's interior, or east from the yard NPC's spot near x=40,y=96
-- not another sweep from the same 3 points. See `world_topology.shop_screen_door_approach` for
the full attempt log.

`shop_screen`'s YARD exploration is DONE (this session, September 10 2026) -- see the State
table and Next question for that result (exterior yard only, no item, door not yet reached as of
that pass).

**Owner-prompted "read all the library's books" / signpost re-test is DONE, September 11 2026
(Explorer session)** -- both parts resolved. (1) crate_room's book_a/book_b UNRESOLVED PUZZLE is
RESOLVED: it was a checkpoint-naming collision, not 2 extra objects. The checkpoints the mandate
believed were book_a/book_b's originals (`lib_crate_probe_A1*`/`lib_crate_probe_B1*`) are all
timestamped September 9, not 8 -- direct OAM reads show they stand at the EXACT positions of
book_c (top-row col1) and book_d (bottom-row col1), and independently replaying them from a fresh
Motherboard reproduces book_c/d's text verbatim, not book_a/b's. True Sept 8 book_a/b checkpoints
are not present anywhere on disk under any name -- this project cannot re-open them. The room still
has exactly 9 `tile=0x58` objects, only 2 of the 8 grid crates are real book stands, no 10th+
object exists. Real open question left behind (not chased, out of this session's scope): the SAME
crate showed DIFFERENT dialogue text on the two separately-recorded live sessions -- book content
at a given crate is observed NOT fixed, mechanism unknown. Full detail:
`world_topology.crate_room_and_riverside_content`'s new resolution paragraph. (2) `225/0`'s
signpost actually has a SECOND PAGE the prior session's 2 quick default `:a` presses dismissed
before it rendered: holding the 2nd `:a` ~110 frames (same order of magnitude as the SELECT map's
own render window) reveals "Se protéger avec un bouclier!" ("Protect yourself with a shield!")
after "Attention aux oursins!" -- the project's first text directly linking the shield (from
starting_house's NPCs) to the sea-urchin hazard by name. Re-approaching from down/left/right
facings produced no dialogue (direction-sensitive as expected, not a second trigger angle). Not
yet tested whether holding the shield actually blocks sea-urchin contact damage specifically.
Full detail: `dialogues.riverside_flower_clearing_sign`. Neither finding relocates the "bidule";
the owner's hint was about a bookkeeping gap and a truncated dialogue, not a hidden item. Both
registry entries still `hypothesis`/`verified_count: 1` (single session each).

```
Question: Where are book_a/book_b actually located/triggered, and does resolving that reveal
  anything new (a 10th+ object, new room state, new text) relevant to the sword hypothesis? Does
  225/0's signpost have a second page or angle-sensitivity?
Answer: confirmed (both). book_a=book_c's crate (top-row col1), book_b=book_d's crate
  (bottom-row col1) -- a checkpoint-naming collision, not new objects; room stays at 9 objects,
  2 real book stands. Signpost has a real, previously-missed 2nd page ("Se protéger avec un
  bouclier!"), gated on a long :a hold, not a new facing angle.
Indicators: game = unchanged (no sword, no new item found) | trip A->B = unchanged | verified
  facts = unchanged (both new findings are hypothesis/verified_count 1, not yet promoted)
Decisions made: none
Next question proposed: none forced by this session -- overworld_screen2's south edge (already
  in flight, see above) remains the live sword-hypothesis thread. If revisited, a real test of
  whether the shield blocks sea-urchin damage specifically (not just the tile=0x60 family's
  knockback) would directly exercise the signpost's new page 2 content.
What NOT to redo: don't try to re-open book_a/book_b's "original" checkpoints again -- confirmed
  not on disk under any name, by timestamp and by content, not just by filename guess. Don't
  re-read 225/0's sign with a quick 2nd :a tap and conclude it's single-page.
```

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
