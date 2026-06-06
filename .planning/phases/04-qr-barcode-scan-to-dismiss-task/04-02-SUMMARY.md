---
phase: 04-qr-barcode-scan-to-dismiss-task
plan: 02
subsystem: scan-task-logic-seams
tags: [scan, qr, barcode, escape-hatch, normalize, pure-seam, tdd, ci, dismiss]
requires:
  - "minSdkVersion 23 + flutter_zxing 2.2.1 pin (04-01) — present so downstream widgets compile, though these two pure seams import neither"
provides:
  - "normalizeCode + codesMatch pure seam (SCAN-03 / D-MATCH-NORMALIZE) — the single source of truth for 'are these two codes the same?'"
  - "EscapeHatchController pure seam (SCAN-06/07 / D-ESC) — time-OR-attempts auto-dismiss + idempotent cam-failure fireNow"
  - "Two headless CI regression tests (code_match_test, escape_hatch_controller_test) covering every SCAN-03/06/07 behavior via flutter_test + fakeAsync"
affects:
  - "Plan 04 ring widget (scan_task.dart) — consumes normalizeCode/codesMatch on each decode and an EscapeHatchController instance (start/recordFailedAttempt/fireNow/dispose)"
  - "Plan 05 registration screen (scan_register_screen.dart) — calls normalizeCode BEFORE storing the registered code (normalize-both-sides invariant)"
tech-stack:
  added: []
  patterns:
    - "Pure dependency-free seam idiom (single owned Timer + injected callback + idempotent stop) mirrored from Phase-3 VolumeRampController"
    - "TDD RED (test commit) -> GREEN (feat commit) gate sequence per seam"
    - "fakeAsync-driven Timer testing for the elapsed-time branch (clock controls DateTime.now, fakeAsync controls Timer firing)"
key-files:
  created:
    - "lib/alarm/logic/code_match.dart"
    - "lib/alarm/logic/escape_hatch_controller.dart"
    - "test/alarm/logic/code_match_test.dart"
    - "test/alarm/logic/escape_hatch_controller_test.dart"
  modified: []
decisions:
  - "normalizeCode strips ASCII control chars [\\x00-\\x1F\\x7F] (incl. NUL/CR/LF/TAB/DEL) BEFORE trim+toLowerCase; null-safe (returns '') — case-fold-for-v1 (O1) accepted as the lenient default; the same transform runs at register AND compare so a trailing newline/whitespace/case diff can never false-reject."
  - "codesMatch guards storedNormalized.isEmpty -> false BEFORE the equality compare — the SCAN-07 save-gate safety floor; an unregistered task never auto-dismisses on any scan."
  - "EscapeHatchController defaults = 10 attempts OR 120s (D-ESC-DEFAULT single conservative pair; v1 UI exposes on/off only, D-ESC-EXPOSURE). _fire() is idempotent via a _fired flag and cancels the owned Timer."
  - "fireNow-vs-enabled asymmetry (SCAN-07, deliberate): the `enabled` toggle gates ONLY the threshold paths (start()'s timer + recordFailedAttempt()); fireNow() fires REGARDLESS of `enabled`, because a denied/unavailable camera must always surface the escape or the scan task would be un-dismissable (threat T-04-05)."
  - "Benign safety auto-dismiss ONLY (D-ESC-MODEL): plain time/attempts unlock, no Alarmy-style predatory Emergency-Escape friction (no guilt-pledge / escalating penalty)."
  - "escape_hatch_controller.dart uses a bare `void Function()` callback (not Flutter's VoidCallback typedef) so its ONLY import is dart:async — stricter than the acceptance criterion permitted."
metrics:
  duration: "~3 min"
  completed: "2026-06-06"
  tasks: 2
  files: 4
---

# Phase 04 Plan 02: Scan-Task Pure Logic Seams Summary

Authored the only two genuinely-new logic objects the scan-to-dismiss feature is
built on — `normalizeCode`/`codesMatch` (SCAN-03 / D-MATCH-NORMALIZE) and
`EscapeHatchController` (SCAN-06/07 / D-ESC) — as dependency-free pure seams plus
their headless CI tests, so every SCAN-03/06/07 behavioral guarantee runs in
`flutter test` (tests.yml) with no device, exactly as the Testing Policy demands.

## What Was Built

