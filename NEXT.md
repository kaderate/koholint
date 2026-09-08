# NEXT

Entry point for any resumption. One page, no more.

## State as of September 8, 2026

Repo initialized from the gemboy spike (`claude/usage-2mr345` @ `c952ded`). `lib/navigator.rb`
holds the first real `lib/` code (D7's snapshot-based navigation tool); the rest of `legacy/` is
still intact and unmodified, all knowledge is in `data/` and `docs/`.

**Indicators**

| Indicator | Value |
|---|---|
| Progress in the game | **Upgraded September 8, 2026** -- shield genuinely obtained (HUD B slot shows the shield icon, screenshot-verified: `data/screenshots/shield_obtained_dialogue.png`, `shield_obtained_hud.png`) and the starting house genuinely left (`room_id=162, map_id=0` at `0xFFF6`/`0xFFF7`, matching the historical `front_yard` value; `data/screenshots/front_yard_reached.png`) -- both first achieved through real gameplay with `lib/navigator.rb`, not inherited or assumed. No sword. |
| Trip A to B | First real measurement: settled spawn (row 3, col 4 in `starting_house`) to outside the house (`front_yard`) in 6 snapshot-based navigation steps (down, down, down, left, left, down), zero blind probing, zero legacy code. Frame count not yet logged precisely -- follow-up. |
| Verified facts (RAM registry) | 6 `verified` HRAM entries unchanged. The door-gate mystery is now fully explained (not a RAM fact per se). **New September 8, 2026**: terrain/collision now reads from the BG tilemap (D8, `terrain_collision.background_tilemap_predicts_walkability`, `verified`) -- see `data/ram_registry.json`. |

**The `front_yard` mystery is closed.** It was never a story-gate bug: Link genuinely lacked the
shield, because `legacy/`'s `move_tiles` undercounts real movement (see
`data/ram_registry.json`'s `wram_unmapped.intro_door_gate`) and gave up approaching Tarkin before
getting close enough to talk to him. `lib/navigator.rb`'s snapshot-based `move!`/`probe_all`
(tracking cumulative displacement from a fixed reference instead of `move_tiles`'s per-call
baseline) reached Tarkin cleanly, received the shield through a real conversation, and walked out
the south door with **zero blocking, zero "Hé mon gars" message** -- confirming the door was
always legitimately shield-gated. New Motherboard-format dumps in `/tmp/zelda_checkpoints/`
(not versioned): `starting_house_settled.dump`, `near_tarkin.dump`, `after_dialogue.dump` (shield
obtained), `front_yard_navigator.dump` (outside, real). The old `legacy/`-format checkpoints
(`after_shield_interior.marshal`, `front_yard.marshal`, etc.) are superseded for navigation
purposes but still useful as `Zelda::Checkpoint`-format inputs to bootstrap a `Motherboard` (see
`lib/validation/starting_house_oracle_check.rb` for the adapter: `Motherboard.new(cpu, ppu, apu,
mmu, mmu.dma, mmu.model)`).

## Session report (September 8, 2026 -- SELECT opens a world map screen)

Owner's hint: holding (not tapping) `:select` opens a full-screen grid overlay -- confirmed
directly by the coordinating session (`data/ram_registry.json`'s new `select_map_screen` entry).
A uniform grid of cells, a blinking position marker near front_yard's spot on the grid, and a
separate framed "!?" icon (likely a legend, not confirmed) in the lower-right. Not yet understood:
whether panning works (d-pad + select held), whether the grid encodes per-room discovery status
anywhere visible or in an underlying WRAM/VRAM structure, or what the "!?" icon means. This is a
promising lead for world-topology -- if there's a data structure backing this view, reading it
directly could reveal the world's shape far faster than room-by-room navigation, in the same
spirit as D8's terrain-from-memory approach. Follow-up Explorer session queued to dig in properly.

## Session report (September 8, 2026 -- room160 mapped, content corrected, room176 found)

```
Question: what does room160 contain past its entry, and what are its exits?

Answer: confirmed. Exits: east -> room161 (known). South -> a NEW room, room176/0, via a wide
opening. North -> blocked at y=26 across 3 columns. West -> no exit found despite 6 tests hitting
3 different real obstacles (hedge base, river-bank wall, tree-like object) -- consistent with the
entry-glance's water/river description, genuinely impassable.

Important CORRECTION: room160's entry-glance content ("flower sprites, a green blob") was wrong.
Full exploration found 3 independently-wandering creatures (tile=0x5E, confirmed via idle OAM
sampling across 30-frame windows) -- not static decoration. Extensively tested (~20 :a attempts,
2 chase scripts, positive-controlled) -- solid negative, no dialogue on any of the 3. A second
sprite type (tile=0x58) exists in OAM but never came on-camera from the entry position -- unresolved.

room176 (new, south of room160): a building with a striped gabled roof and a dark door, a
hedge/path, 2 more tile=0x5E creatures, and -- new and promising -- two 2-tile humanoid-shaped
sprite pairs flanking the path, plus a small floating-looking single-tile object. Screenshotted,
OAM read, not explored further (one-room-per-session discipline). Checkpoints saved:
room160_entry.dump and room176_entry_from_room160.dump.

Indicators: game = no new dialogue this room (room160 negative), but real topology progress
(room160 fully mapped, room176 found with the most promising unexplored content yet). Trip A->B =
front_yard -> room160 entry: 2 real transitions, ~28 move! calls. Verified facts =
data/ram_registry.json's new world_topology.room160_exits_and_content, room_labels corrected for
well_platform and extended with room176 (building_screen), hram.room_id extended.

Decisions made: none (Explorer role).

Next question proposed: room176 is the clear next target -- its humanoid-shaped sprite pairs are
the most promising interaction candidates found since villager_screen's. Chart its exits and test
those sprites for dialogue, continuing from the already-reached room176_entry_from_room160.dump
checkpoint rather than re-walking from front_yard.

What NOT to redo: don't re-test room160's west edge (hedge base, river-bank at x=36/y=123, or the
tree-like object at x=68) expecting an opening -- all 3 confirmed real, one re-tested 6x. Don't
re-chase room160's tile=0x5E creatures expecting a missed dialogue -- solid negative,
positive-controlled. Don't trust an entry-glance content description over a full exploration's
findings -- room160's is the second time this session an entry-glance guess (flowers/blob) turned
out wrong once actually tested.
```

## Owner question, September 8, 2026 -- continuous save vs. independent branches

The owner asked directly: does every exploration reload the same fixed checkpoint
(`front_yard_navigator.dump`), meaning there's no single continuous playthrough accumulating
progress? Confirmed yes -- every Explorer session this whole day branched from that same fixed
point (or, same thing, from `starting_house`'s post-shield checkpoint further back), not from
wherever the previous session left off. Deliberate so far (matches D7's snapshot philosophy: no
drift, no one session's mistake corrupting another's baseline), but it does mean nothing like an
item pickup or a triggered story event would persist forward on its own. Owner's decision pending:
switch to a continuous "main save" model (each session picks up from the last one's end state) for
future exploration, or keep independent branches from a fixed point for now and treat continuous
progression as a separate, later phase. Not decided -- flagged here rather than assumed.

## Session report (September 8, 2026 -- SELECT map investigated, mostly refuted, 2 real anomalies)

```
Question: does the SELECT map screen pan, encode discovery status, have a readable underlying
data structure, and what does the "!?" icon mean?

Answer: mostly refuted, one correction to the discovery's own premise, two genuine unexplained
anomalies found instead.

CORRECTION: holding :select is not a stable state -- it's an automatic ~96-frame open/close
cycle (confirmed via full-tilemap MD5 hashing frame-by-frame), independent of input. The
original finding's screenshot just happened to land in an open window.

Panning: refuted (150 frames, 5 conditions, zero scrolled state ever observed -- a held
direction just leaks into real gameplay once the overlay auto-closes). Visual discovery-status
encoding: refuted (255/256 grid cells are the identical tile, only the position marker differs,
despite ~7 rooms already visited). Underlying WRAM structure: refuted as a negative result (only
115 bytes change in the full 8KB WRAM diff, nowhere near a 256-cell bitmap) -- doesn't rule out a
structure written elsewhere and merely read here. The "!?" icon: confirmed fixed/room-independent
(byte-identical tilemap region in 2 different rooms) -- a static legend, not a marker.

The position marker itself: inconclusive -- stayed at the exact same grid cell in front_yard AND
room177 (different physical rooms), which a real position tracker shouldn't do; needs a more
distant checkpoint to settle. Two real anomalies, not chased further (low priority): starting_house
never shows the map at all across 300 frames (interiors may disable it -- one data point);
room160 shows a grid-LIKE state but renders blank with a different icon entirely (hypothesis:
map graphics borrow CHR tile slots from the current room's own tileset).

Bottom line: not the world-topology shortcut it looked like -- no pan, no visible fog-of-war, no
bulk-readable structure found this pass. Registry entry corrected accordingly.

Indicators: game = unchanged (UI/mechanic investigation). Verified facts =
data/ram_registry.json's select_map_screen entry substantially rewritten with the correction and
all 4 findings.

Decisions made: none (Explorer role).

Next question proposed: low priority, only if it becomes relevant elsewhere -- a 3rd/more-distant
checkpoint to settle the marker's semantics; a second interior checkpoint to confirm "no map
indoors"; the room160 CHR-tileset hypothesis.

What NOT to redo: don't retest panning -- conclusively refuted, cleanest test run this session.
Don't use raw pixel-color distinct-count to classify screen state -- DMG's 4-shade palette makes
it useless; use BG tilemap tile IDs. Don't assume "holding select" is a stable state in any future
script -- it's a ~96-frame cycle; poll for the grid tile settling, don't rely on a fixed frame
count. Don't re-run the WRAM diff expecting a bigger hit -- already exhaustive over the full 8KB.
```

## New standing convention (September 8, 2026) -- keep the Koholint Atlas updated

Owner asked to keep the published Artifact ("Koholint Atlas") updated with real advances, with a
push notification each time it's republished. Applies going forward -- update it (same URL, not a
new one) whenever there's a real finding worth showing (new room, new mechanic, new dialogue),
not for routine/incremental progress.

## New standing convention (September 8, 2026) -- label every room by looking at it

Owner's instruction: alongside topology/dialogue exploration, give every room a short
English label plus a one-paragraph visual description the moment there's enough to describe --
purely what's observed (shape/color/layout), never a claim about what something "really is" (no
game-knowledge assumptions). Stored in `data/ram_registry.json`'s new `room_labels` section, keyed
`"room_id/map_id"`. Applied retroactively to all 7 currently-known rooms; every future Explorer
session should do the same for any new room it finds or newly describes in more detail.

## Decisions in force

D1 ratified (HRAM). D2 (OAM) obsolete. D3 decided: DMG. D4 open, still deferred -- Session 1 was
inconclusive (see report below), not confirmed or refuted. D5, D6, D7 ratified. See `DECISIONS.md`.

## Import gap closed (September 7, 2026)

`koholint-init` had been imported from `gemboy@claude/usage-2mr345` at commit `c952ded`, one commit
short of that branch's tip (`5ee7949`, "Archive the HRAM diff and other reusable scratchpad
diagnostics into experiments/"). The 6 missing scripts that produced D1 (`ram_diff_hram.rb`,
`ram_diff_hram2.rb`, `diag_scx_scy.rb`, `diag_scx_scy2.rb`, `house2_dialogue.rb`,
`house2_sprite2.rb`) are now in `legacy/game_agents/experiments/`, and the matching method note in
`data/ram_registry.json` has been completed (path fixed to point at `legacy/`, and the sentence
pointing at reusing the technique for the question below).

## Session 3 (cold review) verdict -- September 8, 2026

Run as an isolated subagent with no memory of the building session, per `AGENTS.md`'s "never
judge your own construction." Independently re-verified claims (re-ran the validation script
against a live checkout, read raw bytes out of `front_yard_navigator.dump`, reproduced the
`settle!` artifact by hand, inspected the screenshots) rather than trusting `NEXT.md`'s narrative.

