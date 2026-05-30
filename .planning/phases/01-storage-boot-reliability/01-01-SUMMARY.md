---
phase: 01-storage-boot-reliability
plan: 01
subsystem: storage
tags: [dart-io, json, atomic-write, file-rename, salvage, get-storage, settings]

# Dependency graph
requires: []
provides:
  - "Crash-atomic file writes (temp-write + rename) in saveTextFile/saveRingtone — STOR-01"
  - "Per-entry salvage in listFromString: a single corrupt entry is skipped+logged, the rest load — BOOT-04"
  - "loadList never throws (mirrors loadListSync) — top-level unparseable list recovers to []"
  - "Null-safe SettingGroup.load(): null/empty/invalid recovers to schema defaults, GetStorage fallback kept — STOR-02"
  - "SalvageReport module-level alarm-loss flag (alarmsWereLost/markEntryDropped/markListReset/clear) — D-06"
  - "Test-only setAppDataDirectoryPathForTesting() hook in paths.dart for storage unit tests"
affects: [02-boot-reschedule, 03-alarms-lost-notice, snooze-reliability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic temp+rename write inside the shared file-I/O queue"
    - "Per-entry try/catch salvage on JSON list load (skip+log bad, keep good)"
    - "Module-level static flag for cross-cutting recovery signal (no state-mgmt lib)"
    - "Guarded json.decode everywhere: null/empty/invalid -> log + defaults, never throw"

key-files:
  created:
    - lib/common/logic/salvage_report.dart
    - test/common/utils/list_storage_test.dart
    - test/common/utils/json_serialize_test.dart
  modified:
    - lib/common/utils/list_storage.dart
    - lib/common/utils/json_serialize.dart
    - lib/settings/types/setting_group.dart
    - lib/common/data/paths.dart

key-decisions:
  - "SalvageReport modeled as a static class (matching RingingManager), not a new state-mgmt construct"
  - "Alarm-loss flag set ONLY when T == Alarm (markEntryDropped/markListReset) so routine recovery stays silent (Pitfall 5)"
  - "Added @visibleForTesting setAppDataDirectoryPathForTesting() rather than mocking path_provider — keeps storage tests pure dart:io"
  - "Preserved saveRingtone's directory-exists guard when switching to temp+rename (Rule 2 — avoid regressing a missing-dir case)"

patterns-established:
  - "Pattern: temp-write ($key.txt.tmp) + flush + rename over target, inside queue.add — POSIX-atomic save"
  - "Pattern: top-level decode guarded separately from per-element decode in listFromString"

requirements-completed: [STOR-01, STOR-02, BOOT-04]

# Metrics
duration: 5min
completed: 2026-05-30
---

# Phase 1 Plan 01: Storage Hardening (Atomic Writes + Per-Entry Salvage + Null-Safe Load) Summary

**Tier-1 storage hardening: crash-atomic temp+rename writes, per-entry alarm-list salvage with an Alarm-only loss flag, and a null-safe SettingGroup.load() that keeps the GetStorage fallback — no storage rewrite, no new deps.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-30T15:44:07Z
- **Completed:** 2026-05-30T15:48:39Z
- **Tasks:** 3
- **Files modified:** 7 (4 lib + 1 new lib + 2 new tests)

## Accomplishments
- **STOR-01 (atomic writes):** `saveTextFile` and `saveRingtone` now write a `.tmp` sibling in the same directory then `rename()` over the target. A process killed mid-write can no longer leave a half-written file — the previous good file survives until the new one is fully written. The change stays inside the shared `queue.add()` closure, so it remains serialized with all other file I/O.
- **BOOT-04 (per-entry salvage):** `listFromString` guards the top-level `json.decode` separately from each element. An unparseable list recovers to `[]`; a single corrupt entry is skipped + logged while every other entry loads. It no longer rethrows. `loadList` now wraps the call in try/catch returning `[]`, mirroring the never-throw `loadListSync` convention.
- **D-06 (alarm-loss flag):** New `lib/common/logic/salvage_report.dart` exposes a module-level `SalvageReport` (static class, no state-mgmt library). `markEntryDropped<T>()` / `markListReset<T>()` set the user-facing `alarmsWereLost` flag **only** when `T == Alarm`; non-alarm loss (timers, cities) is silent for the flag. Ready for the Plan 03 one-time notice.
- **STOR-02 (null-safe load):** `SettingGroup.load()` declares `value` as `String?`, guards `null`/empty before `json.decode`, and wraps the decode in its own try/catch. It recovers to schema defaults and logs instead of throwing, while keeping the GetStorage dual-store fallback (D-05).

## Task Commits

Each task was committed atomically:

1. **Task 1: Atomic temp-write + rename for file saves (STOR-01 / D-02)** — `a257829` (feat) — `list_storage.dart`, `paths.dart`, `list_storage_test.dart`
2. **Task 2: Per-entry salvage + alarm-loss flag (BOOT-04 / D-04 / D-06)** — `32960c7` (feat) — `salvage_report.dart`, `json_serialize.dart`, `list_storage.dart`, `json_serialize_test.dart`
3. **Task 3: Null-safe SettingGroup.load() (STOR-02 / D-03 / D-05)** — `9edb4bf` (fix) — `setting_group.dart`

_TDD note: Tasks 1 and 2 are `tdd="true"`. The test files were authored alongside the implementation, but RED→GREEN could not be demonstrated because the Flutter/Dart toolchain is not installed in this environment (see Issues Encountered). Each task was committed as a single atomic `feat` commit (test + implementation) rather than separate `test`/`feat` commits._

## Files Created/Modified
- `lib/common/utils/list_storage.dart` — `saveTextFile`/`saveRingtone` now temp-write + `rename` (atomic); `loadList` wrapped in try/catch returning `[]` (never throws).
- `lib/common/utils/json_serialize.dart` — `listFromString` rewritten for per-entry salvage; guarded top-level decode; calls `SalvageReport.markListReset`/`markEntryDropped`; no rethrow.
- `lib/common/logic/salvage_report.dart` (new) — module-level Alarm-loss flag (`alarmsWereLost`, `markEntryDropped<T>`, `markListReset<T>`, `clear`).
- `lib/settings/types/setting_group.dart` — `load()` made null-safe; guards null/empty; wraps decode; keeps GetStorage fallback.
- `lib/common/data/paths.dart` — added `@visibleForTesting setAppDataDirectoryPathForTesting(String)` (+ `flutter/foundation.dart` import) so storage can be exercised against a real temp dir in unit tests.
- `test/common/utils/list_storage_test.dart` (new) — round-trip, no leftover `.tmp`, full replace, target location.
- `test/common/utils/json_serialize_test.dart` (new) — flag transitions, per-entry Alarm salvage, unparseable-list recovery, non-alarm (timer) loss not flagging.

## Decisions Made
- Modeled `SalvageReport` as a static class with private static field + getters (matching `RingingManager`), satisfying the CLAUDE.md "no state-management library" constraint.
- Set the alarm-loss flag strictly on `T == Alarm` so routine recovery (settings defaulted, corrupt timer/city) never trains users to ignore the future notice (Pitfall 5).
- Added a `@visibleForTesting` data-dir setter to `paths.dart` instead of mocking `path_provider`, keeping the storage tests pure `dart:io` and fast.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Preserved ringtones-directory-exists guard in saveRingtone**
- **Found during:** Task 1 (atomic write for saveRingtone)
- **Issue:** The original `saveRingtone` did `file.createSync(recursive: true)` to ensure the ringtones directory existed before writing. Naively switching to temp-write + rename would have dropped that guard, so a write into a not-yet-created ringtones dir would now throw (`FileSystemException`) — a regression.
- **Fix:** Before the temp write, ensure the ringtones directory exists (`Directory(ringtonesDirectory).createSync(recursive: true)` when absent), then write `$newPath.tmp` and rename to `$newPath`.
- **Files modified:** `lib/common/utils/list_storage.dart`
- **Verification:** Code review against original behavior; directory creation is idempotent and stays inside `queue.add`.
- **Committed in:** `a257829` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing-critical, Rule 2)
**Impact on plan:** The single deviation prevents a regression introduced by the atomic-write change. No scope creep; all other work matches the plan exactly.

