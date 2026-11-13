# Agent skills

The skills, protocols and harness behaviours the agent works with. Versioned with the play flow (currently `flow-55`): update this page, not the README, when a flow changes. Layers and data flow are in [ARCHITECTURE.md](../ARCHITECTURE.md).


- Learned capabilities (`data/capabilities.json`, `bin/koholint capability list`): an `operational` entry is a composite of the skills below, offered in the skill schema and listed under "Learned skills" only while its trigger item is held (flow-49) and its object is on screen (today `sword_on_object_92 row col direction`: stand next to object 92, face it, use the sword, step into its cell). `explore` and `goto` also run it themselves when blocked facing such a cell, and the planner routes through those cells as a last resort. `learn` and `capability publish|retire` are offline commands.
- Between decisions the engine waits, with no input, until Link is ready (no screen scroll, door walk, jump or
  knockback, then 2 settled frames): the screen is never mapped and the model never called mid-scroll or mid-jump
  (`notable` `not_ready_wait` for waits over 5 frames; the run stops with `not_ready_stuck` after 600 frames).
- `explore [direction]` (relaunched by the autopilot after benign stops, see Running) explores by itself: it walks to the nearest
  untried border exit (a side never left from this place) or untried door (walking up into it), else toward the nearest
  place it has taken an exit to that still has untried exits or doors (flow-55: or, if surveyed before the capability existed, a tile
  the capability has cleared elsewhere, listed with its source in the route's `clearable`), else to the nearest frontier (a known cell next to
  an unknown one) (`direction` prefers that side), steps out, re-plans, and returns to the model only at an event:
  `new_place`, `known_place` (a return to a place already seen), `dialogue`, `untried_object` (once per thing never talked to within 3 cells), `blocked`, `stalled` (3
  attempts in a row walked no new cell), `no_frontier` (with the exits already tried), `locked`, `damage` or `budget` (600 frames). What it walked, the walls it found, the
  exits it tried and the things it offered are kept per place and rebuilt from the trace on resume.
- `goto row col` walks to a cell of the known grid by a shortest path with the fewest turns (stops `done`, `blocked`,
  `no_path`, ...; a result carries `blocked_at` when a move hit a wall; flow-51: a wall the grid believed open is avoided and the path planned again, up to 3 times, and the edges gone around are listed in `avoided`; flow-54: first it centres exactly and tries the edge once more, for stairs and narrow gaps; talk_to, attack and explore walk the same way); `step direction pixels` moves a few pixels;
  `talk_to row col` walks next to a person, faces them and presses A, trying other sides on no response; the person is
  the entity at or next to the cell, followed when it walks away, and may cover several cells; silent at talk reach, it
  tries once more pressed against the person.
- A scripted scene (Link held by `link_frozen`, e.g. a character arriving to speak, or something Link touches) stops any
  skill with `scene`; the harness waits through it until Link is free, advances its dialogues (past the 40-page cap once) and,
  after any lock, waits as long as the lock (up to 30 frames) before asking the model; `wait frames until_free` ends
  early when Link is free. Unidentified things on screen are offered as `examine-ROW-COL`.
- `attack row col` walks next to the enemy at or next to the cell, lines up within the measured sword reach, faces it
  and strikes with the sword's button until it dies (up to 6 strikes, walking up again after a knockback); it stops
  `done` (`killed`), `damage`, `refused` (no sword on A or B), `no_target`, `target_gone` (flow-53: also when a knockback puts it off the grid), `no_kill`, `out_of_reach` or
  `frame_cap`, and reports `strikes` and `hits`.
- A ledger counts blocked edges per place; an edge blocked twice is marked doubtful in the context, and an objective
  that keeps failing is abandoned as `unreachable`.
- Dialogue pages are advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once
  from page sheets.
- The agent writes a one-line `plan` that the next call sees; the live view shows its reasoning and plan under each
  decision.
- The agent sets its own long-term `goal`, restates or revises it at every objective (the context says when it was set) and, in the call that transcribes a text (dialogue, sign, object), extracts up
  to five leads (`quote`, `claim`, importance `high|normal|low|tip`, `tip` for how-to-play advice); a lead whose quote is not in that transcription is
  dropped. Both are trace events (`goal`, `lead`), shown in the context and the live view and written to `world.json`;
  an objective can cite the lead behind it (`because`). A lead may carry `where` (a place id such as `161-0` or a name the agent gave).
  A lead is `open` until an objective follows it, `tested` once one is achieved and `refuted` after 2 that failed (a loop, stall,
  unreachable target or restart does not count); the context shows the status with the last 3 of those objectives and lists open leads first.
