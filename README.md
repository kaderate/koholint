# Koholint

A deterministic engine that plays Link's Awakening DX headless through emu-gb and calls agents
(Jev for tactical choices, Claude for strategy) at defined decision points. Each run lives in
`runs/<id>/`: manifest, trace, input journal, saves, keyframes.

- Design: `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md`
- Plans: `docs/superpowers/plans/`
- v1 (agent session driving the game): git tag `v1-archive`, analysis in `docs/RETROSPECTIVE.md`

Needs Ruby 4.0.1, an emu-gb checkout and the ROM. Copy `.env.example` to `.env` (gitignored) and set
`EMU_GB_HOME` and `KOHOLINT_ROM`; real environment variables take precedence. Tests: `rake test`.