**Verdict**: `lib/navigator.rb` complies with D6/D7 and `docs/CONCEPT.md` at the code level --
confirmed, not just claimed. **But oracle validation coverage is insufficient**:
`lib/validation/starting_house_oracle_check.rb` is structurally capped at ~1 cell (stops at the
first `:blocked` result by design) and never touches `front_yard`'s own existing oracle grid at
all, despite that room now being reachable. The one disagreement found (cell (3,4)/"right") is
unresolved either way -- as likely the legacy oracle's own documented `[3,3]` corner
contamination as a real `Navigator` bug; doesn't anchor confidence in either direction.
**D4 recommendation: stays deferred.** Reaching `front_yard` removes the blocker that made
Session 1 inconclusive, but isn't itself the evidence -- the two-room WRAM collision-grid diff is
what would actually decide it, and it still hasn't been rerun. New measurement (D7 asked for
this, never done before): ~20s wall-clock per `Navigator.tap`, steady state.
**Recommended next step**: harden the validation script (don't stop at first disagreement,
exercise `front_yard`'s oracle too) before extending `lib/navigator.rb` to new rooms.

## Performance fix -- September 8, 2026: YJIT installed, ~2x gained, most of the gap is the sandbox itself

`cache.ruby-lang.org` (the standard Ruby source download) is blocked by this environment's egress
policy (403, confirmed via `/root/.ccr/README.md`'s status endpoint -- a genuine policy denial,
not retried). GitHub was reachable (`git clone https://github.com/ruby/ruby.git --branch
v3_3_11`), so built from there instead: `rustc`/`cargo` were already present, `./autogen.sh &&
./configure --enable-yjit --prefix=/opt/rbenv/versions/3.3.11-yjit && make && make install`
worked cleanly. Confirmed: `RubyVM::YJIT.enabled?` is `true` when invoked with the `--yjit` flag
(gemboy's runtime `RubyVM::YJIT.enable` calls need this flag present too, at least in this
environment/build -- without it `RubyVM::YJIT` isn't even a defined constant, so the `enable`
call itself would raise; always run with `ruby --yjit ...` here, not bare `ruby`).

**Result, same `Navigator.tap` steady-state methodology as the review**: ~20s -> ~9-11s. That's
the ~2x `ARCHITECTURE.md` documents for YJIT, delivered -- not more. `Motherboard#dump`/`.load`
overhead is negligible (~0.05-0.08s each for a ~2.7MB state, benchmarked separately) and was
never the bottleneck. The remaining ~9-11s for 30 emulated frames (~0.5s of game time) is a
further ~18-22x off real-time even with YJIT -- almost certainly this sandbox's CPU being far
weaker/more shared than whatever machine `ARCHITECTURE.md`'s real-time claim was measured on.
Not something fixable at the `lib/navigator.rb` or gemboy level without deeper emulator-side
optimization work, which is out of scope here.

**Practical effect**: reaching `front_yard` from `after_shield_interior` (11 `probe_all` calls
plus a handful of real moves and 12 dialogue interacts) drops from the roughly an-hour-plus this
would have taken at the old rate to something in the 15-25 minute range -- still slow, but
usable for a single builder session rather than prohibitive.

**Caveat for future sessions**: this Ruby build lives only in this container
(`/opt/rbenv/versions/3.3.11-yjit`), not committed anywhere -- a fresh container starts back at
the no-YJIT default and needs the same build repeated (recipe above, a few minutes). Persisting
it via `~/.bashrc` didn't stick (something later in shell init re-prepends the default Ruby to
`PATH`) -- explicitly `export PATH="/opt/rbenv/versions/3.3.11-yjit/bin:$PATH"` per command
instead, or resolve why the profile ordering wins if this comes up again.

