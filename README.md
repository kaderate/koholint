# Koholint

An agent that plays Link's Awakening DX through the [gemboy](https://github.com/kaderate/gemboy)
emulator, in Ruby. The concept: deterministic execution between decisions, facts read from the
game's memory, the LLM called only at decision points, every fact traced back to its source.

This repo was initialized from gemboy's `lib/game_agents/` spike (branch `claude/usage-2mr345`,
commit `c952ded`), after the architecture review concluded on a rewrite on different foundations
while keeping the accumulated knowledge. The ROM is not versioned.

## Where to start

In this order, and nothing else before you have a session question:

1. `NEXT.md`: current state, indicators, next question.
2. `DECISIONS.md`: the decisions in force and what would invalidate them.
3. `AGENTS.md`: the working rules. They override the urge to "just finish one more fix".
4. `docs/ARCHITECTURE_REVIEW.md`: why we're rewriting, and what.
5. `docs/CONCEPT.md`: the original concept, still valid.

`docs/archive/EXPLORATION_LOG.md` is the spike's narrative log. It's an archive: you look up a
specific fact in it, you don't read it to resume the project.

## Atlas

[Koholint Atlas](https://claude.ai/code/artifact/e67f636d-0b55-4762-976a-21b7cd5fc5bb) -- a visual
report of everything charted so far (room graph, screenshots, walkability overlays, dialogue),
generated from this repo's own data (`data/ram_registry.json`, checkpoints) and rebuilt after
meaningful exploration progress. Read it to see the state of the world; read `NEXT.md` to resume
working on it.

## Layout

| Path | Role |
|---|---|
| `data/ram_registry.json` | Memory addresses for the game, each with its provenance and `verified_count`. Source of truth for anything that reads RAM. |
| `data/world_model.json` | Accumulated facts about the game: rooms, NPCs, dialogue, inventory, movement model. |
| `data/puzzle_*.json` | The input packet and hypotheses for the first solved puzzle. Its original validator lived in `legacy/`, removed once `lib/` reached parity (D5). |
| `lib/` | The current code: `Navigator` (D7 snapshot-based movement), `Terrain` (D8 VRAM-tilemap collision), the Session 4 checkpoint scripts under `lib/validation/`. |

## Dependency on gemboy

`lib/` reaches into a gemboy checkout via `$GEMBOY_HOME` (defaulting to a sibling `../gemboy`
directory) for `Motherboard`, `CartridgeLoader`, and frame-stepping helpers — see
`lib/validation/checkpoint_support.rb`. `legacy/` (the spike's code, replaced per D5 once `lib/`
regenerated every checkpoint and reached parity — see `DECISIONS.md`) is gone; its JSON grids
served as a one-time oracle to validate the new navigation and terrain tools (D8) and are no
longer needed.

## Commands

None yet. They'll arrive with `lib/`.
