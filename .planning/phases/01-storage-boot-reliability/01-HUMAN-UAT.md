---
status: partial
phase: 01-storage-boot-reliability
source: [01-VERIFICATION.md]
started: 2026-05-30
updated: 2026-05-30
---

## Current Test

[awaiting human testing]

## Tests

### 1. On-device reboot-before-unlock (BOOT-01 / BOOT-02 / BOOT-03)
expected: On a secure-lock (PIN/pattern) FBE Android device/emulator (API 24+) with a Flutter 3.22.2 `dev` build installed and ≥2 alarms + 1 timer armed: after `adb reboot` and WITHOUT unlocking, logcat shows a `handleBoot: device locked … deferring` info log and NO `IllegalStateException` / no black screen; after unlock, opening Chrono lands on the normal UI (no splash hang) with alarms/timers still armed and each enabled alarm rescheduled exactly once (no duplicates, no misses). Edge: `adb shell am force-stop com.vicolo.chrono.dev` then reopen → reaches normal UI.
result: [pending]

### 2. One-time alarm-loss notice + TalkBack (BOOT-04 / D-06 accessibility)
expected: With a Flutter build (after `flutter gen-l10n`): corrupting `Clock/alarms.txt` so per-entry salvage drops ≥1 alarm (or making the top-level list invalid) → on next launch the localized "alarms were reset" SnackBar appears exactly once, is announced by TalkBack (Semantics liveRegion reachable), and is dismissible; relaunching again does NOT show it (flag cleared). Negative case: blanking a non-alarm settings file or launching with valid alarms shows NO notice (silent + logged only).
result: [pending]

### 3. Toolchain gate — build, analyze, test (all requirements)
expected: On Flutter 3.22.2 / Dart 3.4+: `flutter gen-l10n` generates the `AppLocalizations.alarmsResetNotice` getter; `flutter analyze lib/` exits 0 (no new issues in the changed files); `flutter test test/common/utils/list_storage_test.dart test/common/utils/json_serialize_test.dart` exits 0. (Test files were authored during execution but NOT run — the Flutter/Dart toolchain is absent in the build environment.)
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
