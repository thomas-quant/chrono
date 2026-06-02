---
phase: 02-snooze-reliability
plan: 01
subsystem: alarm-snooze-state-machine
tags: [snooze, dismiss, isolate, alarm, reliability, SNZ-01, SNZ-02, SNZ-03, SNZ-04, SNZ-05, "#457", "#495"]
requires:
  - "Phase-1 idempotent reschedule funnel (updateAlarmById/updateAlarms -> saveList -> IsolateNameServer notify), reused unchanged"
provides:
  - "Seconds-based snooze duration honoring fractional Length (SNZ-02)"
  - "Authoritative max-snooze gate inside snooze() resolving over-max as a dismiss (SNZ-04)"
  - "Schedule-agnostic _resolveDismiss() (cancelSnooze + update) shared by the isolate dismiss branch and the over-max snooze path (SNZ-03/#457)"
  - "Public async handleDismiss() delegator for the Plan-02 cross-file regression test (D-E)"
  - "Awaited deactivating dismiss in the isolate stopAlarm branch (SNZ-01/SNZ-05)"
affects:
  - lib/alarm/types/alarm.dart
  - lib/alarm/logic/alarm_isolate.dart
  - lib/alarm/data/alarm_settings_schema.dart
tech-stack:
  added: []
  patterns:
    - "package:clock clock.now() for deterministic snooze-time tests (D-B)"
    - "Single shared Duration between _snoozeTime and scheduleSnoozeAlarm (no divergence class)"
    - "Mirror the canonical user-list dismiss (alarm_screen.dart:188) in the model via _resolveDismiss()"
key-files:
  created: []
  modified:
    - lib/alarm/types/alarm.dart
    - lib/alarm/logic/alarm_isolate.dart
    - lib/alarm/data/alarm_settings_schema.dart
decisions:
  - "D-A: over-max snooze resolves as a DISMISS, not a no-op (never leaves the alarm ringing)"
  - "D-B: snooze() reads clock.now() (only that one DateTime.now() switch) for exact frozen-clock tests"
  - "D-C: dismiss calls the canonical update() path, so it is schedule-agnostic (one-shot AND finished-dates)"
  - "D-D: added snapLength: 1 to the Length slider (UI hardening; model fix is authoritative)"
  - "D-E: handleDismiss() kept as a PUBLIC Future<void> delegator to private _resolveDismiss()"
metrics:
  duration: ~8min
  tasks: 3
  files: 3
  completed: 2026-06-02
---

# Phase 2 Plan 01: Snooze State-Machine Source Fix Summary

Fixed the snooze cluster (SNZ-01..05) at its source with three surgical edits across two model/logic files plus one UI-slider hardening: seconds-based fractional snooze duration computed once via `clock.now()`, an authoritative max-count gate in `snooze()`, a schedule-agnostic `_resolveDismiss()` (cancelSnooze + update) wired — awaited — into both the over-max snooze path and the isolate dismiss branch, replacing the incomplete synchronous `handleDismiss()`. No new file, no schema migration, no new dependency, no state-management library.

## What Was Built

### Task 1 — Seconds-based snooze duration + `clock.now()` (SNZ-02) — commit `67ae5f7`
- **`lib/alarm/types/alarm.dart`**
  - Added `import 'package:clock/clock.dart';` to the third-party import block.
  - In `snooze()`: compute the snooze delay **once** as `Duration(seconds: snoozeSeconds < 1 ? 1 : snoozeSeconds)` where `snoozeSeconds = (snoozeLength * 60).round()`. `0.5` min → `30s`; a near-zero value → `1s` (never `0`, which would make `scheduleAlarm` throw "schedule in the past" or re-fire instantly).
  - `_snoozeTime = clock.now().add(snoozeDelay)` — the **only** `DateTime.now()`→`clock.now()` switch in the file (D-B). The three `DateTime.now()` calls inside `update()` (lines ~338/345/352) are deliberately left unchanged (out of scope).
  - Changed `_scheduleSnooze()` → `_scheduleSnooze(Duration delay)` and pass the same `snoozeDelay`, so `_snoozeTime` and the `scheduleSnoozeAlarm` delay can never diverge (Research Pitfall 1). The existing log-message string mentioning `$snoozeLength` is preserved.
  - Fixed the other `_scheduleSnooze()` caller inside `update()` to pass `_snoozeTime!.difference(DateTime.now())`, so re-evaluating a still-snoozed alarm preserves its original re-ring instant instead of resetting to a full length.
