---
status: done
phase: 01-storage-boot-reliability
source: [01-VERIFICATION.md]
started: 2026-05-30
updated: 2026-06-02
closed_by: user-signoff
closure_note: "Closed 2026-06-02 at user direction. Test 3 PASSED via CI; Tests 1 & 2 ACCEPTED without independent verification (see per-test results)."
---

## Current Test

[awaiting human testing]

## Tests

### 1. On-device reboot-before-unlock (BOOT-01 / BOOT-02 / BOOT-03)
expected: On a secure-lock (PIN/pattern) FBE Android device/emulator (API 24+) with a Flutter 3.22.2 `dev` build installed and ≥2 alarms + 1 timer armed: after `adb reboot` and WITHOUT unlocking, logcat shows a `handleBoot: device locked … deferring` info log and NO `IllegalStateException` / no black screen; after unlock, opening Chrono lands on the normal UI (no splash hang) with alarms/timers still armed and each enabled alarm rescheduled exactly once (no duplicates, no misses). Edge: `adb shell am force-stop com.vicolo.chrono.dev` then reopen → reaches normal UI.
result: ACCEPTED BY USER (2026-06-02) — phase closed at user direction. NOT independently verified in this environment (no device/ADB). Source-level verification stands (D-07 probe-and-catch defer-until-unlock guard, time-boxed splash, idempotent `updateAlarms`/`updateTimers` reschedule funnel; see 01-02-SUMMARY). The reboot→reschedule behavior was waived without a recorded on-device run — re-open if a missed/duplicate alarm surfaces after reboot.

### 2. One-time alarm-loss notice + TalkBack (BOOT-04 / D-06 accessibility)
expected: With a Flutter build (after `flutter gen-l10n`): corrupting `Clock/alarms.txt` so per-entry salvage drops ≥1 alarm (or making the top-level list invalid) → on next launch the localized "alarms were reset" SnackBar appears exactly once, is announced by TalkBack (Semantics liveRegion reachable), and is dismissible; relaunching again does NOT show it (flag cleared). Negative case: blanking a non-alarm settings file or launching with valid alarms shows NO notice (silent + logged only).
result: CONVERTED TO AUTOMATED CI COVERAGE (2026-06-01) — on-device manual UAT was impractical (corrupting app-private `alarms.txt` needs root/ADB on a release build). Authored two test files (commit `3e8bd01`):
  - `test/common/logic/salvage_report_test.dart` (unit) — the show/silent gate: `<Alarm>` drop/reset sets the flag; non-Alarm recovery stays silent (negative case); `clear()` resets; flag sticky across mixed losses.
  - `test/app/alarms_reset_notice_test.dart` (widget) — notice shows exactly once on alarm loss then clears the flag; content is a `Semantics(liveRegion)` node (TalkBack announce contract); swipe-dismissible; silent when no alarm lost.
  STATUS: NOT yet executed — Flutter/Dart toolchain absent locally; must go GREEN in CI (Flutter 3.22.2, after `flutter gen-l10n`) before this is PASSED.
  RESIDUAL (not automatable): the *audible* TalkBack announcement and the `GetStorage('onboarded')` onboarding-route gate are not covered by the widget harness (full `App` boot needs platform channels) — accept on the next manual device pass or treat as low-risk given the liveRegion contract is asserted.

### 3. Toolchain gate — build, analyze, test (all requirements)
expected: On Flutter 3.22.2 / Dart 3.4+: `flutter gen-l10n` generates the `AppLocalizations.alarmsResetNotice` getter; `flutter analyze lib/` exits 0 (no new issues in the changed files); `flutter test test/common/utils/list_storage_test.dart test/common/utils/json_serialize_test.dart` exits 0. (Test files were authored during execution but NOT run locally — the Flutter/Dart toolchain is absent in the dev environment.)
result: PASSED via GitHub Actions (fork thomas-quant/chrono, run 26689658169, 2026-05-30). `flutter gen-l10n` ✓, `flutter analyze` (Phase-1 changed files) ✓, `flutter test` ✓ (standalone Tests workflow also green), `flutter build apk --release --flavor dev` ✓ → installable APK artifact `chrono-dev-release-apk`. Note: the debug/D8 build path crashes dexing third-party AARs (tsbackgroundfetch / androidx.lifecycle 2.8.5); the release/R8 build (what ships) is clean.

## Summary

total: 3
passed: 1
accepted: 2
issues: 0
pending: 0
skipped: 0
blocked: 0
notes: |
  Phase closed 2026-06-02 at user direction ("checks waived").
  - Test 3 (toolchain gate): PASSED via CI for real (run 26689658169).
  - Test 1 (on-device reboot): ACCEPTED — not independently verified here (no device/ADB).
  - Test 2 (alarms-reset notice): ACCEPTED — converted to committed CI tests (commit 3e8bd01);
    those tests have NOT yet had a green CI run, so this is acceptance, not a confirmed pass.
  Re-open the phase if either accepted item later fails (a missed/duplicate alarm after reboot,
  or a red CI run on the two new test files).

## Gaps
