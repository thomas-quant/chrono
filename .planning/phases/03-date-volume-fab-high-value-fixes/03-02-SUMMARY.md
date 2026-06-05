---
phase: 03-date-volume-fab-high-value-fixes
plan: 02
subsystem: audio
tags: [flutter, dart, timer, fake_async, ringtone, volume-ramp, cancellation]

# Dependency graph
requires:
  - phase: 02-snooze-reliability
    provides: "the dismiss/snooze paths (_resolveDismiss, isolate dismiss branch) that funnel into RingtonePlayer.stop()/pause() — the ramp cancel terminus"
provides:
  - "VolumeRampController — a pure, audio-free, cancellable Timer-based ramp controller with an injected volume callback"
  - "RingtonePlayer drives the rising-volume ramp through one owned cancellable controller; cancel() is the only ramp-stop signal (decoupled from setVolume)"
  - "CI fake_async coverage proving clean cancel, no late callback, no cross-alarm bleed, reaches-max, zero-duration"
affects: [scan-task, alarm-notification-screen, audio-hardening]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure cancellable Timer controller with an injected void Function(double) callback as the testability seam (extracted from a static service)"
    - "fake_async virtual-time unit testing for Timer-based logic (clock package governs DateTime, not Timer firing)"

key-files:
  created:
    - lib/audio/types/volume_ramp_controller.dart
    - test/audio/types/volume_ramp_controller_test.dart
  modified:
    - lib/audio/types/ringtone_player.dart

key-decisions:
  - "Reimplemented #467 independently with sole credit per D-PR-METHOD — no contributor attribution, no co-author trailer, no PR reference anywhere"
  - "cancel() is the ONLY ramp-stop signal; a plain setVolume() no longer cancels the ramp (decouples the live volume port from ramp death)"
  - "A plain mid-ring setVolume() leaves the ramp running and does NOT retarget the ceiling (safe default per research Open Q1 — flagged for user confirmation at review)"
  - "Used fake_async (transitively available) for deterministic Timer tests — no new dependency, no tick-callback fallback needed"

patterns-established:
  - "Pure controller + injected callback seam: extract time-based logic out of a static audio service into an audio-free, unit-testable unit"
  - "fake_async + async.elapse + a recorder callback list as the standard CI test shape for cancellable Timer logic"

requirements-completed: [VOL-01, PR-01]

# Metrics
duration: 7min
completed: 2026-06-05
---

# Phase 3 Plan 02: Rising-Volume Ramp Cancellation (VOL-01 / PR-01) Summary

**Extracted a pure, audio-free `VolumeRampController` (single owned `Timer` + injected `void Function(double)` callback + real `cancel()`) and rewired `RingtonePlayer` so the rising-volume ramp climbs to max then stops cleanly on dismiss/snooze — replacing 11 fire-and-forget `Future.delayed` callbacks and the conflated static `_stopRisingVolume` flag, and decoupling "stop the ramp" from "set the volume."**

## Performance

- **Duration:** ~7 min
- **Completed:** 2026-06-05
- **Tasks:** 3
- **Files modified:** 3 (2 created, 1 modified)

## Accomplishments

- **VOL-01 fixed at the root:** the ramp is now one cancellable, tracked `Timer` with a real `cancel()`. It stops the instant the alarm is dismissed/snoozed (`stop()`/`pause()` cancel it), reaches the configured target on the final step, and starting a second alarm's ramp emits no stray ticks from the first (`start()` cancels first; `_play()` re-entry cancels too) — no cross-alarm bleed.
- **The decoupling holds:** `setVolume()` no longer sets `_stopRisingVolume = true`. A plain live volume write (the dismiss-task volume-lowering routed through the isolate volume port → `setVolume()`) no longer silently and permanently kills the ramp. `cancel()` is the only ramp-stop signal.
- **`_stopRisingVolume` removed entirely** — the static flag that conflated every legitimate volume write with "kill the ramp" is gone. `RingtonePlayer` stays a static class (Tier-1; only the ramp mechanism changed).
- **CI-runnable coverage authored** (`fake_async`, virtual time): no-callback-after-cancel, no-cross-alarm-bleed, reaches-max, zero-duration. No new dependency.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define VolumeRampController (pure, cancellable, injected callback)** — `543d3b7` (feat)
2. **Task 2: Wire VolumeRampController into RingtonePlayer; decouple cancel from setVolume** — `1b7015e` (fix)
3. **Task 3: CI ramp test — cancel, no-late-callback, no-bleed, reaches-max (fake_async)** — `9460796` (test)

_Note: this `tdd="true"` plan authored the controller (Task 1) and wiring (Task 2) before the test (Task 3) per the plan's explicit task ordering — the plan's `<verify>` for Task 1 states "MISSING — Task 3 creates the test". The Flutter/Dart toolchain is absent locally, so the RED/GREEN ordering could not be observed via a runner; CI is the authoritative gate. See TDD Gate Compliance below._

## Files Created/Modified

- `lib/audio/types/volume_ramp_controller.dart` (NEW) — pure, audio-free `VolumeRampController`: single `Timer? _timer`, injected `void Function(double)` callback, `start({targetVolume, duration, steps})` that cancels first then steps `0 → targetVolume` via `Timer.periodic`, `cancel()` that nulls the timer, `bool get isRunning`. Zero/negative duration (or `steps <= 0`) applies the target immediately with no timer. Imports no audio package. `logger.t` lifecycle.
- `lib/audio/types/ringtone_player.dart` (MODIFIED) — holds one static `VolumeRampController` whose callback wraps `activePlayer?.setVolume`; `_play()` starts the ramp via `_rampController.start(...)` and cancels on re-entry; `pause()`/`stop()` cancel the ramp; `setVolume()` no longer touches the (now-deleted) `_stopRisingVolume` flag.
- `test/audio/types/volume_ramp_controller_test.dart` (NEW) — four `fake_async` tests; a plain recorder callback (no `just_audio`); `async.elapse(...)` for virtual time.

