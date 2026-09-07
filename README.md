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

## Layout

| Path | Role |
|---|---|
| `data/ram_registry.json` | Memory addresses for the game, each with its provenance and `verified_count`. Source of truth for anything that reads RAM. |
| `data/world_model.json` | Accumulated facts about the game: rooms, NPCs, dialogue, inventory, movement model. |
| `data/puzzle_*.json` | The input packet and hypotheses for the first solved puzzle, with its validator in `legacy/`. |
| `legacy/` | The spike's code, untouched. It regenerates `Zelda::Scenarios` checkpoints and runs the "Koholint report". To be replaced, not extended (see `DECISIONS.md`). Its JSON grids serve as an oracle to validate the new navigation tool, once. |
| `lib/` | The new code. Empty at the start. |

## Dependency on gemboy

`legacy/`'s code reaches into gemboy's internals via relative paths (`profiling/utils.rb`,
`lib/ppu/tile.rb`) and so doesn't run as-is here. The new code's first building block is a headless
session API on gemboy's side (frames, keys, memory reads, in-memory snapshot/restore) that this
repo will depend on like a pinned gem. Until it exists, `legacy/` is run from a gemboy clone.

## Commands

None yet. They'll arrive with `lib/`.