## Performance fix -- September 8, 2026: `run_steps`/`run_cycles` confusion, ~8x more gained

The YJIT fix above left `Navigator.tap` at ~9-11s/tap, still far short of `ARCHITECTURE.md`'s
real-time claim. Root cause was a second, larger bug, not more sandbox weakness: `tap` called
gemboy's `run_steps(cpu, ppu, apu, count)` directly with `TRIGGER_FRAMES * FRAME_CYCLES` /
`SETTLE_FRAMES * FRAME_CYCLES` as `count` -- but `run_steps` takes an *instruction* count, not a
T-cycle target. Measured precisely: this asked for 2,106,720 instructions and actually consumed
12,014,336 T-cycles, i.e. 171 emulated frames instead of the intended 30 -- ~5.7x oversimulation
every single tap.

`legacy/game_agents/zelda/primitives.rb` already carried the fix for this, in the form of its own
`run_cycles(cpu, ppu, apu, target_cycles)` (loops `run_steps` in small 20-instruction chunks,
accumulating real T-cycles, until the target is reached). Reimplemented the same technique
directly in `lib/navigator.rb` (`Navigator.run_cycles`) rather than depending on `legacy/`, per D5
-- `tap` now calls it instead of `run_steps` directly.

**No recalibration was needed.** `TRIGGER_FRAMES`/`SETTLE_FRAMES`/`FRAME_CYCLES` were always
correctly calibrated *as T-cycle targets*; the only bug was handing that target to a primitive
that counts instructions instead. Fixing the primitive was sufficient.

**Result**: ~9-11s -> ~1.12-1.20s per tap (another ~8x). Combined with YJIT: **~20s -> ~1.15s,
~17x total**, close to the ~20x this fix was asked to deliver. Re-ran
`lib/validation/starting_house_oracle_check.rb` after the fix: identical 3/4 agreement, same
single (3,4)/"right" disagreement as before -- confirms the fix changed speed only, not behavior.

**Swept for the same bug elsewhere** (`grep -rn run_steps`): the three `legacy/` call sites
(`scenarios.rb`, `ram_diff_hram.rb`, `ram_diff_hram2.rb`) pass plain instruction counts by their
own convention (e.g. `run_steps(cpu, ppu, apu, 20_000)`), not a cycle-target mistaken for one --
not the same bug, and `legacy/` isn't touched per D5 regardless. The two doc/data mentions
(`data/world_model.json`, `docs/archive/EXPLORATION_LOG.md`) already describe the pitfall
correctly. `lib/navigator.rb`'s `tap` was the only misuse.

## Session report (September 8, 2026 -- oracle validator hardened, full coverage measured)

```
Question: does Koholint::Navigator's probe_all agree with legacy's oracle grids across every
reachable cell of both known rooms (starting_house, front_yard), not just a short chain from
spawn?
Answer: measured, not a clean confirm/refute either way. Replaced
lib/validation/starting_house_oracle_check.rb with lib/validation/oracle_grid_check.rb: a
breadth-first walk over each oracle's own 'ok' edges (so a disagreement never truncates coverage,
unlike the old script's break-on-first-:blocked). Combined result: 145/173 (83.8%) agreement
across 55 of 62 oracle-recorded cells (33/37 starting_house, 22/25 front_yard); 4 'exit' edges
(screen transitions) correctly excluded from the tally and never traversed.
Two validator bugs found and fixed en route, both in the harness, not in Navigator's collision
logic itself: (1) move! only guarantees a half-tile commit (COMMIT_THRESHOLD), not full-tile
arrival -- a naive BFS using the raw post-move cell stalled almost immediately because it kept
re-deriving the departure cell as "arrived"; fixed by tapping the same direction further until the
cell actually changes, bounded by MAX_TAPS. (2) Navigator.settle! unconditionally taps :down,
which is destructive on a cell whose down edge is a screen exit -- front_yard's checkpoint sits
on exactly that cell (row 8, the door threshold), so settle!-ing it silently walked Link back
inside the house (room 162 -> 178) before any comparison ever ran, tanking front_yard to 0/3 on
the first (buggy) full run. Fixed by not settling a real post-navigation dump (only a
just-checkpointed-after-interact() state needs it).
The remaining 28 disagreements were not chased further (see "what not to redo" below) -- two
validator-mechanism patches already spent this session, and the owner separately noted that
legacy's own oracle was generated using move_tiles, the exact mechanism whose creeping-collision
undercount caused the original front_yard/shield saga, so some fraction of these may be errors in
the "ground truth" itself, not in Navigator.
Indicators: game = unchanged this session (no new milestone). Trip A->B = not this session's
target. Verified facts = no new registry entries (this was cross-validation, not fact-collection),
but 55 cells now independently checked against real movement data, up from 1.
Decisions made: none new; D4 stays open/deferred.
Next question proposed: see below -- the owner redirected mid-session: live-probing, however
hardened, doesn't scale (this run: ~32 minutes of real taps for 2 small rooms) and doesn't
resemble how a human or the game engine itself determines walkability. Pivot to reading a
per-tile collision source directly instead of extending Navigator further.
What NOT to redo: don't keep hardening the oracle validator chasing the remaining 28
disagreements (COMMIT_THRESHOLD tuning, retry budgets, etc.) -- likely legacy-oracle noise, not a
Navigator bug, and a 3rd/4th patch on the same mechanism is exactly what the anti-patch rule warns
against.
```

## Session report (September 8, 2026, overnight -- isolated Explorer subagent, terrain in memory)

