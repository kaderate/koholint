# NEXT

Entry point for any resumption. One page, no more.

## State as of September 7, 2026

Repo initialized from the gemboy spike (`claude/usage-2mr345` @ `c952ded`). `lib/` is empty, all
code is in `legacy/`, all knowledge is in `data/` and `docs/`.

**Indicators**

| Indicator | Value |
|---|---|
| Progress in the game | Level-1 shield obtained, starting house left, 4 village NPCs with dialogue captured (Tarin, the house's 2nd occupant, screen3's villager, Pépé le Ramollo in house2). No sword. |
| Trip A to B | Not measured in frames. `ScreenMap.navigate!` works on the 7 mapped screens, at the cost of `legacy/` code. |
| Verified facts (RAM registry) | 6 `verified` HRAM entries: X, Y, X shadow, direction, room, map. See `data/ram_registry.json`. |

**Reproducible checkpoints** (`legacy/game_agents/zelda/scenarios.rb`, files in
`/tmp/zelda_checkpoints`, not versioned): `after_shield_interior` confirmed reproducible from a
fresh boot (September 7, 2026, ~24min wall time in a fresh container). `front_yard` is **not**
currently reproducible: replaying it from a fresh `after_shield_interior` deterministically gets
Link wedged near the door-exit target (x=74, y=121), unresponsive to all 4 directions -- see
`data/ram_registry.json`'s `wram_unmapped.intro_door_gate.related_finding_2026_09_07`. Since
`overworld_screen2`, `villager_screen`, `shop_screen`, `screen3_north`, and `house2_interior` all
chain through `front_yard`, none of them are currently reproducible either -- unverified until
this is fixed. Room IDs previously read at `0xFFF6` (from an older, no-longer-reproduced run):
front_yard 162, overworld_screen2 178, villager_screen 177, screen3_north 161, shop_screen 179,
house2_interior 169.

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

Session 1's actual question (is terrain readable from game state?) is still open -- see the report
below for what was tried and why it's inconclusive, not refuted. It cannot be properly retested
without a second, different room, and `front_yard` (the only route to one) is currently broken.

**Falsifiable question**: can Link reliably reach a second room (any room, not necessarily
`front_yard` specifically) from `after_shield_interior`, either by fixing `front_yard`'s door-exit
sequence or via a different route?

- **Role**: explorer.
- **Criterion**: a checkpoint exists for a room with a different `0xFFF6` than `after_shield_interior`,
  reproducible from a fresh boot.
- **Budget**: one session, 3h. If the door-exit bug resists three distinct fix attempts, stop
  (anti-patch rule) and write a "paradigm to question" note here instead of a fourth attempt.
- **Then**: redo the actual Session 1 test -- diff WRAM between the two rooms (not a single-room
  blind correlation search, which is what was tried this round and is far weaker) to isolate the
  block that changes, correlate with both oracle grids.
- **Deliverable**: `data/ram_registry.json`'s `wram_unmapped.room_object_grid` entry promoted or
  refuted with the two-room method, plus the agreement rate.
- **Indicator targeted**: verified facts.

Session 2 (D7 nav tool) stays blocked on D6 regardless, and D4 stays deferred until this closes.

## What NOT to redo

- Look for Link's position anywhere other than HRAM. That's found.
- Extend `ScreenMap`, `TileClassifier`, or `TileCatalog`. They're being replaced, not improved.
- Run `ScreenMap.build` on a new screen "in the meantime". 1.5 to 5h per screen for data that D4
  might make useless.
- Read `docs/archive/EXPLORATION_LOG.md` in full to resume. Look up a fact in it, at most.

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
