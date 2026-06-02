---
phase: 02-snooze-reliability
reviewed: 2026-06-02T00:00:00Z
depth: quick
files_reviewed: 5
files_reviewed_list:
  - lib/alarm/types/alarm.dart
  - lib/alarm/logic/alarm_isolate.dart
  - lib/alarm/data/alarm_settings_schema.dart
  - test/alarm/types/alarm_snooze_test.dart
  - .github/workflows/test-apk.yml
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-06-02
**Depth:** quick (read-augmented — files were read in full to verify the claimed state-machine behaviors)
**Files Reviewed:** 5
**Status:** issues_found

## Summary

This phase rewires the snooze/dismiss state machine: seconds-based fractional snooze
duration, a `maxSnoozeIsReached` over-max→dismiss gate, and a schedule-agnostic
`_resolveDismiss()` exposed via async `handleDismiss()` and awaited from the isolate
dismiss branch. The async/await plumbing across the isolate boundary is correct, the
operator-precedence in the deletion gate is correct, and the `update()` snooze-preservation
path (SNZ-01/05) holds up.

The headline concern is the **SNZ-03 once-alarm regression test (and the behavior it
claims to pin)**: a freshly-constructed once-alarm that was never scheduled into the past
will be **re-armed to a future time** by `_resolveDismiss()` rather than disabled, so the
test's `isEnabled == false` assertion does not hold for the model as written. This is
exactly the #457 "re-arm after dismiss" class the phase claims to close — for the one-shot
case it appears to remain open (or, at minimum, the test does not actually prove it closed).
No Flutter/Dart toolchain is available in this environment, so this was verified by tracing
the call chain by hand rather than by running the suite; it must be confirmed by a real
`flutter test` run.

Secondary issues: the SNZ-04-persist test under-asserts (it does not pin the durable flags
it claims to cover), `update()`'s snooze re-schedule and skip-expiry paths read wall-clock
`DateTime.now()` instead of `clock.now()` (inconsistent with the SNZ-02 fix and untestable
under a frozen clock), and the CI gate is entirely informational (`continue-on-error: true`
plus `workflow_dispatch`-only) so it cannot actually block a regression.

## Critical Issues

### CR-01: One-shot dismiss re-arms to a future time; SNZ-03 once-alarm test assertion does not hold

**File:** `lib/alarm/types/alarm.dart:336-351` (and test `test/alarm/types/alarm_snooze_test.dart:55-73`)

**Issue:** Trace `handleDismiss()` for the SNZ-03 once-alarm test. The test builds a fresh
`Alarm(const Time(hour: 2, minute: 30))`, calls `snooze()`, then `handleDismiss()`:

1. `snooze()` sets `_snoozeTime` and `_isEnabled = true`. It does **not** schedule the
   once-schedule's `AlarmRunner`, so `OnceAlarmSchedule._alarmRunner._currentScheduleDateTime`
   is still `null`.
2. `handleDismiss()` → `_resolveDismiss()` → `cancelSnooze()` (clears `_snoozeTime`) →
   `update("...")`.
3. In `update()` (`alarm.dart:366`), `isEnabled` is true, so it calls `schedule()`.
4. `schedule()` calls `OnceAlarmSchedule.schedule()` (`once_alarm_schedule.dart:28`).
   There, `currentScheduleDateTime?.isBefore(now) ?? false` is `null ?? false → false`
   (the runner was never scheduled into the past), so it takes the **else** branch:
   `getScheduleDateForTime(Time(2,30))` returns a **future** instant and sets
   `_isDisabled = false`.
5. Back in `update()` (`alarm.dart:395`), `activeSchedule.isDisabled && !isSnoozed` is
   `false && true → false`, so the alarm is **not** disabled. `isFinished` is hard-coded
   `false` for `OnceAlarmSchedule`, so `finish()` is not called either.

Result: after dismiss, the once-alarm is left **enabled and re-armed for the next 02:30** —
not `isEnabled == false`. The test asserts:

```dart
expect(alarm.isEnabled, false);   // FAILS — alarm is re-armed to a future time
expect(alarm.isSnoozed, false);   // passes
expect(alarm.snoozeCount, 0);     // passes
```

Two possibilities, both shippable defects:
- **(a) Behavior bug:** dismissing a snoozed one-shot leaves it armed for the future. This is
  the #457 "re-arm after dismiss" failure mode the phase is supposed to close. The dates
  variant works only because `DatesAlarmSchedule.schedule()` sets `_isFinished = true` when
  all dates are in the past; the once-schedule has no equivalent "already rang" signal in the
  test path because `_resolveDismiss()` re-runs `schedule()` which re-computes a fresh future
  date.