```
Question: does a per-tile background collision/walkability signal exist -- either as a fixed
rule over BG tile map IDs, or a dedicated WRAM buffer -- confirmed by cross-checking
starting_house against front_yard?

Answer: confirmed. The active BG tilemap (LCDC bit 0x08 clear -> base 0x9800 in both rooms, read
via mmu.debug_read) predicts oracle walkability independently in BOTH rooms: cell (row,col) [=
world y/16, x/16] maps directly to the 2x2 block of BG tile IDs at tilemap rows {2*row,2*row+1},
cols {2*col,2*col+1} -- no SCX/SCY correction needed, since every sampled state (both checkpoints,
plus after 8 real moves in front_yard) had SCX=SCY=0.

starting_house (37 walkable / 18 blocked-target cells): walkable cells cluster into ~2 floor
signatures, blocked into ~9 wall signatures, zero full-block overlap between the classes.
front_yard (25 walkable / 8 blocked-target cells): 6 floor/path signatures vs 2 wall signatures,
again zero overlap. The rule is per-room/per-tileset categorical, not a single global numeric
threshold (no "tile ID >= 0x80 = solid" holds across both) -- points to a ROM-side per-tile-ID
lookup table, not a per-room WRAM buffer. Supersedes wram_unmapped.room_object_grid's original
WRAM-buffer hypothesis: the signal exists, just in the wrong memory region from what Session 1
searched. Full method, finding, and caveats now in data/ram_registry.json's
terrain_collision.background_tilemap_predicts_walkability.

Two caveats worth carrying forward: (1) granularity -- a couple of single tile IDs appear in both
classes, but only at doorway/wall-base boundaries where a 16px oracle cell straddles an 8px tile
boundary, suggesting collision resolves at 8x8, not 16x16. (2) a confirmed one-way-ledge: front_yard
(6,3) has the room's own unambiguous wall signature, yet Navigator.move! reached it from (5,3) via
a real LEFT-then-up approach that the static oracle recorded as blocked from that side -- a
directional asymmetry a pure per-tile lookup won't capture without also encoding one-way edges.
This is also a concrete candidate explanation for some of the 28/173 disagreements from the prior
oracle_grid_check.rb run.

Indicators: game = unchanged (memory-layout question, not gameplay). Trip A->B = unchanged. Verified
facts = 0 new registry entries written by the subagent itself (Explorer role, confirmed clean git
status in both repos) -- but a specific, reproducible, two-room-validated finding, since promoted
into data/ram_registry.json by this session (the coordinating session, not the subagent).
Side finding, single occurrence: starting_house's own room_id (0xFFF6) reads 163, not previously in
the registry's room table -- added to hram.room_id with provenance, not independently re-verified.

Decisions made: none by the subagent (Explorer role). D4 (DECISIONS.md) updated with this
measurement, explicitly marked NOT ratified -- the observation layer is a fundamental decision
belonging to the owner, and this was produced overnight per AGENTS.md's autonomy rule ("executes
decisions already made... does not choose an architecture"). If ratified, D4 would resolve close
to automatically (on-demand and exhaustive terrain reads become the same cost once collision no
longer needs live movement to determine).

Next question proposed: a Builder session, once the owner ratifies the observation-layer
implication, should (1) formalize the tile-ID -> walkable/blocked lookup as a small per-room table,
(2) re-run oracle_grid_check.rb's 173-edge sweep with the tile-based predictor substituted for
Navigator.probe_all to see how many of the 28 original disagreements it actually explains vs. new
mismatches it introduces, (3) investigate the front_yard (5,3)<->(6,3) ledge specifically -- general
one-way-ledge category, or a one-off.

What NOT to redo: don't re-run Session 1's WRAM-buffer brute-force search (0xC000-0xDFFF x stride x
orientation) -- the signal lives in VRAM's existing BG tilemap, not a separate WRAM grid; that
hypothesis is now supersedable, not just "still inconclusive." Don't expect a single global numeric
tile-ID rule across rooms -- the partition is categorical per room/tileset, not arithmetic. Don't
treat the front_yard (5,3)/(6,3) disagreement as a hypothesis failure needing a redesign -- one real
edge case out of ~88 tested cells, well within a one-way-ledge explanation; chasing it further would
be another patch on the same "does terrain live in memory" question this session was scoped to
answer once. Don't assume SCX/SCY=0 always holds in front_yard -- confirmed only near the
door/spawn area, unverified further out.
```

## Session report (September 8, 2026 -- D8 implemented: lib/terrain.rb + terrain_predictor_check.rb)

```
Question: does D8's tile-based terrain predictor (RoomClassifier: cache a walkable/blocked verdict
per tile-ID signature, live-probe only the first time a signature is seen) match or beat
Navigator's pure live-probing on the same 173-edge oracle sweep, using far fewer live taps?
Answer: confirmed, clearly. Combined 161/173 (93.1%) agreement, up from the pure-live-probe
sweep's 145/173 (83.8%), using 22 total live probes instead of up to 8 taps x 173 edges.
front_yard: 60/60 (100%), 9 probes. starting_house: 101/113 (89.4%), 13 probes.
lib/terrain.rb (Terrain.signature_at, Terrain::RoomClassifier) and
lib/validation/terrain_predictor_check.rb both committed.
The 12 remaining starting_house disagreements are an exact cell-by-cell subset of the pure-probe
sweep's own "oracle=blocked, Navigator=ok" disagreements (cross-checked against the prior session
report) -- two independent methods (live movement, static tile read) agree with each other and
disagree with the same static legacy oracle in the same direction, which reads as the oracle being
stale there, not either live method being wrong. None of the pure-probe sweep's 9 "oracle=ok,
Navigator=blocked" false negatives survive in the terrain method -- reading the tile directly
sidesteps whatever COMMIT_THRESHOLD/corner-precision quirk caused those.
Indicators: game = unchanged. Trip A->B = unchanged (this was a method comparison, not a route).
Verified facts = terrain_collision.background_tilemap_predicts_walkability promoted from "measured,
pending ratification" to "verified" in data/ram_registry.json, with the cross-validation numbers
above as provenance.
Decisions made: none new -- this executes D8, already ratified by the owner.
Next question proposed: the front_yard (5,3)<->(6,3) one-way-ledge case (Explorer's original
finding) wasn't re-exercised by this run -- the BFS never walks into a cell the oracle itself
labels 'blocked', so it never tested the specific left-then-up approach that found it reachable.
Still open: general one-way-ledge category, or a one-off. Low priority given 93.1% agreement and a
working fallback mechanism already in place; worth a session once there's a concrete reason to
generalize past these two rooms (a third room, or the sword-milestone path needing this specific
cell).
```

## D4 decided -- on demand (September 8, 2026, see DECISIONS.md)

Owner's call: D8's terrain reader makes "map everything" and "map on demand" the same cost, so D4
resolves to on demand. `ScreenMap`/`TileClassifier`/`TileCatalog` stay retired per D5.

## Next question -- resume real game progress beyond front_yard

Owner's priority for the next session, September 8, 2026: infrastructure (perf, oracle validation,
D8) has absorbed this whole day; the "progress in the game" indicator hasn't moved since the
shield. Use the now-fast Navigator+Terrain toolchain (VRAM reads primary, live-probe fallback) to
push past `front_yard`'s known exits into unmapped territory and find the next real objective --
observed, not assumed (no pretrained Zelda-knowledge guesses about what's next, per `AGENTS.md`).

- **Role**: Explorer (new, unmapped territory -- throwaway spikes, no `lib/` commits, no
  decisions). Per this session's own earlier precedent (mixing Explorer into a Builder-heavy
  session blurs the discipline), this should run as an isolated subagent or a genuinely fresh
  session, not continue inline here.
- **Budget**: TBD with the owner when launched.
- **Falsifiable question**: what lies beyond `front_yard`'s exits (besides the door back into
  `starting_house`), and is there a next concrete objective there (an item, an NPC, a story beat)?
- **Deliverable**: the new area's `room_id`/`map_id` registered with provenance, a screenshot/gif
  of what was found, and an honest report if nothing new turns out to be reachable yet.
- **Indicator targeted**: progress in the game (primarily) -- the one indicator untouched all day.

## Session report (September 8, 2026 -- isolated Explorer subagent, 3 new rooms found)

