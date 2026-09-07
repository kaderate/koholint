# Plan — since the September 7, 2026 reset

A sequence of SESSIONS, not tasks. Each session follows `AGENTS.md`'s format and roles: one
falsifiable question, one observable end criterion, one budget, one targeted goal indicator. The
plan stops at the first session that runs the concept's decision loop (trigger on RAM state,
planner, executor, action log) on a real game objective — no further, since what follows depends
on what's learned there.

Constraints that hold across this whole plan:

- No session extends `legacy/` or runs `ScreenMap.build` (D5, and `NEXT.md`'s "What NOT to redo").
- No autonomous (unattended) session is planned. The owner is waiting for the foundations to be
  laid (at the earliest after Session 4) before greenlighting autonomy.
- Cold review every 3 sessions — a plan-cadence translation of the owner's "every morning or on a
  major blocker". A real blocker triggers a review out of cadence, without waiting for the 3rd
  slot.
- D6 (headless session API) is written on gemboy's side by another agent, outside the scope of
  koholint sessions. Any session that depends on it notes so explicitly; the owner is warned as
  soon as a session is ready to start but blocked on this dependency.

**Note before Session 1** (a finding from this planning session, not a decision): the initial
import (`koholint-init`, commit `42f1f0e`) comes from `gemboy@claude/usage-2mr345` at commit
`c952ded`, but that branch has one more commit that wasn't imported (`5ee7949`, "Archive the HRAM
diff and other reusable scratchpad diagnostics into experiments/"). It adds the scripts that
produced D1 (`ram_diff_hram.rb`, `ram_diff_hram2.rb`, `diag_scx_scy.rb`, `diag_scx_scy2.rb`,
`house2_dialogue.rb`, `house2_sprite2.rb`) and a note in `ram_registry.json` explicitly pointing
Session 1 at reusing the same full-diff technique. Neither `legacy/`'s code nor its data are
affected (checked identical otherwise). Import status: done — see `NEXT.md`.

---

## Session 1 — Is terrain readable from game state?

```
Role: explorer
Question: does the game decode each room into a 16x16 object grid (10x8) in WRAM, with each
          object type's collision read from a ROM table — instead of being probed?
End criterion: for front_yard and starting_house (already mapped), a WRAM read predicts the
          :blocked/:ok edges of legacy/.../screen_maps/'s grids with a measured agreement rate,
          every disagreement explained.
Budget: 3h
Depends on: D1 (ratified)
Deliverable: data/ram_registry.json entry promoted or refuted, agreement rate in the report
Indicator targeted: verified facts — this is directly a RAM registry entry to be settled
```

Already fully specified in `NEXT.md`; carried over here unchanged, subject to D3's choice (DMG,
confirmed — invalidates nothing: the checkpoints used are in DMG).

## Session 2 — Snapshot-based navigation tool (D7), validated once against the oracle

```
Role: builder
Question: does a navigation tool in lib/, testing each direction from an in-memory snapshot then
          restoring (D7), reproduce the :blocked/:ok edges of legacy/.../screen_maps/'s oracle
          grids for front_yard and starting_house?
End criterion: 100% agreement with the oracle on these two screens, or every disagreement
          documented and explained (notably the known [3,3] corner contamination) before being
          accepted.
Budget: 6h
Depends on: D6 delivered on gemboy's side (EXTERNAL — blocking, see note at the top of the plan),
          D7 (ratified), Session 1's conclusion
Deliverable: code in lib/, checkpoint specs, oracle JSON for both screens marked consumed
Indicator targeted: trip A→B — first crossing measured in frames, with no live probe, on a
          known screen
```

If D6 hasn't landed on gemboy's side when this session is ready to start: don't work around it by
reimplementing a piece of session-object in koholint. Flag the blocker to the owner and wait.

## Session 3 — Cold review: sessions 1–2, and D4's status

