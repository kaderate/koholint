# Koholint — objectives and constraints

Settled with the owner, September 21, 2026, from `docs/RETROSPECTIVE.md`. The architecture that
follows from this document is `docs/ARCHITECTURE.md`.

The retrospective diagnosed a project that produced 58 600 words of prose against 1 734 lines of
Ruby. This document stays short on purpose. If it grows past ~2 500 words, that is itself a
symptom.

---

## 1. Two objectives, kept separate

Conflating these is a large part of why process work kept beating game work (R4).

**The project objective** — an **agent that plays**. gemboy is the substrate that makes playing
observable and reproducible.

**The in-game objective** — what the agent tries to achieve inside the game. It is the *test* of
the project objective, not the project objective itself.

Two consequences:

- The in-game objective is a measuring instrument. It is chosen because it tests the agent well.
- Work that does not make the agent play better is not project work, however justified it looks
  locally. That is the rule R1 was missing: seven checkpoints, terrain, a visual catalog, a
  hazard classification and an avoidance primitive were each reasonable, and none of them made
  an agent play, because there was no agent.

---

## 2. The in-game objective

**Finish Link's Awakening DX.** The agent decomposes it; intermediate steps are its work, not a
hard-coded plan.

This is the owner's decision and the reasoning is his: an objective of "clear dungeon 1" produces
a system optimised for dungeon 1 that has to be rebuilt for dungeon 2. An objective of "finish"
forces the architecture to be general from the first commit.

**The score.** A single monotone number: weighted milestones reached, as a percentage of the
full game. Computed in code from RAM, no prose and no human judgement anywhere in the path —
sword, shield, Tail Cave entered, Roc's Feather, Moldorm defeated, Full Moon Cello, on through
the eight instruments. Requirements on it are in `docs/ARCHITECTURE.md` §L2; the load-bearing
one is that it is **the only indicator**, and that a flat score triggers re-planning in code.
R5 happened because six comfortable metrics sat in the table where one uncomfortable one
belonged, and because nothing treated fourteen flat sessions in a row as a signal.

**The acceptance milestone.** Dungeon 1 cleared unattended. Not the objective — the test that
says whether the architecture holds. An objective with no dated checkpoint cannot tell progress
from motion.

**The budget, honestly.** Link's Awakening is ~6–8 h of game time for someone who knows it,
~12–16 h blind. At 2–2.5× slower than real time, a flawless run is already 20–40 real hours of
emulation before a single mistake; with retries, hundreds. That is a viable north star for a
project running in the background with parallelism. It is not a short-term success criterion,
which is what the acceptance milestone is for.

---

## 3. Where knowledge of the game comes from

**The manual is the only document placed in the agent's context.** No walkthrough, no map, no
solution. This is controllable at the input, which is what makes it a real rule.
`docs/GAME_MANUAL_NOTES.md` already holds it, correctly scoped.

**The model's own priors are allowed, and tagged.** Any claim about the world that the planner
acts on is recorded as a hypothesis carrying its source: `manual`, `model_prior`, or
`in_game_observation`. `model_prior` is a legitimate source, not cheating.

**Nothing becomes a fact without in-game verification**, whatever its source.

The reasoning: a ban on game knowledge is not verifiable. The model driving the agent already
knows this game — it knows the sword is on the beach. A ban does not erase that knowledge, it
converts it into untraced intuition, leaving neither clean discovery nor clean play. Making
knowledge explicit turns provenance into a field with a validator instead of a discipline in
prose (R3), and it lets the project *measure* what fraction of the world model came from priors
versus observation. That is a result rather than a compliance problem, and it sets up the
discovery question as a later ablation with a baseline: build the loop with knowledge, reach the
milestones, then turn knowledge off and measure how far the same agent gets.

The falsification discipline survives intact — 61 recorded refutations say it works.

Supporting evidence: the PokéAgent Challenge (arXiv 2603.15563), a five-institution benchmark
on Pokémon Emerald, does not ban game knowledge either. It states that *"Pokémon knowledge
appears in pretraining corpora"* and works with that rather than against it.

---

## 4. Rollback is a gameplay mechanic

