---
phase: 02-snooze-reliability
verified: 2026-06-02T23:00:00Z
status: human_needed
score: 10/10 must-haves verified (source); 2 items require toolchain/on-device human gates
overrides_applied: 0
human_verification:
  - test: "Toolchain gate: flutter test (authoritative behavioral gate)"
    expected: "git push <branch> triggers tests.yml; flutter test --coverage exits 0; group('Alarm snooze') — 6 cases all green; no regressions in existing suite"
    why_human: "Flutter 3.22.2 toolchain absent in this environment. tests.yml is the authoritative gate (no continue-on-error). Source strongly indicates all 6 cases pass — the _firedOnceAlarm() helper correctly sets up the CR-01 precondition and every assertion maps to a real code path — but runtime confirmation is required before merge."

  - test: "On-device smoke: snooze re-rings, fractional length honored, max enforced, once-alarm stays off after dismiss (SNZ-01..05)"
    expected: "(1) Once-alarm ~1 min out: ring -> SNOOZE -> re-rings after configured length (test 0.5 min -> ~30s) -> DISMISS -> relaunch: alarm does NOT reappear or re-fire. (2) Max Snoozes=1: snooze button disappears after 1 snooze; alarm cannot get stuck ringing. (3) Normal snooze re-rings, does not silently disable the alarm."
    why_human: "Requires a Flutter 3.22.2 device/emulator with flutter run --flavor dev. The full dismiss -> deactivate -> no-re-arm path involves the alarm isolate, IsolateNameServer ports, and AndroidAlarmManager — none of which can be exercised by source inspection or in-process tests."
---

# Phase 2: Snooze Reliability — Verification Report

**Phase Goal:** Snooze does exactly what the user expects — it always re-rings after the set delay, respects the max count, and a snoozed one-shot alarm that gets dismissed stays off for good.
**Verified:** 2026-06-02T23:00:00Z
**Status:** HUMAN_NEEDED
**Re-verification:** No — initial verification

**Toolchain note:** The Flutter/Dart toolchain (flutter, dart) is absent in this environment. All source-level assertions were verified by direct file reads and grep. `flutter test` and `flutter analyze` were NOT run here and are required pre-merge gates. The authoritative test gate is `tests.yml` (push-triggered, no continue-on-error).

**Code-review resolution:** CR-01 from 02-REVIEW.md (once-alarm snooze→dismiss re-armed to future time) was resolved in commit `e8346c4` by the `_firedOnceAlarm()` helper in the test file. The helper performs a JSON round-trip that backdates the OnceAlarmSchedule runner's `currentScheduleDateTime` to a past instant (year 2000), placing the test in the correct production precondition where `once_alarm_schedule.dart:30` evaluates `currentScheduleDateTime?.isBefore(DateTime.now()) ?? false` as `true` and sets `_isDisabled = true`. Production source code in `alarm.dart` is correct and required no change. The test was the only defect; it is now fixed.

---

## Goal Achievement