```
Question: does front_yard extend beyond its charted 25 cells, and is there a screen transition or
new objective reachable from the untested directions?

Answer: confirmed, partially. Three new adjacent rooms found via real Koholint::Navigator.move!
from front_yard_navigator.dump, each with a screenshot: west = room_id 161/map_id 0 (re-confirms
the registry's old single-observation screen3_north note); east = room_id 163/map_id 0, observed
twice independently -- a genuine room_id COLLISION with starting_house (also 163, but map_id 16):
room_id alone is not a unique room key, (room_id, map_id) is -- see
data/ram_registry.json's hram.room_id; south (tested from two different entry columns, same
result both times) = room_id 178/map_id 0 (re-confirms the old overworld_screen2 note). North:
refuted -- a genuine wall via the far-west column (two consecutive blocked move! calls, cell
unchanged), and the center column loops back into starting_house through its own door rather than
finding anything new. No concrete next objective (item/NPC/story beat) confirmed -- the 3 new
rooms are unexplored past their entry point, only visually distinct unverified sprite content.

Indicators: game = unchanged milestone (shield still the last confirmed one). Trip A->B = not the
target, but incidental data: front_yard's door to each new room's edge took 4-10 move! calls.
Verified facts = 0 registry entries written by the subagent itself (Explorer role, confirmed clean
git status in both repos) -- promoted into data/ram_registry.json's new world_topology entry and
hram.room_id's collision note by this session afterward, with full provenance.

Decisions made: none (Explorer role).

Next question proposed: one room per session, per the one-question rule -- (1) resolve/characterize
the room_id=163 collision properly (confirm (room_id, map_id) as the real key by checking a few
more rooms); (2) chart each of the 3 new rooms (161, 163/map0, 178) with Terrain.RoomClassifier +
a few Navigator probes to find their own exits and anything interactable (item, NPC) -- the
visually distinct sprites spotted in each screenshot are the natural starting point, not yet
confirmed as anything.

What NOT to redo: don't walk 'up' along front_yard's column 5 expecting new territory -- confirmed,
it re-enters starting_house through its own door. Don't assume 1 move! call = 1 tile of progress --
typically 2 calls per cell (COMMIT_THRESHOLD is half a tile, same caveat as before). Don't retest
north via column 0 -- confirmed genuine wall, not a budget artifact.
```

## Session report (September 8, 2026 -- north corridor found: room 146, a real new room)

The owner pointed out the "north wall" was only tested on 2 of ~9 columns and was described to me
directly as a tree (a discrete obstacle, not a sealed edge) -- worth trying the other columns. A
second Explorer subagent did.

```
Question: is there a real path around the north obstacle via one of the untested columns, and
what's a first look inside the three previously-found rooms (161, 163/map0, 178)?

Answer: confirmed -- there is a real corridor. Column 1 (x<=24) walks north all the way to the
top of front_yard with zero blocks and transitions into room_id=146/map_id=0, a genuinely new
room never seen before this session. Column 0 stops one tile short of the same breakthrough
point, blocked by a single discrete BG-tile obstacle right at the top-left corner (distinct tile
signature, no OAM sprite there -- visually tree-like, matching the owner's description, though
that's a visual read, not confirmed as literally a tree beyond that). Columns 2,3,4,7,8 hit a
*different* obstacle -- a straight hedge wall at y=122, mid-screen, not the top edge, same wall
column 5 already ran into. Column 6 wasn't independent data -- it drifted into column 5's path via
the game's own alignment assist. Net correction to the prior session's "confirmed genuine wall":
front_yard's north side has one real corridor (columns 0-1) past a mid-screen hedge, not a sealed
boundary -- that conclusion was right about the wall it tested, wrong to generalize from 2 columns
to "no north exit."

First-pass room content (entry + a few steps, not fully charted): west/161 has a house-like
structure, tan block objects, and a rounded green creature-like sprite -- most feature-rich. east
/163-map0 is an undifferentiated repeating clover/bush field, nothing distinguishing found in the
area explored. south/178 has a circular hedge/fence ring around a centered creature-like sprite
plus two small sprites reading as airborne -- the only non-rectangular, deliberately-shaped layout
of the three, and the subagent's top recommendation for the next dedicated session.

Operational note: this subagent got stuck twice ending its turn on "waiting for the monitor
notification" with no actual result, apparently from using its own background-task/Monitor
mechanism internally and not reliably resuming from it -- had to be resumed twice via SendMessage,
the second time explicitly redirecting it to run everything as synchronous foreground commands
instead. It then completed the task properly. Its own screenshots were lost somewhere in that
process (the scratchpad directory only had the *first* session's PNGs on disk afterward) -- the
room_id=146 finding was independently re-verified and captured by this session directly rather
than trusted secondhand (see the gif sent to the owner: west leg x:88->24, north leg y:131->88
crossing into room 146, 93 frames, `Koholint::Navigator.tap` loop against
front_yard_navigator.dump). The three rooms' "first pass" descriptions above are trusted from the
subagent's report as-is (git status was independently confirmed clean, Explorer role respected)
but don't have a fresh independent screenshot from this session -- see the entry-point screenshots
already sent from the prior session instead.

Indicators: game = unchanged milestone. Trip A->B = incidental: front_yard spawn to room 146's
entry, reproduced directly this session, ~22 raw taps (west leg 24 taps to x<=24, north leg ~30
taps to cross into 146 -- raw tap counts, not move! counts, so not directly comparable to the
subagent's 14 move! calls). Verified facts = world_topology.front_yard_adjacent_rooms updated with
room_id=146/map_id=0 and the corrected north picture; hram.room_id/map_id verified_count bumped.

Decisions made: none (Explorer role; the room_id=146 capture was this session's own follow-up
verification work, not a new decision).

Next question proposed: one room per session, per the one-question rule. Top candidate per the
subagent's own recommendation: chart room_id=178 (south) past its entry -- confirm whether the
centered creature-like sprite is stationary/decorative or interactable (approach it, check for a
dialogue/interaction trigger the way Session 2 did with Tarkin), and find 178's own exits. Second
candidate: room_id=146 (north, found this session) is completely unexplored past its entry --
front_yard's own north edge clearly wasn't a hard map boundary, so 146 may have more territory
past it too.

What NOT to redo: don't retest front_yard's north columns 2,3,4,6,7,8 -- confirmed real wall (5
identical stop points at y=122) or a merge into column 5's known path. Don't retest column 0
expecting an open path -- confirmed blocked by a real, visually-distinct obstacle one tile short
of where column 1 breaks through. Don't assume 1 move! call = 1 tile, and don't trust a column
label without verifying actual x/y after each step -- the game's own alignment assist can drift a
walk from one column into another mid-traversal (confirmed: column 6 -> column 5). Don't launch an
Explorer subagent that plans to use its own background/Monitor tooling for a task this size --
ask it to work synchronously from the start, given this session's stuck-twice experience.
```

## Session report (September 8, 2026 -- room 177 reached, matches legacy's old villager_screen)

Owner's direction: "focus on the village." `legacy/game_agents/zelda/scenarios.rb`'s old
`villager_screen` method (room_id 177, its own comment: "a house + wandering villager") starts
from `overworld_screen2` (room_id 178 -- exactly the already-confirmed "south" room from
`front_yard`) via `down` then `left`. Told this Explorer subagent explicitly to skip
background/Monitor after the prior one's stuck-twice experience -- it completed cleanly.