## Issues Encountered

**Flutter/Dart toolchain unavailable — automated verification not run.**
The execution environment (Linux/WSL) has no `flutter` or `dart` binary, and none is reachable on the mounted Windows drives. As a result the plan's automated verification steps could **not** be executed locally:
- `flutter test test/common/utils/list_storage_test.dart` — NOT RUN
- `flutter test test/common/utils/json_serialize_test.dart` — NOT RUN
- `flutter analyze lib/...` — NOT RUN

What was done instead:
- All non-toolchain verification checks from the plan's `<verification>` block were run and **pass**: `FileMode.writeOnly` is gone from `list_storage.dart`; there is no `rethrow;` statement in `json_serialize.dart`; all frontmatter `contains`/`key_link` markers (`.rename(`, `SalvageReport`, `alarmsWereLost`, `SalvageReport.mark`, `.tmp`) are present.
- The implementation and test fixtures were validated by careful source review against the actual `Alarm.fromJson` (throws on `json['schedules'][0]` when `schedules` is `[]`), `ClockTimer.fromJson` (throws on `null * 1000` when `durationRemainingOnPause` is absent), and `appSettings` (statically constructed at module load, so `Alarm`/`ClockTimer` fixtures build without storage init). Null-flow promotion in the guarded `SettingGroup.load()` was confirmed (`String?` narrows to `String` after the `== null || isEmpty` return).

**Action required:** A developer with the Flutter 3.22.2 toolchain should run the three commands above to confirm GREEN before merging. They are expected to pass; if `flutter analyze` flags anything, it would most likely be a lint nicety, not a logic error.

## User Setup Required
None — no external service configuration required. No new dependencies; no `pubspec.yaml` change.

## Next Phase Readiness
- **Plan 02 (boot guard / time-boxed splash / idempotent reschedule):** ready — it depends on loads that recover instead of throw, which this plan delivers (`loadList`/`SettingGroup.load()` are now non-throwing).
- **Plan 03 (one-time "alarms were lost" notice):** ready — it reads `SalvageReport.alarmsWereLost` (set during salvage here) and calls `SalvageReport.clear()` after showing the notice.
- **Concern / blocker:** the test suite has not been executed (toolchain absent). Recommend running `flutter test test/common/utils/` and `flutter analyze` on a machine with Flutter 3.22.2 before relying on these guarantees in CI.

## Self-Check: PASSED

- All created files exist on disk (`salvage_report.dart`, both test files, this SUMMARY).
- All three task commits exist in git history (`a257829`, `32960c7`, `9edb4bf`).

---
*Phase: 01-storage-boot-reliability*
*Completed: 2026-05-30*
