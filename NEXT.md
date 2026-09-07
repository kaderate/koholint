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
at that checkpoint (confirmed by rendering the framebuffer, not just trusting the state) -- no
shield was actually obtained. `front_yard`'s freeze (Link wedged at x=74, y=121, unresponsive to
all input) is **not a geometry/collision bug**: a rendered screenshot shows an open dialogue box
reading "Hé mon gars, attends un peu !" -- byte-for-byte the pre-HRAM story gate documented in
`docs/archive/EXPLORATION_LOG.md` ("Blocked" section): Tarin stops Link at the south door, and it
was never solved, before or after this reset. My first pass at this (see report below) claimed "no
dialogue open" from reading `mmu.read(0xD0..0xDF)` -- wrong check: those are **tile IDs** referenced
through the tilemap, not memory addresses; reading raw ROM bytes at $D0-$DF proved nothing.
Since `overworld_screen2`, `villager_screen`, `shop_screen`, `screen3_north`, and `house2_interior`
all chain through `front_yard`, none of them are currently reproducible either. Room IDs previously
read at `0xFFF6` (from an older, no-longer-reproduced run): front_yard 162, overworld_screen2 178,
villager_screen 177, screen3_north 161, shop_screen 179, house2_interior 169.

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

Corrected understanding (see report below): the blocker isn't a mystery collision bug, it's the
pre-HRAM "Tarin blocks the south door" story gate from `docs/archive/EXPLORATION_LOG.md`,
resurfacing because the shield was never actually obtained in this session's reproduction. That
old entry already names the right method and never got to try it: "a proper WRAM diff around the
block-trigger event itself, not further blind retries."

**Falsifiable question**: what WRAM byte(s) change between (a) a checkpoint just before Tarkin's
second conversation and (b) one right after it, that differ depending on whether the shield was
actually granted -- and does forcing/confirming that state lift the door block?

- **Role**: explorer.
- **Criterion**: either the shield-gift conversation completes (HUD B/A slot shows the shield icon,
  confirmed by rendering the framebuffer, not assumed from a checkpoint's name) and Link then
  passes the south door without the "attends un peu" message reappearing; or, if it still blocks,
  a specific WRAM flag is identified whose value differs between a blocked and unblocked attempt.
- **Budget**: one session, 3h. If three distinct attempts don't move it, stop (anti-patch rule) and
  write a "paradigm to question" note here instead of a fourth.
- **Then**: once past the door, redo the actual Session 1 test -- diff WRAM between two different
  rooms (not a single-room blind correlation search, which is what was tried this round and is far
  weaker) to isolate the block that changes, correlate with both oracle grids.
- **Deliverable**: `data/ram_registry.json`'s `wram_unmapped.intro_door_gate` and
  `room_object_grid` entries promoted or refuted, plus a screenshot-verified checkpoint that
  actually has the shield if one is reached.
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

## Session report (September 7, 2026, evening -- corrects the report below)

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

## Last session's report

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