## Decisions Made

- **Sole-credit independent reimplementation (D-PR-METHOD):** built from scratch using standard `Timer.periodic` + `cancel()`; no contributor attribution, no co-author trailer, no reference to PR #467 in any code, comment, or commit message. (Verified by grep across all changed files and commit messages — clean.)
- **`cancel()` is the only ramp-stop signal:** removed `_stopRisingVolume` from `setVolume` so a legitimate live volume write can never accidentally kill the ramp.
- **Safe default for mid-ring volume writes (research Open Q1):** a plain `setVolume()` while ringing leaves the ramp running and does **not** retarget the ceiling — the minimal correct fix that satisfies VOL-01. **Surfaced for the user to confirm at review** (whether a user lowering volume mid-task should *cap* the ramp's eventual target is a separate product call, not required by VOL-01).
- **`fake_async` over a tick-callback:** `fake_async` is transitively available (pubspec.lock:285), so the controller stays a plain `Timer.periodic` and the test advances virtual time. The plan's tick-callback fallback was not needed.

## Deviations from Plan

None — plan executed exactly as written. The only judgement call was rewriting the no-cross-alarm-bleed test to use **two independent controllers each recording into its own list** (rather than re-starting on a single controller and inferring A's silence from value thresholds). This is a strictly clearer expression of the same `<behavior>` ("no further A-tick is recorded after B started") and the same single-ramp/re-entry invariant the plan describes — not a scope or behavior change.

## TDD Gate Compliance

This plan is `type: execute` with two `tdd="true"` tasks, but the plan deliberately sequences implementation (Task 1 controller, Task 2 wiring) **before** the test (Task 3) — Task 1's `<verify>` explicitly says the test is "MISSING — Task 3 creates it." So the standard RED-before-GREEN commit ordering (`test(...)` then `feat(...)`) does **not** appear in the git log; the order is `feat → fix → test`. This is intentional per the plan, not a gate violation. Because the Flutter/Dart toolchain is absent locally, neither RED (failing test) nor GREEN (passing test) could be observed via a runner — **CI (`tests.yml` on push) is the authoritative gate**, and the test was authored against the finalized Task 1 API.

## Issues Encountered

- **Pre-existing commented-out dead code left untouched:** `ringtone_player.dart` contains an old commented-out `// Future.delayed(...)` block (an unrelated auto-stop-after-duration stub) directly after the ramp. It is **not** the ramp loop (which was removed) and predates this plan — left in place per the deviation scope boundary (only fix what the current task's changes touch). A `grep 'Future.delayed'` on the file matches only this commented line; there is zero live `Future.delayed`.

## Owed Verification (CI / human gates — toolchain absent locally)

- **`flutter test test/audio/types/volume_ramp_controller_test.dart`** — owed via CI (`tests.yml` → `flutter test --coverage` on push). The four ramp tests are the authoritative behavioral gate; never reported as locally passing (Flutter/Dart absent here). Source-level `<verify>` greps all pass (see below).
- **`flutter analyze`** on `volume_ramp_controller.dart` + `ringtone_player.dart` — informational, owed via `test-apk.yml` dispatch; expect no NEW issues.
- **On-device (CI genuinely cannot run):** real `just_audio` ramp audibly climbs to max then stops the instant the alarm is dismissed/snoozed; lowering volume while solving a dismiss task does not freeze/kill the ramp; a second alarm shows no stray bumps from the first.

### Source-level verification performed (in lieu of the absent runner)

- `lib/audio/types/volume_ramp_controller.dart`: `class VolumeRampController` present; `cancel()` (line 41) precedes `Timer.periodic` (line 55) — start-calls-cancel-first invariant; zero `just_audio`/`audio_session` import; `cancel()` nulls `_timer`.
- `lib/audio/types/ringtone_player.dart`: one `_rampController.start(`; three `_rampController.cancel()` (in `_play` re-entry, `pause`, `stop`); zero `_stopRisingVolume`; zero live `Future.delayed` (one commented-out line only); imports `volume_ramp_controller.dart`; class still static.
- `test/audio/types/volume_ramp_controller_test.dart`: imports `package:fake_async/fake_async.dart`; four `test(...)` cases; `fakeAsync` + `async.elapse` used; no `await Future.delayed`; reaches-max asserts the configured target; `pubspec.yaml`/`pubspec.lock` unchanged.
- Clean-room: grep across all three files and the commit messages for `467|co-authored|contributor|pull request|cherry-pick` → none.

## Deferred (NOT done here — for the next `/gsd-transition`)

- **Reword PR-01, PR-02, and ROADMAP Phase-3 success-criterion #4** to drop "crediting the contributor" — a required downstream consequence of D-PR-METHOD (sole credit). The plan explicitly instructed NOT to reword them here; flagged for the next transition.

## Next Phase Readiness

- VOL-01 / PR-01 are source-complete; ready for the phase verifier once CI confirms green. The remaining FAB fix (FAB-01 / PR-02) is the sibling Plan 03 in this wave-1 phase.
- One product question is open for the user at review: should a mid-ring user volume change *retarget* the ramp ceiling? Current safe default: no (ramp continues to its configured target). Not required by VOL-01.

## Self-Check: PASSED

- Files: all 4 found (`volume_ramp_controller.dart`, `ringtone_player.dart`, `volume_ramp_controller_test.dart`, `03-02-SUMMARY.md`).
- Commits: all 3 found (`543d3b7`, `1b7015e`, `9460796`).

---
*Phase: 03-date-volume-fab-high-value-fixes*
*Completed: 2026-06-05*