The agent may snapshot, attempt, and restore as part of playing. Its progress is the best state
reached, not the state of one continuous life.

This follows from owning exact, cheap determinism (~0.05–0.08 s per snapshot) and declining to
use it would be discarding the agent's one structural advantage. Its real value is that it
converts a wall into a search with a budget: room `240/0`'s 8/24 HP floor — six attempts, five
techniques, one identical stop position — becomes 200 attempts from one snapshot, roughly twenty
minutes on one emulator. And a budget gives a mechanical answer to "when is a subgoal wrong",
which the old system could only answer by waiting for the owner (R8, C2).

The costs are accepted knowingly: the agent does tree search over a deterministic simulator
rather than playing one life, which is closer to a tool-assisted run than to a player; "current
progress" becomes the best node of a tree rather than a save file, which is what makes the input
log necessary; and the score's monotonicity becomes structural, since it is the rule that decides
which state to keep.

Noted for the record: the PokéAgent Challenge runs the opposite way — real time, no save states,
*"the game world continues while the agent reasons"*. Its strongest result nonetheless comes from
RL distillation over thousands of replayed episodes, so the retrying is present there too, moved
into training rather than into play.

---

## 5. Constraints

Each one is evidenced, and each one kills at least one architecture.

**C1 — Throughput: ~25–30 minutes of game time per real hour, per emulator.** Best measured rate
is ~1.15 s per ~26-frame tap, *after* a 17× optimisation — roughly 2–2.5× slower than real time,
or 90 000–110 000 emulated frames per real hour. Anything whose cost scales with emulated time is
budgeted before it is designed (R7). Parallel emulators must be possible from day one. Re-walking
a route to reach a position is waste when restoring a snapshot costs 0.05 s.

**C2 — The owner is single and asynchronous.** Any design whose recovery path ends at a human
decision has a latency of hours. The old anti-patch rule did exactly this: the only component
able to say *this goal is wrong* was a person who was frequently absent (R8). The agent must
abandon a subgoal and re-plan on its own. Kader's role is direction and review, never unblocking.

**C3 — Observation is RAM first, pixels second.** RAM is cheap, exact and addressable. The
framebuffer is 160×144, below the reliability threshold for a vision model, and needs a 4–6×
upscale (~500–1 100 tokens per image). Pixels are for the owner and for what RAM does not expose.
Text is decoded by tile bitmap in the scratch range `0xD0–0xEF`, never by tile ID.

**C4 — The LLM is orders of magnitude more expensive than a frame.** At ~100 000 frames per real
hour, a decision per frame is off the table by several orders of magnitude. The loop is
deterministic code; the LLM is called at decision points, on compact state, under a declared
budget of calls per emulated game minute.

**C5 — The ROM is copyrighted; progress must be reproducible from the repository alone.**
`/tmp/zelda_checkpoints/main.dump` on one laptop is not durable state (R9). The durable unit is
the **input log from boot**: the emulator is deterministic given ROM plus inputs per frame, so a
recorded sequence reproduces any state exactly, in a few kilobytes of text, with no ROM in it and
no format fragility. Snapshots become a cache keyed by the log's hash. (gemboy also offers
`Motherboard#dump(with_rom: false)`, a ROM-free snapshot — committable in principle, but a
Marshal dump, so brittle across Ruby versions and refactors. `BatteryRam.save/load` gives the
game's own `.sav`: small and stable, but only a coarse anchor.) Determinism from boot is an
assumption to verify first, not a fact yet.

**C6 — The cold-start read has a hard budget: ≤ 2 000 words**, enforced by a test that fails the
build. A resumption currently costs ~27 300 words before the first action, paid again on every
context rotation (R10).

**C7 — Rules a script can check must be checked by a script.** 63 violations of the project's own
most-audited rule, written up three times (R3). Every invariant a validator can express gets a
validator in CI.

*(Minor, not a blocker: gemboy loads SDL at require time even headless, which affects cloud and
CI runs only. It matters only insofar as CI is part of the answer to C7 — schema validators and
unit tests run fine without the emulator; emulator integration tests in CI would need a lazy
require.)*
