# Screen protocol and improvement loop — design notes (2026-10-24)

Outcome of the owner's review of run `20261024-184627-b97e` (25,896 frames, 18 places, 19/21 objectives achieved, `because` used 18 times: the goal/leads/NPC-memory machinery works). The review found four classes of harness problems and asked for an automated improvement loop. This document records the decisions.

## Findings (with evidence)

1. **Objectives work.** The agent followed a lead south to the beach. 18 of 21 objectives cite a lead.
2. **No systematic routine per screen.** NPCs, signs and enemies are only handled when the model happens to ask. Wanted at the very least: detect NPCs and enemies on arrival; talk to NPCs and read signs (signs are essential to know where to go); enemies get an avoidance/protection routine.
3. **Decisions and mapping happen while the screen is not ready.** Measured on the run: the first `screen` mapping of a place happens a median 0 frames after `room_id` changes (max 30), and for 24 of 67 visits the first terrain hash differs from the second (partial map); 99 of 265 paid calls are made within 20 frames of a place change; the perception at decision time always reads mode 11 / submode 7 / `motion_blocked` 0, so the current "settled" signal sees neither a screen scroll nor a ledge jump. Consequences seen by the owner: places mapped during the scroll (two places merged), the agent called during a ledge jump (intra-screen and inter-screen jumps both occurred).
4. **Inventory is unused.** The agent must learn to use items, starting with the shield.

## Decisions

- **Order:** (1) `ready?` gate; (2) explore autopilot A/B; (3) screen arrival protocol with place card, NPC and sign engagement; (4) enemy census then avoidance; (5) inventory, `guard` and item-gained events; (6) symptom detectors and offline analyst. The explore autopilot comes right after the gate (owner decision).
- **Auto-engage on arrival:** yes for NPCs and signs, with a per-visit frame cap (like Revisit).
- **Combat before the sword:** avoidance and shield only.
- **Improvement loop:** levels 1 and 2 first (below); level 3 later.

## 1. Readiness gate

A deterministic predicate `ready?` that the engine evaluates before any grid mapping, perception-driven decision or agent call: Link controllable, no screen transition in progress, no jump or other scripted animation, screen stable for K frames. While not ready the engine waits (free), with a stuck guard (reason `not_ready_stuck`). Needed signals are not catalogued yet: probe the RAM during a screen scroll and during a ledge jump (hypotheses from general knowledge: Link's height above ground; the room-transition state byte) and store them in `data/addresses.json` / `data/modes.json` with provenance. Maps taken while not ready are discarded; a place keeps only ready screens, and a first screen that later differs is remapped. Inter-screen jumps must not merge places. Trace: a `not_ready` count in `summary.json`; a `notable` when a decision would have been taken not ready (detector input).

## 3. Screen arrival protocol

Once ready on a new screen, the engine runs a deterministic protocol: screenshot (exists), entity scan (RAM entities: npc, enemy, unknown), a **place card** in `world.json` (people, enemies, signs and objects seen, exits seen; this is the missing long-term memory of places), engage not-exhausted NPCs and unread signs (Revisit logic extended; caps per visit), then hand over to the agent. Signs and objects are not probed yet: census first.

## 4. Enemies

Census with a real hostile entity (kind `enemy` never measured: the contact probe saw no damage). Then: planner cost around enemies, explore prefers other directions, damage detection as a symptom. No fighting before the sword.

## 5. Inventory

Inventory in the agent context (slots 0xDB02–0xDB0B, A slot 0xDB01, B slot 0xDB00), a `use_item` skill (hold the item button), `guard` (raise the shield facing a threat), `menu_assign` exists. Event `item_gained` by inventory diff (also gives the sword milestone). Measure how the shield blocks (contact, projectiles).

## 6. Improvement loop (Continual Harness, arXiv 2605.09998)

Today the owner is the loop: watch a run, spot a symptom, request a change. Automate in levels:

1. **Symptom detectors** (deterministic, fill `summary.json` `symptoms` and `suggestions.md` with evidence and frames, shown as timeline markers): decision taken while not ready; first screen differs from later ones; NPC not exhausted; sign not read; damage taken; item never used; same skill failing repeatedly; cost drift; unknown mode.
2. **Offline analyst** (an agent reading summary, symptoms and trace excerpts after a run) that writes proposals as notes; never applies them; the owner approves.
3. *Later:* the analyst prepares the change in a worktree, runs tests and keyframe-forked A/B scenarios (cost and places per 1000 frames, symptom counts), surfaces it only if metrics improve.

Boundary: Continual Harness lets the agent edit its own prompt/skills during a run. Here the agent may write more **data** (goal, leads, place names and notes) but never code; code changes stay versioned (`flow_version`) and owner-approved.