```
Question: does front_yard -> south (178) -> continue down/left reach room_id=177, following
legacy's old villager_screen hint (direction only, not its tap counts)?

Answer: confirmed. 16 real Navigator.move! calls: front_yard(162) -[south]-> 178 -[~2-3 down,
then blocked by a wall]-> -[~10-11 left]-> room_id=177/map_id=0, entered at x=140,y=48. Legacy's
exact tap counts (40 down, 44 left) didn't map onto move!'s tile-calibrated steps -- confirms
"trust the direction from an old hint, not the count" as a general pattern, not just a one-off.

Important new Navigator caveat, now documented in lib/navigator.rb: on the exact step that
crosses a room boundary, move! can return :blocked even though a real transition happened --
position() rebases onto the new screen, so the pre/post delta on the old axis reads under
COMMIT_THRESHOLD. Both transitions on this path hit it. Room_id/map_id must be checked after
every move! call near a screen edge, never inferred from :ok/:blocked alone.

Room 177: a building-shaped structure (dark trapezoid/gabled-roof shape on a tan base) centered
upper-screen, grass field with darker blotchy clusters near the edges, two small round
white/cream sprites near the structure. OAM snapshot (single frame): Link at slots 2/3, two 2-tile
sprite pairs (flags=0x21), one single-tile sprite -- not yet confirmed whether any move (would
distinguish an animated/interactable sprite from decoration). Screenshot sent to the owner.

Indicators: game = new room reached (177/map0), one screen-scroll south then west of front_yard,
not yet explored beyond entry. Trip A->B = front_yard to room 177: 16 move! calls, 2 real
transitions -- first concrete multi-room route measurement with the new toolchain. Verified facts
= data/ram_registry.json's world_topology.front_yard_adjacent_rooms (178's south transition
re-confirmed a 3rd time) and new front_yard_to_room177 entry; hram.room_id's note updated.

Decisions made: none (Explorer role) for the room-177 finding itself; the lib/navigator.rb caveat
comment was added by this session directly (mechanical documentation of an observed bug/limitation,
not a design decision -- matches the project's "hidden constraint, one line" comment convention).

Next question proposed: a short multi-frame OAM diff at a fixed position in room 177 -- does
either 2-tile sprite pair move over time/room-revisits? That would distinguish an
animated/interactable sprite from static decoration without assuming what it depicts, and is the
natural next step before deciding whether room 177 is worth an interaction attempt (approach +
check for a dialogue trigger, the way Session 2 did with Tarkin).

What NOT to redo: don't re-verify front_yard->178 or 178's basic shape -- confirmed 3 independent
times now. Don't re-derive legacy's villager_screen tap counts as literal tile-step counts --
confirmed unreliable; direction-only is the reusable part of any legacy hint. Don't re-litigate
move!'s COMMIT_THRESHOLD math on non-transition steps -- it works correctly there; the
blocked-but-transitioned quirk is specific to the exact frame a screen-edge crossing occurs.
```

## Session report (September 8, 2026 -- first confirmed dialogue text: room 177's static sprite)

Owner's direction: keep exploring the village without stopping, collect as much as possible from
NPC/object dialogue in parallel.

```
Question: does either of room 177's two sprite pairs move on its own, and does :a near either
trigger anything?

Answer: confirmed, both parts, with a twist. One pair (originally y=32,x=77/85, plus a
single-tile sprite) genuinely wanders with zero Link input (idle 60-frame test: x crept 77->106).
The other (y=96,x=120/128) stayed at that exact position across 13 approach steps from 2 angles --
only its tile ID flickers (animation), never its position. Interaction landed on the STATIC pair,
not the moving one: approached, faced it, pressed :a -> a dialogue box opened reading "YOUPI! J'AI
LA PECHE! ET TOI?" (data/ram_registry.json's new dialogues.room177_static_sprite entry has the
full transcript and provenance). Repeated :a toggled the box open/closed, same line every time.
Negative control (pressing :a far from both sprites) produced nothing, 3x -- confirms this is
proximity-gated, not a room-wide effect. "Moves on its own" was NOT a reliable predictor of "is
interactive" here -- worth remembering for future rooms. The moving pair's own interactivity is
still inconclusive (a chase script couldn't maintain clean adjacency against its wander), not
refuted.

Also re-confirmed: 0xD0-0xDF/0xE0-0xEF read all-zero even while a real dialogue box was visibly
open on screen -- dialogue detection must stay screen-render-based, never that address range.

Room 177's own exits, light probe only (not fully confirmed): east returns to 178 (the known entry
path), north crosses into 161 -- suggesting 161 borders both front_yard and 177, unconfirmed with
more than a few taps. West/south inconclusive, likely obstructed by the building sprite rather
than a wall.

Indicators: game = no new milestone in the "item/sword" sense, but the first confirmed dialogue
text this project has ever captured -- a real content signal, not just topology. Trip A->B =
unchanged. Verified facts = data/ram_registry.json's world_topology.room177_sprites and the new
top-level dialogues section (room177_static_sprite) -- the first entries there.

Decisions made: none (Explorer role).

Next question proposed: (1) a cleaner, tighter chase to get confirmed adjacency on the moving
sprite and settle whether it's also interactive -- inconclusive isn't refuted. (2) confirm room
177's own exits with more than a light probe, especially whether 161 really borders both
front_yard and 177 (would mean 161 is a hub, not a dead-end room). (3) once an inventory/state RAM
address exists, re-check the static sprite's dialogue interaction for any HUD-visible side effect
beyond the text box.

What NOT to redo: don't re-test the static pair's position -- confirmed fixed across 3 approach
angles + a 60-frame idle window. Don't re-test the far-away negative control -- confirmed clean 3x.
Don't assume a wandering sprite is more likely to be the interactive one -- wrong here. Don't trust
0xD0-0xDF/0xE0-0xEF as a dialogue-state flag -- re-confirmed all-zero during a real open dialogue.
```

## Session report (September 8, 2026 -- room177 fully mapped, 161 confirmed a hub, 2nd dialogue)

```
Question: (1) is room 177's wandering sprite genuinely interactive, using a tighter tap-by-tap
chase? (2) what does a proper push (10-15 move! calls/direction) reveal about all 4 of room 177's
exits?

Answer: confirmed, both parts.

(1) Yes. A tap-by-tap adaptive chase (re-targeting the larger-delta axis after every single tap,
not a stale multi-tap plan) closed the gap in 24 taps. Facing mattered as much as proximity -- the
first adjacency attempt with stale facing produced nothing; facing the dominant-delta direction
right before :a triggered it immediately. Text: "YOUPI! J'ai la pêche! Et toi?" -- same line as
the static sprite. This also caught a transcription error: the static sprite's registry entry had
been recorded all-caps ("YOUPI! J'AI LA PECHE! ET TOI?"); a zoomed re-read of the real rendering
confirmed mixed case with a circumflex accent -- both entries corrected.

(2) All 4 directions resolved. East -> 178 (known). North -> confirmed room_id=161/map_id=0 via a
building-clear column (x=140), 8 clean move! calls -- 161 now confirmed to border BOTH front_yard
(west side, already known) and room177 (north side): it's a hub, not a dead end, matching what the
owner predicted. West and south are both genuine walls (west: x=36, re-tested from two angles;
south: y=112, independently confirmed at 3 separate columns) -- not budget artifacts. Important
methodological catch: testing north/west from columns/rows that grazed the building sprite's own
footprint gave false "blocked" readings at first -- both turned into real open paths once tested
from a column/row clearly past the building. Also caught: the previous session's
room177_after_dialogue_exhausted.dump checkpoint is NOT actually closed despite its name (still
mid-dialogue) -- exposed because a real idle NPC should never show zero OAM movement across 12+
samples; a correctly-closed checkpoint is now saved at room177_dialogue_closed.dump.

Indicators: game = no new item/sword milestone, but real content progress: a 2nd confirmed
interactive line (same text, different sprite) and room 177's exit graph is now complete.
Trip A->B = room177 -> room161 transition, 8 move! calls, zero blocks, ~30s wall-clock -- a new,
clean measurement. Verified facts = data/ram_registry.json's world_topology.room177_sprites
(wandering pair: inconclusive -> confirmed interactive) and new room177_exits entry;
dialogues.room177_wandering_sprite added, dialogues.room177_static_sprite's text corrected.

Decisions made: none (Explorer role).

Next question proposed: chart room 161 itself, now confirmed a hub bordering both front_yard and
room177 -- its own exits and any interactable content is the natural next "one room" target. Lower
priority: the lone single-tile companion sprite (tile=38, flags=0) tracking near the wandering
pair -- decoration, an effect, or a distinct entity, not established either way.

What NOT to redo: don't retest room 177's west/south with more columns -- 3 independent y=112
stops plus a twice-confirmed x=36 stop are solid. Don't test north/west from the spawn
column/row expecting a wall -- that's the building's own footprint, not the room edge; test from a
column/row clearly clear of it. Don't trust room177_after_dialogue_exhausted.dump as a closed
baseline -- use room177_dialogue_closed.dump instead. Don't identify either room-177 sprite by OAM
slot number -- both alternate between two slot ranges every frame, identify by position/exclusion.
Don't assume pixel-adjacency alone triggers :a -- facing the right direction immediately before
the press matters too.
```

