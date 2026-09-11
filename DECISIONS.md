# Decisions

One entry per structuring choice: context, options, choice, and the condition that would
invalidate it. Statuses: `ratified` (validated by the owner), `measured` (established empirically,
to be ratified), `taken without validation` (inherited from the spike, to be revisited),
`open` (to be decided by the owner).

## D1 — Source of position and room: HRAM, not OAM

- **Status**: ratified (September 7, 2026).
- **Context**: the spike read Link's position from OAM by exclusion and tile detection, and named
  screens by discovery order. Two memory-diff hunts had failed by only scanning WRAM. A diff over
  the whole `0x0000-0xFFFF` space, done on September 7 after the review, found the bytes in HRAM.
- **Choice**: `0xFF98` (X), `0xFF99` (Y), `0xFF9E` (direction), `0xFFF6` (room), `0xFFF7` (map) are
  the primary source. Detail and `verified_count` in `data/ram_registry.json`. OAM becomes a
  cross-check, never the source.
- **Invalidated if**: a room where these bytes don't track Link, or two distinct rooms sharing the
  same `0xFFF6`+`0xFFF7`.

## D2 — Position via OAM

- **Status**: taken without validation during the spike, **obsolete** per D1.
- Kept for the record: it cost `find_link`, `cell_for`, scroll detection via SCX/SCY,
  `clear_entry_lock!`, and part of the retry budgets. Do not reintroduce.

## D3 — Hardware mode: DMG

- **Status**: decided (September 7, 2026) — **DMG**.
- **Context**: the DX ROM runs in DMG for lack of a `--cgb` flag, discovered incidentally. DX
  content (the color dungeon, the photographer) is locked behind CGB mode. Checkpoints and the tile
  catalog (hash including the palette) are mode-specific.
- **Choice**: stay on DMG. Current checkpoints and data remain usable; DX content stays
  inaccessible until this choice is revisited.
- **Invalidated if**: the owner decides that access to DX-only content justifies regenerating
  everything. Known and accepted cost at the time of the switch: every checkpoint/data created in
  DMG up to that point has to be redone.

## D4 — Exhaustive exploration per screen

- **Status**: **decided (September 8, 2026) -- on demand.** D8's tile-based terrain reader
  (`lib/terrain.rb`) is exactly the clean outcome this entry's deciding condition called for:
  reading a cell's walkability from the BG tilemap costs the same whether it's read upfront for a
  whole screen or lazily as `Navigator`/route-planning needs it, so "map everything" and "map on
  demand" collapse to the same cost -- there's no separate exhaustive-mapping step to justify.
  `ScreenMap`/`TileClassifier`/`TileCatalog` (the exhaustive `legacy/` tools this decision was
  originally about) stay retired per D5; nothing resurrects them.
- **Previously**: open, **deferred**. Deciding condition: a clean outcome (confirmed or refuted) from
  Plan Session 1 (`PLAN.md`) — if collision reads from WRAM, the exhaustive approach loses its
  purpose and D4 leans toward "on demand" almost automatically. Session 1's first attempt
  (September 7, 2026) was **inconclusive**, not a clean outcome: `front_yard` (needed for the
  two-room WRAM diff the method requires) turned out not to be reproducible, and a fallback
  single-room correlation search found no credible signal either way — see `NEXT.md` and
  `data/ram_registry.json`'s `wram_unmapped.room_object_grid`. D4 stays deferred past Session 3
  until a second room is reachable and the two-room test actually runs. Deferring still has no
  identified cost: no session in the initial plan depends on D4 before Session 3, and Session 3
  itself can only reiterate this recommendation rather than close D4 until then.
- **Context**: `ScreenMap.build` probes every cell of a screen, 1.5 to 5h per screen, with a floor
  of one live probe per cell. The concept calls for scripted exploration, not exhaustive.
- **Options**: map what the next objective requires, by reading terrain from game state; or map
  everything, with the new snapshot-based tool.
- **Review recommendation**: on demand.
- **Full-coverage measurement, September 8, 2026**: `lib/validation/oracle_grid_check.rb` walked
  every reachable cell of both known rooms' oracle grids (not a short chain) against
  `Navigator.probe_all`: 145/173 (83.8%) agreement, 55/62 oracle cells covered. Still not a clean
  D4 basis on its own -- see `NEXT.md`'s session report for the full breakdown and two validator
  bugs found along the way.
- **Owner redirect, same day**: live-probing (however hardened) doesn't scale -- ~32 minutes of
  real taps for 2 small rooms -- and doesn't resemble how a human or the game engine itself
  determines walkability. D1 answered "where is position," never "where is terrain." Next question
  pivots to reading a per-tile background collision source directly from WRAM/VRAM (Session 1's
  original two-room diff, now finally possible with both rooms reachable) instead of extending
  `Navigator`'s live probing further -- see `NEXT.md`.
