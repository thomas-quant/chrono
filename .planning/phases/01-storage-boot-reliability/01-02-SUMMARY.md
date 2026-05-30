---
phase: 01-storage-boot-reliability
plan: 02
subsystem: boot
tags: [direct-boot, fbe, defer-until-unlock, time-box, idempotent-reschedule, isolate, manifest]

# Dependency graph
requires:
  - "01-01: non-throwing loads (loadList/SettingGroup.load recover instead of throw) — the time-boxed/guarded boot paths only degrade gracefully because corrupt/partial state recovers"
provides:
  - "isDeviceLocked() defer-until-unlock probe (lib/system/logic/device_lock.dart) — API-gated no-op < API 24, probe-and-catch in the boot isolate — BOOT-02 / D-07"
  - "Hardened handleBoot(): defers when locked; initializeIsolate() now inside the try/catch (no crashed isolate with partial state) — BOOT-01 / BOOT-02"
  - "Time-boxed main() storage+reschedule init (8s) — runApp(App()) always reached, no permanent splash hang — BOOT-01 / D-06"
  - "Confirmed updateAlarms/updateTimers as the single idempotent reschedule funnel (the D-08 spine) — preserved unchanged for Phases 2 and 4 — BOOT-03"
affects: [03-alarms-lost-notice, snooze-reliability, qr-scan-dismiss]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Defer-until-unlock boot guard: probe-and-catch a cheap CE-storage read (getApplicationDocumentsDirectory); any throw => locked => defer"
    - "Time-boxed init segment via an inline async closure + .timeout(), with logger.f on timeout/failure and unconditional fall-through to runApp"
    - "Single idempotent reschedule funnel (cancel-by-stable-id then schedule) shared by boot path and app launch"

key-files:
  created:
    - lib/system/logic/device_lock.dart
  modified:
    - lib/system/logic/handle_boot.dart
    - lib/main.dart
    - android/app/src/main/AndroidManifest.xml

key-decisions:
  - "Unlock-detection mechanism = B (probe-and-catch), NOT A (native MethodChannel) — the boot isolate has no MainActivity/FlutterEngine, so a MainActivity-scoped channel is unreachable there (resolves RESEARCH Q2)"
  - "Manifest narrowed (belt-and-suspenders): dropped LOCKED_BOOT_COMPLETED from Chrono's BootBroadcastReceiver intent-filter; aamp RebootBroadcastReceiver left untouched; MainActivity directBootAware left in place (resolves RESEARCH Q1)"
  - "Time-box duration = 8s for the storage+reschedule segment only (research-suggested 6-8s, D-06 discretion)"
  - "MainActivity.kt NOT modified — mechanism B needs no native code, keeping the change Tier-1 minimal"

patterns-established:
  - "Pattern: isDeviceLocked() at the head of any Chrono-owned boot isolate entry point, before any storage touch"
  - "Pattern: wrap only the storage+reschedule segment (not the whole init) in .timeout(); fall through to runApp on any failure"

requirements-completed: [BOOT-01, BOOT-02, BOOT-03]

# Metrics
duration: 4min
completed: 2026-05-30
---

# Phase 1 Plan 02: Boot Guard + Time-Boxed Splash + Idempotent Reschedule Summary

**Defer-until-unlock boot guard (probe-and-catch, no native code), a time-boxed main() init that always reaches the UI, and confirmation that updateAlarms/updateTimers are the single idempotent reschedule spine — the core boot-reliability fix, on top of Plan 01's non-throwing loads.**

## Status

Tasks 1 and 2 (autonomous) are complete and committed. **Task 3 is a blocking
`checkpoint:human-verify`** (on-device reboot-before-unlock validation on a
secure-lock FBE Android device) and has been returned to the orchestrator for
human verification — it is NOT self-approved and was NOT performed here (no FBE
device and no Flutter toolchain in this environment; there is no software
fallback for the pre-unlock crash reproduction).

## Performance

- **Duration:** ~4 min (autonomous tasks)
- **Tasks:** 2 of 3 complete; 1 blocking checkpoint pending human verification
- **Files modified:** 4 (1 new + 3 modified)

## Accomplishments

- **BOOT-02 / D-07 (defer-until-unlock):** New `lib/system/logic/device_lock.dart`
  exposes `Future<bool> isDeviceLocked()`. `handleBoot()` now calls it at the very
  top, before any storage touch, and logs + returns early (`logger.i`) when the
  device is locked. The OS redelivers `BOOT_COMPLETED` after unlock, so deferring
  loses nothing. No more `IllegalStateException` on `LOCKED_BOOT_COMPLETED`.
- **BOOT-01 / BOOT-02 (no crashed isolate with partial state):** `initializeIsolate()`
  — which touches credential-encrypted storage — was moved from OUTSIDE the
  try/catch to INSIDE it, so a pre-unlock storage throw is caught (`logger.f`)
  rather than crashing the boot isolate with partial reschedule state.
  `@pragma('vm:entry-point')` and the `FlutterError.onError` handler are preserved.