```
Role: reviewer
Question: do sessions 1 and 2's deliverables comply with docs/CONCEPT.md and the ratified
          decisions (D1, D6, D7)? Does Session 1's outcome settle D4 (exhaustive exploration vs.
          on demand), and in which direction?
End criterion: written report, compliant/non-compliant judgment per deliverable, explicit
          recommendation on D4 submitted to the owner (the reviewer does not decide D4 itself,
          see AGENTS.md "fundamental decisions belong to the owner")
Budget: 3h, fresh session, no code written
Depends on: Sessions 1, 2
Deliverable: DECISIONS.md (D4's status updated if the owner decides based on the recommendation),
          NEXT.md note
Indicator targeted: verified facts — checks that what sessions 1–2 declared "verified" or
          "validated" holds up on rereading
```

## Session 4 — Regenerate the 7 checkpoints with the lib/ tool, remove legacy/ (D5)

```
Role: builder
Question: are the 7 known checkpoints (after_shield_interior, front_yard, overworld_screen2,
          villager_screen, shop_screen, screen3_north, house2_interior) traversable A→B via lib/
          alone, with no file from legacy/?
End criterion: the 7 checkpoints regenerated and traversed by lib/; legacy/ removed in the same
          commit as the last checkpoint reaching parity (D5's invalidation condition).
Budget: 9h (3 blocks of 3h), one commit per migrated checkpoint
Depends on: Session 2 (navigation tool), D5 (ratified, delay: see DECISIONS.md)
Deliverable: lib/ code, specs on the 7 checkpoints, removal of legacy/
Indicator targeted: trip A→B — the 7 known trips, measured in frames, without legacy/
```

## Session 5 — Decision-loop skeleton (no real objective yet)

```
Role: builder
Question: can a trigger on a RAM state change (room, health, text open) suspend scripted
          execution, call a minimal planner, log the action to a JSONL file, then resume — on a
          toy scenario (e.g. a simple room change)?
End criterion: an end-to-end run produces a usable action-log JSONL, with at least one real
          trigger and one planner decision logged with its provenance.
Budget: 9h (3 blocks of 3h)
Depends on: Session 4 (lib/ at parity, legacy/ removed)
Deliverable: lib/ code (triggers, minimal planner, executor, action log), specs
Indicator targeted: verified facts — the action log becomes the new provenance source for
          decisions made; no game indicator is expected to move here (justified: mechanical
          skeleton, no game objective yet)
```

## Session 6 — Cold review: sessions 4–5, ready for a real objective?

```
Role: reviewer
Question: does lib/ cover checkpoint-regeneration parity with no drift since Session 4? Does
          Session 5's skeleton respect docs/CONCEPT.md's execution/decision decoupling (few LLM
          calls, at precise decision points, RAM-sourced facts)?
End criterion: written report, compliant/non-compliant judgment, green light or not for Session 7.
Budget: 3h, fresh session, no code written
Depends on: Sessions 4, 5
Deliverable: NEXT.md note, DECISIONS.md if a structural gap is found
Indicator targeted: verified facts — same logic as Session 3
```

## Session 7 — First real game objective via the decision loop

```
Role: builder
Question: can the decision loop (RAM triggers, planner, executor, action log) lead Link from a
          point A to a non-trivial real game objective (e.g. getting the sword, or leaving the
          starting house if not already reached by this point) relying on RAM-sourced facts and a
          minimum of LLM calls at decision points?
End criterion: the chosen objective is reached at least once, reproducibly, with a complete
          action log and provenance for every decision.
Budget: 9h (3 blocks of 3h)
Depends on: Session 6 (green light), all prior deliverables
Deliverable: lib/ code, JSONL action log of the successful run, NEXT.md entry with the new
          milestone
Indicator targeted: progress in the game — first real game milestone reached by the decision
          loop itself, not by a spike script. This is the project's goal; the plan stops here.
```

---

The plan stops at Session 7. What follows depends on what this first real loop will have taught
— a new question, a new session, decided cold by the owner based on Session 7's report.