- **Measured, September 8, 2026 (isolated Explorer subagent, overnight)**: this is the clean
  outcome this entry's own context anticipated. The BG tilemap (VRAM, not the WRAM buffer Session 1
  originally searched) predicts oracle walkability via a per-room categorical tile-ID partition,
  confirmed independently in both `starting_house` and `front_yard` -- see
  `data/ram_registry.json`'s `terrain_collision.background_tilemap_predicts_walkability` for the
  full method, finding, and caveats (a granularity edge case at 8px tile boundaries, and one
  confirmed one-way-ledge directional asymmetry). **Not ratified here** -- the observation layer is
  the owner's decision to make (per `AGENTS.md`'s "fundamental decisions belong to the owner"), and
  this was produced during an unattended overnight session per that same document's autonomy rule
  ("executes decisions already made... does not choose an architecture"). If ratified: D4 would
  resolve close to automatically, since reading terrain on demand and mapping a whole screen upfront
  become the same cost once collision no longer requires live movement to determine.

## D5 — `legacy/` gets replaced, not extended

- **Status**: ratified (September 7, 2026).
- **Choice**: the code imported from the spike is used to regenerate `Zelda::Scenarios`
  checkpoints and to run the report, until `lib/` covers both uses. No component or fix is added
  to it beyond what a regeneration requires. Its JSON grids serve as an oracle once, to validate
  the new navigation tool, then get deleted.
- **Invalidated if**: "regenerate every checkpoint" parity is not reached by the 2nd cold review
  following the start of `lib/`'s construction — in the initial plan (`PLAN.md`), Session 6. Past
  that point without parity, back to the owner rather than silent extension. Delay proposed by the
  planner, adjustable by the owner.

## D6 — Headless session API on gemboy's side, pinned-gem dependency

- **Status**: ratified September 7, 2026; fulfilled September 9, 2026 — a cold review found the
  choice below had never actually landed (koholint was instantiating `Motherboard` directly and
  had reimplemented cycle-accurate frame advancing itself, exactly the workaround this decision's
  own invalidation clause anticipated). Built as `Driver` on gemboy's side
  (`gemboy/lib/driver.rb`: `press`/`release`/`tap`, `advance_cycles`/`advance_frames`,
  `read`/`debug_read`, `framebuffer_png`, `snapshot`/`.restore`, `Motherboard` exposed via
  `#motherboard`, never hidden) — gemboy PR #13, merged to gemboy's `main` September 9, 2026.
- **Choice**: gemboy exposes a session object (advance N frames, keys, memory reads, in-memory
  snapshot/restore, `Motherboard` underneath). Save state becomes a feature of the emulator. This
  repo depends on it like a pinned-version gem; a change in the emulator's timing explicitly
  invalidates checkpoints instead of doing so silently.
- **Authorship**: written by an agent on gemboy's side, outside the scope of koholint sessions.
  It's an external blocker for any koholint session that depends on it (Session 2 of the initial
  plan): flagged to the owner as soon as such a session is ready to start but can't, rather than
  worked around by reimplementing a piece of session-object here.
- **Invalidated if**: gemboy refuses this API within its scope; then it lives here instead, relying
  on `Motherboard` only.
- **Not yet done**: koholint's own `lib/` (`Navigator`, the Session 4 checkpoint scripts) still
  drives `Motherboard` directly and hasn't migrated to `Driver` — built in parallel with Session 4
  on purpose, to keep the two efforts decoupled. gemboy PR #13 is merged now, so this is unblocked;
  still optional cleanup, not required.

## D7 — Snapshot-based collision probing, not walk-and-return

- **Status**: ratified (September 7, 2026).
- **Choice**: every measurement on a cell starts from an in-memory snapshot of the state at that
  cell; each direction is tested from that same state, then restored. No more walking back, no
  recovery budget, no direction ordering.
- **Invalidated if**: the memory cost of a snapshot makes it impractical to keep one per screen
  cell; measure before concluding.
- **Empirically validated, September 8, 2026**: `lib/navigator.rb` implements this and used it to
  reach a real NPC conversation and exit `starting_house` for the first time in this repo's
  history -- see `NEXT.md`.
- **Measured, September 8, 2026 (Session 3 review)**: ~20s wall-clock per `Navigator.tap`,
  steady-state, in this session's sandboxed environment -- not the memory cost this clause
  anticipated, but a real practicality cost nonetheless. Root cause found same day: the sandbox's
  Ruby 3.3.6 was built without YJIT support at all (`ruby --yjit` warns "Ruby was built without
  YJIT support"), so every `RubyVM::YJIT.enable` call already in gemboy (`emugb.rb`,
  `headless_emulator.rb`, etc.) silently no-ops here. Not a `lib/navigator.rb` or D7 design flaw --
  an environment gap.