- **BOOT-01 / D-06 (time-boxed splash):** In `main.dart`, the storage+reschedule
  segment (`initializeStorage` → `initializeSettings` → `updateAlarms` →
  `updateTimers`) is wrapped in `.timeout(const Duration(seconds: 8))`. A timeout
  or any error is caught (`logger.f`) and execution falls through;
  `runApp(const App())` is reached on every path. `Future.wait(initializeData)`
  is left outside the timeout.
- **BOOT-03 / D-08 (idempotent funnel preserved):** Confirmed (read-only) that
  `updateAlarms`/`updateTimers` are the single idempotent reschedule funnel called
  by BOTH `main()` and `handleBoot()`, and that `scheduleAlarm` cancels by stable
  `scheduleId` before `oneShotAt`. Left unchanged — this is the D-08 spine Phases
  2 and 4 reuse.

## Resolved Research Questions

- **RESEARCH Q2 (boot-isolate reachability) → mechanism B chosen.** `handleBoot()`
  runs in a background isolate spawned by `flutter_boot_receiver`'s
  `BootHandlerService` (a `JobIntentService`) with NO `MainActivity` /
  `FlutterEngine` attached. A `MainActivity`-scoped `MethodChannel` (mechanism A)
  is therefore not reachable from the boot isolate. Confirmed in-repo: the only
  live `com.vicolo.chrono/documents` channel is registered by plugins, and
  `MainActivity`'s declared `CHANNEL` constant has no handler wired. So the guard
  uses **mechanism B (probe-and-catch)**: it attempts a cheap
  `getApplicationDocumentsDirectory()` read; any throw means CE storage is
  unavailable (device locked) → defer. This needs no native code and is robust in
  the boot isolate. `MainActivity.kt` was intentionally NOT modified.
- **RESEARCH Q1 (manifest narrowing) → narrowed, minimally.** Dropped
  `LOCKED_BOOT_COMPLETED` from Chrono's `com.flux.flutter_boot_receiver.BootBroadcastReceiver`
  intent-filter so `handleBoot` can't fire pre-unlock at the OS level
  (defense-in-depth; the Dart guard is primary because some OEMs deliver
  `BOOT_COMPLETED` itself before full unlock). The aamp `RebootBroadcastReceiver`
  was left untouched (it re-arms from its own store and may legitimately need
  early arming), and `MainActivity`'s `directBootAware="true"` was left in place
  to avoid risking the alarm full-screen-intent-over-lock-screen path.
- **RESEARCH A4 (scheduleId stability / idempotency) → confirmed.** `scheduleAlarm`
  (`schedule_alarm.dart`) removes the prior `scheduleId` from the persisted
  `*_schedule_ids` list, calls `AndroidAlarmManager.cancel(scheduleId)` BEFORE
  `oneShotAt(startDate, scheduleId, ...)` — same stable id replaces, never
  duplicates. `updateAlarms`/`updateTimers` each `cancelAll` then reschedule, so
  re-running (boot-then-launch) re-arms exactly once. No change needed beyond the
  boot guard.
- **Time-box duration:** 8s (within the research-suggested 6-8s; tune on-device).

## Task Commits

1. **Task 1: Defer-until-unlock guard + isDeviceLocked() + try/catch fix (BOOT-02/BOOT-01/D-07)** — `284f1f6` (feat) — `device_lock.dart` (new), `handle_boot.dart`, `AndroidManifest.xml`
2. **Task 2: Time-box main() init + preserve the idempotent reschedule funnel (BOOT-01/BOOT-03/D-06/D-08)** — `f247448` (feat) — `main.dart`
3. **Task 3: On-device reboot-before-unlock verification** — BLOCKING CHECKPOINT, returned to orchestrator (not committed; no code change — human verification step)

## Files Created/Modified

- `lib/system/logic/device_lock.dart` (new) — `isDeviceLocked()` probe-and-catch
  (mechanism B); API-gated no-op < API 24; `FLUTTER_TEST` guarded; null-safe when
  `androidInfo` is unset in the boot isolate; documents why mechanism A was rejected.
- `lib/system/logic/handle_boot.dart` — defer-until-unlock guard at the head of
  `handleBoot()`; `initializeIsolate()` moved inside the try/catch;
  `@pragma('vm:entry-point')` preserved.
- `lib/main.dart` — storage+reschedule segment wrapped in `.timeout(8s)` with
  `TimeoutException`/general catch (logger.f) and unconditional fall-through to
  `runApp`; `Future.wait(initializeData)` left outside the timeout; imported
  `dart:async` + `logger`.
- `android/app/src/main/AndroidManifest.xml` — removed `LOCKED_BOOT_COMPLETED`
  from Chrono's `BootBroadcastReceiver` intent-filter (with explanatory comment);
  aamp `RebootBroadcastReceiver` and `MainActivity` directBootAware untouched.

