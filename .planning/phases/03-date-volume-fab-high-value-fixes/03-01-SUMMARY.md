---
phase: 03-date-volume-fab-high-value-fixes
plan: 01
subsystem: settings
tags: [datetime, serialization, timezone, table_calendar, migration, flutter, dart]

# Dependency graph
requires:
  - phase: 01-storage-boot-reliability
    provides: "per-entry tolerant-load / salvage principle (BOOT-04) — a corrupt element must never lose the whole list"
provides:
  - "Date-only YYYY-MM-DD serialization for DateTimeSetting (specific-date alarms persist as a calendar date, not an epoch instant)"
  - "Migrate-on-read of legacy int epoch dates via UTC reinterpretation (already-broken specific-date alarms self-heal on load)"
  - "Picker-boundary normalization: table_calendar UTC-midnight days are stored as local DateTime(y,m,d)"
  - "CI regression suite: test/settings/types/date_time_setting_test.dart (round-trip + legacy migration + RangeAlarmSchedule boundary safety)"
affects: [date-volume-fab-high-value-fixes, qr-barcode-scan-to-dismiss]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Date-only YYYY-MM-DD string serialization with legacy-int (UTC-read) tolerant fallback"
    - "Migrate-on-read: tolerant loadValueFromJson accepts both new String and legacy int, never crashes the list"
    - "Picker output normalized to a local calendar date at the source (onDaySelected / onRangeSelected)"

key-files:
  created:
    - test/settings/types/date_time_setting_test.dart
  modified:
    - lib/settings/types/setting.dart
    - lib/common/widgets/fields/date_picker_bottom_sheet.dart

key-decisions:
  - "Persist specific dates as date-only YYYY-MM-DD strings (D-DATE-FORMAT); no time/offset/Z/T component"
  - "Read legacy int epochs in UTC (isUtc: true) to recover the originally-picked day (D-DATE-MIGRATION) — table_calendar 3.1.1 stored midnight-UTC, confirmed by research"
  - "Malformed/unknown date elements salvage to today's date-only with logger.e rather than throw (Phase-1 BOOT-04 principle)"
  - "RangeAlarmSchedule was PROVEN unaffected by the date-only round-trip — no range_alarm_schedule.dart change needed"

patterns-established:
  - "Tolerant date deserialization: branch on element type (String | int), catch parse errors, salvage to a safe default"
  - "Normalize picker UTC days to local DateTime(y,m,d) at the UI boundary so the off-by-one cannot re-enter"

requirements-completed: [DATE-01, DATE-02]

# Metrics
duration: 4min
completed: 2026-06-05
---

# Phase 3 Plan 01: Specific-Date Off-by-One Fix Summary

**Fixed the specific-date off-by-one at its serialization root: DateTimeSetting now persists a calendar date as a date-only `YYYY-MM-DD` string, the picker normalizes table_calendar's UTC-midnight days to local dates, and legacy epoch values self-heal via a UTC reinterpretation on load.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-05T00:44:23Z
- **Completed:** 2026-06-05T00:47:26Z
- **Tasks:** 3
- **Files modified:** 3 (2 modified, 1 created)

## Accomplishments
- `DateTimeSetting.valueToJson` now emits date-only `YYYY-MM-DD` strings (no epoch instant) — the DATE-01/02 root cause is removed at the JSON round-trip.
- `DateTimeSetting.loadValueFromJson` reads new `String` dates as local `DateTime(y,m,d)` and legacy `int` epochs via `DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)` → `.year/.month/.day`, so already-broken specific-date alarms self-heal on load; malformed values salvage rather than crash the alarm list.
- The `table_calendar` picker output is normalized to a local calendar date at the `onDaySelected` and `onRangeSelected` boundaries, so the off-by-one cannot be re-introduced at the UI.
- Authored `test/settings/types/date_time_setting_test.dart` covering round-trip, legacy-epoch UTC migration, malformed salvage, and the highest-risk `RangeAlarmSchedule` boundary.

## Task Commits

Each task was committed atomically:

1. **Task 1: Date-only serialization with legacy-epoch UTC migration in DateTimeSetting** - `e9041c3` (fix)
2. **Task 2: Normalize the date-picker output to a local calendar date at the source** - `056cfbe` (fix)
3. **Task 3: CI regression suite — date round-trip, legacy-epoch migration, RangeAlarmSchedule safety** - `555d231` (test)