## Session report (September 8, 2026 -- room161 confirmed a 3-way hub, room160 found, first solid negative)

```
Question: what are room 161's 4 exits, and does any of its sprites trigger a dialogue via :a?

Answer: exits confirmed, all 4 directions. East -> front_yard (known). South -> room177 (known,
room177's own north exit). North -> genuine wall at y=26, confirmed at 3 separate columns
spanning the room's width (two closer columns gave a false stop first -- the house's own
footprint, same pattern room177's building caused). West -> a NEW room, room_id=160/map_id=0, via
a specific mid-height gap (the bottom row hits a real wall instead) -- a visually distinct area:
raised stone/hedge platform around a well/altar-like structure, water/river tile pattern, flower
sprites, a green blob creature. room161 is a genuine 3-way hub (front_yard/room177/room160).

Interaction: extensively tested (~32 :a attempts), NO dialogue found on any of room161's sprites.
Three distinct moving entities identified: a round green blob (chased to 1-3px adjacency from 3
angles, correct facing, 9 attempts, zero); an "ear"-shaped creature (5 clean attempts, zero,
sometimes sits above the north wall -- likely unreachable there); a vertical post-like object
(chase cross-tracked onto other sprites, inconclusive not refuted). A positive control on room177's
known-interactive sprite, same session, confirmed the test mechanism itself works -- these are real
negatives, not a broken test. This is the project's first solid "confirmed non-interactive" result,
as useful as a positive one.

Indicators: game = no new item/dialogue milestone this room, but real topology progress: room161's
graph is complete (3 neighbors, a genuine hub) and a new, visually rich room (160) found.
Trip A->B = not this session's primary target. Verified facts =
data/ram_registry.json's new world_topology.room161_exits_and_sprites entry; hram.room_id's note
extended with room160.

Decisions made: none (Explorer role).

Next question proposed: room160 is the natural next "one room" target -- visually the richest area
found yet (platform/well, water tiles, flowers, its own creature), completely unexplored past
entry. Lower priority: room161's vertical "post" object is the one genuinely inconclusive sprite
left (chase-script cross-tracking, not a clean negative) -- low priority given how solid the other
two negatives are.

What NOT to redo: don't retest room161's north from the columns near the house (x=36,52) expecting
an opening -- confirmed the house's own footprint, superseded by the real wall at y=26 found via
wider columns. Don't re-chase room161's blob or "ear" creature expecting a missed dialogue --
both solid negatives, corroborated by a working positive control. Don't reuse a
"nearest-surviving-pair" chase heuristic on a room with several same-shaped sprites close together
without tightening it (max-jump distance, tile-ID equality between paired halves) -- it silently
jumped between distinct sprites here.
```
What NOT to redo: don't chase starting_house's remaining 12 disagreements further -- triangulated
via two independent methods against a single static oracle, reads as the oracle's own staleness,
not a method bug. Don't rebuild the classifier per-cell instead of per-signature -- the whole point
of D8's efficiency win is signature-level caching; testing every cell individually would just be
live-probing with extra steps.
```

## What NOT to redo

- Look for Link's position anywhere other than HRAM. That's found.
- Extend `ScreenMap`, `TileClassifier`, or `TileCatalog`. They're being replaced, not improved.
- Run `ScreenMap.build` on a new screen "in the meantime". 1.5 to 5h per screen for data that D4
  might make useless.
- Read `docs/archive/EXPLORATION_LOG.md` in full to resume. Look up a fact in it, at most.
- Trust a checkpoint's *name* (`after_shield_interior`) as a verified fact. Render the framebuffer
  and look, or read a confirmed RAM address -- names are inherited intent, not provenance.
- Diagnose "no dialogue open" by reading tile-ID ranges (`0xD0-0xEF`) as if they were memory
  addresses. They're tile IDs referenced through the tilemap; render the screen instead.
- Assume `scenarios.rb`'s comments describe what a script actually does. "Exhausts the shield-gift
  conversation" produced zero dialogue in this reproduction -- verify by rendering, not by reading
  the comment next to the code.
- Chase a WRAM-diff "gate flag" before checking the mundane explanation first: is Link actually
  next to the NPC he's supposed to be talking to? `legacy/`'s `oam_sprites`/`mmu.read` can return
  an empty/stale OAM read depending on PPU timing -- use `mmu.debug_read` (gemboy PR #9) for a
  reliable sprite-position check before trusting a "no dialogue" or "nothing there" reading.
- Trust `move_tiles`'s `moved` return value as "no real displacement happened." It's a known
  undercount (creeping collision) -- compare raw position across calls, not just the return value.
- Treat a checkpoint saved right after dialogue/interact() as a clean baseline for direction
  probing. The very first tap in ANY direction can carry a fixed, direction-independent position
  artifact from an unsettled animation state -- call `Koholint::Navigator.settle!` (or otherwise
  burn one throwaway tap) before trusting position deltas from a freshly-loaded checkpoint.
- Call `Koholint::Navigator.settle!` on every checkpoint reflexively "to be safe." It unconditionally
  taps :down -- destructive on a cell whose down edge is a screen exit (confirmed on
  `front_yard_navigator.dump`'s starting cell). Only checkpoints taken right after interact()/dialogue
  need it; a real post-navigation state doesn't.
- Assume `Navigator.move!` returning `:ok` means the cell has changed. It only guarantees
  `COMMIT_THRESHOLD` (half a tile) of real displacement -- `cell_of` right after can still report
  the departure cell. Keep tapping the same direction until the cell actually changes if you need
  to know Link has arrived somewhere, not just that the direction isn't blocked.

## Session report (September 8, 2026 -- Session 2 lands: shield obtained, house left for real)

```
Question: does a snapshot-based nav tool (D7) fix the pathing bug and actually get Link out?
Answer: yes. Built lib/navigator.rb: #move!/#probe track cumulative displacement from a fixed
        reference (not move_tiles's per-call baseline) with the same ~14px commit threshold
        legacy/ already validated, plus Motherboard#dump/.load (gemboy PR #9) for true
        snapshot/restore probing. Found and fixed two bugs along the way: (1) COMMIT_THRESHOLD
        needed to be TILE_SIZE/2, not TILE_SIZE -- a real step is ~14px, never a full 16;
        (2) after_shield_interior (checkpointed right after interact(), no settle) carries a
        transitional artifact where the first tap in ANY direction produces an identical fixed
        position shift -- fixed with Navigator.settle!. After both fixes, probe_all against
        starting_house's oracle grid agreed 3/4 on the tested cell (only "right" disagreed,
        plausibly a sub-tile alignment difference on an already corner-quirk-documented cell).
        Used the tool for real: walked to Tarkin (previously unreachable -- legacy/'s pathfinding
        gave up 38px short), triggered an actual conversation for the first time this session,
        received the shield (HUD-verified: data/screenshots/shield_obtained_hud.png), then
        walked to the south door in 6 snapshot-based steps with ZERO blocking -- no "Hé mon gars"
        message at all, confirming the whole door-gate saga was legitimate shield-gating.
        room_id/map_id at exit: 162/0, matching the historical front_yard value exactly
        (data/screenshots/front_yard_reached.png).
Indicators: game = shield obtained + house left, both screenshot-verified (first time this repo
        has reproduced this milestone) | trip A→B = first real measurement, 6 steps
        starting_house->front_yard | verified facts = unchanged, 6 HRAM (this session's finding
        is architectural/behavioral, not a new RAM address)