## Decisions Made

- **Mechanism B (probe-and-catch) over A (native MethodChannel)** for unlock
  detection in the boot isolate — the boot isolate has no FlutterEngine, so A is
  unreachable there; B needs no Kotlin, keeping the change Tier-1 minimal.
- **Minimal manifest narrowing** (Chrono's boot receiver only) as belt-and-
  suspenders; Dart guard remains primary and mandatory.
- **8s time-box** on the storage+reschedule segment only — "never infinite" is
  the goal, not "fast."
- **Did not modify `MainActivity.kt`** — no native code is needed for mechanism B.

## Deviations from Plan

None — plan executed as written. The plan explicitly left the unlock-detection
mechanism (A vs B) and the manifest-narrowing decision to be made during the task
based on actual boot-isolate reachability; both decisions are recorded above
under Resolved Research Questions.

## Issues Encountered

**Flutter/Dart toolchain unavailable — automated verification not run.**
No `flutter`/`dart` binary is present in this environment (WSL or the Windows
mounts). The plan's automated checks could NOT be executed:
- `flutter analyze lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart` — NOT RUN (deferred — requires `flutter analyze` on Flutter 3.22.2 before merge).
- `flutter build apk --debug --flavor dev` (Kotlin compile) — NOT APPLICABLE: `MainActivity.kt` was not changed (mechanism B), so no native compile is needed for this plan.

What was done instead — toolchain-free source assertions, all passing:
- `@pragma('vm:entry-point')` preserved on `handleBoot` (line 8).
- `isDeviceLocked()` guard is at the head of `handleBoot`, before any storage
  touch (line 26), with an early `return`.
- `initializeIsolate()` now appears AFTER the `try {` line (line 32 → call at
  line 36) — confirmed by grep.
- `device_lock.dart` exports `isDeviceLocked()`, returns `false` when
  `androidInfo` sdkInt < 24, and is `FLUTTER_TEST`-guarded.
- `lib/main.dart` contains `.timeout(` (line 61) and catches `TimeoutException`
  (line 62); `runApp(const App())` (line 74) is after the try/catch (reachable on
  every path); `Future.wait(initializeData)` (line 45) is outside the timeout.
- `update_alarms.dart` / `update_timers.dart` show no diff (funnel unchanged).
- The only remaining `LOCKED_BOOT_COMPLETED` in the manifest (line 105) is on the
  aamp `RebootBroadcastReceiver`, intentionally left untouched.

**Action required:** A developer with Flutter 3.22.2 should run
`flutter analyze lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart`
to confirm no new errors before merge (expected to pass; any finding would most
likely be a lint nicety).

## Checkpoint — Task 3 (blocking, human-verify)

The pre-unlock crash fix (BOOT-02), the no-permanent-hang behavior (BOOT-01), and
exactly-once reschedule (BOOT-03) can only be TRULY validated on a secure-lock
(PIN/pattern) File-Based-Encryption Android device/emulator running API 24+.
There is no software fallback. The verification steps are in the PLAN
(`01-02-PLAN.md`, Task 3 `<how-to-verify>`): build+install the dev flavor, create
≥2 alarms + 1 timer, `adb reboot`, check `adb logcat` pre-unlock for the
`handleBoot: device locked ... deferring` info log and the ABSENCE of
`IllegalStateException`, then unlock and confirm normal UI + exactly-once
re-arm. Resume signal: "approved" if the app reaches the normal UI pre/post
unlock with no `IllegalStateException` and alarms re-arm exactly once; otherwise
describe the observed behavior so the guard mechanism, timeout, or manifest
narrowing can be revisited (D-07 says revisit if on-device proves the
defer-until-unlock approach insufficient).

## User Setup Required

A secure-lock (PIN/pattern) FBE Android device or emulator (API 24+) is required
for the Task 3 on-device verification. No service/credential setup; no new deps.

## Next Phase Readiness

- **Plan 03 (one-time "alarms were lost" notice):** ready — it reads
  `SalvageReport.alarmsWereLost` (Plan 01) in `app.dart`; this plan deliberately
  did NOT touch `app.dart` so Plan 03 has no merge overlap.
- **Phases 2 & 4:** the idempotent reschedule funnel (`updateAlarms`/
  `updateTimers`) is preserved unchanged as the shared spine.
- **Blocker carried forward:** automated verification (this plan + Plan 01) not
  run — toolchain absent. Run `flutter analyze` + the on-device Task 3 checkpoint
  before relying on these guarantees.

## Self-Check: PASSED

- `lib/system/logic/device_lock.dart` exists on disk.
- Task commits `284f1f6` and `f247448` exist in git history.
- `handle_boot.dart`, `main.dart`, `AndroidManifest.xml` modifications committed.

---
*Phase: 01-storage-boot-reliability*
*Completed (autonomous tasks): 2026-05-30 — Task 3 checkpoint pending human verification*
