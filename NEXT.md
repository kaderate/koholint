# NEXT

Entry point for any resumption. One page, no more. Full chronological history (every session's
question/answer/decisions) lives in `docs/archive/SESSION_LOG.md` -- read it to look up a past
finding, not to resume the project.

## State as of September 9, 2026 (PLAN.md Session 4 follow-up)

6 of the 7 PLAN.md Session 4 checkpoints (`after_shield_interior`, `front_yard`,
`overworld_screen2`, `villager_screen`, `shop_screen`, `screen3_north`) are regenerated and
traversed via `lib/` alone, no `legacy/` file. `house2_interior` (the 7th) is REFUTED, not
inconclusive, via a real walkability-map BFS (`lib/validation/checkpoint_house2_interior.rb`,
`Terrain::RoomClassifier`) -- see `data/ram_registry.json`'s `world_topology.room177_exits` for
the full finding. **`legacy/` was NOT removed**: D5's parity condition (all 7 checkpoints) isn't
met.

**Indicators**

| Indicator | Value |
|---|---|
| Rooms found | 13 labeled in `data/ram_registry.json`'s `room_labels` (8 "charted", 5 "glimpsed"/less). Graph and screenshots published in the Koholint Atlas artifact. |
| Dialogues / readable text | 7 confirmed entries in `ram_registry.json`'s `dialogues` (villager duo's shared line, room176's two save-mechanic NPC lines, two hint-book pages in the crate_room library, more). |
| Terrain / collision | D8 live: reads BG tilemap signatures from VRAM (`lib/terrain.rb`), 93.1%-validated against live-probe oracle. Primary method; live probing kept as fallback. |
| Save/continue | Mechanically verified end-to-end: hold A+B+START+SELECT opens the real save menu, "SAUVEGARDER & QUITTER" writes a real `.sav` (MD5-diffed), "REVENIR AU JEU" continues at the room's own door. This is the durable-progress path -- see "Standing conventions" below. |
| Current position | `/tmp/zelda_checkpoints/main.dump` (continuous session state, not versioned -- see below), last saved September 8 17:05, around `riverside_south_room` (208/0), glimpsed but unexplored past the entrance. |

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

## Paradigm to question (anti-patch, house2_interior)

Two genuinely distinct attempts at a real walkability-map BFS (`Terrain::RoomClassifier`, cache-
respecting sweep with a targeted supplementary re-probe, then a corrected exhaustive sweep
checking every edge's real room identity) both converge: villager_screen (177/0) has only 2 exits
(161/0 north, 178/0 east), no door into the building anywhere in the 83 cells reachable from
spawn. This isn't "one more probe away" -- it's the mechanism itself (tile-based cardinal
movement from a BFS-reachable cell) coming up empty on a full, real sweep. Owner must decide the
next approach; candidates, not yet tried: (a) sub-pixel wall-hugging alignment before pushing
into the door (legacy/'s old route detoured into the SW corner first, suggesting position within
a tile matters, not just which tile); (b) an animation/dialogue trigger (talk to the room's 2
NPCs first?); (c) house2 is entered from a different room/approach entirely, not villager_screen.
Do NOT re-run more BFS sweeps or column guesses on this same mechanism without picking one of
these first.

## Next question

Paused, awaiting the owner's go-ahead (explicit "arrête-toi et ping moi" checkpoint). Candidates
once resumed: the house2_interior paradigm question above; explore past
`riverside_south_room`'s entrance (two unidentified figures seen at the door), test the
SELECT-map cursor lead from the crate_room hint book, retest `riverside_screen`'s signpost with a
positive control. Also deferred, not urgent: formalizing a navigation spec/format (raised by an
external review, judged sound but not blocking).

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
