# Koholint — notes for agents

A deterministic engine plays Link's Awakening DX through emu-gb and calls agents at decision
points. Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`.
High-level architecture: `ARCHITECTURE.md` (update it in the same commit as any change to a layer, a data flow or a run artifact). Plans: `docs/superpowers/plans/`. Skills and harness behaviour per flow: `docs/AGENT_SKILLS.md` (update it with a flow change); commands and viewer: `docs/OPERATING.md`. v1 is archived under the git tag `v1-archive`.

## Conventions

- Everything in the repo is English: code, comments, docs, commits.
- Commits: one line, imperative, no body.
- Comments: almost none; only a hidden constraint or a *why* that code cannot show, in one line.
- Ruby style: use the short hash syntax (`{ buttons:, frames: }`, `f(frame:)`) wherever the key and the
  local have the same name; the project's Ruby version supports it.
- Time is the frame. No `sleep`, no wall clock in game logic; wait for a state condition.
- The ROM and the game manual are never committed (`$KOHOLINT_ROM`, `manual/`).
- The full `rake test` runs locally on ABK's Mac once before each merge; CI runs the ROM-free set (`rake test:ci`).
- Only the engine writes a run's `trace.jsonl` and `save/`. A run resumes only with the same
  `flow_version`, ROM hash and capabilities digest (the operational entries of `data/capabilities.json`). A change to the
  play flow in code means a new `flow_version`; publishing or retiring a capability changes the digest, never `flow_version`.
- A rule a script can check is a validator, not a paragraph.
- Game facts live in typed data with provenance (`data/addresses.json`, a run's `world.json`),
  never in prose. `verified` needs `verified_count >= 2` from independent checks. `data/capabilities.json` follows the same
  rule: every entry carries its trigger, trials and history, and `validated` needs successes in 2 independent places.
- How to play is public knowledge and may be used freely, in code, data and prompts: controls, menus, map, save and game-over screens, dialogue, interactions with people, signs and objects, item use, general mechanics. Where to go and what to do next (routes, solutions, item locations, the order of the game) is a walkthrough and stays out: it is observed or read from in-game texts. Anything measurable is measured; a value taken from general knowledge enters data files as a hypothesis with its source and is verified by a probe.
- What remains to do lives in `ROADMAP.md` (only what is left; delete items as they land, git is the history).
- Runs are committed only as the light bundle written by `bin/koholint archive`; prompts, keyframes and saves stay local.
- Playing and evolving the flow are separate: a run only emits `suggestions.md`. `learn` and `capability` are offline
  commands; a run never calls them.
