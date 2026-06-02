---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-06-02T02:34:28.451Z"
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 5
  completed_plans: 3
  percent: 25
---

# Project State: Chrono — Reliability + QR Dismiss Task Milestone

## Project Reference

- **Core value:** The alarm must reliably ring and reliably stop — reliability before any new feature.
- **Current focus:** Phase 2 — Snooze Reliability (Phase 1 closed 2026-06-02)
- **Type:** Brownfield (bug-fix + feature work on an existing, mature Flutter/Android alarm app).
- **Key docs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/`, `.planning/codebase/`.

## Current Position

Phase: 1 (Storage & Boot Reliability) — DONE (closed 2026-06-02 by user sign-off)
Next: Phase 2 (Snooze Reliability) — not yet planned

- **Phase:** 1 of 4 closed; Phase 2 of 4 is next
- **Closure basis:** All 3 plans code-complete & committed. Test 3 (toolchain gate) PASSED via CI for real. The two on-device checks were WAIVED by the user and recorded as ACCEPTED (not independently verified): Test 1 (reboot→reschedule) has no recorded on-device run; Test 2 (alarms-reset notice) was converted to committed CI tests (commit `3e8bd01`) that have not yet had a green CI run.
- **Status:** Ready to execute
- **Progress:** [██▌░░░░░░░] ~25% (1 of 4 phases complete)

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Storage & Boot Reliability | BOOT-01..04, STOR-01..02 (6) | ✅ Done (closed 2026-06-02 by user sign-off; on-device checks accepted, not independently verified) |
| 2 | Snooze Reliability | SNZ-01..05 (5) | Not started |
| 3 | Date, Volume & FAB High-Value Fixes | DATE-01..02, VOL-01, FAB-01, PR-01..02 (6) | Not started |
| 4 | QR/Barcode Scan-to-Dismiss Task | BUILD-01..02, SCAN-01..12 (14) | Not started |

## Performance Metrics

- **Phases complete:** 0/4
- **Requirements delivered (source-level):** 3/31 (STOR-01, STOR-02, BOOT-04 — BOOT-04/STOR-02 now have both their detection (01-01) and user-facing notice (01-03); BOOT-01/02/03 source-complete in 01-02 pending on-device sign-off)
- **Plans fully complete:** 1 (01-01 Storage Hardening, ~5 min, 3 tasks, 7 files); **code-complete but checkpoint-pending:** 2 (01-02, 01-03)
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
- **[01-03] One-time alarms-lost notice = post-frame callback + module-level `SalvageReport` flag, no state-mgmt lib (D-06/D-01)** — `_AppState.initState` registers `WidgetsBinding.addPostFrameCallback` → shows a `Semantics(liveRegion)`-wrapped, localized (`alarmsResetNotice`) `SnackBar` via the existing `_messangerKey` ScaffoldMessenger only when `SalvageReport.alarmsWereLost` AND on the post-onboarding route, then `SalvageReport.clear()` (shows exactly once). Routine recovery stays silent (Pitfall 5).
- **[01-03] Notice dismiss = swipe-to-dismiss, not a SnackBarAction button** — no generic "OK"/"Dismiss" ARB key exists; rather than ship an untranslated label or misuse `dismissAlarmButton` (alarm-specific), used `DismissDirection.horizontal` on a 10s floating SnackBar (long enough for TalkBack). Adds zero surplus ARB key; English-only `alarmsResetNotice`, other locales via Weblate.

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
- **[01-03] `flutter gen-l10n` + `flutter analyze lib/app.dart` not run — toolchain absent.** The new `AppLocalizations.alarmsResetNotice` getter referenced in `lib/app.dart` does NOT exist on disk yet; codegen (`flutter gen-l10n` or a normal build) MUST run before `lib/app.dart` compiles. ARB key is present + valid JSON, only `app_en.arb` touched. Source assertions all pass (Semantics-wrapped, localized-not-literal, gated, clear-after-show, no state-mgmt lib). Deferred — requires Flutter 3.22.2 before merge.

## Session Continuity

- **Last action:** Executed Phase 1 Plan 03 (alarms-lost one-time notice). Autonomous Tasks 1-2 committed atomically (`d7f9de2` new `alarmsResetNotice` ARB string — English baseline only; `98d028b` `app.dart` post-frame `_showAlarmsResetNoticeIfNeeded()` — Semantics-wrapped localized SnackBar gated on `SalvageReport.alarmsWereLost` + post-onboarding route, cleared after one show). Task 3 is a blocking on-device `checkpoint:human-verify` — returned to the orchestrator, NOT self-approved. One Rule 3 auto-fix: dropped a `localizations.ok` SnackBarAction (no such ARB key) in favour of swipe-to-dismiss.
- **Next action:** Human runs **two** pending Phase-1 on-device checkpoints:
  - **01-03 Task 3** — `flutter run --flavor dev`; corrupt `Clock/alarms.txt` so per-entry salvage drops ≥1 entry → relaunch shows the localized notice exactly once (gone on next relaunch); TalkBack announces it; blank a SETTINGS group file → NO notice; confirm swipe-dismiss. Approve when it fires once on alarm loss only, is announced, and dismissible.
  - **01-02 Task 3** — secure-lock FBE device, API 24+: `flutter build apk --debug --flavor dev`, create alarms+timer, `adb reboot`, check logcat pre-unlock for the `deferring` log + absence of `IllegalStateException`, unlock → normal UI + exactly-once re-arm.
- **Watch:** Toolchain absent here — owe `flutter gen-l10n` (generates `AppLocalizations.alarmsResetNotice`, needed for `lib/app.dart` to compile) then `flutter analyze lib/app.dart` for 01-03; `flutter analyze lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart` for 01-02; and Plan 01 `flutter test`/`flutter analyze`. Run all on a Flutter 3.22.2 machine before merge.

---
*State initialized: 2026-05-30*
*Last updated: 2026-05-30 after executing 01-03-PLAN.md (Tasks 1-2; Task 3 blocking on-device checkpoint pending — 01-02 Task 3 also still pending)*

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 01 P03 | 6min | 2 tasks | 2 files |
