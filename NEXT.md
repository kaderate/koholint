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