- **`lib/alarm/data/alarm_settings_schema.dart`** (D-D, secondary UI hardening): added `snapLength: 1` to the `Length` `SliderSetting`, mirroring the `Max Snoozes` sibling. The model `(snoozeLength*60).round()` fix remains the authoritative guarantee.

### Task 2 — `_resolveDismiss()` + public `handleDismiss()` delegator + max-snooze gate (SNZ-03, SNZ-04, #457) — commit `c70f156`
- **`lib/alarm/types/alarm.dart`**
  - Added `Future<void> _resolveDismiss() async`: `_snoozeCount = 0;` → `await cancelSnooze();` (cancels the pending OS snooze by id and clears `_snoozeTime`) → `await update("_resolveDismiss(): re-evaluate schedule after dismiss");`. Because `cancelSnooze()` clears `_snoozeTime` first, `isSnoozed` is false when `update()` runs, so `update()`'s `if (activeSchedule.isDisabled && !isSnoozed) await disable()` disables a resolved one-shot **and** `if (isFinished) await finish()` deactivates a finished-dates schedule (D-C, schedule-agnostic — generalizes #457 to "On Specified Days"). The mark-for-deletion check is preserved and reads `isFinished` **after** `update()` runs.
  - Converted `handleDismiss()` from synchronous `void` to a **public** `Future<void> handleDismiss() async` that delegates to `_resolveDismiss()` (D-E). The incomplete synchronous body is gone.
  - Added the authoritative max-count gate at the **top** of `snooze()`, before `_snoozeCount++`: `if (maxSnoozeIsReached) { await _resolveDismiss(); return; }` (SNZ-04, D-A). Over-max resolves as a dismiss (Pitfall 5), independent of the UI button (closes the stale-read race, Landmine 3).

### Task 3 — Wire the isolate dismiss branch to the deactivating resolution (SNZ-01, SNZ-03, SNZ-05) — commit `3e0c69c`
- **`lib/alarm/logic/alarm_isolate.dart`** (`stopAlarm` dismiss branch only):
  - Replaced the un-awaited `(alarm) async => alarm.handleDismiss()` with `(alarm) async => await alarm.handleDismiss()` (now async + deactivating). Awaiting it inside the `updateAlarmById` callback lets `saveList` persist `_isEnabled=false` / cleared `_snoozeTime` / `_snoozeCount` before the firing isolate tears down (Landmine 1 / Pitfall 2).
  - Added a `logger.i` lifecycle line for the deactivating dismiss (reused the existing singleton `logger`).
  - Snooze branch (`(alarm) async => await alarm.snooze()`), `triggerAlarm`'s `updateAlarms("triggerAlarm(): Updating all alarms on trigger")` re-arm funnel, and the timer paths (`stopTimer`/`triggerTimer`) are all untouched. Once dismiss sets `_isEnabled=false`, the enabled-check on the next trigger makes the #457 re-arm impossible by construction.

## How It Fits

- **SNZ-01/SNZ-05:** the isolate dismiss is now awaited and deactivating, so a snooze can never resolve to a disabled-and-not-rescheduled state and a dismissed one-shot never silently re-arms.
- **SNZ-02:** snooze duration is computed once in seconds, clamped ≥1s, shared between `_snoozeTime` and `scheduleSnoozeAlarm`; `clock.now()` makes the test exact.
- **SNZ-03/#457:** a single `_resolveDismiss()` (cancelSnooze + update) deactivates one-shot AND finished-dates schedules via the canonical `update()` path; called from the isolate dismiss branch (via public `handleDismiss()`) and the over-max path.
- **SNZ-04:** `snooze()` refuses to exceed `maxSnoozes` and resolves over-max as a dismiss; `_snoozeCount` persistence is unchanged (still via `updateAlarmById`→`saveList`; serialized in `toJson`/`fromJson`).
- **Reuse, not reinvention:** `lib/alarm/logic/update_alarms.dart` (the Phase-1 idempotent funnel) and `lib/alarm/screens/alarm_screen.dart` (the canonical dismiss template) are **unchanged** — verified by `git diff HEAD~3 HEAD`.

## Decisions Made

