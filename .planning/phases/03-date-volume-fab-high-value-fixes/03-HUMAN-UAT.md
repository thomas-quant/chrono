---
status: partial
phase: 03-date-volume-fab-high-value-fixes
source: [03-VERIFICATION.md]
started: 2026-06-05T02:00:00Z
updated: 2026-06-05T02:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Specific-date alarm fires on correct calendar day (non-UTC device, after restart)
expected: On a non-UTC Android device (e.g. UTC+9 or UTC-5), a specific-date alarm created for tomorrow still shows/fires on exactly the picked local calendar date after an app restart — not shifted by a day, regardless of the device's UTC offset.
result: [pending]

### 2. Legacy-epoch specific-date alarms self-heal on upgrade
expected: A pre-existing alarm whose dates were serialized as legacy epoch ints (created before this update) self-heals to the originally-picked calendar day on reload; the alarm list does not crash.
result: [pending]

### 3. Rising-volume ramp climbs then stops cleanly on dismiss/snooze
expected: A rising-volume alarm (risingVolumeDuration > 0) audibly climbs to the configured max, then stops the instant the alarm is dismissed or snoozed — no residual/stray volume tick after stop.
result: [pending]

### 4. Lowering volume mid-ring does not kill the ramp
expected: Lowering the volume (Android volume-down / live volume port) while a rising-volume alarm rings does NOT cancel the ramp; the alarm continues climbing toward its configured max (setVolume decoupled from ramp-stop).
result: [pending]

### 5. No cross-alarm volume bleed
expected: Ringing alarm A then alarm B (before A finishes) produces no stray volume ticks from A's ramp after B starts; A's ramp stops cleanly when B's takes over.
result: [pending]

### 6. FAB clearance holds on a real device (portrait + landscape, both styles)
expected: On the alarm list screen in portrait and landscape, Material and non-Material style, the last alarm's menu button (three-dot / swipe actions) is fully visible above the FAB — nothing occluded.
result: [pending]

### 7. FAB clearance holds across a second OEM
expected: The FAB-clearance check passes on a second OEM (e.g. Samsung + Pixel, or Pixel + OnePlus) in both portrait and landscape; no regression in either style.
result: [pending]

### 8. CI tests.yml green on the three new test files
expected: On the next push, CI (tests.yml → flutter test --coverage, headless ubuntu-latest) passes green for date_time_setting_test.dart, volume_ramp_controller_test.dart, and fab_clearance_test.dart. (Toolchain absent locally — CI is the authoritative gate; tests authored + structurally verified, never reported as locally passing.)
result: [pending]

### 9. fab_clearance_test.dart CI stability / degradation decision
expected: If the headless pump throws because appSettings schema construction reaches storage under CI, degrade fab_clearance_test.dart to on-device-only and document per D-TEST-COVERAGE; otherwise confirm it is non-flaky over 3 consecutive CI runs.
result: [pending]

## Summary

total: 9
passed: 0
issues: 0
pending: 9
skipped: 0
blocked: 0

## Gaps
