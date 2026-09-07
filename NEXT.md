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
`/tmp/zelda_checkpoints`, not versioned): `after_shield_interior`, `front_yard`,
`overworld_screen2`, `villager_screen`, `shop_screen`, `screen3_north`, `house2_interior`.
Room IDs read at `0xFFF6`: front_yard 162, overworld_screen2 178, villager_screen 177,
screen3_north 161, shop_screen 179, house2_interior 169.

## Decisions in force

D1 ratified (HRAM). D2 (OAM) obsolete. D3 decided: DMG. D4 open, deferred to Session 1's outcome
(see `PLAN.md`, formally decided in Session 3). D5, D6, D7 ratified. See `DECISIONS.md`.

## Import gap closed (September 7, 2026)

`koholint-init` had been imported from `gemboy@claude/usage-2mr345` at commit `c952ded`, one commit
short of that branch's tip (`5ee7949`, "Archive the HRAM diff and other reusable scratchpad
diagnostics into experiments/"). The 6 missing scripts that produced D1 (`ram_diff_hram.rb`,
`ram_diff_hram2.rb`, `diag_scx_scy.rb`, `diag_scx_scy2.rb`, `house2_dialogue.rb`,
`house2_sprite2.rb`) are now in `legacy/game_agents/experiments/`, and the matching method note in
`data/ram_registry.json` has been completed (path fixed to point at `legacy/`, and the sentence
pointing at reusing the technique for the question below).

## Next question proposed (Plan Session 1, see `PLAN.md`)

**Is terrain readable from game state?** Engineering hypothesis, to verify: the game decodes each
room into a 16x16 object grid (10x8) in WRAM and reads each object type's collision from a ROM
table. If true, collision is read instead of probed, and D4 decides almost by itself.

- **Role**: explorer.
- **Criterion**: for two already-mapped screens (`front_yard`, `starting_house`), a WRAM read
  predicts the `:blocked`/`:ok` edges of `legacy/.../screen_maps/`'s grids, with a measured
  agreement rate and every disagreement explained.
- **Budget**: one session, 3h.
- **How**: from a checkpoint, diff WRAM between two rooms (different `0xFFF6`) to isolate the zone
  that changes as a block; correlate its 10x8 layout with the visible tilemap; then check against
  the oracle grids.
- **Deliverable**: `data/ram_registry.json` entry promoted or refuted, plus the agreement rate in
  the session report.
- **Indicator targeted**: verified facts.

Next session if this one is confirmed (or refuted): Plan Session 2, the snapshot-based navigation
tool (D7) — blocked until the headless session API (D6) has landed on gemboy's side (external,
outside koholint's scope, see `DECISIONS.md`).

## What NOT to redo

- Look for Link's position anywhere other than HRAM. That's found.
- Extend `ScreenMap`, `TileClassifier`, or `TileCatalog`. They're being replaced, not improved.
- Run `ScreenMap.build` on a new screen "in the meantime". 1.5 to 5h per screen for data that D4
  might make useless.
- Read `docs/archive/EXPLORATION_LOG.md` in full to resume. Look up a fact in it, at most.

## Last session's report

```
Question: are Link's position and room ID in HRAM?
Answer: confirmed. 0xFF98/0xFF99 (X/Y, verified_count 8), 0xFF9E (direction), 0xFFF6 (room,
        6 distinct screens), 0xFFF7 (map: 0 outdoors, 16 for house2).
Indicators: game = 4 NPCs, no sword | trip A→B = not measured | verified facts = 6 HRAM
Decisions made: D1 (measured, to be ratified). Three more screens mapped with the legacy code
        before the review (shop_screen, screen3_north, house2_interior).
Next question proposed: see above.
What NOT to redo: see above.
```
