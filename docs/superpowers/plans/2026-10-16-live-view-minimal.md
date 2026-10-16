# Koholint Live View (minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `bin/koholint watch <run_dir>` serves a local web page showing the game screen, a status bar and the latest decisions/actions of a run, live while the run is going or after it ended, without any effect on the run.

**Architecture:** The video is derived, not recorded: a separate `Follower` process replays the run's input journal on its own emulator and renders frames, so the engine is untouched and determinism is preserved. A stdlib-only HTTP server on 127.0.0.1 serves `/` (page), `/frame.png`, `/state.json`; the page polls both. For the follower to stay live the input journal becomes append-only and durable per macro.

**Tech Stack:** Ruby 4.0.1, stdlib `socket`/`json`/`zlib`, minitest, no new gems.

**Spec:** `docs/superpowers/specs/2026-10-16-koholint-v2-architecture-design.md` (sections "Live view", "Run model"). Layout chosen by the owner is A + C; this plan does A only (video, decision/action feed, top status bar). The clickable timeline and fork-from-UI (C) are a later plan.

## Global Constraints

- Everything in the repo is English; comments almost none; commits one imperative line, no body; short hash syntax (`{ buttons:, frames: }`) wherever key and local match.
- Time is the frame; the viewer never writes into a run directory and never touches the engine's emulator.
- The server binds `127.0.0.1` only.
- Replay stays bit-exact; the viewer reports when its replay diverges from recorded `state_hash` events instead of hiding it.
- Tests: `rake test` (parallel, one process per file); ROM tests use `skip_without_rom!`; `EmulatorCache` for boot states.
- No new runtime dependency.

## Review Focus

- Viewer started on a run whose journal is being appended: a partially written last entry must be ignored, never crash or desync.
- Viewer started on a run with no keyframe yet, on an empty run, and on a missing or garbled run dir: one-line error or empty state, no backtrace.
- Viewer falling far behind a headless run (engine faster than real time): must show the lag and jump forward instead of drifting forever.
- Replay divergence (recorded `state_hash` differs): shown in the status, not silent.
- Port already in use: one-line actionable error.

---

### Task 1: PNG frames from the emulator

**Files:** Create `lib/koholint/png.rb`; Modify `lib/koholint/emulator.rb`; Test `test/png_test.rb`, `test/emulator_test.rb`

**Interfaces:**
- Produces: `Koholint::Png.encode(rgb: String, width:, height:) -> String` (binary PNG, 8-bit RGB, no filter, zlib); `Emulator#frame_rgb -> String` (160×144×3 bytes from `ppu.framebuffer.pixels_frame`, packed RGBA ints → R,G,B); `Emulator#frame_png -> String`.

- [ ] **Step 1: Tests.** `png_test`: encode a 2×2 image, parse the chunks by hand (signature, IHDR width/height/bit depth 8/color type 2, IDAT inflate, rows prefixed by filter byte 0, IEND, CRCs valid). `emulator_test`: after 60 boot frames `frame_rgb.bytesize == 160 * 144 * 3` and `frame_png` starts with the PNG signature; two emulators with the same inputs give equal `frame_png`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** both; reading the framebuffer must not change `state_hash` (assert it in the test).
- [ ] **Step 4: Run** → PASS. **Step 5: Commit** `Add PNG frame output to the emulator adapter`

### Task 2: Append-only, durable input journal

**Files:** Modify `lib/koholint/input_log.rb`, `lib/koholint/engine.rb`; Test `test/input_log_test.rb`, `test/hardening_test.rb`

**Interfaces:**
- Produces: format version 2: 1 header byte then 5-byte entries `(mask u8, count u32 LE)`, uncompressed, appended. `InputLog#flush` appends only entries not yet on disk (a run still growing is written as its own entry; readers coalesce equal consecutive masks). `InputLog.load` still reads version 1 files; opening a version 1 file for appending rewrites it as version 2 on the first `flush`. `InputLog.read_from(path, offset) -> [entries, new_offset]` returns only complete entries after a byte offset (ignores a partial trailing entry). `Engine` calls `flush` after every macro.

- [ ] **Step 1: Tests.** Round trip and RLE-small still hold; `flush_then_read_without_closing`; `partial_trailing_entry_is_ignored` (append 3 stray bytes); `read_from_returns_only_new_entries`; `version_1_files_still_load`; engine test: after one macro the on-disk journal has exactly the frames played (no waiting for a keyframe), and the old `test_journal_on_disk_covers_the_last_keyframe…` still passes.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (keep `each_frame`, `frames`, `append`). **Step 4: Run full suite** → PASS (fork, resume, verify depend on the journal).
- [ ] **Step 5: Commit** `Make the input journal append-only and durable per macro`

### Task 3: Follower (replay a run, live)

**Files:** Create `lib/koholint/viewer/follower.rb`; Test `test/follower_test.rb`