- At `choose_objective` the context lists candidate objectives with ids (`candidates.rb`): untried exits by side (`exit-up`) and doors
  (`door-R-C`) of this place, people (`person-tT`, listed first) and unread signs (`sign-R-C`) here worth a visit, known places with untried exits
  (`place-R-M`), people and unread signs of other known places (from their place cards) and places tied to a lead by its `where`
  (`lead-N`), nearest first by moves over exits explore took. The agent answers with `candidate` (or still a free title and predicate);
  the objective event carries `candidate` and its `target`, which the autopilot follows. While a person here is not
  exhausted, every candidate that leaves the place says `leaves unexhausted people here: ...`.
- The agent may name the current place (`place_name`, any call): a `place_name` trace event, shown in the context header,
  `world.json` `places` (`name`) and the viewer's map.
- Screens are modes of the catalogue `data/modes.json`: the context names the open screen, how to leave it, its inputs,
  cursor and options, and offers only the skills that work there. `open_menu`/`close_menu` (START), `menu_move slot`
  (inventory cursor 0-9), `menu_assign a|b` (swap the selected item with that button's item), `open_map`/`close_map`
  (SELECT, B), `choose_option option` (save and game-over screens); used elsewhere they stop with `wrong_mode`. An
  uncatalogued screen gets `press` and `wait` and a `notable` `unknown_mode` in the trace; 600 frames on it stop the
  run as `unknown_mode_stuck`. Options that quit to the title are refused. The game-over screen is answered by the harness, free: it
  continues with the first option that does not quit (`notable` `death`); a health drop emits a `notable` `damage` and
  the next prompt's health line shows the hearts lost since the last model call. There is no low-health rule (flow-37); six fruitless results in one
  place without a new cell emit a `notable` `stuck` and a `STUCK` reset hint; a known place entered 4 times within 3600 frames
  with no new place emits a `notable` `stuck` (`loop: ...`) and a `LOOP` hint until a new place; the harness then explores toward
  the nearest place with untried work or, when none is left, toward the reachable place entered least outside the loop.
- The context header lists the items on A and B and in the inventory slots (`data/items.json` names; a `?` marks a name
  not measured yet). `use_item item [button] [frames]` uses a held item (assigning it through the START menu to `button`,
  default B, when it is on no button); `guard frames [direction]` raises the shield (Link walks at full speed and turns
  while guarding). A new item emits `item_gained` in the trace.
- Scrolling dialogue pages are stitched into one text; the context remembers what each person said and whether talking
  again is worth it; `new_text` is an objective predicate; the live view lists the dialogues read.
- People on screen come from the game's entity table in RAM (`entities.rb`): the context lists each entity with its cell,
  type id and measured kind (`data/entities.json`), sprites without an entity as a fallback, and the names people gave
  (`speaker`, asked in the transcription call); creatures (measured to give no dialogue) and unidentified entities are
  listed apart for information and are never offered as people to talk to. People are remembered by (place, entity type), so a person who moved
  keeps their memory.
- On arrival in a place, before the model is called, people and signs are engaged deterministically (`revisit.rb`, no
  model call to decide it): when a verified `npc` of the current place is not exhausted for the current world stamp
  (milestone, items held, number of high and normal leads; a place visited does not count) or a verified sign was never read, the policy issues `talk_to` itself (agent `delegated`,
  cost 0), lets the pages advance, and repeats until two conversations in a row are identical or give nothing new (a sign is read once), at
  most 6 rounds per person, 2 per sign, 1800 frames of free play per stamp and 2700 per visit (frames spent in
  dialogue pages or locked are not counted, so long dialogues never cut it short), 3 stamps per visit (counted by milestone and items, not leads), or 2 failed
  talks per visit; while one is due it replaces any choice, so no exit (model, autopilot, harness objective) happens first; never when hurt, hemmed, or near a hostile or moving unknown entity (a measured `creature` that gives no dialogue does not count); each round is
  a `notable` `revisit` event (`{npc|sign, round, outcome}`). Each new place also gets a `place_card` (people, enemies,
  creatures, signs, objects, exits) kept in `world.json` `places`. A conversation is identified by a signature of its pages' text pixels; a conversation
  already read is not sent to the model again (its stored text is reused, `dialogue` events with `cached: true`).

