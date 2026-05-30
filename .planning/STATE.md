---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-30T15:50:09.093Z"
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 3
  completed_plans: 1
  percent: 0
---

# Project State: Chrono — Reliability + QR Dismiss Task Milestone

## Project Reference

- **Core value:** The alarm must reliably ring and reliably stop — reliability before any new feature.
- **Current focus:** Phase 1 — Storage & Boot Reliability
- **Type:** Brownfield (bug-fix + feature work on an existing, mature Flutter/Android alarm app).
- **Key docs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/`, `.planning/codebase/`.

## Current Position

Phase: 1 (Storage & Boot Reliability) — EXECUTING
Plan: 1 of 3 complete; 2 of 3 PAUSED at blocking on-device checkpoint

- **Phase:** 1 of 4 — Storage & Boot Reliability
- **Plan:** 01-02 (boot guard / time-box / idempotent reschedule) — autonomous tasks 1-2 complete & committed; Task 3 is a blocking `checkpoint:human-verify` (on-device reboot-before-unlock on a secure-lock FBE device) awaiting human verification
- **Status:** Executing Phase 1 — Plan 02 paused at checkpoint
- **Progress:** [███░░░░░░░] 33% (1/3 plans complete; 01-02 code done, pending on-device sign-off)

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Storage & Boot Reliability | BOOT-01..04, STOR-01..02 (6) | In progress (1/3 plans) |
| 2 | Snooze Reliability | SNZ-01..05 (5) | Not started |
| 3 | Date, Volume & FAB High-Value Fixes | DATE-01..02, VOL-01, FAB-01, PR-01..02 (6) | Not started |
| 4 | QR/Barcode Scan-to-Dismiss Task | BUILD-01..02, SCAN-01..12 (14) | Not started |

## Performance Metrics

- **Phases complete:** 0/4
- **Requirements delivered:** 3/31 (STOR-01, STOR-02, BOOT-04)
- **Plans executed:** 1 (01-01 Storage Hardening, ~5 min, 3 tasks, 7 files)
- **Milestone started:** 2026-05-30

## Accumulated Context

### Decisions (from PROJECT.md, carried into roadmap)

- **Reliability before feature** — an unreliable alarm app fails its one job; reliability phases (1–3) precede the scanner feature (4).
- **Storage hardening + one idempotent reschedule primitive are the spine** — built once in Phase 1, depended on by the boot path and the snooze path.
- **Scanner is `flutter_zxing`, exact-pinned 2.2.x** (not a caret) — the only F-Droid-clean Flutter scanner (native ZXing via FFI, zero ML Kit / Play Services). 2.3.0 needs Flutter ≥3.41 (incompatible with Chrono's 3.22.2); 2.1.0 keeps minSdk 21 but the F-Droid-clean line forces minSdk 23.
- **Bump minSdk 21 → 23** — drops Android 5.0/5.1 (negligible base) to support the F-Droid-clean scanner. One-way door; gates all scan-task UI work.
- **QR/barcode as a new `AlarmTask` type, not a new subsystem** — reuse the existing pluggable task framework; ring-screen orchestration needs zero changes; no `json_serialize.dart` factory entry needed (tasks ride inline alarm JSON).
- **Match a pre-registered code; gate dismiss only; escape hatch ON by default and configurable** — non-predatory, accessible, never traps the user.
- **Clean-room implementation** — no decompiled/copied Alarmy code or assets.
- **Merge community PRs #467 (rising volume) and #466 (FAB)** rather than reimplement — credit contributors, less duplicate work.
- **DST recurring-alarm recompute (#359) deferred** to its own milestone (v2).
- **[01-01] Storage hardened Tier-1, no rewrite (D-01)** — atomic temp+rename writes (`saveTextFile`/`saveRingtone`), per-entry list salvage (one bad alarm no longer loses the whole list; unparseable list → `[]`), null-safe `SettingGroup.load()` keeping the GetStorage fallback. New `SalvageReport` module-level Alarm-loss flag (set only on Alarm loss) feeds the Plan 03 one-time notice.
- **[01-02] Unlock detection = mechanism B (probe-and-catch), not native (D-07/Q2)** — the boot isolate runs without a MainActivity/FlutterEngine, so a MainActivity-scoped MethodChannel is unreachable there; `isDeviceLocked()` instead probes `getApplicationDocumentsDirectory()` and treats any throw as "locked, defer." No `MainActivity.kt` change. API-gated no-op < API 24.
- **[01-02] Manifest narrowed minimally (Q1)** — dropped `LOCKED_BOOT_COMPLETED` from Chrono's `BootBroadcastReceiver` (belt-and-suspenders; Dart guard is primary); aamp `RebootBroadcastReceiver` + `MainActivity` directBootAware left untouched.
- **[01-02] Splash time-box = 8s on the storage+reschedule segment only (D-06)** — `runApp(App())` always reached; `Future.wait(initializeData)` left outside the timeout.
- **[01-02] `updateAlarms`/`updateTimers` confirmed idempotent and preserved unchanged as the D-08 spine (A4/BOOT-03)** — cancel-by-stable-id then schedule; re-running boot-then-launch re-arms exactly once.

### Open decisions to resolve during planning

- **Pre-unlock alarm firing in scope?** (Phase 1) — default assumption "no" (defer-until-unlock = pure code guard); "yes" means heavier device-protected (DE) storage work. Decide during Phase 1 planning.
- **Direct-Boot manifest ownership + `flutter_boot_receiver` capabilities** (Phase 1) — which `directBootAware`/`LOCKED_BOOT_COMPLETED` lines are Chrono-owned vs forked-plugin-supplied; does the plugin expose unlock state or are native edits needed?
- **Lock-screen camera go/no-go** (Phase 4) — the milestone's biggest unknown; resolve via the on-device spike (Phase 4 success criterion #1) BEFORE committing the scan-task UI. A black preview reshapes the feature.

### Known root causes (line-level, from research — feed into planning)

- Boot: `handle_boot.dart:20` awaits `initializeIsolate()` outside try/catch and reads CE storage pre-unlock.
- Load: unguarded `json.decode` at `setting_group.dart:265`; silent GetStorage fallback at 262-263.
- Write: non-atomic `saveTextFile` at `list_storage.dart:82-90` (`FileMode.writeOnly`).
- Snooze: `.floor()` on fractional `snoozeLength` at `alarm.dart:226,234`; `handleDismiss()` (`alarm.dart:309-315`) leaves a one-shot enabled and a pending snooze uncancelled (#457).
- Date: epoch round-trip in `DateTimeSetting` (`setting.dart:957-966`) + picker boundary (`date_picker_bottom_sheet.dart:145`).
- Volume: uncancellable `Future.delayed` ramp + static `_stopRisingVolume` flag in `ringtone_player.dart`.

### Todos / watch items

- Verify zero `mlkit`/`gms`/`play-services` in the Gradle graph as the Phase 4 build gate (`cd android && ./gradlew app:dependencies | grep -Ei 'mlkit|play-services|gms'` → expect none).
- Time-box the splash so a recoverable error can never become a fatal hang (Phase 1).
- Normalize both sides of code matching identically (trim/control-char/case) so a trailing newline can't false-reject (Phase 4).
- Remove the existing `print(setting.value)` leak in `dynamic_toggle_setting_card.dart:39` if working in settings-card code; never log scan payloads.

### Blockers

- **[01-01] Tests not executed — Flutter/Dart toolchain absent in the execution environment.** `flutter test test/common/utils/{list_storage,json_serialize}_test.dart` and `flutter analyze lib/...` could NOT be run. Source-level verification passed (no `FileMode.writeOnly`, no `rethrow` in `listFromString`, all artifact markers present) and fixtures were validated by review, but GREEN must be confirmed on a machine with Flutter 3.22.2 before relying on these guarantees in CI.

## Session Continuity

- **Last action:** Executed Phase 1 Plan 02 (boot guard / time-boxed splash / idempotent reschedule). Autonomous Tasks 1-2 committed atomically (`284f1f6` defer-until-unlock guard + isDeviceLocked() + try/catch fix + manifest narrowing, `f247448` time-boxed main() init). Task 3 is a blocking on-device `checkpoint:human-verify` — returned to the orchestrator, NOT self-approved. BOOT-01/02/03 delivered at source level. Mechanism B chosen (boot-isolate reachability); 8s time-box; funnel idempotency confirmed.
- **Next action:** Human runs the Task 3 on-device verification (secure-lock FBE device, API 24+): `flutter build apk --debug --flavor dev`, create alarms+timer, `adb reboot`, check logcat pre-unlock for the `deferring` log + absence of `IllegalStateException`, unlock → normal UI + exactly-once re-arm. On "approved", proceed to Plan 03 (alarms-lost notice).
- **Watch:** Run `flutter analyze lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart` to confirm Plan 02 GREEN (toolchain absent here). Also still owe Plan 01 `flutter test`/`flutter analyze`.

---
*State initialized: 2026-05-30*
*Last updated: 2026-05-30 after executing 01-02-PLAN.md (Tasks 1-2; Task 3 checkpoint pending)*
