---
status: partial
phase: 02-snooze-reliability
source: [02-VERIFICATION.md]
started: "2026-06-02T23:15:00Z"
updated: "2026-06-02T23:15:00Z"
---

## Current Test

[awaiting human testing]

## Tests

### 1. Toolchain gate: flutter test (authoritative behavioral gate)
expected: Pushing the phase branch to the repo triggers `.github/workflows/tests.yml`, which runs `flutter test --coverage` (no `continue-on-error`) on Flutter 3.22.2. The new `group('Alarm snooze', ...)` suite — 6 cases (SNZ-02, SNZ-03 once, SNZ-03 dates, SNZ-04 max, SNZ-04 persist, SNZ-01/05) — all pass green, and no existing tests regress.
how: `git push <remote> <phase-branch>` then `gh run watch` / `gh run list --branch <phase-branch>`. (Outward-facing — push only with explicit authorization. Targets a GitHub remote.)
result: [pending]

### 2. On-device smoke: snooze re-rings, fractional length honored, max enforced, once-alarm stays off after dismiss (SNZ-01..05)
expected: On a Flutter 3.22.2 device/emulator (`flutter run --flavor dev`): (a) a one-shot alarm snoozed then dismissed re-rings after the configured length, then on dismiss does NOT reappear/re-fire (SNZ-01/03/05, #457); (b) a fractional Length (e.g. 0.5 → ~30s) is honored, never instant, never floored to 0 (SNZ-02); (c) with Max Snoozes low, the max is enforced and the alarm never gets stuck ringing (SNZ-04). Optionally build the APK via `gh workflow run test-apk.yml --ref <phase-branch>` and sideload.
how: Run on a real Android device — the alarm isolate, `IsolateNameServer` ports, `AndroidAlarmManager` callbacks, and `RingtonePlayer` are all no-ops under `FLUTTER_TEST`, so unit tests cannot exercise this path.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
