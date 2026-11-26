# Agent skills

The skills, protocols and harness behaviours the agent works with. Versioned with the play flow (currently `flow-103`): update this page, not the README, when a flow changes. Layers and data flow are in [ARCHITECTURE.md](../ARCHITECTURE.md).


- Learned capabilities (`data/capabilities.json`, `bin/koholint capability list`): an `operational` entry is a composite of the skills below, offered in the skill schema and listed under "Learned skills" only while its trigger item is held (flow-49) and its object is on screen (today `sword_on_object_92 row col direction`: stand next to object 92, face it, use the sword, step into its cell). `explore` and `goto` also run it themselves when blocked facing such a cell, and the planner routes through those cells as a last resort. `learn` and `capability publish|retire` are offline commands.
- Between decisions the engine waits, with no input, until Link is ready (no screen scroll, door walk, jump or
  knockback, then 2 settled frames): the screen is never mapped and the model never called mid-scroll or mid-jump
  (`notable` `not_ready_wait` for waits over 5 frames; the run stops with `not_ready_stuck` after 600 frames).
- `explore [direction]` (relaunched by the autopilot after benign stops, see Running in [OPERATING.md](OPERATING.md)) explores by itself: it walks to the nearest
  untried border exit (a side never left from this place) or untried door (walking up into it), else toward the nearest
  place it has taken an exit to that still has untried exits or doors (flow-67: the cells beside a learned hole, a look Link fell
  through more often than he walked onto it, are no frontier and are crossed by explore or goto only when no other route
  exists, though a goal there is still reached (flow-70: never on the way to a frontier, neither when explore picks it
  nor on the leg that walks there, so a frontier only reachable past a hole is left unexplored); flow-72: a cell Link already walked into is never a frontier, even one explore treats as pushable (the cell of an uncleared capability target or of a still enemy), so explore no longer steps back and forth across it; flow-66: a door already walked through is never a frontier,
  even when it is no door object, and routes go through it like a door object;
  flow-55: or, if surveyed before the capability existed, a tile
  the capability has cleared elsewhere, listed with its source in the route's `clearable`; inferred from the trace when a run is forked or resumed, not during a live run's first visit), else to the nearest frontier (a known cell next to
  an unknown one) (`direction` prefers that side), steps out, re-plans, and returns to the model only at an event:
  `new_place`, `known_place` (a return to a place already seen), `dialogue`, `untried_object` (once per thing never talked to within 3 cells), `blocked`, `stalled` (3
  attempts in a row walked no new cell), `no_frontier` (with the exits already tried), `locked`, `damage`, `budget` (600 frames),
  `enemy` (an enemy to fight on sight, flow-90) or `fell` (Link starts to fall, flow-90).
  flow-68: at one heart or less the autopilot hands every decision to the model; walk, goto and explore keep out of every
  enemy contact zone grown by a cell (the extra ring only as a last resort, the contact zone never, a goal inside one still
  reached), and from inside one Link may take any step that does not head toward an enemy within a cell of its touch
  (flow-73: judged from where he stands, not from his cell's centre); walk stops `danger`
  otherwise, and goto's `no_path` cause names the contact zones. What it walked, the walls it found, the
  exits it tried and the things it offered are kept per place and rebuilt from the trace on resume. flow-56: a dialogue the game opens by
  itself while Link stands flush against his cell's edge during a leg or step (a rock too heavy to push) bars that edge for the rest of
  the call (in `blocked_edges`), so the place's `pending` work leaves out what lies only behind it; elsewhere it bars nothing.
- `goto row col` walks to a cell of the known grid by a shortest path with the fewest turns (stops `done`, `blocked`,
  `no_path`, ...; a result carries `blocked_at` when a move hit a wall; flow-51: a wall the grid believed open is avoided and the path planned again, up to 3 times, and the edges gone around are listed in `avoided`; flow-54: first it centres exactly and tries the edge once more, for stairs and narrow gaps; talk_to, attack and explore walk the same way); `step direction pixels` moves a few pixels;
  `talk_to row col` walks next to a person, faces them and presses A, trying other sides on no response; the person is
  the entity at or next to the cell, followed when it walks away, and may cover several cells; silent at talk reach, it
  tries once more pressed against the person (counted as contact only once Link stays still past the frames that follow A).
  `touch row col type` (flow-84) is the harness's own: it walks next to the thing and holds into it, one side after another,
  and reports `picked_up` from the item bytes between arrival and the game settling; you are never offered it.
- A scripted scene (Link held by `link_frozen`, e.g. a character arriving to speak, or something Link touches) stops any
  skill with `scene`; the harness waits through it until Link is free, advances its dialogues (past the 40-page cap once) and,
  after any lock, waits as long as the lock (up to 30 frames) before asking the model; `wait frames until_free` ends
  early when Link is free. Unidentified things on screen are offered as `examine-ROW-COL` (flow-88: picking a sprite one starts its objective, which the trace
  refused until then, so the pick fell back to a wait). flow-60: locks less than 30
  frames apart are one scene, so each release waits as long as the scene so far, up to 30 frames. The harness's settle wait
  (`wait frames until_held`) ends when Link is held again, and Link is not ready while health is still being added
  (`pending_heal`, reason `healing`): together these wait out the flickering hold of a healing scene.
- When Link is hemmed in (blocked with no movement in 4 directions at the same position), the harness waits 120 frames at
  a time with no model call, up to 1800 frames. flow-63: after each wait it steps 2 pixels (up, right, down, left in turn),
  so a hold that ends unseen hands Link back to the model after one wait.
- flow-57: `damage` means Link's health once the pending damage has drained (`pending_damage`, 0xDB94) fell: a hit stops a
  skill on its own frame with its whole loss, and the drain that follows (one unit every 2 frames) stops nothing.
- `attack row col` walks next to the enemy at or next to the cell, lines up within the measured sword reach, faces it
  and strikes with the sword's button until it dies (up to 6 strikes, walking up again after a knockback; flow-73: never
  from inside the enemy's touch, its `contact_px` or 9 px when unmeasured, plus 2, and when backing off is walled it lines
  up on the other axis); it stops
  `done` (`killed`), `damage`, `refused` (no sword on A or B), `no_target`, `target_gone` (flow-53: also when a knockback puts it off the grid), `no_kill`, `out_of_reach`, `hole`
  (flow-90: a lineup step would enter a hole) or `frame_cap`, and reports `strikes` and `hits`. flow-61: its target is the thing nearest the cell (an enemy only on a tie),
  and when Link already stands on or next to the target's cell he strikes from there instead of walking to another cell
  next to it, which the pieces of a split enemy can all block. flow-65: after an attack that stops `done` or `target_gone`,
  the harness attacks the nearest other `enemy` within 2 cells itself, or an unidentified type already struck in this
  visit, never the slot just struck (it stays listed while it dies), with no model call. It hands back to the model when
  no target is left, health is below 2 hearts or a heart below its level at the last call, an attack stops any other
  way (a room change is one: `room_change` ends the chain), or after 8 attacks or 900 frames since that call (checked
  before each attack, so the last one may run past it). The viewer counts no autopilot decision as an objective attempt.
