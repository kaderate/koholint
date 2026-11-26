# $0 stub gates

A gate forks a checkpoint run and plays it for 12000 frames with a stub in place of the model (`stub.rb`), so it costs nothing and gives the same numbers at the same code. The gate then checks five numbers against `expected.json` for the run's `flow_version`.

The stub picks a souvenir first, else a person or thing Link holds other items for, else a new place. It tries the objective's person (`talk_to`, then `touch`), closes map and menu screens, and explores otherwise.

Run gates from the repository root, with `$KOHOLINT_ROM` set, one or two at a time:

| gate | checkpoint | command |
|---|---|---|
| respawn-171 | 20261124-191800-abbe @95758 | `caffeinate -dims ruby tools/gates/gate.rb respawn-171` |
| post-gain-172 | 20261124-191800-abbe @94304 | `caffeinate -dims ruby tools/gates/gate.rb post-gain-172` |
| sword-obtained | 20261111-194737-9ba1 @60404 | `caffeinate -dims ruby tools/gates/gate.rb sword-obtained` |

- `all` plays the three in turn.
- `--root DIR` sets where the forks go (default `~/.capy/work/runs/gates`).
- `--check RUN_DIR` checks a fork already played. It refuses a fork of another checkpoint.
- Checkpoint runs are looked up under the `roots` of `gates.json`.
- The exit status is 0 when every number matches. It is 1 on a mismatch, or when the flow has no expected numbers yet.

A change to the play flow either keeps every number or states the change in its pull request and adds the new numbers to `expected.json` under its `flow_version`.

## Expected numbers

| flow | gate | calls | calls at ≤8 hp | hp lost | deaths | first delivery |
|---|---|---:|---:|---:|---:|---:|
| flow-110 (0533699) | respawn-171 | 81 | 78 | 16 | 0 | 100019 |
| flow-110 | post-gain-172 | 63 | 0 | 4 | 0 | 99292 |
| flow-110 | sword-obtained | 74 | 54 | 8 | 1 | — |
| flow-111 (a07990bb) | respawn-171 | 69 | 0 | 12 | 0 | 100084 |
| flow-111 | post-gain-172 | 65 | 0 | 4 | 0 | 99292 |
| flow-111 | sword-obtained | 74 | 54 | 8 | 1 | — |

What each number counts, from the fork frame on:
- **calls:** decisions the stub answered.
- **calls at ≤8 hp:** those taken at 8 hp or less.
- **hp lost:** health drops between decisions.
- **deaths:** `death` notables.
- **first delivery:** the frame of the first `use_item` that opened a dialogue.

## Reading a fork

- `ruby tools/gates/metrics.rb RUN_DIR` prints the five numbers.
- `ruby tools/gates/timeline.rb RUN_DIR` prints one line per decision, objective, and damaging or blocked action.