_Note: Task 1 and Task 3 carry `tdd="true"`. With the Flutter/Dart toolchain absent locally (CLAUDE.md Testing Policy), the RED/GREEN cycle could not be run locally; the source fix (Tasks 1–2) and the regression test (Task 3) are authored in-repo and are owed green via CI (`tests.yml` on push). Source-level acceptance was verified by grep, never reported as locally passing._

## Files Created/Modified
- `lib/settings/types/setting.dart` - `DateTimeSetting.valueToJson` now emits `YYYY-MM-DD` strings; `loadValueFromJson` tolerantly reads `String` (local) and legacy `int` (UTC-read) elements with malformed-value salvage; added `logger` import. Change confined to the two `DateTimeSetting` methods + the import.
- `lib/common/widgets/fields/date_picker_bottom_sheet.dart` - `onDaySelected` and `onRangeSelected` normalize the raw `DateTime.utc(y,m,d)` table_calendar days to local `DateTime(y,m,d)` before they enter `_selectedDates`/`onChanged`; the range expansion loop re-normalizes each day to avoid DST drift; `isSameDay` predicates left unchanged.
- `test/settings/types/date_time_setting_test.dart` - **(new)** CI regression: round-trip preserves y/m/d (TZ-agnostic, asserts on components not `==`); legacy `DateTime.utc(2026,6,7).millisecondsSinceEpoch` recovers 2026-06-07; malformed element salvaged not thrown; `RangeAlarmSchedule` finish boundary identical before/after the date-only round-trip for both an in-window and a fully-elapsed range.

## Decisions Made
- **RangeAlarmSchedule did NOT regress.** Per the plan, the boundary was proven by test before any pre-emptive edit. The schedule reads `startDate = value.first` / `endDate = value.last` and compares `getScheduleDateForTime(...).isAfter(endDate)`. Because the picker now feeds local `DateTime(y,m,d)` (midnight) and the in-repo round-trip is a no-op for midnight inputs, the in-window range stays not-finished and the elapsed range stays finished across the round-trip — the last-day boundary does not flip. **No `range_alarm_schedule.dart` boundary normalization was needed.**
- Reading legacy epochs in **UTC** (`isUtc: true`) is load-bearing — research confirmed table_calendar 3.1.1 stored picked days as midnight-UTC, so a local read would re-apply the exact off-by-one (Pitfall 3). The UTC read recovers the originally-picked calendar day.
- Malformed/unknown elements salvage to today's date-only (`logger.e`) rather than throwing — a corrupt date must never lose the whole alarm list (Phase-1 BOOT-04 salvage principle, ASVS V5 tolerant load).

## Deviations from Plan

None - plan executed exactly as written. No bugs, missing-critical functionality, blocking issues, or architectural changes were encountered (deviation Rules 1–4 not triggered). The RangeAlarmSchedule contingency in Task 3 ("normalize the schedule comparison IF the boundary flips") did not fire — the boundary was proven stable, so no schedule edit was made.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Owed CI / Human Gates (toolchain absent locally)
- **`flutter test test/settings/types/date_time_setting_test.dart`** — owed green via CI (`tests.yml` → `flutter test --coverage` on `ubuntu-latest`, headless, UTC runner). The four cases run there; this is the authoritative behavioral gate. CI runs on push; no push performed by this executor (user-authorized only).
- **`flutter analyze`** on the three changed files (`lib/settings/types/setting.dart`, `lib/common/widgets/fields/date_picker_bottom_sheet.dart`, `test/settings/types/date_time_setting_test.dart`) — informational, via `gh workflow run test-apk.yml`. Expect no new issues.
- **On-device (human gate, CI cannot run):** (1) an actual specific-date alarm fires on exactly the picked local calendar day after an app restart on a non-UTC device; (2) a pre-existing legacy-epoch specific-date alarm self-heals to the correct day after the update.

## Next Phase Readiness
- DATE-01 and DATE-02 are source-complete and locked by a CI-runnable regression suite. The date serialization seam is now date-only and migration-tolerant, ready for the volume (VOL-01) and FAB (FAB-01) plans in this phase, which are independent (no shared files).
- No blockers introduced. The only outstanding items are the standard owed CI/human gates above (consistent with Phases 1–2).

## Self-Check: PASSED

- Files: `lib/settings/types/setting.dart`, `lib/common/widgets/fields/date_picker_bottom_sheet.dart`, `test/settings/types/date_time_setting_test.dart`, `03-01-SUMMARY.md` — all FOUND.
- Commits: `e9041c3`, `056cfbe`, `555d231` — all FOUND in git history.

---
*Phase: 03-date-volume-fab-high-value-fixes*
*Completed: 2026-06-05*