| Task | Requirement | Seam + Test | RED commit | GREEN commit |
|------|-------------|-------------|-----------|--------------|
| 1 | SCAN-03 | `code_match.dart` (`normalizeCode` + `codesMatch`) + `code_match_test.dart` | `98fc391` | `3a6696c` |
| 2 | SCAN-06, SCAN-07 | `escape_hatch_controller.dart` (`EscapeHatchController`) + `escape_hatch_controller_test.dart` | `4f43fd6` | `5b89cae` |

Both seams import zero camera/UI/audio package: `code_match.dart` has **zero
imports at all** (truly pure functions); `escape_hatch_controller.dart` imports
**only `dart:async`** (for `Timer`) and uses a bare `void Function()` callback
rather than Flutter's `VoidCallback` typedef — the strictest possible purity,
mirroring the Phase-3 `VolumeRampController` discipline (single owned `Timer` +
injected callback + idempotent `cancel`/`dispose`).

## Why These Choices

- **Strip-before-trim, case-fold (O1):** `normalizeCode` removes ASCII control
  chars (`[\x00-\x1F\x7F]` — NUL, CR, LF, TAB, DEL) **before** `.trim()` so an
  embedded control byte never survives, then `.toLowerCase()`. Case-folding is
  the lenient v1 default (fewer false rejects); it is applied identically at
  register and compare, so it is internally consistent and reversible in one
  line if it ever false-accepts (threat T-04-06, accepted).
- **Empty-stored safety floor (SCAN-07):** `codesMatch` returns `false` the
  instant the stored side is empty, before any equality check — an unregistered
  task can never auto-dismiss on a scan. This is the logic half of the Plan-05
  D-REG-REQUIRED save gate.
- **fireNow-vs-enabled asymmetry (SCAN-07):** the most consequential decision.
  The `enabled` toggle gates only the *threshold* escape (`start()`'s timer +
  `recordFailedAttempt()`); `fireNow()` — the camera-denied / camera-unavailable
  path — fires **regardless** of `enabled`. If the toggle also gated `fireNow`, a
  user who disabled the threshold escape and then hit a dead camera would have an
  **un-dismissable alarm**, violating the core "never trap the user" guarantee
  (threat T-04-05). The doc comment states this rationale and a dedicated test
  asserts it (`enabled:false` → `fireNow()` still fires once).
- **Idempotent single-fire:** `_fire()` is guarded by a `_fired` flag and cancels
  the owned `Timer`, so the time-OR-attempts race never double-fires — proven by
  two race tests (9 attempts + 120s → 1; 10 attempts before 120s → 1, with the
  later timer elapse asserting no second fire).
- **TDD gate sequence:** each seam landed as a `test(...)` RED commit then a
  `feat(...)` GREEN commit, per the plan's `tdd="true"` discipline.

## TDD Gate Compliance

Both seams follow the mandated RED → GREEN sequence in git history:

- Task 1: `98fc391` test(04-02) → `3a6696c` feat(04-02)
- Task 2: `4f43fd6` test(04-02) → `5b89cae` feat(04-02)

No REFACTOR commit was needed (the GREEN implementations match the RESEARCH
verbatim shapes; no cleanup pass changed behavior).

**Important honesty note on RED:** the Flutter/Dart toolchain is ABSENT in this
environment (CLAUDE.md / STATE.md), so the RED commits could not be *observed*
failing locally — `flutter test` cannot run here. The test files are authored to
fail against a non-existent seam (RED) and pass against the committed seam
(GREEN); both the RED-fails and GREEN-passes states are **owed via CI** and are
NOT claimed as locally executed. This is the standard discipline for this
toolchain-absent repo (mirrors Phase 2/3 plans).

## Test Coverage (authored; authoritative gate = CI)

**`code_match_test.dart` (SCAN-03):** trailing-newline + case-fold collapse to
the same value; surrounding whitespace trimmed; NUL + control chars + DEL (0x7F)
stripped; null → `''`; CRLF round-trip matches the bare code; wrong code does not
match; **empty stored never matches** (both `('anything','')` and `('','')`).

**`escape_hatch_controller_test.dart` (SCAN-06/07, fakeAsync):** time branch
(119s → 0, 120s → 1, drain → still 1); attempt branch (9 → 0, 10th → 1, more →
still 1); time-OR-attempts race both directions (never double-fires); `fireNow()`
immediate + exactly once + inert afterward; `enabled:false` threshold paths never
fire; `enabled:false` `fireNow()` STILL fires (the SCAN-07 asymmetry);
`dispose()`/`cancel()` before threshold → silent afterward; custom injectable
thresholds honored.

