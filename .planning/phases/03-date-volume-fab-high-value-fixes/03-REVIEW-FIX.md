---
phase: 03-date-volume-fab-high-value-fixes
fixed_at: 2026-06-05T01:19:54Z
review_path: .planning/phases/03-date-volume-fab-high-value-fixes/03-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-06-05T01:19:54Z
**Source review:** .planning/phases/03-date-volume-fab-high-value-fixes/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (WARNING-severity WR-01..WR-05; INFO items IN-01..04 intentionally out of scope per phase constraints)
- Fixed: 5
- Skipped: 0

## Fixed Issues

### WR-01: Full-volume blip before rising-volume ramp resets to 0

**Files modified:** `lib/audio/types/ringtone_player.dart`
**Commit:** 04a484c
**Applied fix:** In `RingtonePlayer._play`, computed `willRamp = secondsToMaxVolume > 0` and changed the pre-play seed from `await setVolume(volume)` to `await setVolume(willRamp ? 0.0 : volume)`. When a rising-volume ramp will run, the player is now seeded to 0 and the ramp owns the climb, eliminating the brief full-volume window before `start()`'s leading `_setVolume(0)`. The ramp-start condition was switched to reuse the same `willRamp` flag. Non-ramping playback (preview via `playUri`) is unchanged — it still seeds to the full target. The pure `VolumeRampController` is untouched, so its CI suite (`volume_ramp_controller_test.dart`) still holds.

### WR-02: Range-fill loop cursor drifts across a DST boundary

**Files modified:** `lib/common/widgets/fields/date_picker_bottom_sheet.dart`
**Commit:** 0c87ed9
**Applied fix:** In the non-rangeOnly `onRangeSelected` fill loop, replaced the cursor advance `date = date.add(const Duration(days: 1))` (a fixed 24h instant) with a calendar-date rebuild `date = DateTime(date.year, date.month, date.day + 1)`, which is DST-safe (a `day + 1` rebuild always lands on the next local midnight regardless of a 23h spring-forward or 25h fall-back day). The previously misleading comment — which claimed the per-step `DateTime(...)` *normalization of the stored value* fixed DST drift, while the cursor was still advanced by a fixed Duration — was rewritten to accurately describe that the **cursor advance** is now the DST-safe step.

**Note:** This is a logic change to the loop's iteration count; flagged for human verification that the boundary-day inclusion is correct under multi-month, DST-straddling ranges. No CI test currently exercises this date-picker fill loop directly.

### WR-03: FAB clearance was a hardcoded constant that could silently desync from fab.dart

**Files modified:** `lib/common/widgets/fab.dart`, `lib/common/widgets/list/custom_list_view.dart`, `test/common/widgets/list/fab_clearance_test.dart`
**Commit:** fb6d7e6
**Applied fix:** Exported shared FAB-geometry constants from `fab.dart` as the single source of truth: `fabIconPadding = 16`, `fabIconSize = 24`, `fabMaterialExtraOffset = 20`, and the derived `fabExtent = fabIconPadding * 2 + fabIconSize` (= 56). Refactored `fab.dart`'s own layout to consume them (`EdgeInsets.all(fabIconPadding)`, `size: fabIconSize * widget.size`, `bottomPadding + fabMaterialExtraOffset`). `custom_list_view.dart` now imports `fab.dart` and derives `fabBottomClearance = 8 + fabExtent + fabIconPadding + (useMaterialStyle ? fabMaterialExtraOffset : 0)`, numerically equivalent to the previous `8 + 56 + 16 + (… ? 20 : 0)`. `fab_clearance_test.dart` now imports the shared `fabExtent` / `fabMaterialExtraOffset` instead of re-hardcoding `56` / `20`, so the test can now catch a `fab.dart` drift. No circular import is introduced (`fab.dart` does not depend on `custom_list_view.dart`).

### WR-04: Range while-loop could produce a 1-element "range" for a reversed range

**Files modified:** `lib/common/widgets/fields/date_picker_bottom_sheet.dart`
**Commit:** 1aa246b
**Applied fix:** After the raw table_calendar days are normalized to local calendar dates in `onRangeSelected`, added an order-normalization guard: when both dates are non-null and `endDate.isBefore(startDate)`, the two are swapped via a local `DateTime swap` temporary before `setState`. This ensures both the rangeOnly assignment (`[startDate, endDate]`), the fill loop, and the stored `_rangeStartDate`/`_rangeEndDate` always receive an ordered pair, so a reversed range (e.g. from unordered programmatic `initialDates`) can no longer skip the fill loop and silently append only `endDate` as a 1-element list while `_isSaveEnabled` stays true. Null-safety is preserved (both operands checked non-null before `isBefore`).

**Note:** This is a logic change (added ordering branch); flagged for human verification that the swap interacts correctly with `_isSaveEnabled` (which requires exactly 2 selected dates in rangeOnly mode). No CI test currently exercises this date-picker range path directly.

### WR-05: `DateTimeSetting.loadValueFromJson` accepted malformed `YYYY-MM-DD` with out-of-range parts

**Files modified:** `lib/settings/types/setting.dart`, `test/settings/types/date_time_setting_test.dart`
**Commit:** 8fbb278
**Applied fix:** In the new-format `String` branch of `loadValueFromJson`, added validation before constructing the `DateTime`: throw a `FormatException` if `parts.length != 3` (rejects both too-few parts and trailing junk like `'2026-06-07-extra'`), and throw if `month < 1 || month > 12 || day < 1 || day > 31` (rejects silent rollover from corrupt strings like `'2026-13-40'`). Both throws route to the existing catch-block salvage path (fall back to today's date-only, the Phase-1 BOOT-04 salvage principle), so a corrupt persisted date can no longer load as a plausible-but-wrong date. Added two CI tests to `date_time_setting_test.dart` asserting that `'2026-13-40'` and `'2026-06-07-extra'` are salvaged to today rather than silently rolled over / truncated. The existing salvage test (`'not-a-date'` -> 1 part) and valid-date tests still hold.

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-06-05T01:19:54Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