- **D-A — over-max snooze → dismiss.** Resolve an over-max attempt as a dismiss inside `snooze()`, never a silent no-op (Research Pitfall 5).
- **D-B — `clock.now()` for testability.** Only `snooze()`'s snooze-time write switched from `DateTime.now()` to `clock.now()`; the `update()` comparisons were left untouched (out of scope).
- **D-C — dismiss is schedule-agnostic.** Calls `update()`, not a once-only branch, so it deactivates both `OnceAlarmSchedule` (via `isDisabled`) and finished `DatesAlarmSchedule` (via `isFinished`→`finish()`).
- **D-D — `Length` slider `snapLength: 1`.** Secondary UI hardening; the model conversion is authoritative.
- **D-E — public `handleDismiss()` delegator.** Kept public (not deleted) so Plan 02's cross-file regression test can drive the dismiss resolution through a public entry point without exposing private `_resolveDismiss`.

## Deviations from Plan

**1. [Rule 1 — Bug] Fixed the third `_scheduleSnooze()` caller inside `update()`**
- **Found during:** Task 1.
- **Issue:** Changing `_scheduleSnooze()` to take a `Duration delay` parameter broke its other call site inside `update()` (line ~337), which re-schedules a still-pending snooze. Left as-is it would not compile.
- **Fix:** Pass `_scheduleSnooze(_snoozeTime!.difference(DateTime.now()))` so re-evaluation preserves the original re-ring instant rather than resetting to a full snooze length. This stays within the Task-1 scope (the duration-conversion edit) and is required for the file to compile.
- **Files modified:** `lib/alarm/types/alarm.dart`.
- **Commit:** `67ae5f7`.

No other deviations — the plan executed as written.

## Verification

### Source-level (run locally — all 13 assertions PASS)
- `(snoozeLength * 60).round()` present (non-comment); `Duration(minutes: snoozeLength.floor())` absent (non-comment); `import 'package:clock/clock.dart';` present.
- `Future<void> _resolveDismiss() async` present with `cancelSnooze()` before `update(` (confirmed via perl `-0777` — the `ugrep -P -z` multiline form reported a false negative; the source ordering is correct).
- `Future<void> handleDismiss() async` present; `void handleDismiss()` gone.
- `snooze()` max-gate (`if (maxSnoozeIsReached) … _resolveDismiss()`) precedes `_snoozeCount++`.
- Isolate dismiss `async => await alarm.handleDismiss()` present; un-awaited form gone; snooze branch and `triggerAlarm` funnel unchanged.
- `update_alarms.dart` and `alarm_screen.dart` unchanged across `HEAD~3..HEAD`.

### CI / human gates — OWED, not run here (no Flutter/Dart toolchain in this env; no push performed)
These are recorded as owed. **Do not run any `git push` / `gh` command without explicit user authorization** — both remotes (`origin=thomas-quant/chrono`, `upstream=vicolo-dev/chrono`) are outward-facing.

- **`flutter analyze`** on the three changed files (Flutter 3.22.2). The analyze list is repointed to these files in Plan 02 Task 2; it runs in the `test-apk.yml` dispatch build. Owed command (run by the user when ready):
  ```
  gh workflow run test-apk.yml --ref <phase-branch>
  gh run watch   # read the Analyze step log for new issues
  ```
  (Scoped + informational: `alarm.dart` is a large pre-existing file — read the log rather than expecting a hard zero.)
- **`flutter test`** behavioral proof. Plan 02 authors `test/alarm/types/alarm_snooze_test.dart`; pushing the phase branch triggers `tests.yml`:
  ```
  git push <remote> <phase-branch>
  gh run watch   # tests.yml
  ```
- **On-device smoke (human gate):** snooze a once-alarm, dismiss the re-ring, confirm it does not reappear; snooze a fractional-length alarm and confirm it re-rings ~30s later; snooze past max and confirm it dismisses.

## Known Stubs

None — every edit is a complete behavioral change wired end-to-end (model + isolate). No placeholder values, no TODO/FIXME introduced, no component left without a data source.

## Threat Flags

None — this plan adds no network endpoint, auth path, file-access pattern, or schema change at a trust boundary. The only persisted shapes (`snoozeCount`/`snoozeTime`/`enabled`) are unchanged; the fix changes *when/how* they are written, not their format.

## Self-Check: PASSED

- `lib/alarm/types/alarm.dart` — FOUND, contains `_resolveDismiss`, `(snoozeLength * 60).round()`, `clock.now()`, `Future<void> handleDismiss() async`.
- `lib/alarm/logic/alarm_isolate.dart` — FOUND, contains `async => await alarm.handleDismiss()`.
- `lib/alarm/data/alarm_settings_schema.dart` — FOUND, `snapLength: 1` count = 2.
- Commits `67ae5f7`, `c70f156`, `3e0c69c` — all FOUND in `git log`.
- `update_alarms.dart` / `alarm_screen.dart` — unchanged (FOUND, no diff).