- **Re-measured after the fix, same day**: built a YJIT-enabled Ruby from source (see `NEXT.md`
  for the recipe and why). ~20s -> ~9-11s per tap -- the ~2x `gemboy/ARCHITECTURE.md` documents
  for YJIT, delivered, not more. `Motherboard#dump`/`.load` overhead separately measured and
  negligible (~0.05-0.08s for a ~2.7MB state) -- confirms the cost this clause worried about
  (snapshot memory/time) was never the real bottleneck; raw CPU emulation speed in this sandbox
  is. Still no practicality problem with D7's design itself -- the snapshot mechanism is cheap,
  the environment's raw emulation speed is what's slow.
- **Second fix, same day**: the remaining ~9-11s/tap wasn't sandbox weakness either -- `tap` was
  calling gemboy's `run_steps(cpu, ppu, apu, count)` (an *instruction* count) with a T-cycle target
  as `count`, oversimulating ~5.7x every tap (171 emulated frames instead of the intended 30).
  Fixed by adding `Navigator.run_cycles` (small-chunk accumulation until the T-cycle target is
  reached, same technique `legacy/`'s own `run_cycles` already used, reimplemented locally per D5)
  and switching `tap` to call it. No recalibration of `TRIGGER_FRAMES`/`SETTLE_FRAMES` needed --
  they were always correct as T-cycle targets, only the primitive consuming them was wrong.
  Result: ~9-11s -> ~1.12-1.20s/tap. Combined with YJIT: ~20s -> ~1.15s, ~17x total. Oracle
  validation re-run after the fix gave an identical result to before it -- speed changed, not
  behavior. See `NEXT.md` for the measurement detail and the sweep confirming no other call site
  shares this bug.

## D8 — Terrain source of truth: VRAM tilemap reads, live-probing kept as fallback

- **Status**: ratified (September 8, 2026).
- **Context**: D4 flagged that exhaustive live-probing doesn't scale and doesn't resemble how a
  human or the game engine itself determines walkability -- ~32 minutes of real taps to cover 2
  small rooms (`NEXT.md`). An isolated Explorer subagent (overnight, September 8) confirmed a
  per-tile background collision signal in the BG tilemap (VRAM `0x9800`/`0x9C00`), independently
  cross-checked in `starting_house` and `front_yard` with zero walkable/blocked signature overlap
  in either room -- see `data/ram_registry.json`'s
  `terrain_collision.background_tilemap_predicts_walkability`. Known caveats: an 8px
  tile-granularity edge case at doorway/wall-base boundaries, and one confirmed one-way-ledge
  directional asymmetry (`front_yard` (5,3)<->(6,3)) a pure tile lookup can't capture alone.
- **Choice**: VRAM tilemap reads become the initial/primary terrain source of truth.
  `Navigator`'s live-probing (D7) is kept, not deleted -- it's the fallback and cross-check for
  cases the tile read doesn't resolve cleanly (ledges, an unclassified tile signature, a room
  where the categorical partition doesn't separate as cleanly as the first two).
  Owner's framing: "utiliser la lecture VRAM comme source de vérité initiale, mais pas hésiter à
  repartir sur l'exploration alternative live probing si jamais ça ne marche pas."
- **Invalidated if**: the tile-ID partition fails to separate cleanly in a third room, or the
  fraction of cells needing live-probe fallback grows large enough that VRAM reads stop being the
  practical primary path.
- **Implemented and validated, same day**: `lib/terrain.rb` (`Terrain.signature_at`,
  `Terrain::RoomClassifier` -- caches a walkable/blocked verdict per tile-ID signature, live-probes
  only the first cell seen with a new signature) and
  `lib/validation/terrain_predictor_check.rb`. Result: 161/173 (93.1%) combined agreement on the
  same oracle sweep `oracle_grid_check.rb` used, up from the pure-live-probe result (145/173,
  83.8%), using 22 total live probes instead of up to 8 taps x 173 edges -- `front_yard` reached
  100% (60/60, 9 probes). The remaining 12 disagreements (all `starting_house`) triangulate as
  oracle staleness, not a method flaw -- see `NEXT.md` and `data/ram_registry.json`'s
  `terrain_collision` entry (now `verified`).

## D9 — Cross-room visual/gameplay catalog: mobility diffing + CHR-pattern matching, piloted first

- **Status**: pilot approved (September 9, 2026), not yet ratified as a standing convention.
- **Context**: D8 covers terrain/walkability, not the rest of what's on screen. The owner asked
  for a systematic way to build gameplay understanding from what's visible per room -- not just
  narrative color, but which visual elements might be interactable -- while explicitly rejecting
  an unbounded "look at the screen and understand it" mandate (`AGENTS.md`'s own invalid-mandate
  example). Owner's refinements on the raw idea: rooms aren't guaranteed static over time (rare
  but real changes possible, so a survey needs a timestamp/checkpoint reference, not a one-time
  truth); a room's screenshot should be compared against itself over a few frames to separate
  static decor from moving elements; and matching should let one room's confirmed-interactable
  element inform priors about the same-looking element elsewhere.
- **Choice (pilot method)**: per room, take 2-3 OAM/framebuffer samples spaced in time from the
  same checkpoint and diff sprite x/y positions to separate static (terrain/decor) from mobile
  (creatures, animated objects) elements -- reuses the OAM-reading approach already proven for
  crate_room's object survey, not new pixel-diffing infrastructure. Cross-room matching compares
  actual CHR pattern bytes (`0x8000 + tile_id*16`), the same technique that decoded the SELECT
  map's icon -- not raw tile IDs, which D8's own caveats already showed are unreliable across
  tilesets. New artifacts: a `visual_catalog` section in `data/ram_registry.json` (one entry per
  distinct visual pattern: which rooms it's been seen in, static/mobile, interaction-tested
  y/n/pending, first-seen date) and a `visual_survey` sub-object per `room_labels` entry (which
  catalog entries were seen in that room, an `as_of` checkpoint/date). No fixed re-survey
  schedule -- a room's `as_of` just makes staleness visible; re-survey opportunistically when a
  session revisits a room for another reason and notices a mismatch, same pattern as an
  invalidated decision elsewhere in this file.
- **Scope**: pilot on 2 already-charted rooms (`villager_screen`, `front_yard` -- both have
  existing checkpoints, `villager_screen` has two known NPCs as a mobility/interaction test case)
  before deciding whether to fold this into the "Room labeling" standing convention in `AGENTS.md`
  and apply it to all charted rooms.
- **Invalidated if**: OAM/CHR-pattern diffing turns out too noisy (pattern-byte collisions between
  genuinely different sprites) or too expensive per room relative to the signal it yields, in
  which case the method -- not necessarily the goal -- needs reconsidering.
- **Pilot result, same day**: confirmed on both rooms. Mobility diffing reproduced
  `villager_screen`'s already-known static/wandering NPC split exactly (4 OAM samples, ~2s apart,
  no checkpoint reload between them). CHR-pattern matching found a real cross-room hit on the
  first pair: `front_yard`'s previously-unsurveyed wandering creature has byte-identical pattern
  data to `villager_screen`'s confirmed-interactive wandering NPC -- a concrete, evidence-backed
  interaction candidate, not a guess. Cost: ~15-20 minutes, 2 emulator boots, 8 OAM samples, 16
  CHR reads -- well under budget. Data in `data/ram_registry.json`'s new `visual_catalog` section
  (`hypothesis`/`verified_count: 1`, not yet independently re-checked) and `room_labels`'
  `visual_survey` sub-objects, commit `2599a61`.
