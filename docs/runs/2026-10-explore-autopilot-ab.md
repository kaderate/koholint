# Explore autopilot A/B (2026-10-26)

Setup: `bin/koholint ab-plan runs/20261024-184627-b97e --at-frame 6100 --forks 3`, six runs forked from that frame (3 with `--autopilot on`, 3 with `--autopilot off`), `--agent --max-dollars 0.8 --frames 3000`, flow-13, all stopped on `frames` (no fallback). A first attempt on 2026-10-24 was cut by the Claude quota (`agent_failures`) and discarded. Raw runs: `tmp/ab/runs/` (not tracked).

| arm | runs | frames | usd | usd/1000f | calls/1000f | places/1000f | cells/1000f | stalls | autopilot decisions |
|---|---|---|---|---|---|---|---|---|---|
| autopilot | 3 | 9000 | 0.5985 | 0.0665 | 4.44 | 0.78 | 7.67 | 0 | 43 |
| off | 3 | 9000 | 0.9412 | 0.1046 | 7.33 | 0.67 | 5.78 | 0 | 0 |

Pre-registered criterion: cost per 1000 frames <= 50 % of `off` and places per 1000 frames >= 90 %. Result: cost ratio 0.636 (miss), places ratio 1.17 (pass). Decision: keep the autopilot on; tune toward 50 % (ROADMAP item 1). Caveats: 3 runs per arm, one zone, caps unmeasured.