## Deviations from Plan

None — plan executed exactly as written. No Rules 1–4 deviations were triggered;
both tasks were pure-seam authoring with no discovered bugs, missing
functionality, or blockers.

One implementation refinement (within plan latitude, not a deviation): the plan's
acceptance criterion allowed importing Flutter's `VoidCallback` typedef "if
needed". It was not needed — a bare `void Function()` keeps the controller's only
import `dart:async`, which is strictly purer and still satisfies AC1.

## Owed CI Gates (NOT run locally — toolchain absent)

Per CLAUDE.md and STATE.md, Flutter/Dart is absent in this environment. The
following were **authored and statically verified (grep/read), NOT executed**:

- **`flutter test test/alarm/logic/code_match_test.dart`** and
  **`flutter test test/alarm/logic/escape_hatch_controller_test.dart`** — run via
  `tests.yml` (`flutter test --coverage`) on push; the authoritative behavioral
  gate. Both the RED-fails and GREEN-passes states are owed via CI. NO push was
  performed (user-authorized only — remotes are outward-facing).
- **`flutter analyze`** on the two new `lib/` files — via `test-apk.yml`
  (informational). Not run locally.

`fake_async` is already resolved as a transitive dependency (`pubspec.lock`
line 285, same as the Phase-3 `volume_ramp_controller_test.dart` uses) — no new
dependency was added, and `pubspec.yaml`/`pubspec.lock` were not touched.

## Static Verification Performed (local, not behavioral)

- SCAN-03 purity: `code_match.dart` has zero `import` lines; no
  `flutter|flutter_zxing|just_audio` import; no `logger`/`print`.
- SCAN-03 logic: `normalizeCode` contains `RegExp(r'[\x00-\x1F\x7F]')`, `.trim()`,
  `.toLowerCase()`, and `if (raw == null) return ''`; `codesMatch` has the
  `if (storedNormalized.isEmpty) return false;` guard before the equality return.
- SCAN-06/07 purity: `escape_hatch_controller.dart` imports only `dart:async`; no
  forbidden import; no `logger`/`print`.
- SCAN-06/07 logic: `_fired` flag + `if (_fired) return;` guard; `if (!enabled)
  return;` in both `start()` and `recordFailedAttempt()`; `fireNow()` calls
  `_fire()` with no `enabled` guard; defaults `maxFailedAttempts = 10` and
  `elapsedThreshold = const Duration(seconds: 120)`; `cancel()`/`dispose()` cancel
  the owned `Timer?`.
- Tests: `code_match_test.dart` asserts every `<behavior>` case;
  `escape_hatch_controller_test.dart` uses `fakeAsync` (9 cases) covering all six
  required branches plus a custom-threshold case.
- No file deletions in any of the four task commits; no stub patterns
  (`TODO`/`FIXME`/placeholder) in either seam.

## Notes for Downstream Plans

- **Plan 04 ring widget** wires: `onScan` → `codesMatch(normalizeCode(code.text),
  storedNormalized) ? onSolve() : (haptic + escape.recordFailedAttempt())`;
  `onControllerCreated(_, exception) { if (exception != null) escape.fireNow(); }`
  (SCAN-07); `start()` when the scanner opens; `dispose()` on every exit path
  (SCAN-11 — the controller's timer must not outlive the widget).
- **Plan 05 registration screen** must call `normalizeCode(code.text)` BEFORE
  storing into the "Registered Code" `StringSetting` (normalize-both-sides
  invariant). The Plan-05 save gate (D-REG-REQUIRED) can rely on
  `codesMatch`'s empty-stored floor as a backstop, but should also block save on
  an empty stored code directly.
- `recordFailedAttempt()` must be called ONLY on a non-matching VALID decode
  (never raw frames) — `ReaderWidget.scanDelay` (1000ms) rate-limits upstream so
  distinct non-matching reads arrive ~1/sec (RESEARCH Pitfall 2).

## Self-Check: PASSED

All four created files exist on disk; all four task commit hashes
(`98fc391`, `3a6696c`, `4f43fd6`, `5b89cae`) exist in git history.
