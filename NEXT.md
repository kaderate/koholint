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
| Rooms found | 18 labeled in `data/ram_registry.json`'s `room_labels` (8 "charted", 10 "glimpsed"/less -- `224/0` riverside_south_river_room and `225/0` riverside_flower_clearing, south/east of `riverside_south_room`, both further explored (224/0's scroll mechanism and "totem" identity resolved, 225/0's ground-accessible extent mapped to a dead-end pocket); `209/0` riverside_east_room, found east of `riverside_south_room`'s south band (past the prior x=134,y=115 stop point), single-glance only, September 10 2026; `179/0` shop_screen, first actually explored September 10 2026 -- turns out to be the shop's EXTERIOR yard, not its interior; see `world_topology.shop_screen_door_approach` and Next question below). Graph and screenshots published in the Koholint Atlas artifact (not yet updated with these rooms or this session's findings). D9 visual-catalog `visual_survey` now covers 4/18 (`front_yard`, `villager_screen` pilot + `crate_room`, `screen3_north` rollout, same day, autonomous session) -- see `DECISIONS.md`'s D9 entry. |
| Dialogues / readable text | 14 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 4 books + 1 wall object, 9/9 tile objects resolved via OAM; house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a signpost reading "Attention aux oursins !", NOT a chest/item; `shop_screen_yard_npc` (179/0) -- a friendly yard NPC reciting the SAME save-tip line as room176's pair, first confirmed case of a reused dialogue asset, September 10 2026 -- all hypothesis/verified_count 1). |
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
`unknown`) for this. Full rationale for each: `DECISIONS.md`.

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

**Not yet tried**: a fresh push past `225/0`'s NE route (this time routing around/through the
knockback rather than treating it as a wall, per D11) and a fuller sweep of `224/0` beyond its
entry point, specifically looking for the "bidule"; separately (lower priority now), testing
`overworld_screen2`'s (178/0) south edge remains a real but less on-narrative frontier; locating
the inventory/equipped-item RAM bytes. `shop_screen` is RESOLVED not to be this session's answer --
its yard held only a recycled-dialogue NPC and a decorative object, no item, and its actual
interior (behind the "MAGASIN" door) was never reached -- see Next question below.

## In-flight work (for resumability)

As of September 10, 2026, two subagents were dispatched and may still be running or may have
completed with results not yet folded in here -- check `ListAgents` before assuming either is
idle or before re-dispatching a duplicate:
- **D9 rollout on `well_platform` + `building_screen`** (visual-catalog survey, same method as
  the `front_yard`/`villager_screen`/`crate_room`/`screen3_north` rollout already in
  `DECISIONS.md`'s D9 entry). Running unusually long (4h+ as of last check, vs. ~45-90 min for
  similar tasks) -- a status check was sent; no reply folded in here yet.
- **`225/0`/`224/0` re-push** ("Plage Coco" -- pushing past `225/0`'s NE route with the D11
  knockback understanding, plus a fuller sweep of `224/0`, looking for the "bidule" NPC A
  mentioned). See "Quest hypothesis" above for the full reasoning.

`shop_screen` interior exploration is DONE (this session, September 10 2026) -- see the State
table and Next question for the result (exterior yard only, door not reached).

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
- `225/0`'s signpost (the room's only known interactive object, "Attention aux oursins !") is
  resolved -- don't re-approach it expecting an item; it's a hazard warning, not a chest, and
  produces no HUD/inventory change. `225/0` does not scroll (single fixed screen) and its ground-
  accessible area dead-ends at a hedge/water pocket SE of the sign (`probe_all` blocked both
  down and right there) -- don't re-walk that same SW pocket expecting a new exit; the open gap is
  the untried NE route past the sign instead (see "Next question"). `lib_explorer_225_route7.dump`
  is a real but LOW-HEALTH (1 heart) checkpoint -- resume from `lib_explorer_225_fresh_entry.dump`
  (full health) instead unless deliberately continuing from the dead end.
