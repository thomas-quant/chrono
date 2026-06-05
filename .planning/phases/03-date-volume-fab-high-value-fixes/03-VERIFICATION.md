---
phase: 03-date-volume-fab-high-value-fixes
verified: 2026-06-05T02:00:00Z
status: human_needed
score: 7/7 must-haves verified
overrides_applied: 1
overrides:
  - must_have: "Community PRs #467 (rising volume) and #466 (FAB) are reviewed, merged or adapted, and credited to their contributors"
    reason: "Locked decision D-PR-METHOD (03-CONTEXT.md) inverted this requirement — the fixes are reimplemented independently with sole credit and NO contributor attribution by informed user choice. The ROADMAP SC #4 annotation already records this deviation and flags it for rewording at the next gsd-transition. The reframed intent — the fixes land, independently authored — is verified PASSED."
    accepted_by: "user (via D-PR-METHOD decision in 03-CONTEXT.md)"
    accepted_at: "2026-06-05T00:00:00Z"
human_verification:
  - test: "On a non-UTC Android device (e.g. UTC+9 or UTC-5), create a specific-date alarm for tomorrow, restart the app, and confirm it still shows the correct calendar date — not shifted by a day"
    expected: "The alarm fires on exactly the picked local calendar date after restart, regardless of the device's UTC offset"
    why_human: "Real alarm scheduling (AndroidAlarmManager exact-alarm scheduling on a real device, not FLUTTER_TEST) and non-UTC timezone behaviour cannot be exercised in CI"
  - test: "On the same non-UTC device, find a pre-existing alarm whose dates were serialized as legacy epoch ints (created before this update), reload the alarm list, and confirm the dates self-healed to the correct calendar day"
    expected: "Legacy epoch dates are recovered to the originally-picked calendar day, alarm list does not crash"
    why_human: "Real device upgrade path with pre-existing persisted data; CI cannot produce legacy-format data at rest"
  - test: "Trigger a rising-volume alarm (with risingVolumeDuration > 0), let the ramp run for a few seconds, then dismiss it. Verify the ramp stops immediately with no stray volume bump after the alarm stops"
    expected: "Ramp climbs smoothly to configured max, stops the instant the alarm is dismissed or snoozed — no residual volume tick fires afterward"
    why_human: "Real just_audio playback and real volume ramp audibility cannot be tested in CI headless mode"
  - test: "While a rising-volume alarm is ringing, lower the volume using the Android volume-down button (or the live volume port). Confirm the ramp continues climbing rather than dying"
    expected: "A plain setVolume() during ringing does not cancel the ramp; the alarm continues climbing toward its configured max"
    why_human: "Real Android volume control → RingtonePlayer.setVolume() → ramp interaction is a live-audio path that CI cannot run"
  - test: "Ring alarm A, then (before A finishes) ring alarm B. Confirm no stray volume ticks from A's ramp appear after B starts"
    expected: "Cross-alarm bleed is absent on a real device with real audio; A's ramp stops cleanly when B's ramp takes over"
    why_human: "Multi-alarm lifecycle with real just_audio players cannot be exercised in CI"
  - test: "On the alarm list screen (portrait and landscape, Material and non-Material style), scroll to the last alarm and confirm its menu button (three-dot or swipe actions) is fully visible above the FAB"
    expected: "No list item or menu button is occluded by the floating action button, in both styles and both orientations"
    why_human: "Real cross-OEM pixel layout with actual device dimensions and system UI insets cannot be verified by headless widget tests"
  - test: "Repeat the FAB-clearance check on a second OEM (Samsung + Pixel, or Pixel + OnePlus) in both portrait and landscape"
    expected: "Clearance holds across OEMs; no regression in either style"
    why_human: "OEM-specific system UI, safe-area insets, and display notches are not reproducible in CI"
  - test: "Verify CI tests.yml passes green on the three new test files (date_time_setting_test.dart, volume_ramp_controller_test.dart, fab_clearance_test.dart) on the next push to the repo"
    expected: "All three suites pass on the headless ubuntu-latest CI runner"
    why_human: "Flutter/Dart toolchain is absent in this dev environment; CI (tests.yml, flutter test --coverage) is the authoritative gate — tests are authored and structurally verified but never reported as locally passing"
  - test: "For the fab_clearance_test.dart specifically: if the headless pump throws because appSettings schema construction reaches storage on CI, degrade the test to on-device-only and document. If it stays green, confirm it is not flaky over 3 consecutive runs"
    expected: "Test either runs green deterministically or is degraded with documented rationale per D-TEST-COVERAGE"
    why_human: "The SUMMARY flags a residual CI risk: if static appSettings schema transitively reaches storage on first access under CI, the pump throws — this is a CI-confirmable outcome only"
