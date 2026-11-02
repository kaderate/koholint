# Arrival protocol lot B: live run and autopilot A/B (2026-11-02)

Flow-16: candidate menu at `choose_objective` (ids, structured `target` followed by the autopilot), place names, lead `where`, autopilot relaunch after `untried_object` and harness-picked `new_place` objectives after a chain reaches a place.

## Live run `20261102-075426-e333` (tag `lotb-1`, harness `3d7db58`)

`--agent --realtime --grid --max-dollars 1 --minutes 30`, stopped on `dollars` at frame 10927.

| frames | usd | calls | calls/1000f | usd/1000f | places | objectives (achieved) | by candidate | picked by the harness | talk_to (talked) | place names |
|---|---|---|---|---|---|---|---|---|---|---|
| 10927 | 1.005 | 54 | 4.94 | 0.092 | 8 | 14 (13) | 11 | 3 | 15 (12) | 2 |

All 11 model objectives were picked by id; 21 autopilot decisions. Two defects seen and fixed in `a23d21b` before the A/B: the door Link had just come out of was offered as `door-4-5` and re-entered the house (a door Link stands on or just below is no longer a candidate), and a `new_text` sign target left behind by the agent's own explore was routed back to, ping-ponging 146/0 and 162/0 for 1800 frames (only `reach_place` targets are routed to now). The sign at (4,5) of 146/0 answered no `talk_to` three times (unmeasured cause).

## A/B (harness `a23d21b`)

`bin/koholint ab-plan runs/20261102-075426-e333 --at-frame 7760 --forks 3`, 3000 frames per fork, `--max-dollars 0.8`, all six stopped on `frames`. The old anchor (`20261024-184627-b97e`, flow-13) was replaced by this flow-16 run; `off` disables the chained explores, the target following and the harness-picked objectives together.

| arm | runs | frames | usd | usd/1000f | calls/1000f | places/1000f | cells/1000f | stalls | autopilot decisions |
|---|---|---|---|---|---|---|---|---|---|
| autopilot | 3 | 9000 | 0.6975 | 0.0775 | 5.67 | 2.78 | 7.33 | 0 | 43 |
| off | 3 | 9000 | 1.6058 | 0.1784 | 13.11 | 2.11 | 7.89 | 0 | 0 |

Criterion (cost per 1000 frames <= 50 % of `off`, places >= 90 %): pass, cost ratio 0.434, places ratio 1.32. Objectives after the fork: autopilot arm 23 (9 by candidate, 14 picked by the harness), `off` arm 27 (25 by candidate); `talk_to` talked in 10 of 21 (autopilot) and 10 of 21 (`off`). Caveats: 3 runs per arm from one frame in one zone; the `off` cost is higher than the old baseline (0.1046) because the zone and anchor differ; caps (6 explores, 2400 frames) still unmeasured. Total spent: 3.31 USD.
