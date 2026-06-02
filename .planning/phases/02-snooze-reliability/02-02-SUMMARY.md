---
phase: 02-snooze-reliability
plan: 02
subsystem: alarm-snooze-regression-tests
tags: [snooze, dismiss, test, regression, ci, SNZ-01, SNZ-02, SNZ-03, SNZ-04, SNZ-05, "#457", "#495"]
requires:
  - "Plan 02-01 post-fix Alarm: public async handleDismiss(), clock.now()-based seconds snooze, maxSnoozeIsReached over-max->dismiss gate"
  - "FLUTTER_TEST guards in schedule_alarm.dart (scheduleAlarm/cancelAlarm/scheduleSnoozeAlarm no-op under test)"
provides:
  - "CI-runnable, device-free regression coverage for the SNZ-01..05 snooze state machine (asserts on Alarm flags only)"
  - "Exact-time SNZ-02 proof (now+30s under a frozen clock) enabled by Plan-01's clock.now() switch"
  - "test-apk.yml analyze gate repointed from Phase 1 files to the Phase 2 changed files"
affects:
  - test/alarm/types/alarm_snooze_test.dart
  - .github/workflows/test-apk.yml
tech-stack:
  added: []
  patterns:
    - "withClock(Clock.fixed(...)) frozen-clock unit test pinning clock.now() (analog: test/alarm/logic/alarm_time.dart)"
    - "Direct domain-method drive (snooze()/handleDismiss()) under FLUTTER_TEST, assert on Alarm flags, never on AndroidAlarmManager"
    - "toJson->fromJson round-trip as the disk-durability proof for cross-isolate snoozeCount persistence"
key-files:
  created:
    - test/alarm/types/alarm_snooze_test.dart
  modified:
    - .github/workflows/test-apk.yml
decisions:
  - "Set settings in-test via setSettingWithoutNotify for Length/Max Snoozes/Type/Dates (flattened top-level lookup), matching the construction analog"
  - "Dates SNZ-03 case uses Type=DatesAlarmSchedule + a single past Date; update() on dismiss finishes the schedule (finish()->disable())"
  - "SNZ-02 fixedNow is a fixed future instant (2030-01-01 08:00) so the assertion is deterministic; exact now+30s holds because Plan-01 D-B switched snooze() to clock.now()"
metrics:
  duration: ~7min
  tasks: 2
  files: 2
  completed: 2026-06-02
---

# Phase 2 Plan 02: Snooze Regression Suite + Analyze Repoint Summary

Authored the single new test file for the phase — `test/alarm/types/alarm_snooze_test.dart` — locking in every Plan-01 snooze fix (SNZ-01..05) as CI-runnable, device-free proofs that drive `Alarm.snooze()` / `Alarm.handleDismiss()` directly and assert on `Alarm` flags only (the OS scheduler no-ops under `FLUTTER_TEST`). Also repointed `test-apk.yml`'s informational `flutter analyze` gate from the nine Phase-1 files to the four Phase-2 changed files so a dispatch run's analyze log covers the snooze fix, not Phase-1 code. No `lib/` source change, no new dependency, no `pubspec.yaml` change.

## What Was Built

### Task 1 — `alarm_snooze_test.dart` covering SNZ-01..05 — commit `6e332c2`
New file `test/alarm/types/alarm_snooze_test.dart` (151 lines). Opens `main()` with `TestWidgetsFlutterBinding.ensureInitialized();` (so the statically-constructed `appSettings` schema is reachable for `Alarm()` construction, per the construction analog `alarm_card_test.dart`) and wraps all cases in `group('Alarm snooze', ...)` with a `setUp` that builds a fresh `Alarm(const Time(hour: 2, minute: 30))` per test. Cases authored (one CI-runnable case per SNZ row plus the SNZ-04 persistence round-trip):