- **One adjustment before wider rollout**: OAM-entry matching across samples was done by
  eyeballing per-slot position continuity, which only holds up in sparsely-populated rooms (6-7
  entries here). A denser room (`crate_room`'s 9-object grid) needs a nearest-neighbor matching
  helper instead of slot-stability assumptions before this scales past a couple more rooms.
- **Rollout, September 9, 2026 (autonomous overnight Explorer session)**: the flagged helper is
  built (`scratchpad/walkability/oam_match.rb`, `OamMatch.greedy_match`/`.track` -- greedy nearest-
  neighbor across samples, not an optimal assignment, per this project's "throwaway spike" scope)
  and applied to `crate_room` and `screen3_north`. `crate_room`: no new mobile elements, all 9
  tile=0x58 objects independently reconfirmed static via this genuinely different method --
  satisfies `AGENTS.md`'s `verified_count >= 2` bar for that specific mobility claim (not the
  whole `world_topology.crate_room_and_riverside_content` entry). `screen3_north`: up to 6 distinct
  moving OAM tile-patterns found, more granular than the room's pre-existing 3-creature narrative
  count -- which tile group corresponds to which previously-tested creature is NOT established,
  left as an open question rather than forced into the old count. 2 more confirmed cross-room CHR
  matches, both extending patterns from the pilot rather than finding new ones: `front_yard`'s
  wandering-creature shadow tile is byte-identical to one of `screen3_north`'s creature shadows,
  and `villager_screen`'s previously-undetermined single-tile "companion sprite" is byte-identical
  to (and confirmed mobile via) 2 concurrent instances in `screen3_north`. Neither match links to
  an already-confirmed-interactive element, so no bonus interaction test was run for either (see
  `data/ram_registry.json`'s `visual_catalog` for the full per-entry detail). Separately, this
  session's `front_yard` creature interaction follow-up (flagged pending by the pilot) came back
  INCONCLUSIVE, not negative -- 3 navigation attempts (blind chase, door-avoiding chase, D8-grid-
  routed chase) all failed to reach adjacency at all, stopped per the anti-patch rule rather than
  tried a 4th way; see `visual_catalog.villager_wandering_creature`'s `interaction_tested['162/0']`
  for the full detail. Still not ratified as a standing convention -- now piloted-plus-rolled-out on
  4 rooms total (2 pilot + 2 rollout), the owner's call on whether to fold it into `AGENTS.md`'s
  "Room labeling" convention for all charted rooms.
- **Methodological correction, September 10, 2026**: re-verification (owner-prompted) found the
  pilot and rollout's CHR comparisons only ever read the OAM-listed tile ID alone -- but LCDC
  confirmed 8x16 sprite mode was active in every checkpoint used, meaning each on-screen sprite is
  actually a top tile + an auto-paired bottom tile (and often two such columns side by side for a
  16x16 composite). The matches themselves held up when re-checked in full (all 4 tiles of the
  villager_screen/front_yard creature match byte-for-byte, not just the 2 originally compared), but
  the method itself was incomplete and got lucky, not verified as thoroughly as the confidence
  level implied. Also checked and ruled out a real confound: whether the "cross-room match" was
  trivially Link's own sprite matching itself (Link consistently reads as tile 0/2 in every room
  checked, structurally distinct from the matched creature's tile 80-83). Fixed going forward:
  `scratchpad/sprite_render.py`, a reusable 2bpp-tile-to-image decoder (handles 8x16 pairing and
  16x16 two-column composites, with or without an X-flip), promoted from one-off scratch scripts to
  a standard tool -- rendering an actual image is now part of investigating any sprite, not an
  optional extra. It already caught one real mislabel this way: `front_yard_creature_shadow`
  (named from lockstep position tracking alone) turned out, once rendered, to look like spiky
  grass/reed tufts, not a flat ground shadow -- renamed pending a clearer read.

## D10 — Walkability grids combine D8 (BG tilemap) with D9 (static OAM sprites)

- **Status**: ratified (September 10, 2026).
- **Context**: the owner spotted, by inspecting the Atlas after the HUD-row fix, that
  `crate_room`'s walkability overlay shows all 9 of its confirmed-physical crate/book-stand
  objects as uniformly walkable. Root cause: `Terrain::RoomClassifier` (D8) only ever reads the BG
  tilemap; these objects are OAM sprites sitting on top of ordinary walkable grass tiles, so
  nothing in the model sees them as obstacles at all. Not a crate_room-only issue -- any room with
  a static sprite-based obstacle has the same blind spot. See
  `data/ram_registry.json`'s `terrain_collision.background_tilemap_predicts_walkability.caveats`
  (the newest, "CONFIRMED, September 10 2026" entry) for the full evidence.
- **Choice**: combine the two systems already built rather than inventing a third. For any room
  D9 has surveyed (`data/ram_registry.json`'s `visual_catalog`), a cell containing a *static*
  tracked sprite (mobility == static, per D9's OAM multi-sample diffing) is marked blocked in the
  walkability grid regardless of what its BG signature says. Mobile sprites are NOT folded in this
  way -- a wandering creature isn't a fixed obstacle, and D9 already tracks those separately by
  position, not by walkability. This only fixes the gap where D9 coverage already exists (4/14
  rooms as of this decision); rooms D9 hasn't surveyed keep the blind spot until they are.
- **Invalidated if**: a static sprite turns out to be walkable-under (e.g. a sprite drawn for
  visual layering but with no real collision, like a floor decal) -- in that case marking its cell
  blocked would be a false negative, and the model needs a third state (sprite present, but not
  necessarily an obstacle) rather than the binary treatment assumed here.

## D11 — Mobile sprites get a friendly/hostile classification, tested before chased

- **Status**: ratified (September 10, 2026).
- **Context**: an Explorer session's adaptive live-tracking experiment (the anti-patch
  "middle ground" the owner authorized) reached genuine adjacency with `riverside_south_room`'s
  tan creature for the first time across 5 total attempts, and still got no dialogue. A follow-up
  investigation (reproducing a plain tap sequence with before/after screenshots + OAM reads) found
  why: Link's own position was jumping in a direction opposite the input, and in both captured
  instances the wandering creature was adjacent right before the jump -- a contact/collision
  knockback, not a navigation-access problem or an input glitch. This reframes the open
  mobile-sprite-interaction question: some of these sprites aren't NPCs at all, they're enemies,
  and no amount of chase-tooling precision would ever produce dialogue from one. Not all mobile
  sprites are the same kind of object -- D9 already has one CHR-confirmed counterexample
  (`front_yard`'s creature matches `villager_screen`'s confirmed-friendly, dialogue-bearing NPC
  byte-for-byte).
- **Choice**: before attempting a dialogue chase on any not-yet-classified mobile sprite, run a
  cheap contact/proximity test first (approach to near-adjacency, watch HUD hearts and Link's own
  position for an unexplained jump) -- this is now a known, reproducible signature, cheaper than a
  full adaptive chase-for-dialogue attempt, and tells you whether that effort is worth spending at
  all. `visual_catalog` entries gain a status field for this (`friendly` / `hostile` / `unknown`),
  populated as sprites get tested, alongside the existing static/mobile classification. Don't build
  a general `lib/navigator.rb` intercept primitive yet -- the one working instance tonight was a
  throwaway adaptive-tracking script, and that pattern is reusable as-is for confirmed-`friendly`
  targets without committing new Navigator code on the strength of a single success.
- **Invalidated if**: the contact-test signature (position jump + no damage, or a heart drop)
  turns out to have a different cause in some other room (e.g. a real environmental hazard
  unrelated to any sprite) -- then the test needs a second confirming signal (e.g. explicit
  distance-to-nearest-OAM-sprite at the moment of the jump) before being trusted as a friendly/
  hostile classifier on its own.

## D12 — RAM writes to gameplay state (HP, and by extension any writable mechanic) are case-by-case, owner-validated each time

- **Status**: ratified (September 10, 2026).
- **Context**: a bed-healing test needed a genuine below-max HP state to be meaningful, and no
  safe in-game way to reach one existed near `house2_interior` without retracing into a hostile
  area already flagged as risky -- the test session used a direct `mmu.write(0xDB5A, 8)` on a
  fresh scratch checkpoint to manufacture the condition, which incidentally confirmed and promoted
  `wram_unmapped.link_health` (0xDB5A current HP / 0xDB5B heart containers) to `verified`. This
  surfaced a real question: now that HP is a known, writable byte, a future session could top HP
  back up with a direct write before pushing further into `riverside_ne_cove`/`riverside_south_river_room`
  ("Plage Coco"), which are otherwise blocked by real, unavoidable contact damage with no
  confirmed healing mechanism. Whether that's in scope was not this project's call to make
  unilaterally -- it changes what "exploring" means (reading/navigating vs. also writing state),
  even though it would never touch `main.dump`.
- **Choice**: RAM writes to gameplay state (HP today; any other writable mechanic found later)
  are permitted ONLY for isolated, narrowly-scoped tests where the write itself is the method
  being tested or is needed to set up a clean test condition (e.g. the bed-healing test itself --
  writing HP down to test whether something restores it). They are NOT permitted to advance
  exploration past a real in-game obstacle (e.g. topping HP back up to push deeper into a
  hostile-creature area) without asking the owner first, every time -- this is not a one-time
  blanket approval, each specific use needs its own go-ahead. Never on `main.dump` either way.
- **Invalidated if**: the owner later grants a standing blanket approval for a specific mechanic
  (e.g. "always top up HP before an Explorer session, no need to ask") -- until then, default to
  asking.
- **Amendment (September 10, 2026, same day)**: the owner granted a SCOPED standing approval,
  narrower than a full blanket ("Oui pour toute poussée nécessaire à la découverte de l'épée, sur
  la plage coco") -- HP writes via `0xDB5A` on scratch checkpoints (never `main.dump`) no longer
  need a fresh ask for each individual push into the "Plage Coco" cluster (`riverside_ne_cove`
  226/0, `riverside_south_river_room` 224/0, `riverside_flower_clearing` 225/0) specifically in
  service of the sword-hypothesis search there. This does NOT extend to any other room, mechanic,
  or goal -- a write to unblock a different room, or for a purpose unrelated to finding the sword
  lead, still needs its own ask under the base rule above.

## D13 — Build a real hostile-avoidance primitive in lib/navigator.rb

- **Status**: ratified (September 11, 2026).
- **Context**: D11 deliberately deferred building a general `lib/navigator.rb` intercept/avoidance
  primitive, on the grounds that one adaptive-tracking success was not enough evidence to justify
  the investment -- explicitly conditioned on the pattern recurring "a few times" first. Since
  then, the same hostile-creature-avoidance problem (hold the shield, tap-push toward a target,
  watch HP, manually top it up via D12's scoped write permission when low) has been independently
  re-derived from scratch by at least 4 separate Explorer sessions across 4 rooms in the
  "Plage Coco" cluster (`riverside_south_river_room` 224/0, `riverside_flower_clearing` 225/0,
  `riverside_ne_cove` 226/0, `riverside_east_room` 209/0), each spending real session budget
  reimplementing the same tactic rather than reusing a shared tool. D11's own invalidation
  condition ("this pattern recurring a few times") is now met -- owner-confirmed, September 11.
- **Choice**: a Builder task (implements a decision already made, no new paradigm invention) to
  formalize this into a real, reusable `lib/navigator.rb` primitive. Reference implementation to
  build from: `world_topology.riverside_south_room_adaptive_chase_experiment`'s throwaway script
  (the one D11 itself is built on) plus every Plage Coco session's own ad-hoc scripts referenced in
  `room_labels["224/0"]`/`["225/0"]`/`["226/0"]`/`["209/0"]`. Scope: read nearby OAM sprites
  already classified `hazard_status: hostile` (D11) or `unknown`, hold B automatically if a shield
  is confirmed equipped (B-slot check), and bias movement to increase distance from the nearest
  hostile sprite while still making net progress toward a target direction/position -- the exact
  method name/API shape is the Builder's call within this scope, not dictated here. Validate by a
  live re-test against one of the two still-unswept Plage Coco pockets (`226/0`'s east/south past
  x=46,y=26, or `209/0`'s east half past its creature bottleneck) and report whether it measurably
  reduces damage/session time versus the ad-hoc scripts' own logged figures.
- **Not in scope**: full pathfinding/AI; non-hostile obstacle handling (D8/D10's job already);
  changing hostile/friendly classification itself (D11 owns that).
- **Invalidated if**: a live retest with the new primitive doesn't measurably reduce damage or
  session time versus the ad-hoc scripts it replaces -- then the investment didn't pay off and
  should be reconsidered openly, not kept silently on the strength of intent alone.
- **Built, September 11 2026 (Builder task)**: `lib/navigator.rb`'s `Navigator.avoid_hostiles_and_move!(motherboard, target_direction, radius:)`
  is the primitive -- one avoidance-biased step, holding B automatically via a new
  `Navigator.shielded_move!`/`Navigator.move_holding!` pair (holds the button across every
  internal tap, unlike `#tap_button`'s per-tap clear, matching every ad-hoc script's own
  workaround) whenever `Navigator.shield_equipped?` reads true. `Navigator.nearby_hazards` reads
  OAM directly (`mmu.debug_read`, the PPU-bus-gate workaround already established) and filters by
  a hardcoded `HAZARD_TILE_IDS` constant (0x60/0x62/0x64/0x66/0x68/0x6a confirmed hostile per D11
  + 0x6c, the pale creature's "unknown, suggestive of hostile" entry) rather than parsing
  `visual_catalog`'s free-text `hazard_status` field at runtime -- that field isn't reliably
  machine-parseable (see the entries themselves), so the correlation is done once, in a comment
  citing the exact catalog entries it's sourced from, not re-derived live every call. Deliberately
  excludes every other visual_catalog entry marked "unknown" (e.g.
  `building_screen_flutter_object`) as outside this decision's Plage Coco motivating scope.
  `Navigator.biased_direction` is a pure 4-way dot-product choice (target-direction unit vector
  plus a weighted push away from the nearest in-radius hazard), not a path search. A thin
  `Navigator.avoid_hostiles_and_push!(motherboard, target_direction, max_steps:, min_hp:)` repeats
  it with an HP safety floor, mirroring every ad-hoc script's own stop-before-KO behavior; it does
  NOT itself perform any D12 HP-write top-up -- that stays the caller's explicit, logged decision.
  Side finding, flagged per this project's provenance rule rather than assumed: the B-slot
  equipped-item byte was not in `data/ram_registry.json` before this session (confirmed absent --
  `lib/validation/checkpoint_after_shield_interior.rb`'s own comment already said so). Found by
  diffing WRAM between a fresh pre-shield boot and 8 independently-created post-shield checkpoints
  spanning 6+ rooms/several past sessions: `0xDB00` reads 0 pre-shield and 4 on every post-shield
  checkpoint checked, stable regardless of room/HP/position; `0xDB01` read 0 throughout (consistent
  with, not proof of, being the empty A-slot's counterpart address). Recorded in
  `data/ram_registry.json`'s `wram_unmapped.equipped_b_item` as `hypothesis`/`verified_count: 1` --
  this session's own correlation method only, not independently re-run by a second session; the
  item-ID-to-"shield" mapping is inferred from being the only inventory change this project has
  ever observed (Tarin's gift), not cross-checked against any external item-ID table.
  **Validation retest result**: see the same entry's next addendum below.
- **Validation retest, September 11 2026 (same Builder session), 209/0's east bottleneck**: per
  D13's own invalidation clause, retested against `riverside_east_room`'s creature-pocket
  bottleneck (room_labels['209/0']) from `lib_e209_final_state.dump` (x=60,y=74, the exact point
  the ad-hoc baseline session stopped at, CLOSED under the anti-patch rule after "6+ distinct
  tries... oscillated between x~52-70 without reaching the room's east half", HP dropping "as low
  as 8/24 twice", east area x>95 explicitly logged UNREACHED). FIRST FINDING (a real regression,
  not hidden): the initially-shipped default (`HAZARD_PROXIMITY_PX = 40`, ~2.5 tiles) did WORSE
  than the ad-hoc tactic in this exact spot -- 2 calls, 12 damage, and the avoidance bias walked
  Link backward into the room's already-fully-explored west dead-end pocket (x=52 -> x=4) chasing
  the locally-optimal-but-wrong "up" direction against a hazard sitting south, then took another
  16 damage over 2 more calls making zero position progress once there (a real wall, not a
  transient block). A 0px-radius control (avoidance disabled, shield-hold only, i.e. exactly the
  ad-hoc tactic minus manual scripting) fared much better in the same spot: 8 calls, only 4 total
  damage, though net ZERO position progress (matches the baseline's own "oscillated... without
  reaching" outcome closely, just cheaper). A 16px-radius variant (~1 tile, closer to contact
  range than anticipation range) beat both: 22 total calls across 4 healed batches, 56 total
  damage, and -- unlike either the 40px or 0px runs, and unlike the entire ad-hoc baseline session
  -- reached genuinely new ground: x=60 -> x=140 (past the x>95 boundary the baseline never
  crossed), y drifting from 74 down to 46, before hitting the room's real east wall (x=140,
  reproduced blocked across a full batch) and a real north wall further up. No `bidule`/item/
  chest/signpost found anywhere in the newly-reached area (screenshots checked at every stop) --
  see room_labels['209/0']'s own addendum for the full detail and checkpoint chain. Shipped
  default changed to `HAZARD_PROXIMITY_PX = 16` based on this evidence (see the constant's own
  comment in `lib/navigator.rb`) -- `AVOIDANCE_WEIGHT` was not independently retuned this session,
  flagged as a follow-up knob if a future room shows the same over-eager-bias failure mode at 16px.
  3 D12-scoped HP-writes used, all on scratch checkpoints (`lib_e209_variantC_batch*.dump` chain),
  never `main.dump`, logged transparently at each use.
  **VERDICT**: measurably helped, once retuned -- the untested/first-guess default did not, and
  that gap would have gone unnoticed without this retest. Reaching x=140 (versus the baseline's
  hard stop at ~x=94, closed under the anti-patch rule for a full session) is the clearest signal:
  the primitive finished what the ad-hoc tactic gave up on, in the same room, at a comparable
  damage order of magnitude. D13 stays ratified; its `HAZARD_PROXIMITY_PX` default is now
  evidence-based rather than a first guess, and the 40px failure mode is recorded so it isn't
  silently reintroduced by a future "seems more thorough" tweak.
- **Second validation data point, September 11 2026 (independent Explorer subagent), `226/0`'s
  east/south pocket**: used as the PRIMARY method, `radius: 16` (the already-retuned default) with
  NO further retuning needed. Reached a real, reconfirmed wall (x=124,y=26 -- 10 consecutive
  `:blocked` results with zero position drift across two batches plus a clean full-HP re-probe),
  then real new ground south (x=124,y=26 -> x=119,y=59) and further east to a genuine 3-way
  water-bounded cul-de-sac (x=154,y=58), and correctly showed a third branch (`up` from x=119,y=59)
  loops back to the same already-found wall rather than opening new ground -- i.e. it reliably told
  real walls apart from hazard-blocked pushes across a genuinely different room shape than 209/0's
  bottleneck. One usability gap found and logged (not a defect in the primitive's own job, but worth
  naming for a future caller): it doesn't detect "the last N calls all hit the same wall" and stop
  itself -- re-pushing the same blocked direction a second time still spent a full batch and real HP
  before the caller applied that judgment manually. See `room_labels['226/0']`'s own addendum for
  full route/checkpoint detail. Combined with the 209/0 retest above, D13 now has two independent
  live validations in two differently-shaped rooms, both net positive with the retuned 16px default
  -- strengthens confidence in the primitive as shipped, no further tuning indicated by either.

## D14 — The official game manual is a legitimate mechanic reference, not forbidden knowledge

- **Status**: ratified (September 11, 2026).
- **Context**: `AGENTS.md`'s "Pre-trained knowledge" rule forbids assuming game-specific facts
  (where an item is, who an NPC "really" is) -- everything must be observed, never assumed from
  the model's own training. This was written to stop the project from short-circuiting genuine
  discovery. The owner directly provided the official Link's Awakening DX instruction booklet
  (PDF) and asked that it be read and kept, after separately pointing out (in conversation) that
  the project was missing an understanding of the game's own genre/gameplay-loop conventions
  (explore + solve environmental puzzles; NPC dialogue and signs are the game's built-in hint
  delivery system) needed to reason about "what's the right next step," not just spatial mapping.
- **Choice**: the manual is now a legitimate source for GENERIC MECHANIC knowledge -- how systems
  work (the SELECT map's `!?`/message markers, pushing vs. pulling, diving, shield timing, the
  8-dungeon/heart-piece/named-shop structure) -- read once, distilled into original paraphrased
  notes at `docs/GAME_MANUAL_NOTES.md` (not verbatim booklet text, and the booklet's own PDF/scans
  are NOT committed to this repo -- copyrighted Nintendo material, same reasoning as `roms/` being
  gitignored). This does NOT become a walkthrough or a license to assume specific facts about
  koholint's current state (where an item actually is, whether a specific NPC has already given a
  specific hint) -- those stay observed-only, exactly as before. The manual explains SYSTEMS; this
  project still discovers STATE.
- **Not in scope**: fan wikis, walkthroughs, or any other external spoiler source -- this decision
  covers the one official manual the owner provided, not license to use pre-trained knowledge more
  broadly.
- **Invalidated if**: the distinction between "mechanic knowledge" and "assumed game state" proves
  hard to hold in practice (e.g. a future session starts asserting specific unverified facts and
  attributing them to "the manual") -- if that happens, tighten `docs/GAME_MANUAL_NOTES.md`'s own
  scope or revisit this decision with the owner rather than let the boundary erode silently.