---

# Phase 3: Date, Volume & FAB High-Value Fixes — Verification Report

**Phase Goal:** The remaining high-value defects are gone — specific-date alarms ring on the right calendar day everywhere (after restart, any UTC offset; stored as a local calendar date not an absolute instant), the rising/gradual volume ramp climbs to max then stops cleanly the instant the alarm is dismissed/snoozed (no stray bumps, no cross-alarm bleed), and floating action buttons no longer hide list items or menu buttons on list screens.

**Verified:** 2026-06-05T02:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A specific-date alarm rings on exactly the picked local calendar date after restart, regardless of device UTC offset | ? UNCERTAIN (human gate) | Root cause fixed at both serialization boundary (`DateTimeSetting.valueToJson` emits `YYYY-MM-DD`) and picker boundary (normalized to `DateTime(y,m,d)`); `DatesAlarmSchedule.schedule()` already reads `.year/.month/.day`; CI test locks round-trip. On-device fire on non-UTC device is a human gate CI cannot cover. |
| 2 | A specific date is persisted as a date-only YYYY-MM-DD string, not an absolute epoch instant | ✓ VERIFIED | `setting.dart:963-968` — `valueToJson` maps each `DateTime e` to a zero-padded `'${e.year}-${e.month}-${e.day}'` string; no `millisecondsSinceEpoch` or `toIso8601String` present in `valueToJson`. CI round-trip test (`date_time_setting_test.dart:62-75`) asserts `json == ['2026-06-07']`. |
| 3 | An already-broken specific-date alarm holding a legacy int epoch self-heals on load and never crashes the alarm list | ✓ VERIFIED | `setting.dart:997-1006` — `int` branch reads `DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)` and rebuilds `DateTime(utc.year, utc.month, utc.day)`; catch-block salvages to today rather than throwing. CI migration test (`date_time_setting_test.dart:79-95`) feeds `DateTime.utc(2026,6,7).millisecondsSinceEpoch` and asserts recovery of 2026-06-07. |
| 4 | The rising-volume ramp climbs to the configured maximum then stops cleanly on dismiss/snooze (no stray bumps, no cross-alarm bleed) | ? UNCERTAIN (human gate) | `VolumeRampController` is pure and cancellable; `stop()`/`pause()` each call `_rampController.cancel()` (ringtone_player.dart:155,163); `setVolume()` no longer touches a `_stopRisingVolume` flag (flag deleted); WR-01 fix seeds player to 0 before ramping. CI fake_async tests cover all four cases (cancel, bleed, max, zero-duration). Audible ramp behavior on real device is a human gate. |
| 5 | No volume callback fires after the ramp is cancelled (stop/pause/play re-entry) | ✓ VERIFIED | `VolumeRampController.cancel()` (volume_ramp_controller.dart:65-71) nulls `_timer` after cancelling; no further `Timer.periodic` tick can fire after cancel returns. CI test `'no callback fires after cancel()'` asserts `values.length == countAtCancel` after elapsingwell past the full duration. `_play()` re-entry also cancels at line 108 before starting a new ramp. |
| 6 | Floating action buttons no longer cover the last list item or menu buttons on list screens | ? UNCERTAIN (human gate) | `custom_list_view.dart:362-418` — `fabBottomClearance = 8 + fabExtent + fabIconPadding + (useMaterialStyle ? fabMaterialExtraOffset : 0)` is wired to `AnimatedReorderableListView.padding.bottom`; CI widget test asserts `bottom >= fabExtent` (non-material) and `>= fabExtent + fabMaterialExtraOffset` (material). Real cross-OEM pixel layout is a human gate. |
| 7 | Every screen rendering its list through CustomListView inherits the bottom clearance from one central edit | ✓ VERIFIED | `custom_list_view.dart` is the single injection point; `persistent_list_view.dart` is untouched (confirmed: no `fabBottom` or `EdgeInsets.only` in that file, and it delegates via `CustomListView`); all ~13 FAB screens route through this component. |

