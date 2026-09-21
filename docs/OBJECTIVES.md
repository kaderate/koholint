# Koholint — objectives and constraints

Settled with the owner, September 21, 2026. The architecture that follows from this document is
`docs/ARCHITECTURE.md`.

This document stays short on purpose. If it grows past ~2 500 words, that is itself a symptom.

---

## 1. Two objectives, kept separate

**The project objective** — an **agent that plays**. gemboy is the substrate that makes playing
observable and reproducible.

**The in-game objective** — what the agent tries to achieve inside the game. It is the *test* of
the project objective, not the project objective itself.

Two consequences follow, and both are load-bearing:

- The in-game objective is a measuring instrument. It is chosen because it tests the agent well,
  and it can be swapped without the project changing.
- Work that does not make the agent play better is not project work, however justified it looks
  locally. Foundation work is attractive precisely because it is tractable when playing is not,
  and it will absorb unlimited effort unless something points it back at the loop.

---

## 2. The in-game objective

**Finish Link's Awakening DX.** The agent decomposes it; intermediate steps are its work, not a
hard-coded plan.

The reasoning: an objective of "clear the first dungeon" produces a system optimised for the
first dungeon that has to be rebuilt for the second. An objective of "finish" forces the
architecture to be general from the first commit.

**The score.** A single monotone number: weighted milestones reached, as a percentage of the
full game, computed in code from RAM with no prose and no human judgement anywhere in the path —
sword, shield, first dungeon entered, Roc's Feather, first boss defeated, Full Moon Cello, on
through the eight instruments. Its full requirements are in `docs/ARCHITECTURE.md` L2. The two
load-bearing ones: it is **the only indicator**, and a flat score triggers re-planning in code.
A metric that does not order states in the search is a diagnostic, not an indicator, and a
system that reports several of them side by side will drift toward whichever one happens to be
moving.

**The acceptance milestone.** The first dungeon cleared unattended. Not the objective — the test
of whether the architecture holds. An objective with no dated checkpoint cannot distinguish
progress from motion.

**The budget, honestly.** Link's Awakening is ~6–8 h of game time for someone who knows it,
~12–16 h blind. At 2–2.5× slower than real time, a flawless run is already 20–40 real hours of
emulation before a single mistake; with retries, hundreds. That is a viable north star for a
project running in the background with parallelism, and it is not a short-term success
criterion, which is what the acceptance milestone is for.

The real unknown is the overhead factor between a flawless run and an agent that explores and
backtracks. Nobody has measured it. Measuring it early beats estimating it.

---

## 3. Where knowledge of the game comes from

**The manual is the only document placed in the agent's context.** No walkthrough, no map, no
solution. This is controllable at the input, which is what makes it a real rule.
`docs/GAME_MANUAL_NOTES.md` holds it, correctly scoped.

**The model's own priors are allowed, and tagged.** Any claim about the world that the planner
acts on is recorded as a hypothesis carrying its source: `manual`, `model_prior`, or
`in_game_observation`. `model_prior` is a legitimate source, not cheating.

**Nothing becomes a fact without in-game verification**, whatever its source.

The reasoning: a ban on game knowledge is not verifiable. The model driving the agent already
knows this game — it knows where the sword is. A ban does not erase that knowledge; it converts
it into untraced intuition, which leaves neither clean discovery nor clean play. Making
knowledge explicit turns provenance into a field with a validator rather than a discipline in
prose, and it lets the project *measure* what share of the world model came from priors versus
observation. That is a result rather than a compliance problem.

It also sets up the discovery question properly, as a later ablation with a baseline: build the
loop with knowledge, reach the milestones, then turn knowledge off and measure how far the same
agent gets. Under the run-directory design that experiment costs one configuration key
(`docs/ARCHITECTURE.md` §5).


---

## 4. Rollback is a gameplay mechanic

The agent may snapshot, attempt, and restore as part of playing. Its progress is the best state
reached, not the state of one continuous life.

The project owns exact, cheap determinism — ~0.05–0.08 s per snapshot — and declining to use it
would discard the agent's one structural advantage over a human player. Its real value is that
it converts a wall into a search with a budget: a hostile crossing that cannot be survived by
walking through it becomes 200 attempts from one snapshot, roughly twenty minutes on one
emulator. And a budget gives a mechanical answer to *when is a subgoal wrong*, which otherwise
has to wait for a human (C2).

The costs are accepted knowingly. The agent does tree search over a deterministic simulator
rather than playing one life, which is closer to a tool-assisted run than to a player. "Current
progress" becomes the best node of a tree rather than a save file, which is what makes the input
log necessary rather than merely tidy. And the score's monotonicity becomes structural, since it
is the rule that decides which state to keep.


---

## 5. Constraints

Each one is evidenced, and each one kills at least one architecture.

**C1 — Throughput: ~25–30 minutes of game time per real hour, per emulator.** The measured rate
is ~1.15 s per ~26-frame tap, *after* a 17× optimisation — roughly 2–2.5× slower than real time,
or 90 000–110 000 emulated frames per real hour. Anything whose cost scales with emulated time
is budgeted before it is designed. Parallel emulators must be possible from day one. Re-walking
a route to reach a position is waste when restoring a snapshot costs 0.05 s.

**C2 — The owner is single and asynchronous.** Any design whose recovery path ends at a human
decision has a latency of hours. The agent must abandon a subgoal and re-plan on its own. The
owner's role is direction and review, never unblocking.

**C3 — Observation is RAM first, pixels second.** RAM is cheap, exact and addressable. The
framebuffer is 160×144, below the reliability threshold for a vision model, and needs a 4–6×
upscale (~500–1 100 tokens per image). Pixels are for the owner and for what RAM does not
expose. Text is decoded by tile bitmap in the scratch range `0xD0–0xEF`, never by tile ID.

**C4 — The LLM is orders of magnitude more expensive than a frame.** At ~100 000 frames per real
hour, a decision per frame is off the table by several orders of magnitude. The loop is
deterministic code; the LLM is called at decision points, on compact state, under a declared
budget of calls per emulated game minute, receipted per call and enforced by a guard.

**C5 — The ROM is copyrighted; progress must be reproducible from the repository alone.** The
durable unit is the **input log from boot**: the emulator is deterministic given ROM plus inputs
per frame, so a recorded sequence reproduces any state exactly, in a few kilobytes of text, with
no ROM in it and no format fragility. Snapshots become a cache keyed by the log's hash.
(gemboy also offers `Motherboard#dump(with_rom: false)`, a ROM-free snapshot — committable in
principle, but a Marshal dump, so brittle across Ruby versions and refactors. `BatteryRam.save`
gives the game's own `.sav`: small and stable, but only a coarse anchor.) Determinism from boot
is an assumption to verify first, not a fact yet.

**C6 — A cold process must resume without reading its way back in.** Durable memory is a
queryable state, not a narrative written for a reader; a `reconcile` command computes the safe
next action from the run directory. The human-facing orientation file is capped at 2 000 words,
enforced by a test, because it serves a different purpose.

**C7 — Rules a script can check must be checked by a script.** Every invariant a validator can
express gets a validator in CI. A rule written as prose for a future reader to apply by hand is
not enforced.

*(Minor, not a blocker: gemboy loads SDL at require time even headless, which affects cloud and
CI runs only. It matters only insofar as CI is part of the answer to C7 — schema validators and
unit tests run fine without the emulator; emulator integration tests in CI would need a lazy
require.)*
