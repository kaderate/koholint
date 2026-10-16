# Koholint — notes for agents

A deterministic engine plays Link's Awakening DX through emu-gb and calls agents at decision
points. Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`.
Plans: `docs/superpowers/plans/`. v1 is archived under the git tag `v1-archive`.

## Conventions

- Everything in the repo is English: code, comments, docs, commits.
- Commits: one line, imperative, no body.
- Comments: almost none; only a hidden constraint or a *why* that code cannot show, in one line.
- Time is the frame. No `sleep`, no wall clock in game logic; wait for a state condition.
- The ROM and the game manual are never committed (`$KOHOLINT_ROM`, `manual/`).
- Only the engine writes a run's `trace.jsonl` and `save/`. A run resumes only with the same
  `flow_version` and ROM hash. A change to the play flow means a new `flow_version`.
- A rule a script can check is a validator, not a paragraph.
- Game facts live in typed data with provenance (`data/addresses.json`, a run's `world.json`),
  never in prose. `verified` needs `verified_count >= 2` from independent checks.
- The agent knows the manual and the genre, not a walkthrough: game facts are observed.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`.
