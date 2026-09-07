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

## Next question proposed (Session 1 continuation -- not Plan Session 2 yet)

The block-trigger diff recommended since the pre-HRAM spike finally happened this session (see
report below): stepping the door approach one move at a time and diffing WRAM+HRAM+OAM+IO right
at the trigger found two candidate flags, `0xD3E7` and `0xDFF9` (both 0 -> 1), isolated from 195
bytes of dialogue-render/audio/OAM-reposition noise. Neither is cross-validated yet -- single
occurrence only.

**Falsifiable question**: do `0xD3E7` and `0xDFF9` reliably flip on every trigger of this gate
(different approach angle/timing), and is there any reachable state where they're 0 while Link is
still free to walk past this position (i.e. are they the gate condition, or just rendering-adjacent
noise that happens to correlate once)?

- **Role**: explorer.
- **Criterion**: both flags checked across at least 2 more independently-triggered instances of the
  gate; if either fails to replicate, it's noise, not the flag -- say so plainly rather than keep
  the weaker one. If both hold up, try writing the "unblocked" value (1, or whatever bypasses it)
  into a fresh pre-trigger checkpoint via `mmu.write` and see if Link then walks through -- a write
  experiment, not just a read, per D6/D7's whole reason for existing (bypass gate testing this way
  once the gemboy session API is usable outside koholint's ad-hoc scripts too, though a raw
  `mmu.write` works fine meanwhile).
- **Budget**: one session, 3h. Three distinct attempts, then stop and report (anti-patch rule).
- **Then**: once past the door, redo the actual Session 1 test -- diff WRAM between two different
  rooms (not a single-room blind correlation search, which is what was tried before this round and
  is far weaker) to isolate the block that changes, correlate with both oracle grids.
- **Deliverable**: `data/ram_registry.json`'s `wram_unmapped.intro_door_gate` promoted to verified
  (or refuted) with `verified_count` >= 2, and `room_object_grid` retested once a second room
  exists.
- **Indicator targeted**: progress in the game (getting past a gate the original spike never
  solved) and verified facts.

Session 2 (D7 nav tool) stays blocked on D6 regardless, and D4 stays deferred until this closes.

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

## Session report (September 7, 2026, night -- isolates the real door-gate trigger)

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