- **(b) Test bug:** the test never schedules the once-runner into the past before dismissing,
  so it does not reproduce the real "alarm already rang" precondition. As written the
  assertion cannot pass against the model, so the suite is red (or the assertion is wrong).

Either way the claimed SNZ-03/#457 guarantee for the one-shot case is **not** established by
this code+test pair. In production the once-alarm only disables because its runner's
`_currentScheduleDateTime` is already in the past when `schedule()` re-evaluates — a
precondition the regression test does not set up, and which `_resolveDismiss()` does not
itself enforce.

**Fix:** Make the dismiss deactivate the one-shot independently of whether the runner's
prior fire time was persisted as past, and update the test to reproduce the real precondition.
Minimal model fix — disable a one-shot on dismiss directly rather than relying on
`schedule()` re-evaluation:

```dart
Future<void> _resolveDismiss() async {
  _snoozeCount = 0;
  await cancelSnooze();
  // A dismissed one-shot has fired; it must not re-arm. Force-disable before
  // re-evaluating so a fresh runner can't recompute a future fire time.
  if (scheduleType == OnceAlarmSchedule) {
    await disable();
  } else {
    await update("_resolveDismiss(): re-evaluate schedule after dismiss");
  }
  if ((scheduleType == OnceAlarmSchedule && shouldDeleteAfterRinging) ||
      (shouldDeleteAfterFinish && isFinished)) {
    _markedForDeletion = true;
  }
}
```

And give the test the real precondition (runner already scheduled into the past) before
asserting `isEnabled == false`, e.g. drive a `schedule()` under a frozen clock set after
02:30 so the once-schedule disables on re-evaluation. Confirm with a real `flutter test` run —
this could not be executed here (no Dart toolchain).

## Warnings

### WR-01: `update()` re-schedules snooze and expires skips off wall-clock `DateTime.now()`, not `clock.now()`

**File:** `lib/alarm/types/alarm.dart:368-385`

**Issue:** `snooze()` was deliberately switched to `clock.now()` (SNZ-02, D-B) so the snooze
instant is testable under `withClock`. But `update()` still reads `DateTime.now()` in three
places that participate in the same state machine:

- `alarm.dart:370` — skip-expiry comparison `_skippedTime!.millisecondsSinceEpoch < DateTime.now()...`
- `alarm.dart:377` — `DateTime.now().isAfter(_snoozeTime!)` (decides whether a pending snooze is unsnoozed)
- `alarm.dart:384` — `_snoozeTime!.difference(DateTime.now())` (the re-scheduled remaining delay)

This is internally inconsistent with the SNZ-02 change and means the SNZ-01/05 test
(`alarm_snooze_test.dart:133`) only passes because it runs in real wall-clock time where
`_snoozeTime` (now + a few minutes) is trivially after `DateTime.now()`. Under a frozen clock
the unsnooze branch at line 377 would behave differently from the snooze instant set via
`clock.now()`, and the re-scheduled delay at line 384 would be computed against a different
clock than the one that produced `_snoozeTime` — a latent divergence between the displayed
snooze time and the actually-scheduled re-ring.

**Fix:** Use `clock.now()` consistently in `update()` for the snooze/skip time math so it
matches `snooze()` and is testable:

```dart
import 'package:clock/clock.dart';
// ...
if (_skippedTime != null &&
    _skippedTime!.millisecondsSinceEpoch < clock.now().millisecondsSinceEpoch) {
  cancelSkip();
}
// ...
if (isSnoozed) {
  if (clock.now().isAfter(_snoozeTime!)) {
    _unSnooze();
  } else {
    await _scheduleSnooze(_snoozeTime!.difference(clock.now()));
  }
}
```

### WR-02: SNZ-04-persist test under-asserts — does not pin the durable flags it claims to cover

**File:** `test/alarm/types/alarm_snooze_test.dart:119-131`

**Issue:** The test is titled "snoozeCount round-trips ... disk durability across the isolate
boundary" but only asserts `rebuilt.snoozeCount == 1`. `snooze()` also sets `_snoozeTime`
and `_isEnabled`, and the JSON round-trip carries `snoozeTime`/`enabled`. The cross-isolate
durability the comment claims is "source of truth" is not actually verified — a regression
that dropped `snoozeTime` from `toJson`/`fromJson` (or mishandled the `!= 0` guard at
`alarm.dart:454`) would pass this test. For a reliability milestone where the firing isolate
reloads from disk, the snoozed instant is as load-bearing as the count.

**Fix:** Assert the full snooze state survives the round-trip:

```dart
final rebuilt = Alarm.fromJson(alarm.toJson());
expect(rebuilt.snoozeCount, 1);
expect(rebuilt.isSnoozed, true);
expect(rebuilt.snoozeTime, alarm.snoozeTime);
expect(rebuilt.isEnabled, true);
```

### WR-03: The Test-APK workflow cannot gate a regression — analyze and test are both `continue-on-error`, trigger is manual-only

**File:** `.github/workflows/test-apk.yml:12-13, 48-60`

**Issue:** The phase plan describes a "CI gate," but this workflow cannot block anything:
- `on: workflow_dispatch` only — it never runs on push/PR, so a snooze regression can merge
  without it ever executing.
- The "Analyze changed files" step (line 49) and the "Test" step (line 59) are both
  `continue-on-error: true`. A failing `flutter test` (including a red SNZ-03 assertion from
  CR-01) is explicitly swallowed; the job still goes green and uploads the APK.

So even if CR-01's test is red, this workflow reports success. The only hard-failing steps
are the keystore generation and APK build, which test packaging, not snooze correctness.

**Fix:** Add a real gate that runs on PRs to the snooze-relevant paths with a failing test
step, e.g. a separate job/workflow:

```yaml
on:
  pull_request:
    paths:
      - 'lib/alarm/**'
      - 'test/alarm/**'
jobs:
  test:
    steps:
      # ... setup ...
      - run: flutter test test/alarm/types/alarm_snooze_test.dart   # no continue-on-error
```

Keep the manual APK build as-is, but a regression must be able to turn a check red.

### WR-04: Over-max snooze path runs `_resolveDismiss()` which re-schedules a one-shot before disabling — inherits CR-01

**File:** `lib/alarm/types/alarm.dart:225-228`

**Issue:** The SNZ-04 authoritative gate routes an over-max snooze attempt through
`_resolveDismiss()`. For a `DatesAlarmSchedule` past-dates alarm this disables correctly, but
for a one-shot it inherits the CR-01 re-arm defect: `_resolveDismiss()` → `update()` →
`OnceAlarmSchedule.schedule()` recomputes a future fire time and leaves the alarm armed. The
SNZ-04 unit test (`alarm_snooze_test.dart:97-117`) uses the default once-schedule and asserts
`isEnabled == false` after the over-max snooze — so it is subject to the same failure as
CR-01. Fixing CR-01 (`_resolveDismiss` force-disabling one-shots) resolves this path too.

**Fix:** Covered by CR-01's fix. After it lands, re-run the SNZ-04 test to confirm the
over-max one-shot ends `isEnabled == false`.

## Info

### IN-01: Empty no-op method left in place

**File:** `lib/alarm/types/alarm.dart:302`

**Issue:** `Future<void> cancelAllSchedules() async {}` is an empty-bodied public async
method. If it has no callers it is dead code; if it does, it silently no-ops. Either is a
trap.

**Fix:** Remove it, or implement it to iterate `_schedules` and `cancel()` each (mirroring
`cancel()` at line 304).

### IN-02: Stray empty-statement method bodies

**File:** `lib/alarm/types/alarm.dart:404-406`

**Issue:** `setRingtone(BuildContext context, int index) { ; }` is a lone empty statement
(`;`) — a no-op method that takes args and does nothing. Likely a stub. Reads as a bug to a
caller expecting it to set the ringtone.

**Fix:** Implement or remove; if intentionally a stub, add a `// TODO:`/comment explaining why.

### IN-03: Commented-out code blocks left in scope

**File:** `lib/alarm/types/alarm.dart:44,298-300,325,450,492`; `lib/alarm/logic/alarm_isolate.dart:35,145-152,185,216`; `lib/alarm/data/alarm_settings_schema.dart:301-303,335-341`

**Issue:** Multiple commented-out lines/blocks (`_isFinished` field and its JSON, the
`cancelReminderNotification` stub, the alarm-isolate volume-port doc and `RingtonePlayer.pause()`
no-op, commented kDebugMode task defaults). CLAUDE.md notes this is "accepted but not
preferred." Not introduced by this phase in most cases, but the dead `_isFinished` plumbing
(field, toJson key, fromJson read) is noise around the exact state machine under review and
can mislead a maintainer into thinking a persisted "finished" flag exists when it does not.

**Fix:** Delete the dead `_isFinished` remnants (`alarm.dart:44,325,450,492`) since `isFinished`
is now computed from `activeSchedule.isFinished`; sweep the rest opportunistically.

---

_Reviewed: 2026-06-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: quick (read-augmented; no Dart toolchain available — CR-01 must be confirmed by `flutter test`)_
