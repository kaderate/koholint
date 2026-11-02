# Koholint v2 retrospective (2026-11-02)

**Verdict.** The engine/policy/skill/readiness/autopilot/viewer layering holds and the discipline is real (no `verified` address or entity below 2 checks, one `flow-16` constant, 674 commits of traceable history). But the product goal has not moved since 2026-10-20: 29 archived runs, 31.35 USD and 228,781 frames all end at milestone `shield` or `none` (`docs/runs/index.md`), while the last ~60 commits since 10-24 polish navigation/talk/explore plumbing (`policies/delegated.rb` 764 lines, `skills/explore.rb` 418, `skills/talk_to.rb` 374). Cost per 1000 frames fell 0.385 to 0.092 USD and places per run rose 1 to 28, so the loop is cheaper and wider, but nothing in the code can yet perceive or acquire the sword (no inventory in the context, no `item_gained`, no combat, no enemy census): the bottleneck is missing capability, not agent tuning.

## Health scorecard
- Architecture: good. 82 lib files, 10.3k lines, 72 test files (14.4k lines); only 4 files over 340 lines; one real god object, `lib/koholint/policies/delegated.rb` (764 lines, 44 methods) paired with `test/delegated_policy_test.rb` (1846 lines, ~170 s warm).
- Test cost: weak. About 5 min full suite (`ROADMAP.md` last line); `Rakefile` already runs one process per file in parallel, so the cost is the ROM-booting tests (10 files) and the one giant file.
- Determinism/replay: good by design (frame-only time, `verify` replays from boot); `verify` from boot does not scale (`ROADMAP.md` Viewer); fork copies a parent of an older flow into the current one with only an assumed-compatible prefix.
- flow_version: good. `FLOW_VERSION = 'flow-16'` in `lib/koholint.rb`; 16 flows since 2026-10-19 is high churn but each is tagged in `docs/runs/index.md`.
- Data provenance: good. `data/addresses.json` 33 entries and `data/entities.json` 15 entries, none `verified` with count < 2; 9 addresses and 5 entities sit at count 1 (hypotheses).
- Docs accuracy: mixed. `ARCHITECTURE.md` and README commands match `lib/koholint/cli.rb` (`ab-plan`, `ab-report`, `prune-heavy` exist); `ROADMAP.md` is 39 lines but about 60 percent is dense loose-end paragraphs (several 1,000+ characters), and item 1 still lists work as "next" with the goal line saying "shield is done".
- Flakiness: moderate risk; tests depend on ROM and a shared `tmp/emulator_cache` (cold cache in a new worktree is the main cost).
- Repo hygiene: fixed 2026-11-02 (was 12 worktrees and 10 non-main branches, 7 merged); now 5 worktrees, one unmerged branch (`jev-spike`).

## Delete / Prune now
Done 2026-11-02: merged worktrees and branches removed (`arrival`, `fixes`, `lotb`, `retro`, `tl`, `tn`, `ts`; branches `arrival-protocol`, `arrival-fixes`, `lot-b`, `retrospective`, `agent-loop-t*`, `feat/autonomous-recovery`); the September v1 content of this file replaced (git keeps it). Kept: `agent-loop` (holds the `.env` copied into new worktrees), `jev-spike` (4 unique commits, result already in `docs/runs/2026-10-jev-spike.md`: decide merge or drop), `inventory-shield` and `talk-reliability` (agents at work).
1. Archive finished plans `docs/superpowers/plans/2026-10-16-*.md`, `2026-10-18-*.md`, `2026-10-19-*.md` (5 plans, 697 lines, all landed per ARCHITECTURE) and keep only the 3 specs; plans carry paths that rot. Effort S.
2. Collapse the ROADMAP "Open decisions and loose ends" wall (about 20 bullets of measured history, e.g. talk_to, Explore, Readiness) into `docs/runs/` notes or `data/` and keep one line per open item. Why: AGENTS.md says "only what is left"; most of it is a changelog. Planned right after `inventory-shield` and `talk-reliability` merge (they edit ROADMAP too). Effort M.

## Fix drift
1. `bin/measure_speed` and `bin/generate_start_fixture` are referenced only by old plans/spec, not by README or tests; document or delete (`bin/`). Effort S.
2. `lib/koholint/policies/walk_and_talk.rb`, `start_game.rb`, `with_fallback.rb` are the no-agent baseline (CLI default at `cli.rb:232`); ROADMAP says `resume` without `--agent` on an agent run "silently continues with WalkAndTalk": a bug, make it an error. Effort S.
3. Several ROADMAP "loose ends" are bugs, not decisions: talk_to `target_free` 24 of 36 (run 20261101-122743-1fec) and `talk_to` talked only 10 of 21 in the A/B (`docs/runs/2026-11-arrival-protocol-lot-b.md`), `loading` readiness fail-open, timed-out agent calls counted as 0 USD, 170-char line in `agents/context.rb`. Move to issues with a repro. Effort M.
4. Comment density: AGENTS.md says almost none; `lib` has 128 comment lines across 10.3k lines (acceptable) but ROADMAP carries the prose instead; check `lib/koholint/skills/screens.rb` (284 lines) and `lib/koholint/viewer/*.html` for game knowledge in prompts (`agents/prompts.rb`) against the walkthrough rule. Effort S.
5. `GRID_ROWS`/`GRID_COLS` duplicate `Geometry`, goto centring duplicates perpendicular logic (ROADMAP "Parked code smells"); cheap, do while touching them. Effort S.

## Do next
1. In progress (agent on branch `inventory-shield`): inventory in the context plus `item_gained` by inventory diff (RAM slots `item_a`/`item_b` are already read in `lib/koholint/perception.rb:25` but never reach the agent or the milestone): this is the single missing signal for the sword. Effort M.
2. Enemy census and avoidance (`lib/koholint/probes/entity_census.rb`, `data/entities.json` has kind `enemy` never measured): sword needs a place Link can survive. Effort M.
3. Add a goal-progress metric to `summary.json` (milestone, new items, hearts) and stop archiving runs whose milestone stays `shield`; the last 10 runs all stay at `shield` and 7 ended on `dollars`. Effort S.
4. Split `lib/koholint/policies/delegated.rb` (arrival/revisit/autopilot hooks vs. decision cycle) and `test/delegated_policy_test.rb`; target under 400 lines per file and a suite under 2 min. Effort L.
5. Freeze new flows for the sword work: batch navigation fixes (explore/talk) into one flow bump per live run instead of one per defect (16 flows since 2026-10-19). Effort S.

Questions for the owner: (1) Is the sword reachable by the current agent without combat, or should combat precede inventory? (2) Merge or drop `jev-spike`? (3) Is a hard per-run cap below 1 USD acceptable for runs that show no milestone gain?
