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
| Dialogues / readable text | 19 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, crate_room's library fully read -- 8 books + 1 wall object, 9/9 tile objects resolved via OAM
(corrected September 11 2026 from an earlier, buggy "4 books" count -- see In-flight work below); house2_interior's 2 OAM-verified telephone objects; `riverside_flower_clearing_sign` (225/0) -- a two-page signpost, "Attention aux oursins !" then "Se protéger avec un bouclier !" (2nd page found September 11 2026, needs a long `:a` hold to reveal), NOT a chest/item; `shop_screen_yard_npc` (179/0) -- a friendly yard NPC reciting the SAME save-tip line as room176's pair, first confirmed case of a reused dialogue asset, September 10 2026 -- all hypothesis/verified_count 1). |
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
  named, not-yet-found item in this whole project. Not located anywhere yet.
- **Warp holes** -- `book_f` describes teleporting between them ("il y a des trous Warp...").
  Never encountered/tested anywhere in this project. Could shortcut navigation if found.

Also newly known, not yet acted on: `book_e` mentions a laser-blocking shield variant beyond the
standard one (owned); `book_g` opens the real SELECT-map atlas directly from its own dialogue.
The owner-provided game manual (`docs/GAME_MANUAL_NOTES.md`, D14) flagged pushing (no item needed)
and diving (`B` in water) as untested mechanics -- Plage Coco's water strips were always treated
as boundaries, never actually dived into; worth revisiting given the cluster is otherwise closed.

`shop_screen`'s door is CLOSED (anti-patch budget spent) -- bushes block its south approach, the
same conditional-terrain blocker as the sword hypothesis's core evidence. Worth a cheap retest
once any cutting item is found, not a routing problem.

### Clue-weighting synthesis, September 11 2026 (synthesis session, no new measurement)

Cold re-read of `AGENTS.md`, `DECISIONS.md` D11-D14, `docs/GAME_MANUAL_NOTES.md`, all 19
`dialogues.*` entries, `select_map_screen` and `data/world_model.json`. Nothing here is a new
observation -- it is a ranking of facts already on file. Archive this block once its recommended
action has been run and its outcome folded into the state above.

