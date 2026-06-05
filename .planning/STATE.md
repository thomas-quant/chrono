---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-06-05T00:55:25.316Z"
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 8
  completed_plans: 7
  percent: 50
---

# Project State: Chrono — Reliability + QR Dismiss Task Milestone

## Project Reference

- **Core value:** The alarm must reliably ring and reliably stop — reliability before any new feature.
- **Current focus:** Phase 03 — date-volume-fab-high-value-fixes
- **Type:** Brownfield (bug-fix + feature work on an existing, mature Flutter/Android alarm app).
- **Key docs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/`, `.planning/codebase/`.

## Current Position

Phase: 03 (date-volume-fab-high-value-fixes) — EXECUTING
Plan: 3 of 3
Next: Plan Phase 3 → `/gsd-plan-phase 3`
Resume file: None

**Phase 3 discussion outcome (2026-06-05):** Date → store as local date-only `YYYY-MM-DD`, auto-correct
legacy epoch on load (contingent on confirming `table_calendar` midnight-vs-noon UTC). Volume/FAB →
**reimplement #467/#466 independently, sole credit (no contributor attribution)** — DEVIATES from
PR-01/PR-02 + ROADMAP success-criterion #4 ("credit the contributor"); reword those at next transition.
FAB → shared bottom-clearance fix at the list/FAB layer (all ~12 screens). Tests → all three get CI
coverage (date unit, volume-cancel via extracted ramp controller, narrow FAB widget test). **New project
policy:** `CLAUDE.md` now defaults all CI-runnable testing (unit + headless widget) to GitHub Actions for
every phase/plan.

- **Phase:** 3 of 4 (date, volume & fab high value fixes)
- **Closure basis (Phase 2):** Plan 02-01 fixed the snooze state machine at source (SNZ-01..05); Plan 02-02 authored the CI-runnable regression suite (`test/alarm/types/alarm_snooze_test.dart`) and repointed `test-apk.yml`'s analyze gate to the Phase-2 files. `flutter test` (via `tests.yml` on push) and the scoped `flutter analyze` (via `gh workflow run test-apk.yml`) are OWED via CI — no push/dispatch performed (both remotes outward-facing). An end-of-phase on-device snooze→dismiss smoke is the one remaining human gate.
- **Status:** Ready to execute
- **Progress:** [█████████░] 88%

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Storage & Boot Reliability | BOOT-01..04, STOR-01..02 (6) | ✅ Done (closed 2026-06-02 by user sign-off; on-device checks accepted, not independently verified) |
| 2 | Snooze Reliability | SNZ-01..05 (5) | 🟡 Code-complete (both plans committed) — ready for verification (CI test/analyze + on-device smoke owed) |
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

- **Last action:** Executed Phase 2 Plan 02 (wave 2 — snooze regression suite + analyze repoint). Both tasks autonomous, committed atomically: `6e332c2` new `test/alarm/types/alarm_snooze_test.dart` (SNZ-01..05 — exact `now+30s` under `withClock(Clock.fixed(...))` enabled by Plan-01's `clock.now()`; once + finished-dates snooze→dismiss deactivation #457; over-max→dismiss; `snoozeCount` `toJson↔fromJson` round-trip; SNZ-01/05 survives an unrelated `update()` still enabled+snoozed; asserts on `Alarm` flags only — OS no-ops under `FLUTTER_TEST`); `09dc3ec` repointed `test-apk.yml`'s informational `flutter analyze` gate from the nine Phase-1 files to the four Phase-2 paths (`alarm.dart`, `alarm_isolate.dart`, `alarm_settings_schema.dart`, `alarm_snooze_test.dart`), keeping `continue-on-error: true` and all other steps unchanged. No deviations. No `lib/` or `pubspec.yaml` change. All source-level verify assertions pass.
- **Next action:** Verify Phase 2, then plan Phase 3 (Date, Volume & FAB High-Value Fixes — DATE-01..02, VOL-01, FAB-01, PR-01..02).
- **Watch (owed CI/human gates — toolchain absent here, NO push performed):** Plan 02's `flutter test` runs via `tests.yml` on push (the authoritative behavioral gate — the new `Alarm snooze` cases run there); the scoped `flutter analyze` (now pointed at the Phase-2 files) + the sideloadable `chrono-dev-release-apk` come from `gh workflow run test-apk.yml`. Owed commands (user-authorized only — both remotes outward-facing): `git push <remote> <phase-branch>` then `gh run watch` (capture the `tests.yml` run id/result); `gh workflow run test-apk.yml --ref <phase-branch>` then `gh run watch` (read the Analyze log for new issues; download the APK). Plus the end-of-phase on-device snooze→dismiss smoke (once-alarm dismiss does not reappear; fractional snooze re-rings ~30s; over-max dismisses; normal snooze does not silently disable). Phase-1 gates (`01-02`/`01-03` on-device + l10n/analyze) still owed from the prior phase.

---
*State initialized: 2026-05-30*
*Last updated: 2026-06-02 after executing 02-01-PLAN.md (all 3 tasks autonomous + committed; SNZ-01..05 source-complete; CI/test gates owed via Plan 02 + CI)*

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 01 P03 | 6min | 2 tasks | 2 files |
| Phase 02 P01 | 8min | 3 tasks | 3 files |
| Phase 02 P02 | ~7min | 2 tasks | 2 files |
| Phase 3 P1 | 4min | 3 tasks | 3 files |
| Phase 03 P02 | 7min | 3 tasks | 3 files |

## Decisions

- [Phase ?]: [02-01] Snooze fixed at source: seconds-based duration shared between _snoozeTime and scheduleSnoozeAlarm; snooze() reads clock.now() (D-B); snapLength:1 on Length slider (D-D).
- [Phase ?]: [02-01] Single _resolveDismiss() (cancelSnooze + canonical update()) deactivates one-shot AND finished-dates schedules (D-C/#457); over-max snooze resolves as a dismiss (D-A); handleDismiss() kept as a public async delegator (D-E); isolate dismiss branch awaits it. update_alarms.dart + alarm_screen.dart reused unchanged.
- [Phase ?]: [02-02] Authored alarm_snooze_test.dart (SNZ-01..05 regression: exact now+30s under withClock from Plan-01 clock.now(); once+finished-dates snooze->dismiss deactivation #457; over-max->dismiss; snoozeCount toJson<->fromJson). Repointed test-apk.yml analyze to the 4 Phase-2 files. No lib/ or pubspec change; flutter test+analyze owed via CI.
- [Phase ?]: [03-01] Specific-date off-by-one fixed at the serialization root: DateTimeSetting persists date-only YYYY-MM-DD strings (D-DATE-FORMAT); loadValueFromJson reads new Strings as local DateTime(y,m,d) and legacy int epochs via isUtc:true UTC reinterpretation (D-DATE-MIGRATION) so broken alarms self-heal; malformed values salvage not crash (BOOT-04). Picker normalizes table_calendar UTC days to local at onDaySelected/onRangeSelected.
- [Phase ?]: [03-01] RangeAlarmSchedule proven by test unaffected by the date-only round-trip — finish boundary identical before/after for in-window and elapsed ranges; no range_alarm_schedule.dart change needed.
- [Phase ?]: [03-02] Rising-volume ramp fixed at root: extracted a pure audio-free VolumeRampController (single owned Timer + injected void Function(double) callback + real cancel()); RingtonePlayer drives it and cancels at stop/pause/_play re-entry. cancel() is the ONLY ramp-stop signal — setVolume no longer kills the ramp (removed _stopRisingVolume). Reimplemented #467 independently, sole credit, no contributor attribution (D-PR-METHOD).
- [Phase ?]: [03-02] Safe default (research Open Q1, for user to confirm at review): a plain mid-ring setVolume() leaves the ramp running and does NOT retarget the ceiling. Used fake_async (transitive) for CI Timer tests — no new dep. flutter test/analyze owed via CI; on-device audio ramp check is the remaining human gate. PR-01/PR-02/ROADMAP criterion #4 still say 'credit the contributor' — reword at next transition (deferred).
