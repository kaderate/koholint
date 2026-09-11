# Game manual notes

Paraphrased mechanic notes from the official *Legend of Zelda: Link's Awakening DX* instruction
booklet (owner-provided PDF, September 11, 2026 — see `DECISIONS.md`'s D14). Original booklet
text/images are copyrighted Nintendo material and are NOT reproduced verbatim or committed here or
anywhere in this repo, consistent with `roms/` being gitignored for the same reason. This file is
original commentary distilling which MECHANICS exist and how they generally work — never a
walkthrough, never a claim about where a specific item is on Koholint Island. Per D14/AGENTS.md,
still don't assume any of this applies to koholint's current game state without observing it.

## Map screen (SELECT)

- Two distinct marker types can appear at a *specific location* on the overworld map, not just as
  a fixed legend:
  - **`!?` mark**: "shows important locations you need to visit to proceed through the game." A
    real per-location hint the game places on the map itself — not yet checked in this project as
    a live per-cell marker (only encountered as a fixed legend region so far). Worth scanning the
    SELECT map's interior grid for this icon appearing at a *specific room's cell*, not just its
    presence in the icon-legend block.
  - **"message" mark**: "marks a location where you heard an important message. Press A to make
    the message appear again." A distinct icon from `!?`. If found on the map linked to a cell,
    pressing A there should replay that location's dialogue without physically returning.
- The cursor+`:a`-hold text box this project already found (place name + a second, shorter line)
  matches the booklet's description of this "message" system — the second line is likely tied to
  this mechanic, not necessarily a generic "owl hint" for every room.

## Movement / interaction mechanics not yet tested in this project

- **Pushing**: stand next to a stone/statue-shaped object and hold a direction into it — no item
  required for basic pushing (distinct from *pulling*, which needs the Power Bracelet). "Sometimes
  there are objects hidden under stones, and other times a moveable stone may be the trigger that
  will open a dungeon door." This project has recorded several "genuine wall, zero position drift"
  results against stone/statue-shaped objects — worth double-checking whether any of those were
  actually pushable (a push registers as slow net displacement over several held-direction frames,
  not the single-tap-then-check pattern most of this project's wall tests have used).
- **Diving**: "Press A to swim, B to dive... try diving in suspicious places, you never know what's
  hidden in the water depths." This project has repeatedly treated water strips (`224/0`'s scroll
  boundary, `225/0`/`226/0`'s SE/water edges) as simple impassable boundaries and never actually
  attempted the dive input specifically. Flippers are described as auto-used once owned, not a
  selectable item — whether basic swimming/diving requires them at all, or what happens attempting
  it without them, is untested here.
- **Ramming (Pegasus Boots)**: running into a wall/tree at speed can break through it or shake
  loose a hidden object. Requires an item not yet confirmed obtained — noted for later, not
  actionable now.
- **Shield**: must be actively "brought up into a ready position" by holding its assigned button;
  explicitly "repels MOST enemy attacks," not all — matches this project's own empirical finding
  that shield-holding mitigates but doesn't eliminate contact damage. Not a bug, expected behavior.
- **Long-press requirement for text**: "if the message is very long, press A to see all of it" —
  matches this project's own hard-won lesson (the `225/0` signpost's hidden 2nd page, the SELECT
  map's typewriter box) that a short tap can truncate real content. General pattern, not
  room-specific — worth assuming for ANY untested dialogue object this project has only tap-tested.

## World structure (general, not a walkthrough)

- 8 dungeons total, each guarded by a "Nightmare" boss holding one of 8 musical instruments; a
  dungeon needs its own key to enter.
- Treasure chests: some open on sight, others only appear after clearing all monsters in a room.
- Named locations mentioned generically (existence, not position on koholint's actual map): a
  fishing pond, a "Trendy Game" crane game, a "Town Tool Shop", a telephone booth (this project has
  already found and tested `house2_interior`'s telephone object — plausibly this one), a witch who
  makes Magic Powder from mushrooms, a photo shop.
- Named NPCs (identity only, not yet cross-referenced against this project's own observed NPCs):
  Marin, her father Tarin, a mysterious Owl who "knows much of the island," Grandpa Ulrira, Mr.
  Write, Crazy Tracy. This project's own `starting_house` NPCs and the "Tarkin" name recorded
  earlier were never matched against these -- worth a light cross-check (name spelling only, not
  an assumption about role) if useful, but not chased for its own sake.
- Heart Pieces: 4 collected = +1 Heart Container, 12 total on the island (on top of the starting 3
  Heart Containers). A real, separate collectible from whatever "bidule" this project's NPCs
  described -- don't conflate the two without direct evidence.

## What this does NOT tell us

The booklet is deliberately non-spoiling about exact item locations — it describes systems, not a
walkthrough. It does not say where the first sword is. The sword/"bidule" hypothesis this project
has been pursuing is not resolved by anything in this manual; what changes is the TOOLING now known
to exist (push, dive, the `!?`/message map markers) that hasn't been tried yet.