**Weighting rule used** (re-apply it, don't re-derive it): rank a clue by (a) whether it names a
PLACE / PERSON / ACTION or only describes a generic mechanic, (b) whether it has already been acted
on to exhaustion, (c) whether it was captured before this project knew short `:a` taps truncate real
content -- two confirmed instances so far (`riverside_flower_clearing_sign`'s page 2, and
`crate_room_book_a/b/e/f/g/h`'s initial trigger). Anything transcribed with `Navigator.tap_button`
defaults and never re-held is a candidate third instance.

1. **`house2_telephone_examine` (169/16) -- the strongest untested lead on file.** The only dialogue
   in the registry naming a character, a mechanism and a place at once ("Téléphone... A
   l'extérieur... Pépé le Ramollo n'a pas l'air d'être un grand causeur..."). Independent
   corroboration from the game itself: `select_map_screen`'s EIGHTH SESSION read `177/0`'s own
   in-game place name as **"Chez Pépé le Ramollo"** and `162/0`'s as "Chez Marine et Tarkin" -- the
   only two rooms in this project carrying a "Chez <name>" label, and the other one is the household
   that gave Link the shield and both beach clues. `169/16` is the interior of `177/0`'s building
   (`room_labels['169/16']`, `world_topology.room177_exits`, which found exactly one door), so the
   telephone and the named character are the SAME location. **Discrepancy to settle, flagged not
   resolved**: the owner's framing is "ma petite maison à côté de celle de Pépé le Ramollo" (next
   door); on-file data says same house. Cheap to settle -- read the SELECT place-name box while
   standing in `169/16`, or recount `177/0`'s enterable doors. Two errors in this entry's own note
   have kept the thread under-weighted: it cross-references "`world_model.json`'s building_screen
   entry (176/0, a different room)" when `world_model.json` actually catalogues Pépé le Ramollo in
   `house2_interior` ITSELF, as an NPC, with a 4-page capture and a 2-cell approach test proving the
   two OAM pairs are one 2x2 body; and it calls that 4-tile block "an invisible interactive trigger,
   not a rendered object" because no BG furniture matches its position -- but OAM sprites are not BG
   furniture, and `world_model.json` records the same block's tiles as 112/114/116/118
   (0x70/0x72/0x74/0x76, flags 2), the same family as `visual_catalog.shop_screen_yard_npc`
   (0x70/0x72, a confirmed humanoid). If the speaker is a character rather than a thought-bubble,
   the line reads as a hint CHANNEL ("hints come by telephone, and telephones are outside"), not a
   one-off remark -- and `docs/GAME_MANUAL_NOTES.md` independently lists a telephone booth among the
   island's generic location types (D14 mechanic knowledge, not a claim about where one is here).
   Never acted on: no session has ever looked for a telephone outside, and neither `177/0` NPC has
   been re-approached since September 8. Captured with `tap_button` defaults (12 `:a`), before the
   truncation bug was known.
2. **`house2_telephone_call` (169/16) -- "always a wrong number" is NOT established.** One session,
   one object; the single retest only confirmed the sequence restarts from "DRING DRING!", it never
   re-read the ending. Fixed vs. random vs. state-gated is genuinely open, and a "who do you want to
   call" `Oui/Non`-shaped prompt of the kind every crate_room book turned out to have would be
   invisible to a short tap. Note the shape: an indoor rotary phone giving a gag is exactly what
   entry 1's text predicts if the real hint instrument is a booth outside.
3. **`starting_house_npc_beds` + `_bench` (163/16) -- highest-trust source, clue largely spent.** Two
   characters in the household the game names "Chez Marine et Tarkin" both point south to "la plage";
   the bench NPC names "un autre bidule qui est resté sur la plage". Still the most directionally
   specific clue on file, but acted on to exhaustion (Plage Coco swept, `178/0`'s south edge a
   confirmed wall). NOT refuted -- two live outs: "la plage" need not be limited to the two rooms the
   SELECT map calls "Plage Coco", and the bench line is the REPEAT-state line of a story-flag-gated
   table (its first-meeting line differs, on file), so it can change when a flag flips. Also never
   re-held: its own entry says it stopped without testing whether more `:a` presses exhaust or loop.
4. **The SELECT box's second line ("le message du hibou") -- rendered on screen, never transcribed.**
   `crate_room_book_a` describes that box as place name + owl message; the manual's "message mark" is
   the same system generically. Six place names are on file, but exactly ONE room ever produced a
   second line -- `160/0` well_platform, "Village des Mouettes" -- and `select_map_screen`'s note
   records only that `a_hold=110f` "completed the 2nd line", never what it said (its screenshot is in
   a scratchpad that may not survive). A real, cheap, un-harvested in-game hint.
5. **`crate_room_book_h` -- "la Loupe".** The only named item never found; proves it exists. Zero
   locational content, and the manual confirms hint books are deliberately non-spoiling about
   locations. A flag to check back against, not a destination.
6. **`crate_room_book_f` -- Warp holes.** Self-gating by its own text (you cannot warp to a hole that
   has not appeared on screen yet), so worth nothing until one is physically found. Useful mainly as
   a reason to stop reading unfamiliar BG art as ordinary terrain.
7. **`riverside_flower_clearing_sign` page 2 -- "se protéger avec un bouclier".** Already acted on
   (shield-hold, then D13). Tells you how to survive one room's hazard, not where to go; its real
   value was methodological (truncation instance #1).
8. **`crate_room_book_e` -- the laser-blocking shield.** Forward-looking only, no location, and it
   names an enemy class never encountered -- weak evidence we are still very early.
9. **`book_b`/`book_c`/`book_d`, `crate_room_book_g`, `crate_room_wall_object`.** Mechanics and
   flavour. Worth noting: `book_b`'s title is the ONLY occurrence of "épée" anywhere in the registry
   -- no character has ever mentioned a sword.
10. **`room176_pair_a`/`_b`, `shop_screen_yard_npc`, `room177_static_sprite`/`_wandering_sprite`.**
    Near-zero weight, and the calibration examples: the save-tip line is byte-identical across two
    rooms (recycled asset, confirmed) and `177/0`'s two sprites recite one identical flavour line.
    One cheap exception: dialogue here is story-flag-gated (proven at `starting_house`), and `177/0`'s
    pair has not been re-approached since September 8.

**Sword and shield, plainly.** Shield: closed as a lead -- owned and observed (`0xDB00`=4), and every
clue since is about USING it; only book_e's laser variant is open, and it names no location. Sword:
never observed and never mentioned by any character -- the hypothesis rests entirely on indirect
inference (conditionally-blocked bushes, two books teaching sword mechanics, an empty A-slot), with
"un bidule" (unspecified) as the closest first-person clue. Hold it as a hypothesis, not as an
observed objective.

**Whose words carry the most weight**: Tarin/Marin's household first by trust -- they gave a real item
and two convergent directional clues -- but their clue is spent in reachable territory. Pépé le
Ramollo is second by trust and FIRST by remaining value: the only other character the game itself
honours with a "Chez <name>" screen, the only one whose line names a mechanism for receiving future
hints, and the only one nobody has ever followed up on. The children and the books are background;
they explain systems, and per D14's manual notes that is by design.

**Recommended next action (one).** Dispatch an Explorer to `house2_interior` (169/16) from
`lib_house2_interior.dump` and re-run BOTH telephone objects with the sustained-hold method (~110-120
frames per `:a` via `mmu.joypad.key_state.press`/`clear`, never `tap_button`'s default), rendering
every frame and stepping away between objects to avoid the documented re-trigger trap -- and, in the
same visit, read OAM slots 12-15's tile IDs and screenshot the room. Falsifiable question: *does
either house2_interior telephone object hide content that short taps truncated (a further page, a
Oui/Non prompt, a different call outcome), and is the 4-tile block at (y=64-80, x=72-80) a rendered
humanoid rather than an invisible trigger?* Why this over everything else: it is the owner's own
flagged lead; it is the cheapest session on the board (interior, zero hostiles, confirmed route,
existing checkpoint, no D12 write needed); it targets the exact bug class that produced two real
finds tonight, on an object transcribed before that bug was known; and it resolves two documented
errors in the registry's own note. It routes the session after it either way -- a branch or a named
place becomes a destination, and a confirmed-fixed gag promotes "téléphone... à l'extérieur" into a
concrete search for a booth among the frontier's unexplored village-side rooms (`146/0`
north_corridor_room, `163/0` clover_field, both glimpsed-only with zero exits explored). Runner-up if
it comes back empty: transcribe `160/0`'s never-read second SELECT-box line (#4 above).

## In-flight work (for resumability)

**Major discrepancy found, September 11 2026**: `data/world_model.json` (an older "spike"-era hand-curated
file, never fully reconciled with the current registry) records `house2_interior`'s (169/16)
4-tile OAM block (y=64/80, x=72/80, tile 112/114/116/118) as **Pépé le Ramollo himself** -- a real
visible NPC, not the "invisible trigger" the current `room_labels['169/16']` describes -- and says
there's only ONE NPC here, not two separate "telephone" objects. The current registry's own note
also cites world_model.json with a WRONG room ("building_screen 176/0" -- that room doesn't exist
in that file; Pépé is recorded under `house2_interior` itself). Dispatched a reconciliation below.

As of September 11, 2026, ~03:30 UTC, one subagent is dispatched (model: Opus, not the usual
Sonnet -- owner-requested for reasoning/synthesis strength, see the conversation) -- check
`ListAgents` before assuming it is idle or before re-dispatching a duplicate:
- **Synthesis task, not live exploration**: rank every dialogue clue in the registry by how much
  weight it deserves for "where to go next", covering the sword, shield (+ `book_e`'s laser-shield
  mention), "la Loupe", Warp holes, and specifically the owner's own flagged lead --
  `house2_interior`'s telephone (`dialogues.house2_telephone_examine`/`_call`) explicitly
  namechecks Pépé le Ramollo (`villager_screen`'s NPC, next door) and was only ever tested once for
  a single fixed outcome. Expected to end in ONE concrete recommended next action, appended to this
  section by the agent itself. Tonight's dispatch history (D9 restart, Plage Coco
pushes, D13 build+validation, the south-edge test, the crate_room library correction, the SELECT
marker scan) is archived at `docs/archive/SESSION_LOG.md` -- resolved, not needed to resume.
## Next question

Session 4 (PLAN.md) is fully complete -- see the State section above. NOT currently paused (that
framing is stale from an earlier session); see "Quest hypothesis" above for the live thread. Most
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