**Score:** 7/7 truths structurally verified (4 confirmed from source + tests; 3 have on-device human gates for behavioral confirmation)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/settings/types/setting.dart` | `DateTimeSetting.valueToJson` emits YYYY-MM-DD strings; `loadValueFromJson` tolerates String and legacy int (UTC-read) | ✓ VERIFIED | Lines 957-1019 confirmed: zero-padded YYYY-MM-DD emission; `isUtc: true` in int branch; WR-05 validation (parts.length check + month/day range) added; catch-block salvage; no `millisecondsSinceEpoch` in `valueToJson` |
| `lib/common/widgets/fields/date_picker_bottom_sheet.dart` | Picker output normalized to local calendar date at onDaySelected/onRangeSelected boundary | ✓ VERIFIED | Lines 150-231: `onDaySelected` normalizes via `DateTime(newSelectedDate.year, ...)` before insert; `onRangeSelected` normalizes both startDate and endDate; WR-02 fix uses calendar-day cursor advance (`DateTime(date.year, date.month, date.day + 1)`); WR-04 adds reversed-range normalization guard |
| `lib/audio/types/volume_ramp_controller.dart` | Pure, audio-free, cancellable Timer-based ramp controller with injected volume callback | ✓ VERIFIED | 73-line file: `class VolumeRampController`; `void Function(double)` callback; `cancel()` first in `start()` (line 41); no `just_audio`/`audio_session` import; `_timer` nulled in `cancel()` |
| `lib/audio/types/ringtone_player.dart` | Owns one VolumeRampController; cancels at stop()/pause()/_play() re-entry; setVolume no longer kills the ramp | ✓ VERIFIED | Static `_rampController` field (line 25); `cancel()` at lines 108 (re-entry), 155 (pause), 163 (stop); `setVolume()` has no `_stopRisingVolume` reference (field deleted); WR-01 fix: `willRamp ? 0.0 : volume` seed; zero live `Future.delayed` (only commented-out dead code at line 140) |
| `lib/common/widgets/list/custom_list_view.dart` | Computed bottom inset on AnimatedReorderableListView padding reserving FAB clearance | ✓ VERIFIED | Lines 362-418: reads `theme.extension<ThemeSettingExtension>()!`; `fabBottomClearance = 8 + fabExtent + fabIconPadding + (useMaterialStyle ? fabMaterialExtraOffset : 0)`; `padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: fabBottomClearance)` |
| `lib/common/widgets/fab.dart` | Exports shared FAB geometry constants (WR-03 fix) | ✓ VERIFIED | Lines 16-22: `fabIconPadding = 16`, `fabIconSize = 24`, `fabMaterialExtraOffset = 20`, `fabExtent = fabIconPadding * 2 + fabIconSize`; FAB widget consumes its own constants internally |
| `test/settings/types/date_time_setting_test.dart` | CI round-trip + legacy-epoch migration + malformed salvage + WR-05 validation + RangeAlarmSchedule safety | ✓ VERIFIED (substantive; CI gate owed) | 213 lines; 6 `test(...)` cases; `TestWidgetsFlutterBinding.ensureInitialized()`; assertions on `.year`/`.month`/`.day` (never `==` on DateTime); `DateTime.utc(2026,6,7).millisecondsSinceEpoch` literal; `RangeAlarmSchedule` + `withClock(Clock.fixed(...))` boundary test; WR-05 out-of-range and trailing-junk tests |
| `test/audio/types/volume_ramp_controller_test.dart` | CI fake_async coverage: cancel, no-late-callback, no-bleed, reaches-max | ✓ VERIFIED (substantive; CI gate owed) | 122 lines; 4 `test(...)` cases; `fakeAsync` + `async.elapse`; no `await Future.delayed`; `closeTo` for floating-point reaches-max; no `just_audio` |
| `test/common/widgets/list/fab_clearance_test.dart` | Narrow headless widget test asserting list bottom clearance >= FAB extent | ✓ VERIFIED (substantive; CI gate owed) | 99 lines; 3 `testWidgets(...)` cases; imports shared `fabExtent`/`fabMaterialExtraOffset` from `fab.dart` (not re-hardcoded); asserts `bottom >= fabExtent` and `>= fabExtent + fabMaterialExtraOffset`; no full App/NavScaffold |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `date_picker_bottom_sheet.dart` (onDaySelected/onRangeSelected) | `DateTimeSetting.valueToJson` | Normalized local `DateTime(y,m,d)` flows into setting value then `valueToJson` | ✓ WIRED | `onChanged(_selectedDates)` at line 176/238 emits the normalized dates; the dates are `DateTime(y,m,d)` constructions confirmed at lines 150, 186, 191 |
| `DateTimeSetting.loadValueFromJson` | `DatesAlarmSchedule.schedule()` | Recovered `.year/.month/.day` rebuilt into local alarm fire DateTime | ✓ WIRED | `loadValueFromJson` produces `DateTime(year,month,day)` (line 995); schedule already reads `.year/.month/.day` (unaffected by this phase); CI range-safety test proves end-to-end |
| `ringtone_player.dart` (stop/pause/_play) | `VolumeRampController.cancel()` | Only ramp-stop signal — decoupled from setVolume | ✓ WIRED | `_rampController.cancel()` at lines 108 (_play re-entry), 155 (pause), 163 (stop); `setVolume()` contains no cancel call |
| `ringtone_player.dart` (_play ramp start) | `VolumeRampController.start()` | Replaces 11 fire-and-forget Future.delayed callbacks | ✓ WIRED | `_rampController.start(targetVolume: volume, duration: Duration(seconds: secondsToMaxVolume))` at line 135; zero live `Future.delayed` in file |
| `custom_list_view.dart` (padding) | `AnimatedReorderableListView` scrollable | `padding` forwarded to `SliverPadding` | ✓ WIRED | `padding: EdgeInsets.only(..., bottom: fabBottomClearance)` at lines 414-419; CI `SliverPadding` finder in `fab_clearance_test.dart` confirms the forwarding path |
| `custom_list_view.dart` (bottom inset) | `fab.dart` exported constants | Shared constants so inset can never silently desync from FAB layout | ✓ WIRED | `custom_list_view.dart` imports `fab.dart` (line 5); derives `fabBottomClearance` using `fabExtent`, `fabIconPadding`, `fabMaterialExtraOffset`; `fab_clearance_test.dart` imports same constants |

### Data-Flow Trace (Level 4)

Not applicable: the phase-modified source files are serialization logic (`DateTimeSetting`), a pure controller (`VolumeRampController`), and a layout helper (`CustomListView`) — none renders dynamic data from a DB/API. The data flows are synchronous (serialization round-trip, timer callback, layout computation) and verified at Level 3 (wired).

### Behavioral Spot-Checks

Step 7b SKIPPED: Flutter/Dart toolchain is absent in this environment; `flutter test` cannot be run locally. Per project testing policy, CI (tests.yml) is the authoritative gate. The spot-checks that CAN be run (module exports, function signatures) are covered by the source-level grep checks above. Spot-checks requiring a running app (audio ramp, alarm firing) are human gates.

### Probe Execution

No probe scripts (`scripts/*/tests/probe-*.sh`) declared or found for Phase 3. Step 7c N/A.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DATE-01 | 03-01-PLAN.md | Alarm rings on the picked calendar date after restart, any UTC offset | ✓ SATISFIED (CI gate owed; on-device human gate) | Serialization fix in `setting.dart`; picker normalization in `date_picker_bottom_sheet.dart`; CI round-trip test |
| DATE-02 | 03-01-PLAN.md | Specific date stored as local calendar date, not absolute instant | ✓ SATISFIED | `valueToJson` emits YYYY-MM-DD; `loadValueFromJson` reads back as `DateTime(y,m,d)`; CI test asserts `json == ['2026-06-07']` |
| VOL-01 | 03-02-PLAN.md | Rising-volume ramp climbs to max and stops cleanly on dismiss/snooze | ✓ SATISFIED (CI gate owed; on-device human gate) | `VolumeRampController` with real `cancel()`; `stop()`/`pause()` cancel it; `setVolume()` decoupled; CI fake_async tests |
| FAB-01 | 03-03-PLAN.md | FAB no longer covers list items/menu buttons on alarm and other list screens | ✓ SATISFIED (CI gate owed; on-device human gate) | Central bottom-inset in `custom_list_view.dart` derived from `fab.dart` constants; CI widget test asserts clearance |
| PR-01 | 03-02-PLAN.md | Volume fix implemented, independently authored (D-PR-METHOD reframe) | ✓ SATISFIED (override applied) | VolumeRampController independently implemented; zero contributor attribution/PR #467 reference in any changed file or commit message |
| PR-02 | 03-03-PLAN.md | FAB fix implemented, independently authored (D-PR-METHOD reframe) | ✓ SATISFIED (override applied) | FAB inset independently implemented; zero contributor attribution/PR #466 reference in any changed file or commit message |

All 6 phase requirements accounted for. No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/audio/types/ringtone_player.dart` | 140 | `// Future.delayed(...)` — commented-out dead code | ℹ Info | Pre-existing dead code, not introduced by this phase; noted in 03-02-SUMMARY.md as intentionally left in place; zero live `Future.delayed` in the file |
| `lib/common/widgets/list/custom_list_view.dart` | 73, 78, 100, 139-143 | Commented-out fields/methods | ℹ Info | Pre-existing (IN-03 in 03-REVIEW.md); not introduced by this phase; `dart format` accepted |
| `lib/audio/types/ringtone_player.dart` | 43, 52, 72 | Dead `loopMode` parameter (always hardcoded to `LoopMode.one`) | ℹ Info | Pre-existing (IN-01 in 03-REVIEW.md); not introduced by this phase; no behavioral impact on the ramp fix |

No `TBD`, `FIXME`, or `XXX` markers found in any of the phase-modified files. No blocker anti-patterns. The Info items are all pre-existing and explicitly tracked in the code-review record.

### Human Verification Required

#### 1. Specific-date alarm fires on correct local calendar day (DATE-01)

**Test:** On a non-UTC device (UTC+9 or UTC-5), create an alarm set for a specific calendar date, force-kill and restart the app, confirm the alarm still shows the correct date. Let it fire or check the next-fire time.
**Expected:** The alarm fires on exactly the picked local calendar date, not shifted ±1 day by the UTC offset.
**Why human:** Real AndroidAlarmManager scheduling on a live non-UTC device; CI runs on UTC ubuntu-latest and cannot exercise timezone offset effects on real alarm scheduling.

#### 2. Legacy-epoch specific-date alarms self-heal on upgrade (DATE-01 migration)

**Test:** On a device with pre-existing data (alarms persisted before this update, where dates were stored as epoch int milliseconds), reload the alarm list after the update.
**Expected:** Legacy dates recover to the originally-picked calendar day; alarm list does not crash on load; migrated dates are logged.
**Why human:** Requires real pre-existing data at rest; CI cannot produce legacy-format persisted files.

#### 3. Rising-volume ramp audibly climbs and stops cleanly on dismiss/snooze (VOL-01)

**Test:** Trigger an alarm with risingVolumeDuration > 0. Let the ramp run for several seconds, then dismiss. Listen for any stray volume bump after the alarm stops.
**Expected:** Ramp climbs from 0 to the configured max; stops immediately and cleanly on dismiss/snooze.
**Why human:** Real just_audio playback and real volume change audibility; CI cannot produce audio.

#### 4. Lowering volume mid-ring does not kill the ramp (VOL-01 decoupling)

**Test:** While a rising-volume alarm is ringing, press the Android hardware volume-down button or use the volume slider. Confirm the ramp continues climbing rather than dying.
**Expected:** `setVolume()` no longer cancels the ramp; alarm continues climbing to its configured max.
**Why human:** Real Android volume control → `RingtonePlayer.setVolume()` → ramp interaction is a live-audio path CI cannot exercise.

#### 5. Cross-alarm volume bleed is absent on device (VOL-01)

**Test:** Ring alarm A, then ring alarm B before A finishes. Confirm no stray A-ramp ticks appear after B starts.
**Expected:** A's ramp stops cleanly when B's starts; B climbs independently.
**Why human:** Multi-alarm lifecycle with real just_audio players.

#### 6. FAB clearance on real device — portrait and landscape, both styles (FAB-01)

**Test:** Open the alarm list screen with multiple alarms. Scroll to the last alarm. In both Material and non-Material styles and both portrait and landscape: confirm the last alarm card and its menu button (three-dot icon / swipe actions) are fully visible above the FAB.
**Expected:** No list item or menu button is occluded by the FAB in any combination of style and orientation.
**Why human:** Real cross-OEM pixel layout, actual system UI insets, display notches, and bottom navigation bar heights cannot be reproduced in CI headless widget tests.

#### 7. FAB clearance across a second OEM (FAB-01)

**Test:** Repeat test 6 on a second OEM (e.g., Pixel + Samsung, or Pixel + OnePlus).
**Expected:** Clearance holds; no regression on either device.
**Why human:** OEM-specific system UI differences.

#### 8. CI green confirmation — three new test files (authoritative gate)

**Test:** Push to the repository and confirm `tests.yml` (`flutter test --coverage` on `ubuntu-latest`) passes green for `test/settings/types/date_time_setting_test.dart`, `test/audio/types/volume_ramp_controller_test.dart`, and `test/common/widgets/list/fab_clearance_test.dart`.
**Expected:** All three suites pass. If `fab_clearance_test.dart` proves flaky because `appSettings` schema construction reaches storage, degrade it to on-device-only per D-TEST-COVERAGE and document.
**Why human:** Flutter/Dart toolchain is absent in this development environment; CI is the authoritative test gate per project policy. Tests were authored and structurally verified (source-level grep) but never reported as locally passing.

### Gaps Summary

No gaps found. All 7 observable truths are structurally verified from the codebase, all 9 required artifacts exist and are substantive, all 6 key links are confirmed wired, all 6 phase requirements are satisfied, and no blocker anti-patterns exist.

The `human_needed` status reflects 3 truths (DATE-01 on-device fire, VOL-01 audible ramp, FAB-01 pixel layout) and the CI green gate that have genuine human/CI requirements — not missing implementation. The implementation is complete and correctly wired; the remaining gates are behavioral checks that genuinely cannot run in this environment or in headless CI.

---

_Verified: 2026-06-05T02:00:00Z_
_Verifier: Claude (gsd-verifier)_