- **SNZ-02 (fractional honored, exact under frozen clock):** `setSettingWithoutNotify("Length", 0.5)`, then `await withClock(Clock.fixed(fixedNow), () async { await alarm.snooze(); })` with `fixedNow = DateTime(2030, 1, 1, 8, 0, 0)`. Asserts `alarm.snoozeTime == fixedNow.add(const Duration(seconds: 30))` exactly, asserts it is NOT `fixedNow` (never floored to 0), and `isSnoozed == true`. The exact assertion is valid because Plan-01 D-B switched `snooze()` to read `clock.now()`.
- **SNZ-03 (once → dismiss deactivates, #457):** default once-alarm; `await alarm.snooze()` (asserts `isSnoozed`, `isEnabled`, `snoozeCount == 1`), then `await alarm.handleDismiss()` asserts `isEnabled == false`, `isSnoozed == false`, `snoozeCount == 0`.
- **SNZ-03 dates (#457 generalizes):** `setSettingWithoutNotify("Type", DatesAlarmSchedule)` + `setSettingWithoutNotify("Dates", [DateTime(2000, 1, 1, 2, 30)])` (past). Snooze → dismiss; asserts `isFinished == true`, `isEnabled == false`, `isSnoozed == false` (the dismiss `update()` runs the dates schedule, finds no future date → `_isFinished = true` → `finish()` → `disable()`).
- **SNZ-04 (max gate):** `setSettingWithoutNotify("Max Snoozes", 2)`; three `await alarm.snooze()` calls (1 → 2 → over-max). After the 3rd asserts `snoozeCount != 3`, `snoozeCount == 0`, `isSnoozed == false`, `isEnabled == false` — the over-max attempt resolved as a dismiss (D-A), never left ringing.
- **SNZ-04 persist (disk durability):** `await alarm.snooze()` (count 1), then `Alarm.fromJson(alarm.toJson())` and assert `rebuilt.snoozeCount == 1` — proves the count survives serialization (the cross-isolate source of truth).
- **SNZ-01/SNZ-05 (survives unrelated update):** `await alarm.snooze()` then `await alarm.update("test: unrelated update while snoozed")`; asserts `isEnabled == true` AND `isSnoozed == true` — the pending snooze is preserved, the alarm is not silently disabled.

Asserts only on `Alarm` flags; no assertion references `AndroidAlarmManager` (the single textual occurrence is a comment explaining why the OS is not asserted on). No `lib/` file modified, no `pubspec.yaml` change.

### Task 2 — Repoint `test-apk.yml` analyze gate to the Phase 2 files — commit `09dc3ec`
Edited ONLY the `flutter analyze` argument list (and refreshed the stale Phase-1 comment above it) inside the "Analyze changed files (informational)" step of `.github/workflows/test-apk.yml`. Replaced the nine Phase-1 paths with the four Phase-2 paths:
- `lib/alarm/types/alarm.dart`
- `lib/alarm/logic/alarm_isolate.dart`
- `lib/alarm/data/alarm_settings_schema.dart`
- `test/alarm/types/alarm_snooze_test.dart`

`continue-on-error: true` retained (informational; the analyze log is read for new issues — `alarm.dart` is a large pre-existing file). The `on: workflow_dispatch` trigger and the gen-l10n / test / keystore / build / artifact-upload steps are unchanged (verified by the focused diff).

## How It Fits

- **SNZ-01/SNZ-05:** the "survives unrelated update" case proves a snoozed alarm is never silently disabled by the `triggerAlarm`→`updateAlarms` re-arm funnel re-touching it while a snooze is pending.
- **SNZ-02:** the frozen-clock exact assertion locks the seconds-based, clamped-≥1s snooze duration computed once via `clock.now()` — regressions to `.floor()` minutes would fail this test.
- **SNZ-03/#457:** both the once-alarm and the finished-dates cases prove the shared `_resolveDismiss()` (cancelSnooze + canonical `update()`) deactivates a dismissed alarm so it can never re-arm — generalized beyond once-alarms.
- **SNZ-04:** the max-gate case proves the over-max snooze resolves as a dismiss (never an increment-past-max or a stuck ring); the persistence case proves `snoozeCount` round-trips through JSON (the disk durability the isolate boundary relies on).
- **CI scoping:** `test-apk.yml`'s analyze now covers the actual Phase-2 surface, so a dispatch run's log reflects the snooze fix.

## Decisions Made

- **In-test settings via `setSettingWithoutNotify`** for `Length` / `Max Snoozes` / `Type` / `Dates` — these flatten to top-level lookup on the alarm's `_settings`, matching the construction analog's `setSettingWithoutNotify("Label", ...)`. No storage init or fixtures needed.
- **Dates SNZ-03 setup** = `Type = DatesAlarmSchedule` + a single past `Date`; the dismiss `update()` runs the dates schedule's `schedule()`, finds no future date, sets `_isFinished = true`, and `finish()` → `disable()` deactivates it.
- **SNZ-02 `fixedNow`** = a fixed future instant (`2030-01-01 08:00`) for a fully deterministic assertion; the exact `now + 30s` holds only because Plan-01 D-B switched `snooze()` to `clock.now()` (a tolerance window would have been required otherwise).

## Deviations from Plan

None — both tasks executed exactly as written. No bugs, missing functionality, blocking issues, or architectural changes encountered (deviation Rules 1-4 not triggered). The pre-existing untracked `.claude/` directory was left untouched (out of scope, not part of either task).

## Verification

### Source-level (run locally — all assertions PASS)
- `test -f test/alarm/types/alarm_snooze_test.dart` → EXISTS.
- `grep -F "group('Alarm snooze'"` → line 23. `grep -F 'TestWidgetsFlutterBinding.ensureInitialized();'` → line 21.
- `grep -E "import 'package:clock/clock.dart';"` → line 1 (frozen-clock import present).
- `grep -cE 'snooze\(\)|handleDismiss\(\)'` → 12 (well above the one-per-row minimum).
- `grep -E 'Max Snoozes|Length|snoozeCount|isSnoozed|isFinished|toJson|fromJson' | grep -c .` → 25.
- No `AndroidAlarmManager` assertion (only a clarifying comment). No `lib/` change; no `pubspec.yaml`/`pubspec.lock` change.
- `test-apk.yml`: the four Phase-2 paths present; `lib/common/utils/list_storage.dart` and `lib/system/logic/handle_boot.dart` absent; `continue-on-error: true` retained; `workflow_dispatch` unchanged; gen-l10n / test / keystore / build / upload steps unchanged (focused diff confirms only the analyze step + its comment changed).

### CI / human gates — OWED, not run here
No Flutter/Dart toolchain in this environment (verified absent) and NO push/dispatch performed — both remotes (`origin=thomas-quant/chrono`, `upstream=vicolo-dev/chrono`) are outward-facing and require explicit user authorization that was not given. The following are recorded as owed-via-CI with the exact commands the user can run later:

- **`flutter test` (authoritative behavioral gate):** pushing the phase branch triggers `.github/workflows/tests.yml` → `flutter test --coverage`. The new `group('Alarm snooze', ...)` cases run here.
  ```
  git push <remote> <phase-branch>
  gh run watch                          # tests.yml
  gh run list --branch <phase-branch>   # capture run id + conclusion
  ```
  Owed run id / result: _not yet driven (no push performed)._
- **`flutter analyze` (scoped, informational) + sideloadable APK:** the dispatch build.
  ```
  gh workflow run test-apk.yml --ref <phase-branch>
  gh run watch                          # read the Analyze step log for NEW issues
  # download artifact: chrono-dev-release-apk
  ```
  Owed run id / analyze-log result / APK artifact: _not yet driven (no dispatch performed)._
  Note: PR runs from a fork show `action_required` (need maintainer approval); a direct push to a branch on the repo auto-runs `tests.yml`.

### End-of-phase on-device smoke (the one remaining genuine human gate)
On a Flutter 3.22.2 device/emulator, `flutter run --flavor dev` (consistent with Phase 1's handling):
1. Create a "Once" alarm ~1 min out; let it ring; tap SNOOZE; confirm it re-rings after the configured length (test a fractional `Length` like 0.5 → ~30s); on the re-ring tap DISMISS. Relaunch / wait to the next day window: the once-alarm must NOT reappear or re-fire (SNZ-03/#457).
2. Set Max Snoozes low (e.g. 1); snooze up to max; confirm the snooze button disappears and the alarm cannot exceed max (and never gets stuck ringing) (SNZ-04).
3. Confirm a normal snooze re-rings and does NOT silently disable the alarm (SNZ-01/SNZ-05).

## Known Stubs

None — the test file is complete behavioral coverage wired end-to-end (drives real `Alarm` methods, asserts real flags). No placeholder values, no TODO/FIXME introduced, no mocked/empty data source.

## Threat Flags

None — this plan adds a test file and edits a CI workflow's analyze argument list. No new network endpoint, auth path, file-access pattern, or schema change at a trust boundary. The ephemeral-keystore step in `test-apk.yml` is unchanged.

## Self-Check: PASSED

- `test/alarm/types/alarm_snooze_test.dart` — FOUND; contains `group('Alarm snooze'`, `TestWidgetsFlutterBinding.ensureInitialized();`, `import 'package:clock/clock.dart';`, `withClock(`, `snooze()`/`handleDismiss()`, `toJson`/`fromJson`.
- `.github/workflows/test-apk.yml` — FOUND; contains the four Phase-2 analyze paths; Phase-1 paths absent.
- Commits `6e332c2` (test) and `09dc3ec` (ci) — both FOUND in `git log`.
- No `lib/` or `pubspec.yaml` change introduced by this plan.