### Observable Truths (Plan Frontmatter Must-Haves — Plans 02-01 and 02-02)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Snoozing an alarm re-rings it after the configured length and never silently dismisses it (SNZ-01/SNZ-05) | VERIFIED (source) | `alarm_isolate.dart:197` — dismiss branch awaits `alarm.handleDismiss()` inside `updateAlarmById` callback; `saveList` persists disabled state before isolate tears down. `snooze()` sets `_isEnabled=true` + `_snoozeTime`. `update()` preserves snooze on unrelated re-evaluation (line 376-385). CI gate owed. |
| 2 | A fractional snooze length (e.g. 0.5 min) schedules ~30s ahead, never floored to 0 (SNZ-02) | VERIFIED (source) | `alarm.dart:240-242` — `snoozeSeconds = (snoozeLength * 60).round()`, `Duration(seconds: snoozeSeconds < 1 ? 1 : snoozeSeconds)`. Old `Duration(minutes: snoozeLength.floor())` is absent. `clock.now()` used at line 246. `_scheduleSnooze(Duration)` receives the same computed Duration. |
| 3 | A snoozed-then-dismissed one-shot or finished-dates alarm becomes inactive and does NOT re-arm (SNZ-03/#457) | VERIFIED (source) | `_resolveDismiss()` (line 336): `cancelSnooze()` clears `_snoozeTime` → `update()` re-evaluates. For a fired once-alarm (past runner time): `once_alarm_schedule.dart:30` evaluates `currentScheduleDateTime?.isBefore(now) ?? false` as `true` → `_isDisabled=true` → `update()` line 395 `disable()`. For dates: `isFinished=true` → `finish()`. Disabled alarm is skipped at `alarm_isolate.dart:105`. Test uses `_firedOnceAlarm()` to supply past runner time (CR-01 resolved). CI gate owed. |
| 4 | `snooze()` refuses to exceed Max Snoozes and resolves an over-max attempt as a dismiss (SNZ-04) | VERIFIED (source) | `alarm.dart:225-228` — `if (maxSnoozeIsReached) { await _resolveDismiss(); return; }` precedes `_snoozeCount++` at line 229. Over-max routes to the deactivating dismiss, never increments. |
| 5 | Snooze count persists on disk through the updateAlarmById→saveList funnel, surviving the isolate boundary (SNZ-04) | VERIFIED (source) | `_snoozeCount` serialized at `toJson` line 494 (`'snoozeCount': _snoozeCount`) and deserialized at `fromJson` line 457 (`json['snoozeCount'] ?? 0`). `updateAlarmById` in `update_alarms.dart` is unchanged and calls `saveList` after the callback. Test SNZ-04 persist asserts `rebuilt.snoozeCount == 1`, `rebuilt.isSnoozed == true`, `rebuilt.isEnabled == true`. |
| 6 | A CI-runnable test suite asserts every SNZ-01..05 behavior on Alarm flags without a device | VERIFIED (source) | `test/alarm/types/alarm_snooze_test.dart` exists (178 lines), contains `group('Alarm snooze', ...)`, `TestWidgetsFlutterBinding.ensureInitialized()`, `import 'package:clock/clock.dart'`, `withClock(Clock.fixed(...))`. 12 occurrences of `snooze()/handleDismiss()` calls. 33 assertion-token matches (isEnabled, isSnoozed, isFinished, snoozeCount, toJson, fromJson, Max Snoozes, Length). NOT executed (toolchain absent). |
| 7 | SNZ-02: a 0.5-min snooze pins `_snoozeTime` to exactly now+30s under a frozen clock | VERIFIED (source) | Test line 54-68: `setSettingWithoutNotify("Length", 0.5)`, `withClock(Clock.fixed(fixedNow), ...)`, asserts `alarm.snoozeTime == fixedNow.add(Duration(seconds: 30))` and `isNot(equals(fixedNow))`. Valid because `snooze()` reads `clock.now()`. |
| 8 | SNZ-03: a snoozed-then-dismissed once-alarm is disabled and not re-armed; a finished dates-alarm is finished | VERIFIED (source) | Test lines 71-92 (SNZ-03 once via `_firedOnceAlarm`): asserts `isEnabled==false, isSnoozed==false, snoozeCount==0`. Lines 94-113 (SNZ-03 dates): sets past date, asserts `isFinished==true, isEnabled==false, isSnoozed==false`. |
| 9 | SNZ-04: snooze past Max Snoozes does not increment and resolves as dismiss; snoozeCount round-trips through JSON | VERIFIED (source) | Test lines 116-140 (max gate via `_firedOnceAlarm`): 3 snooze calls with Max Snoozes=2; asserts `snoozeCount != 3`, `snoozeCount==0, isSnoozed==false, isEnabled==false`. Lines 142-157 (persist): `fromJson(toJson())` round-trip asserts `snoozeCount==1, isSnoozed==true, isEnabled==true`. |
| 10 | SNZ-01/SNZ-05: a snoozed alarm survives an unrelated update() still enabled+snoozed | VERIFIED (source) | Test lines 160-175: `snooze()` then `update("test: unrelated update...")`, asserts `isEnabled==true, isSnoozed==true`. Mirrors `triggerAlarm`'s `updateAlarms` re-arm funnel running while a snooze is pending. |

**Score:** 10/10 truths verified at source level. 2 items require toolchain/on-device confirmation before the phase can be closed.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/alarm/types/alarm.dart` | Seconds-based snooze duration, max-count gate in `snooze()`, `_resolveDismiss()`, public async `handleDismiss()` | VERIFIED | `(snoozeLength*60).round()` at line 240; clamp `< 1 ? 1` at line 242; `if (maxSnoozeIsReached)` gate at line 225; `Future<void> _resolveDismiss() async` at line 336; `Future<void> handleDismiss() async` at line 356; synchronous `void handleDismiss()` is absent |
| `lib/alarm/logic/alarm_isolate.dart` | Dismiss branch awaits `alarm.handleDismiss()` inside `updateAlarmById` | VERIFIED | Line 197: `(alarm) async => await alarm.handleDismiss()`. Un-awaited form `alarm.handleDismiss()` without `await` is absent. Snooze branch (line 184) and `triggerAlarm` funnel (line 98) unchanged. |
| `lib/alarm/data/alarm_settings_schema.dart` | `snapLength: 1` on `Length` slider (UI hardening) | VERIFIED | `snapLength: 1` appears 2 times in file (line 255 for `Length`, existing for `Max Snoozes`). |
| `test/alarm/types/alarm_snooze_test.dart` | Unit regression suite, ≥80 lines, SNZ-01..05, `withClock`, `_firedOnceAlarm` | VERIFIED | 178 lines. `_firedOnceAlarm()` helper at line 26 (CR-01 fix). All required test cases present. No `lib/` file modified, no `pubspec.yaml` change. |
| `.github/workflows/test-apk.yml` | Analyze gate scoped to Phase 2 files; `continue-on-error: true` retained | VERIFIED | Lines 52-55: exactly the four Phase 2 paths. Phase 1 paths (`list_storage.dart`, `handle_boot.dart`) absent. `continue-on-error: true` at line 49. `workflow_dispatch` trigger unchanged. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `alarm_isolate.dart` dismiss branch | `Alarm.handleDismiss` → `Alarm._resolveDismiss` | `updateAlarmById(scheduleId, (alarm) async => await alarm.handleDismiss())` | VERIFIED | Line 196-197. `await` keyword confirmed present. Inside `updateAlarmById` callback so `saveList` persists state before isolate exits. |
| `alarm.dart snooze()` | `Alarm._resolveDismiss` | `if (maxSnoozeIsReached) { await _resolveDismiss(); return; }` | VERIFIED | Lines 225-228. Gate precedes `_snoozeCount++` at line 229. |
| `alarm.dart _resolveDismiss()` | `Alarm.update` / `Alarm.cancelSnooze` | `cancelSnooze()` then `update(...)` in sequence | VERIFIED | Lines 340 (`await cancelSnooze()`) and 343 (`await update(...)`). `cancelSnooze` before `update` confirmed. |
| `update_alarms.dart` | `saveList` | unchanged funnel — `await callback(alarm)` already awaits async callbacks; `saveList` persists before return | VERIFIED | Confirmed no diff in `update_alarms.dart` across the phase commits (git diff output: 0 lines). |

---

### Data-Flow Trace (Level 4)

This phase modifies state-machine logic (not UI components that render queries). Level 4 data-flow tracing is not applicable to the production source changes. For the test file, the data source is the `Alarm` model itself (driven by direct method calls), which is the correct test design.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — Flutter toolchain absent (`flutter` binary not on PATH). `flutter test` is the authoritative behavioral gate and is a required human/CI item.

---

### Probe Execution

Step 7c: No `scripts/*/tests/probe-*.sh` files found. SKIPPED.

---

### Requirements Coverage

All five Phase 2 requirements are declared in both plan frontmatters and traced in REQUIREMENTS.md.

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| SNZ-01 | 02-01, 02-02 | Snooze reliably re-rings; never silently fails to re-fire | VERIFIED (source) | Isolate dismiss awaited; `_isEnabled=true` preserved through snooze; `update()` preserves snoozed state. Test SNZ-01/SNZ-05 case passes by source trace. |
| SNZ-02 | 02-01, 02-02 | Fractional snooze lengths honored (no floor to zero) | VERIFIED (source) | `(snoozeLength*60).round()` + `Duration(seconds:...)` + clamp ≥1s. Frozen-clock test asserts exact 30s. |
| SNZ-03 | 02-01, 02-02 | One-shot snoozed-then-dismissed becomes inactive, does not reschedule (#457) | VERIFIED (source) | `_resolveDismiss()` = `cancelSnooze` + `update`; once-alarm disables when runner time is past. `_firedOnceAlarm()` sets up the past-runner precondition. Dates case also covered. |
| SNZ-04 | 02-01, 02-02 | Max snooze count enforced; snooze count persists across isolate boundary | VERIFIED (source) | `maxSnoozeIsReached` gate in `snooze()`. `_snoozeCount` in `toJson`/`fromJson`. `updateAlarmById→saveList` funnel unchanged. |
| SNZ-05 | 02-01, 02-02 | Snooze re-rings without unintentionally dismissing alarm (#495) | VERIFIED (source) | `snooze()` sets `_isEnabled=true`; `update()` preserves snooze when `!DateTime.now().isAfter(_snoozeTime!)`. Test assertion: `isEnabled==true && isSnoozed==true` after unrelated `update()`. |

**Coverage:** 5/5 Phase 2 requirements covered. All marked Complete in REQUIREMENTS.md traceability table. No orphaned requirements.

---

### Anti-Patterns Found

No debt-marker (`TBD`, `FIXME`, `XXX`) or warning-level (`TODO`, `HACK`, `PLACEHOLDER`) patterns found in any of the four Phase 2 modified files (`alarm.dart`, `alarm_isolate.dart`, `alarm_settings_schema.dart`, `alarm_snooze_test.dart`).

Pre-existing issues in `alarm.dart` noted in code review (IN-01 `cancelAllSchedules() {}`, IN-02 `setRingtone` empty body, IN-03 commented-out code blocks) are not introduced by this phase and are not blockers.

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `lib/alarm/types/alarm.dart` | 302 | Empty `cancelAllSchedules() async {}` body (pre-existing) | INFO | Pre-existing dead code; not introduced by Phase 2 |
| `lib/alarm/types/alarm.dart` | 404-406 | `setRingtone { ; }` empty body (pre-existing) | INFO | Pre-existing stub; not introduced by Phase 2 |

---

### Human Verification Required

#### 1. Toolchain Gate: flutter test (authoritative behavioral gate)

**Test:** On a machine with Flutter 3.22.2, push the phase branch:
```
git push <remote> <phase-branch>
gh run watch                          # watch tests.yml
gh run list --branch <phase-branch>   # capture run id + conclusion
```

**Expected:** `tests.yml` runs `flutter test --coverage` and exits 0. The `group('Alarm snooze', ...)` suite (6 cases) passes green. No regressions in the existing test suite. Run id recorded.

**Why human:** Flutter 3.22.2 toolchain is absent in this environment. `tests.yml` triggers on push to any branch, has no `continue-on-error`, and is the project's authoritative test gate. Source inspection is strong but not a substitute for a green CI run.

**Supplementary analyze (informational):**
```
gh workflow run test-apk.yml --ref <phase-branch>
gh run watch   # read the Analyze step log for new issues (continue-on-error — informational)
# download artifact: chrono-dev-release-apk (for smoke below)
```

#### 2. On-Device Smoke: Snooze Re-Rings, Fractional Length, Max Enforced, Once-Alarm Stays Off

**Test:** `flutter run --flavor dev` on a Flutter 3.22.2 device/emulator:
1. Create a "Once" alarm ~1 min out. Let it ring. Tap SNOOZE. Confirm it re-rings after the configured length — test a fractional `Length` like 0.5 → confirm ~30s delay. On the re-ring, tap DISMISS. Relaunch / wait to next day window: the once-alarm must NOT reappear or re-fire. (SNZ-03/#457)
2. Set Max Snoozes to 1. Let the alarm ring, tap SNOOZE (count=1). On re-ring: confirm snooze button is gone (or over-max attempt resolves as dismiss), and the alarm does not get stuck ringing. (SNZ-04)
3. Normal snooze re-rings. Alarm is not silently disabled between snooze and re-ring. (SNZ-01/SNZ-05)

**Expected:** All three scenarios behave as described. Fractional snooze length is visibly honored (re-rings in ~30s, not 0s or 1+ min). Max is enforced without leaving the alarm in a ringing loop. A dismissed once-alarm never reappears.

**Why human:** The isolate boundary, `IsolateNameServer` port delivery, `AndroidAlarmManager` callback, and `RingtonePlayer` are not exercised by the unit tests (FLUTTER_TEST guards no-op the scheduler). The full dismiss→deactivate→no-re-arm path requires a running Android environment.

---

### Gaps Summary

No source-level gaps identified. All Phase 2 source changes are present, substantive, and correctly wired:

- **SNZ-02:** Fractional snooze duration fully implemented — `(snoozeLength*60).round()`, single shared `Duration`, clamped ≥1s, `clock.now()` in `snooze()`. Old `.floor()` form is absent.
- **SNZ-03/#457:** `_resolveDismiss()` (cancelSnooze + update) is schedule-agnostic. The `_firedOnceAlarm()` test helper correctly sets up the past-runner precondition that CR-01 identified as missing. The production code path traced to `once_alarm_schedule.dart:30` is sound.
- **SNZ-04:** Authoritative max-count gate present before `_snoozeCount++`. `_snoozeCount` persists through `toJson`/`fromJson`.
- **SNZ-01/SNZ-05:** Isolate dismiss awaited inside `updateAlarmById` callback. `saveList` persists state before isolate exit.
- **Test suite:** 6 cases covering every SNZ row. `_firedOnceAlarm()` fix resolves CR-01. SNZ-04 persist test now also asserts `isSnoozed` and `isEnabled` round-trip (WR-02 partially addressed).
- **CI scope:** `test-apk.yml` analyze gate correctly repointed to Phase 2 files.
- **Unchanged invariants:** `update_alarms.dart`, `alarm_screen.dart`, `pubspec.yaml`, `pubspec.lock` — all unchanged (confirmed by git diff).

**Two items remain before the phase can be closed:** the `flutter test` run via `tests.yml` (authoritative behavioral gate) and the on-device smoke check. Both are structural requirements that cannot be substituted by source inspection, consistent with the Phase 1 precedent.

---

*Verified: 2026-06-02T23:00:00Z*
*Verifier: Claude (gsd-verifier)*