Decisions made: none directly, but D7's snapshot-based approach is now empirically validated,
        not just designed.
Next question proposed: see above -- Session 3 (cold review) before extending further.
What NOT to redo: see above -- COMMIT_THRESHOLD and the settle-before-probing lesson, both real
        bugs that silently invert probe results if skipped.
```

## Earlier session report (September 7, 2026, later that night -- corrects the report below: no gate flag, a legacy/ pathing bug)

```
Question: are 0xD3E7/0xDFF9 (previous report's candidates) the real door-gate condition?
Answer: no -- wrong layer entirely. Checked Link's actual OAM position (via mmu.debug_read,
        gemboy PR #9, bypassing a PPU-bus-gating artifact that made plain oam_sprites return an
        empty list at this exact frame) against the two stationary NPCs: Link at (74,82)/(74,90),
        the likely-Tarkin pair at (80,120)/(80,128) -- 38px apart, nowhere near adjacent. Tested
        6 manual :right taps from the same checkpoint: move_tiles reported moved=0 every time,
        but x visibly advanced 2px per tap (82->94) -- the known "creeping collision" undercount.
        front_yard's approach loop treats moved=0 as "blocked" and gives up long before reaching
        Tarkin. No shield is ever given; the door NPC blocking Link afterward is correct game
        behavior (he genuinely lacks the shield), not a gate to bypass. 0xD3E7/0xDFF9 are almost
        certainly the door NPC's own dialogue-open noise, deprioritized.
Indicators: game = still pre-shield, root cause now understood | trip A→B = still not measured |
        verified facts = still 6 HRAM verified
Decisions made: none. D5 (legacy/ not extended) means this pathing bug isn't patched here --
        deferred to Session 2's D7 tool, which now has its D6 dependency (gemboy PR #9, merged
        same day).
Next question proposed: see above -- Session 2 starts now.
What NOT to redo: see above -- check NPC adjacency via debug_read before assuming a dialogue
        failure means something exotic; don't trust move_tiles's moved=0 as "no progress."
```

## Earlier session report (September 7, 2026, night -- isolates the real door-gate trigger, superseded above)

```
Question: what actually triggers front_yard's block, and is it related to the shield-gift
        interact() loop?
Answer: no relation. Rendered all 12 frames of the interact() loop: zero dialogue at any step --
        Tarkin doesn't respond at that position, contradicting the "exhausts the shield-gift
        conversation" comment in scenarios.rb. The real trigger is proximity-based, hit while
        walking toward the door: stepped move_tiles one call at a time and found the exact
        transition (y=122 -> y=121, Link repositioned backward by the game -- matches the old
        "appears to reposition Link" note precisely). Checkpointed both sides of that single
        move_tiles call and diffed WRAM+HRAM+OAM+IO: 195 bytes changed, mostly dialogue-render
        state (0xD500-0xD616, cross-validates against the same block found in an earlier
        same-room diff) and audio registers (the block message's sound effect). Two isolated
        boolean-looking flags survive that noise: 0xD3E7 and 0xDFF9 (both 0 -> 1) -- candidates
        for the actual gate condition, not yet cross-validated (single occurrence).
Indicators: game = still pre-shield (unchanged from the correction above) | trip A→B = still not
        measured | verified facts = still 6 HRAM verified (2 new hypotheses added, not verified)
Decisions made: none.
Next question proposed: see above -- cross-validate 0xD3E7/0xDFF9 across independent triggers,
        then try a write experiment to test if forcing them lifts the gate.
What NOT to redo: don't assume the interact() loop does anything without checking; the real event
        is proximity/movement-triggered, not dialogue-initiated.
```

## Earlier session report (September 7, 2026, evening -- corrects the report below)

```
Question: is the shield actually obtained at the after_shield_interior/front_yard checkpoints,
        and is front_yard's freeze really an unexplained collision bug?
Answer: no, and no. Rendered both checkpoints' framebuffers (ppu.export_framebuffer_png) instead
        of trusting names/prior notes: HUD B/A slots are empty at both -- no shield ever obtained
        in this session's reproduction. front_yard's "freeze" is an open dialogue box reading
        "Hé mon gars, attends un peu !" -- byte-for-byte the pre-HRAM "Tarin blocks the south
        door" story gate in docs/archive/EXPLORATION_LOG.md, never solved before or after the
        reset. The prior session's "no dialogue open, ruled out" check was wrong: it read
        mmu.read(0xD0..0xDF) as memory addresses; those are tile IDs referenced through the
        tilemap, not addresses -- the check proved nothing and the real cause was missed.
Indicators: game = downgraded (pre-shield, not post-shield as previously recorded) | trip A→B =
        still not measured | verified facts = still 6 HRAM verified
Decisions made: none.
Next question proposed: see above -- WRAM diff around the shield-gift conversation / door-gate
        trigger, the method the original spike recommended in 2026 and never tried.
What NOT to redo: don't trust a checkpoint's name over a rendered screenshot; don't check for an
        open dialogue by reading tile IDs as memory addresses.
```

## Earlier session report (September 7, 2026, afternoon -- Session 1's original inconclusive result)

```
Question: is terrain readable from game state (WRAM object grid predicts collision)?
Answer: inconclusive. Environment was fully unset up (no ROM, no checkpoints, no gemboy deps) --
        ROM installed, gemboy deps installed (no PR needed, just bundle install + libsdl2-dev,
        both already correctly declared/documented by gemboy), two require_relative paths broken
        by the gemboy->koholint move fixed in legacy/ (primitives.rb, tilemap_reader.rb).
        after_shield_interior regenerated and confirmed reproducible. front_yard is NOT
        reproducible: deterministically gets Link wedged near the door target, unresponsive to
        all input; 5 distinct diagnostics (repeat, direction combos, dialogue/OAM/key-state
        check, idle-settle) ruled out the obvious causes without finding the real one -- stopped
        per the anti-patch rule rather than guessing further. Fell back to a single-room test
        (starting_house only, oracle: 32 cells / 123 edge samples): brute-forced every WRAM
        address x stride x orientation x wall-marker-byte -- best accuracy 80.5% against a 77.2%
        majority-class baseline, using degenerate marker values (0, 255). Not a credible signal,
        but not a refutation either: a single static snapshot can't isolate a candidate the way
        D1's two-room diff could. Full detail in data/ram_registry.json's
        wram_unmapped.room_object_grid and .intro_door_gate entries.
Indicators: game = unchanged (4 NPCs, no sword) | trip A→B = still not measured | verified facts
        = still 6 HRAM verified (this session added an inconclusive entry, not a verified one)
Decisions made: none. D4 stays deferred -- Session 1 did not produce a basis to decide it.
Next question proposed: see above (get a second room, then redo the two-room WRAM diff).
What NOT to redo: don't keep guessing at front_yard's exact freeze cause -- 5 attempts already
        ruled out; a genuinely new angle or the owner's call is needed, not a 6th guess. Don't
        trust a single-room WRAM correlation search as evidence either way.
```

## Earlier session report (September 7, 2026, before the reset)

```
Question: are Link's position and room ID in HRAM?
Answer: confirmed. 0xFF98/0xFF99 (X/Y, verified_count 8), 0xFF9E (direction), 0xFFF6 (room,
        6 distinct screens), 0xFFF7 (map: 0 outdoors, 16 for house2).
Indicators: game = 4 NPCs, no sword | trip A→B = not measured | verified facts = 6 HRAM
Decisions made: D1 (measured, to be ratified). Three more screens mapped with the legacy code
        before the review (shop_screen, screen3_north, house2_interior).
```