- A ledger counts blocked edges per place; an edge blocked twice is marked doubtful in the context, and an objective
  that keeps failing is abandoned as `unreachable`.
- Dialogue pages are advanced automatically (one `decision` with agent `delegated` and cost 0 per page) and read once
  from page sheets.
- The agent writes a one-line `plan` that the next call sees; the live view shows its reasoning and plan under each
  decision.
- The agent sets its own long-term `goal`, restates or revises it at every objective (the context says when it was set) and, in the call that transcribes a text (dialogue, sign, object), extracts up
  to five leads (`quote`, `claim`, importance `high|normal|low|tip`, `tip` for how-to-play advice; flow-86: `need: true` when a person
  asks Link for something, kept only for a person's text); a lead whose quote is not in that transcription is
  dropped. Both are trace events (`goal`, `lead`), shown in the context and the live view and written to `world.json`;
  an objective can cite the lead behind it (`because`). A lead may carry `where` (a place id such as `161-0` or a name the agent gave).
  A lead is `open` until an objective follows it, `tested` once one is achieved and `refuted` after 2 that failed (a loop, stall,
  unreachable target or restart does not count); the context shows the status with the last 3 of those objectives and lists open leads first.
  flow-58: a text the game opens while Link presses toward something (the edge it bars) also becomes a `normal` lead on its own, whatever the agent
  extracts: its quote is the text read, its `source` and `contact` name the cell pressed toward and what is in it (a catalogued npc's type, else the
  object id, never an id Link has stood on in that place or one filling a tenth of the room, a ground kind), its `where` is the place, and its claim says only that contact with that thing opened the text.
  There is one such lead per thing and text (a text overlapping an earlier one about the same thing, or any lead already quoting it in that place, is dropped), at most 5 per place, and they never
  change the dialogue stamp, so they do not reopen people.
  flow-59: a lead whose claim or `where` names a catalogued item (name or alias) that neither any text the run has read (earlier texts, the whole
  transcription, earlier lead quotes) nor any item Link has ever held (`Items.held_ids`, cumulative) names is dropped (`LeadCheck.named`, the rule `check-leads` applies to traces) and recorded as a `lead_leak` notable, so it never reaches a prompt. flow-86: a claim naming a person, a role or a thing
  (`data/vocabulary.json`) that no text read names is withheld: the lead stays, and its quote is shown in place of the claim and of its `where` (only the place id the `where` resolves to, if any).
- At `choose_objective` the context lists candidate objectives with ids (`candidates.rb`): untried exits by side (`exit-up`) and doors
  (`door-R-C`) of this place (flow-84: a side known only as the way back you came in by says so and comes after them), people (`person-tT`, listed first) and unread signs (`sign-R-C`) here worth a visit, known places with untried exits
  (`place-R-M`), people and unread signs of other known places (from their place cards; flow-62: a person exhausted
  under other held items or another milestone is offered again, once; flow-86: an unidentified thing never tried, seen still in one cell
  on two looks while Link held other items, is offered among them as `examine-R-M-tT`, and a place whose only work is such a thing, still on its last two looks, is a place with work; a roaming one is not)
  and places tied to a lead by its `where`; flow-86: every person who asked for something (a lead marked `need`) and has not
  answered with a new text since, once Link holds other items than at the last talk with them (`need-tT` here, `need-R-M-tT` away, all of them),
  (`lead-N`), nearest first by moves over exits explore took (flow-69: never through a pocket, so a place routes cannot reach
  is not offered; a sign elsewhere is a `new_text` objective the autopilot walks to and reads, done only when that sign's text is read, not on arrival or on
  another text met on the way). The agent answers with `candidate` (or still a free title and predicate);
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
  the next prompt's health line shows the hearts lost since the last model call. Low health has one rule (flow-68): at one heart or less (`health <= HP_PER_HEART`) the autopilot holds (`low health`), so the model
  takes every decision, and walk, goto and explore grow every enemy contact zone by a cell, crossed only as a last resort (the contact zone
  never); the disengage walk below steps away from a near enemy. Six fruitless results in one
  place without a new cell emit a `notable` `stuck` and a `STUCK` reset hint; a known place entered 4 times within 3600 frames
  with no new place emits a `notable` `stuck` (`loop: ...`) and a `LOOP` hint until a new place; the harness then explores toward
  the nearest place with untried work outside the loop (flow-66: the loop's places are not aimed at, only crossed) or, when none is left, toward the reachable place entered least outside the loop.
- flow-74: the explore log keeps every destination seen through a way (a side or a door) and compares the first crossing of a way with
  the way back it assumed, else the screen next to it on the overworld map (16 rooms wide, measured). A crossing that lands elsewhere is a
  `puzzle` event (`unexpected_arrival`, `refuted`) and assumes no way back; a second destination through the same way is a `contradiction`,
  routed through (to its most observed destination) only when nothing else reaches the goal; a way back assumed from another map predicts nothing.
  The header shows the last two puzzles of the place once per visit as `PUZZLE (observed, not explained): ...` lines, and `summary.json` counts them per place and kind.
- flow-75: the offline exit bench (`koholint bench exits`) measures each way of a puzzle place from its keyframes; in the same milestone and
  held items, its edges fill the ways the run never crossed (`one lineage` marks an edge measured in a single run lineage), and the PUZZLE line
  says what it reached, which ways it did not reach, and whether every way reached and none led somewhere new (then the outcome depends on the
  context, with the leads read there). A `puzzle-R-M` candidate ("investigate ...") is offered first, at most once per run and context, while a
  puzzle place has an open lead about it and no conclusive bench in the current context.
- flow-76: while a place has an open puzzle (no conclusive bench in the current context), the header quotes every text read there in full,
  each once, as `TEXT READ HERE (quoted in full while a puzzle here is open): « ... »`: a lead keeps one sentence, and a low lead is never shown again.
  It appears at every objective decision there and at the first decision of each visit, newest texts first within 2,000 characters; a text cut
  by that budget ends with `... (cut)`.
- flow-78: explore treats a side known only as the assumed way back (never crossed) as an untried exit; it cuts a clearable object
  only on the way to an untried exit or door or an unknown cell that is not an object, and a cell Link stood in on an earlier visit is
  never a frontier. A way explore could not reach from the side Link came in by, on two visits, is no longer routed through from that side: the cut lasts until a new item or milestone, or until a crossing from that side takes the way (flow-84: a cut no
  longer expires after a number of visits, and a place entered through a door or a walk-in exit is entered by that way, so a way unreachable from that landing
  is cut too; flow-86 below adds landings reached without a crossing and the count of calls within one visit).
- flow-82: a stone (object 167) slides one cell when Link holds a direction into it for 32 frames and the cell beyond is floor; walk, goto and explore
  keep pressing that long before they report `blocked`, wait for it to land and stop `pushed`; goto routes and explore frontiers cross a stone only in a
  direction it slides, and the things on screen list such stones. Object 166 is a stone that does not move, and the room puts stones back on re-entry.
- flow-89: explore no longer routes through stones on the way to an exit. When an untried exit or door, or the way its route takes, is reached only
  by moving stones, it searches the pushes first (`Navigation::Stones`: breadth first over the stone positions of the live room objects, each stone
  sliding one cell onto floor and landing fixed, from the cells Link walks to) and makes the first push of the fewest that open it, as a `push`
  target, ranked by the exit or door it opens; it stops `pushed` and the next explore searches again on the fresh screen. The search stops at
  1000 states (the result then says `stone_search: cut short`). A push target passes the same filters as any target (blocked and doubtful edges,
  triggers). Before holding a push, Link steps to the stand's centre across the push, since a few pixels off the hold doubles or never ends; a
  push that still leaves its stone in place (`failed_push`) is never planned again in that visit. A room whose exit still needs a
  push keeps pending work. A stone ahead of an unknown cell is still a frontier. Leaving a visit that pushed a stone drops the room's cuts,
  since its stones are back on re-entry; the second-visit and spent-cut memories stay, so a way shut by anything else is cut
  again at its first finding, and a visit that pushed nothing lifts nothing. Cuts elsewhere are kept.
  Within a place, explore takes a side known only as the assumed way back (flow-78) after the place's other reachable untried exits, doors and frontiers;
  it is still a frontier, taken when nothing else here is reachable, before a route to another place. An explore that stops `no_frontier`
  in at most one frame is answered by the harness at the next decision, not after three, since from the same cell it would find none again.
- flow-103: a dialogue that stops explore's walk to an exit or a door counts that way as unreachable from the landing, so a
  second such stop cuts it (as a dialogue on a frontier already did). An attack that did not hurt Link (`done`, `target_gone`,
  `hole`, `out_of_reach`) leaves an objective's target for the autopilot to follow, through the wait after it; damage still
  hands the choice back. Path skills blocked from one spot count their blocked direction toward the hemmed latch, and an explore
  that finds no frontier without walking keeps the count, so a scene that holds Link (the heal) is waited out without calls.
- flow-102: a reachable souvenir naming an item Link holds by the words of its pickup text is taken up by the harness before
  the model is asked, as a lineage text naming a held item is: talk with it held, then use it. Each souvenir is taken once
  (read back from the trace on resume); a drop is offered again by the flow-101 re-offer rules.
- flow-101: explore never plans a walk into a stone on screen, even one whose look was walked on after a push emptied its cell, so
  the stone search's pushes open the way. At one heart or less, an objective whose route crosses a place where enemies were seen
  first goes to the nearest place where a talk healed Link (read from the hp rises after a dialogue), up to twice, and the heal
  objective holds until Link's hp rises, however many people the place shows. Sent back by the same side of a place twice within 3000 frames, the third time
  marks the place guarded: the objective is set aside and explore heads for work elsewhere. A need or souvenir objective a loop break,
  heal detour or guard set aside is offered again once per drop, up to twice, while the menu still offers it. The heal
  detours, retreats and re-offers are read back from the trace on resume. A souvenir is retired once its item, used in
  its place, opened a dialogue and left both buttons. A frontier whose walk opened a dialogue twice, on any visits, is no work there.
- flow-100: the harness never waits beside a hostile at any health: when explore finds no way out while a hostile's contact zone
  reaches Link's cell or a neighbour, it sends explore back by the side Link came in at once (once per cell, until Link changes
  place or heals). Fight on sight also takes an enemy whose two sword hits are verified, not only one-strike ones. A cell
  doubted on every side (two blocked attempts per side) forgets those doubts: Link stands on it, so it was a hold such as a healing scene, not four walls.
  Above half health one `damage` stop in a place no longer ends fights there: verified enemies are still fought until a second one or half health.
- flow-99: souvenirs. A text a person said in another branch (`data/souvenirs.json`, the run's `souvenirs` cutoff) whose words hold the
  name of an item Link holds, by flow-97's rule or a name of `data/items.json` that the item's observed pickup text quotes, read by
  someone who did not hold it, from a person this lineage never heard say it nor talked to holding the item, at a place this lineage's
  own routes reach, becomes candidate `souvenir-<place>-t<type>`: its label quotes the text as a souvenir of another playthrough, never
  heard in this one, and its target is flow-97's delivery (talk holding the item, then use it). It takes the slot of the candidate for
  the same place and person or thing; with none it joins the people here or ends the list. Souvenirs appear nowhere else in the context
  and never count as texts read for leads. A picked candidate whose target is still to try is not refused for its place being reached.
  A pickup name is the capitalised words right after an article in the first sentence; one letter is no name, and a text opened more
  than 600 frames before the gain names nothing.
- flow-98: at one heart or less, when explore finds no way out of a place (every route crosses a hostile's contact zone), the harness
  sends explore back by the side Link came in, as from a closed pocket: at once while a hostile's contact zone reaches Link's cell or
  a neighbour, else after three waits at the same cell that changed nothing; once per cell until Link changes place or heals above
  one heart, so a way back out of reach too falls back to the waits. A disengage step takes Link farther from every enemy in
  touch, never into or beside another hostile's contact zone, and never in a direction the grid or a blocked walk from that cell shows
  walled (kept across model calls; a danger stop is not a wall); with no such step, none is taken. An enemy an attack only could not
  reach is fought on sight again once it comes within a cell, twice a visit at most.
- flow-97: an item gained takes its name from its pickup text, the first text transcribed at its place after it shows as held (within
  600 frames, never an earlier text): the first run of capitalised words of its first sentence, past the first word (`Items.name_words`;
  the same rule rebuilds it from the trace on resume). After a gain, the people and unidentified things of other places this lineage
  never read are all candidates past the cap of four, nearest first, then those of places no known route reaches yet, nearest on the
  map; without a gain the cap holds. A candidate no known route reaches whose objective stalled is not offered again until a route to
  it appears. At an objective choice, a person whose recorded text holds that name as whole words in a row, and
  who never talked with Link holding the item, becomes the objective (picked by the harness): Link talks to them holding it, then the
  harness uses it facing them; only that item used after the talk ends the objective. It is picked again for that person only once
  Link read a new text from them or a route to them appeared. A step of explore a hostile knocked Link back from just before it failed
  (`knocked_edges` in the result) is barred for that call only: it is no wall, no blocked edge and no tried exit, and the place's work
  stays pending; from the third knock on that step in one visit it is learned like any failed step.
- flow-96: an examine- objective is achieved only once the thing at its place is tried: talk_to first, then touch when the talk drew
  no answer (an answered talk, or a dialogue that opens as Link walks up to it, is a try); the agent is told so; the autopilot follows each of those steps once, even when the model's own explore brought Link
  there. The walk probe records a way, like a wall, only from a start lined up with the row or column
  it crosses (Link sliding under a rock on a row edge read as a way into it), and a dialogue the game opens while explore pushes flush
  against a cell, with no person or unidentified thing on screen and no object ahead that could have spoken (`too_heavy` in the
  result), records that cell's appearance as no way in that direction. A talk or touch tries the thing only when it reached it, and
  the autopilot makes those two steps at any health.
- flow-95: a still sprite stands only on the cells holding at least half of it each way (a person straddling a cell edge evenly still
  stands on both sides), and never on the cell Link stands on, so a speaker that stops a few pixels into his cell no longer walls him in.
- flow-94: below full health (`health < max_hp`, one heart or less included) the harness walks to a heart on screen with no model call, right after
  the disengage step and before any fight: the nearest entity whose catalogued `heals` is verified (type 45), visible (a still sprite on its cell,
  whose background tile was walked before; a heart hidden under a pot or a bush has no sprite) and outside every enemy contact zone (a cell wider at
  one heart or less, as the planner draws them then), by a safe touch of its slot, which walks to a cell beside it on a route that never
  crosses a contact zone (or gives up) and holds into it; any heal settles a touch at once, so no other side is tried, and the touch ends
  `target_gone` when the slot stops holding the heart with no heal counted. A pickup that ends `done` or `target_gone` keeps the
  autopilot chain going, as if the touch had not happened. Each slot is aimed at once per visit of a place, 2 at most per visit.
- flow-93: an attack strikes from reach: its walk ends as soon as the target is inside the sword's measured reach, and once the target has
  come closer between two frames the lineup no longer backs off, since backing off from an enemy that walks at Link never opens the gap;
  it turns to face it and strikes. A route never aims at a place whose untried ways are all cut off from the side the route lands by,
  whatever that place's survey left pending (a lifted cut counts as open); an assumed way back no path reaches is reported unreachable
  like any other untried exit, so it is cut from that landing too; the result lists it as `held` as well, and a held way back is never
  dropped from the graph, since health returning or an enemy leaving can open it again (one a route found out of reach on two dead-end
  visits is still dropped, as before). The lineup forgets an approaching enemy when it turns to another target. Object 176 is a hole like 174 and 175.
- flow-91: no skill stands on floor that gives way past its time. The game counts the frames the cell under Link's foot point
  (`link_foot`, 4 px below him) has been crumbling floor (`crumble_timer`), starts over when that cell changes and drops the cell
  into a hole at its `give_way` value (40 for object 223). While the game is in play, every skill's step (goto, explore, touch with
  its hold and settle, talk_to, wait, walk and the attack lineup; never a menu or a dialogue) checks it first from the skill's second
  frame on: when the shortest step that takes the foot point onto another floor cell (crumbling floor included, since the
  count starts over there; never a hole, live ones included) would just fit in the frames left, Link takes that step to the end, and a
  step that leaves him in place for 2 frames is retried another way. A step that would put the foot point into a hole that opened after
  the skill planned ends the skill (`hole`). The autopilot never tries an untried object cell a catalogued enemy stands on. An unaimed explore
  whose only reachable way on is the side Link came in by, after the routes it preferred proved unreachable, reports `dead_end`, so
  that landing becomes a pocket.
- flow-90: holes and crumbling floor are read from the live room objects. Objects 174 and 175 are holes wherever they appear
  (the grid's `hole_objects`, never walked, with their margin); object 223 is a floor that becomes a hole when Link stands on it
  about half a second, and the room restores it on re-entry; it counts as crumbling in a place only once one of its cells there was
  seen turning into a hole (the engine traces `floor_gave_way` once per place and object), since the same object also fills cells
  outside the walls of rooms where it never gives way. Above one heart the harness fights on sight with no model call:
  the nearest `enemy` within 32 px whose `sword_hits` is 1, or 2 when verified (flow-100; explore stops `enemy`, a stop the autopilot treats as benign), up to
  8 attacks per call, never while Link's footprint (his measured row band) covers a crumbling cell, never again in the visit of a place where an
  attack stopped `damage` twice, or once at half health or below (above it only enemies with verified sword hits; flow-100; model calls in between included), and never again a slot an attack missed there (`blocked`, `no_path`, `out_of_reach`, `no_kill`, `hole`)
  or the slot just struck; a fight on sight never starts the flow-65 chain of fights after a kill.
  The attack strikes from where Link stands when its target is within 2 cells of him, turns to any enemy that comes nearer than its
  target within 2 cells, and stops `hole` before a lineup step enters a hole. Explore stops `fell` as soon as Link starts to fall.
  An untried exit or door that no path reaches and that is not the way back is reported `unreachable`, so it is cut, except in a
  room with crumbling floor, whose holes come and go. The least-visited place explore heads for skips one whose landing from here
  is a pocket.
- flow-81: a closed treasure chest (object 160) is untried work like an unread sign, but only while a route on the current grid reaches the cell below it:
  the revisit opens it with `talk_to` (walk up into it from below, then A; no model call, 2 rounds per chest), it is a `chest-R-C` objective candidate
  (`chest-R-M-R-C` for a place where one was seen reachable), and the things on screen list each chest as open or closed with the cell to open it from
  (or `no known route to that cell`). A chest that gave no response stays off the work list for the rest of that visit, and a chest objective ends once its chest is open. The Items line gives the rupee count (`rupees: N`). The engine traces `chest_opened` and summary.json counts it.
- flow-80: when every place with untried work is reachable only through cut ways, explore routes through the oldest cut not yet tried
  instead of stopping `no_frontier`; each cut is tried once until a new item or milestone. Three explores that find no frontier and walk
  no cell on one visit of a place (moves between them do not count; a new item, lead or goal, or a longer non-move skill starts over)
  are answered by the harness: it explores toward the nearest place with untried work, else toward the reachable place entered least,
  else waits. The autopilot also goes on exploring after a dialogue that brought no new lead or goal, after an arrival while
  the objective's target cannot be followed from here, and steps up through a door when your `goto` ended on the cell right below it.
- flow-86: a place reached without a crossing from where Link was (a continue after a game over, a jump) is entered by a landing of its own
  (`:landed`), never by the stale entry of an earlier visit. A way explore finds unreachable from a landing is cut from that landing when it is
  found on two visits, or on `CUT_CALLS` (3) calls within one visit; the count starts over on each new visit and when Link crosses that way from
  that landing, which also lifts the cut. A cut lasts for the context (items and milestone) otherwise.
- flow-79: an uncatalogued entity (kind unknown) on screen whose type no `talk_to` ever aimed at in this place, and the objects an
  `untried_object` stop named, are tried once by the autopilot with `talk_to` (nearest first, no model call, at most 6 per visit, outside the chain caps) before it
  explores on; results show as `(autopilot) talk_to`. A place whose last card lists such an entity counts as untried work for explore's
  route, like an untried exit. `world.json` lists, per place, each unknown type's `tries`, `answered` (a dialogue opened) and `moved`
  (talk_to had to chase it) in `unknown_types`, and the `items_gained` there.
- flow-83: a still uncatalogued entity whose `talk_to` try gave nothing (`no_response`, `no_path`, `frame_cap`, `blocked`,
  `target_free`) and which is still in the cell the try aimed at is touched once per visit by the harness
  (`touch`, nearest first, no model call, sharing the 6 tries per visit), because a thing that does not answer may still be
  picked up. A pickup is read from the item bytes alone (the inventory and the rupee count), between Link's arrival next to
  it and the game settling there (no text box, Link free and controllable; a scene or a text in between is read as usual and
  the bytes are judged once it has settled, within 900 frames of arrival), so nothing met on the way counts. The harness
  explores on afterwards either way. `world.json` counts each type's `touched` and `picked_up`
  in `unknown_types` and keeps a top-level `pickups`: every type a touch picked something up from, with each touch as
  provenance, `observed` from one place and `verified` from 2.
- flow-77: entering a place with an open puzzle and texts read there, with no objective of yours current, ends the harness's own objective
  and asks you once for the next objective with those texts in the header; whatever comes back, the harness takes over again after that
  one ask. It asks again only after a new text was read there or with a new item or milestone. A loop hint is dropped once Link is
  outside the looped places. When `puzzle-R-M` is a candidate, the texts read in that place are quoted beside it
  (`TEXT READ IN R-M ...`, same budget). An objective you write is no longer replaced by a loop break during its first 1,800 frames.
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
- Answers and fallbacks: an invalid model answer falls back deterministically to a 30-frame wait, and 5 fallbacks in a row stop the run
  (`agent_failures`); an engine exception before the model call is an `engine_error` fallback counted apart, 5 in a row stopping the run as
  `engine_errors`. Autopilot decisions leave both counts untouched; loop and stall abandonment still apply to them.
- Screens and locks: once the run has played, a menu, map, save or uncatalogued screen goes to the model with its own skills only, after a
  deterministic wait while it is still opening. A `cutscene` (the dying animation included) waits like `locked`, in waits that end the frame
  Link is free (flow-50). A hold that outlasts the 900-frame wait cap emits one `notable` `lock_cap`, and the model decides from then on.
- Dialogue caps: a dialogue that reaches its page or frame cap is sent as sheets once and advanced on (the model's choice is replaced while the
  box is open); only a second cap of the same dialogue hands the pages to the model. A dialogue that opens with no current objective is
  advanced before a new objective is asked for.
- Leads in the context: every `high` lead, the `normal` ones of the current place and the 4 newest tips, never `low` ones. A lead dropped
  because its quote is not in the transcription is counted in a `notable` `lead_rejected`; duplicates are dropped by quote. A lead stops being
  a `lead-N` candidate once refuted or once an achieved objective reached the place it points to. `new_text` compares the stitched text
  whitespace-insensitively with the texts read before in the run.
- flow-68 disengage: at one heart or less with an enemy within a cell of its touch, the harness walks one cell in the direction with no enemy
  ahead that ends farthest from them, skipping directions a walk found blocked (or refused at once for danger) since the last model call and
  cells on or beside a learned hole, up to 3 times per model call; the model decides after. There is no retreat and no shelter candidate.
- Loop break (flow-44, flow-47): at the next skill or objective decision after a loop detection, once per detection, the harness abandons the
  current objective (reason `loop`) and starts its own new-place objective; when no known place has untried work, it starts a `reach_place`
  objective toward the reachable place entered least outside the loop, nearest first.
- Zero cap (flow-45): after 3 identical results of at most one frame in one place (same skill and stop), the harness answers the next skill
  decision itself with a `notable` `stuck`: it explores toward the nearest place with untried work, unless its own explore already came back
  instantly in this streak, else it waits 120 frames; its own answers keep the count until a result takes more than a frame or the place changes.
- Autopilot details beyond OPERATING's Running section: a `known_place` stop does not count in the 6-explore chain, but a third return to the
  same place goes back to the model; an objective with a `target` is followed from the first skill decision after the model's call, and a new
  goal from that call does not hold it.
- A skill that ends its move with Link off the grid (a border crossing whose room id changes only after the scroll) waits up to 120 frames for
  the room change. A capability that ran on an object without clearing it is recorded in the explore log (`failed_clears`), and that cell is no
  longer a frontier there. Revisits of people wait while a surveyed place still has untried work.

