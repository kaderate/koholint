# Koholint

A deterministic engine that plays Link's Awakening DX headless through emu-gb and calls agents
(Jev for tactical choices, Claude for strategy) at defined decision points. Each run lives in
`runs/<id>/`: manifest, trace, input journal, saves, keyframes.

- Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`
- Plans: `docs/superpowers/plans/`
- v1 (agent session driving the game): git tag `v1-archive`, analysis in `docs/RETROSPECTIVE.md`

Needs Ruby 4.0.1, an emu-gb checkout and the ROM. Copy `.env.example` to `.env` (gitignored) and set
`EMU_GB_HOME` and `KOHOLINT_ROM`; real environment variables take precedence. Tests: `rake test` (one process per file, in parallel, ~40 s; the first run builds a local emulator
state cache in `tmp/`), `rake test:e2e` to also play the full boot from frame 0.

Live view: `bin/koholint watch runs/<id> [--port N] [--from live|start] [--speed X]` prints
`watching http://127.0.0.1:PORT` and serves the run as video, status and feed from a read-only replay (works on a
finished run or one being written; Ctrl-C to stop). `run`/`resume --realtime` paces the engine at about 60 fps of
wall time so the viewer can keep up; pacing never changes the journal or the game state.