**Interfaces:**
- Consumes: `Run`, `Keyframes`, `InputLog.read_from`, `Emulator`, `Trace.read`.
- Produces: `Viewer::Follower.new(run_dir, from: :live, max_lag_frames: 1800)`; `#step_available(max_frames: 60) -> Integer` (steps as many frames as the journal now has, up to `max_frames`, returns frames stepped; pacing is the caller's job); `#frame -> Integer`; `#journal_frames -> Integer`; `#lag -> Integer` (journal frames minus own frame); `#frame_png -> String`; `#sync -> :in_sync | :diverged | :unknown` (compares `state_hash` of recorded `perception` events at frames the follower has passed). On start it restores the keyframe nearest below the live edge (or boots) and never opens the run lock. When `lag > max_lag_frames` it jumps to the nearest keyframe that reduces the lag. Raises `Koholint::Error` (one line) for a missing or garbled run dir.

- [ ] **Step 1: Tests (ROM).** After an engine run of 600 frames, a follower stepped to completion has `frame == 600` and `state_hash` equal to `Replay.to(run, 600)`; `sync == :in_sync`. Growing journal: append entries to a copy of the journal, `step_available` picks them up and frame grows. `partial_trailing_entry_is_ignored`. Empty run: `frame == 0`, no error. Tampered `state_hash` in a perception event → `:diverged`. Lag jump: a journal 4 000 frames ahead with keyframes jumps (frame >= nearest keyframe). Missing run dir → `Koholint::Error`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `Add the replay follower that renders a run live`

### Task 4: State feed

**Files:** Create `lib/koholint/viewer/feed.rb`; Test `test/feed_test.rb`

**Interfaces:**
- Produces: `Viewer::Feed.for(run_dir, follower, limit: 30) -> Hash` with `status` (`Summary.for` fields plus `run_id`, `flow_version`, `manifest_status`, `budget` from the manifest), `replay` (`frame`, `journal_frames`, `lag`, `sync`), `events` (last `limit` `decision` and `action` events condensed to `{frame, type, agent, choice|skill, params, confidence}`).

- [ ] **Step 1: Test** with a hand-built trace and a stub follower: the hash has exactly these keys, `events` is capped and ordered oldest to newest, perception events are excluded, an empty trace gives empty events and `health: 'progressing'`. **Step 2–4** FAIL → implement → PASS. **Step 5: Commit** `Add the live view state feed`

### Task 5: HTTP server and page

**Files:** Create `lib/koholint/viewer/server.rb`, `lib/koholint/viewer/page.html`; Test `test/server_test.rb`

**Interfaces:**
- Produces: `Viewer::Server.new(follower:, feed:, port: 0, host: '127.0.0.1')` where `feed` is a callable returning the state Hash (the CLI passes `-> { Viewer::Feed.for(run_dir, follower) }`); `#start -> Integer` (bound port; background thread, one thread per connection, `Connection: close`); `#stop`. Routes: `GET /` → page; `GET /frame.png` → `image/png` of `follower.frame_png`; `GET /state.json` → JSON of `feed.call`; anything else `404`; non-GET `405`. Port in use raises `Koholint::Error` (one line). The page (plain HTML + JS, no framework) shows the frame scaled ×3 with `image-rendering: pixelated`, refreshing every 100 ms; a top bar (run id, flow, health, hearts, frame, lag, sync, budget); a scrolling decision/action list refreshed every 500 ms; a "replay diverged" banner when `sync == 'diverged'`.

- [ ] **Step 1: Tests (no emulator, stub follower/feed objects).** Real TCP requests on an ephemeral port: `/` is 200 `text/html` and contains `frame.png` and `state.json`; `/frame.png` starts with the PNG signature; `/state.json` parses and has `status`; `/nope` is 404; `POST /` is 405; two simultaneous connections both answer; second server on the same port raises `Koholint::Error`; the socket is bound to `127.0.0.1` (check `local_address`). **Step 2–4** FAIL → implement (`TCPServer`, minimal request-line parsing, ignore headers) → PASS. **Step 5: Commit** `Add the local HTTP server and live page`

### Task 6: CLI, throttle, smoke test

**Files:** Modify `lib/koholint/cli.rb`, `lib/koholint/engine.rb`, `README.md`; Create `lib/koholint/viewer.rb`; Test `test/cli_test.rb`

**Interfaces:**
- Produces: `koholint watch <run_dir> [--port N] [--from live|start] [--speed X]` (prints `watching http://127.0.0.1:PORT`, loops `follower.step_available(max_frames:)` paced to `speed` × 60 frames per second (wall-clock pacing lives only in this loop) until SIGINT; exit 0 on SIGINT); `koholint run ... --realtime` makes the engine sleep so it plays at ~60 fps (a wall-clock pacing detail inside `Engine`, outside game logic); one-line errors via `Koholint::Error`.

- [ ] **Step 1: Tests.** `watch` on a missing dir exits 1 with one line; `watch` on a finished 300-frame run (spawn the process, request `/state.json` and `/frame.png` over HTTP, then SIGINT) returns `status.health == 'stopped'` and a PNG, exit 0; `run --realtime --frames 120` takes at least ~1.5 s of wall time.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5: Manual smoke test:** start `bin/koholint run --realtime` in the background and `bin/koholint watch` on its run dir; fetch `/frame.png` twice a few seconds apart, confirm the images differ, open one to look at it; confirm `verify` on that run still reports 0 diverged (the viewer did not disturb it). Record the evidence in the commit message.
- [ ] **Step 6: Commit** `Add the watch command and a realtime pacing option`

---

## Self-review against the spec
- Live view A covered (video, feed, status bar, headless same engine, trace-derived, derived video never versioned). C (timeline, fork from UI) deferred.
- The follower never uses the run lock, never writes in the run dir, does not alter the engine's determinism (Task 1 asserts frame reads leave `state_hash` unchanged).
- Side effect, on purpose: the journal change in Task 2 removes the kill -9 window between keyframes for inputs (the v1-style trace/journal gap), but keyframes remain the resume accelerator.
- Known limits: a headless run faster than real time outruns the viewer; it shows the lag and jumps. `run --realtime` keeps them together when watching matters.
