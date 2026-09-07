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

- **Status**: open, **deferred**. Deciding condition: a clean outcome (confirmed or refuted) from
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

- **Status**: ratified (September 7, 2026).
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
  an environment gap. See `NEXT.md` for the fix in progress.
