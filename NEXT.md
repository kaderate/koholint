# NEXT

Entry point for any resumption. One page, no more.

## State as of September 7, 2026

Repo initialized from the gemboy spike (`claude/usage-2mr345` @ `c952ded`). `lib/` is empty, all
code is in `legacy/`, all knowledge is in `data/` and `docs/`.

**Indicators**

| Indicator | Value |
|---|---|
| Progress in the game | **Downgraded September 7, 2026, evening** -- "shield obtained, house left" was inherited from a pre-reset run whose checkpoints no longer exist and turned out NOT reproducible (see below): actual verified state is pre-shield, still inside the starting house, 0 NPCs with a *completed* dialogue this session (Tarin's exchange is stuck mid-conversation). No sword. |
| Trip A to B | Not measured in frames. `ScreenMap.navigate!` works on the 7 mapped screens, at the cost of `legacy/` code -- but see above, those checkpoints are not currently reproducible from boot. |
| Verified facts (RAM registry) | 6 `verified` HRAM entries: X, Y, X shadow, direction, room, map. See `data/ram_registry.json`. |

**Reproducible checkpoints** (`legacy/game_agents/zelda/scenarios.rb`, files in
`/tmp/zelda_checkpoints`, not versioned): `after_shield_interior` reproduces deterministically from
a fresh boot (~24min wall time), **but its name is wrong**: the HUD's B/A item slots are both empty
at that checkpoint -- no shield was actually obtained. `front_yard`'s freeze is a **proximity-
triggered story gate**, isolated September 7 evening: the 12x `interact()` loop that's supposed to
be "the shield-gift conversation" (per `scenarios.rb`'s comment) produces zero dialogue at that
position (confirmed by rendering all 12 frames) -- Tarkin doesn't respond there at all. The real
trigger fires later, during the walk toward the door: stepping `move_tiles` one call at a time,
the gate fires between y=122 and y=121 (Link is repositioned backward by the game, matching the
old "appears to reposition Link" note exactly), opening the dialogue "Hé mon gars, attends un
peu !" -- byte-for-byte the pre-HRAM story gate in `docs/archive/EXPLORATION_LOG.md` ("Blocked"
section), never solved before or after this reset. New checkpoints from this session:
`before_shield_gift.marshal` (right before the fruitless interact loop),
`after_shield_gift_attempt.marshal` (right after it, functionally identical),
`door_approach_end.marshal` (blocked, dialogue open). Since `overworld_screen2`, `villager_screen`,
`shop_screen`, `screen3_north`, and `house2_interior` all chain through `front_yard`, none of them
are currently reproducible either. Room IDs previously read at `0xFFF6` (from an older, no-longer-
reproduced run): front_yard 162, overworld_screen2 178, villager_screen 177, screen3_north 161,
shop_screen 179, house2_interior 169.

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

## Next question proposed (Plan Session 2 -- D7 nav tool, starts now)

**The door-gate flag hunt was abandoned -- it was chasing the wrong layer.** Root cause found
September 7, night: there is no hidden gate flag. Link never gets close enough to Tarkin to
receive the shield in the first place, because `front_yard`'s approach loop abandons early on
`move_tiles`'s known "creeping collision" undercount (`moved` reports 0 while position visibly
advances a few px per tap -- see `data/ram_registry.json`'s `wram_unmapped.intro_door_gate`,
`root_cause_2026_09_07_night`). The door NPC blocking Link afterward is correct game behavior:
he genuinely lacks the shield. Per D5, this isn't worth patching in `legacy/`, which is exactly
the class of bug D7's snapshot-based tool exists to not have.

D6 landed in gemboy the same day (PR #9: `Motherboard#dump`/`.load`, `MMU::Debug#debug_read`), so
Session 2 is no longer blocked. Starts now, adjusted from `PLAN.md`'s original scope: it called
for validating against both `front_yard` and `starting_house`'s oracle grids, but `front_yard`
(the room) has never actually been reached -- reaching it is what this tool is for. Validate
against `starting_house` alone first (reachable now, from `after_shield_interior`), then use the
tool itself to walk Link to Tarkin and out the door; validate against `front_yard`'s oracle once
that room is actually reached.

- **Role**: builder.
- **Criterion**: a `lib/` navigation primitive that tests each direction from an in-memory
  `Motherboard#dump` snapshot then restores via `.load` (D7), reproducing `starting_house`'s
  oracle grid (`legacy/.../screen_maps/starting_house.json`) with every disagreement explained.
  Then: used to reach Tarkin from `after_shield_interior` and exit the house, producing a
  screenshot-verified checkpoint with the shield actually obtained.
- **Budget**: 6h per `PLAN.md`.
- **Deliverable**: code + specs in `lib/`, a real (not name-only) `front_yard` checkpoint.
- **Indicator targeted**: trip A→B (first snapshot-based traversal) and progress in the game
  (actually leaving the house, for the first time in this repo's history).

D4 stays deferred -- still no second room to redo Session 1's two-room WRAM diff with, until this
closes.

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

## Session report (September 7, 2026, later that night -- corrects the report below: no gate flag, a legacy/ pathing bug)

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
