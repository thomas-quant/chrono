---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-06-06T00:32:33.352Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 14
  completed_plans: 12
  percent: 75
---

# Project State: Chrono — Reliability + QR Dismiss Task Milestone

## Project Reference

- **Core value:** The alarm must reliably ring and reliably stop — reliability before any new feature.
- **Current focus:** Phase 04 — qr-barcode-scan-to-dismiss-task
- **Type:** Brownfield (bug-fix + feature work on an existing, mature Flutter/Android alarm app).
- **Key docs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/`, `.planning/codebase/`.

## Current Position

Phase: 04 (qr-barcode-scan-to-dismiss-task) — EXECUTING (authorable plans complete; on-device gates deferred)
Plans complete this phase: 4 of 6 (04-01, 04-02, 04-04, 04-05)
Deferred (on-device only — no device/toolchain in this env): 04-03 lock-screen camera spike, 04-06 end-to-end sign-off
Next: run the two on-device gates on hardware (build the dev APK in CI first), then phase verification + completion
Resume file: None

**Phase 4 execution outcome (2026-06-06):** All four authorable plans landed on `master`.
04-01 build gate (`flutter_zxing` 2.2.1 exact pin, minSdk 23, CAMERA manifest, blocking zero-ML-Kit CI
graph gate). 04-02 pure seams (`normalizeCode`/`codesMatch` + `EscapeHatchController`) with headless
tests. 04-04 ring-time `ScanTask` (`AlarmTaskType.scan`, `ReaderWidget` dismiss gated by registered
code, escape hatch / torch / camera-release / unlock-to-scan, JSON round-trip test). 04-05
setup/registration half (inline scan-to-register card, setup-time camera permission, D-REG-REQUIRED
save gate, `print` leak removed). **Code review (quick depth) found 2 BLOCKERs — both fixed:** CR-01 the
D-REG-REQUIRED save gate was bypassed on the list ADD path (a code-less scan task could be added →
un-dismissable at ring time with the escape hatch off) → the add path now routes validating items
through the gated customize screen (commit `c687226`); CR-02 `ScanTask` had no re-entrancy latch on
`onSolve` (double-dismiss) → one-shot `_solved` latch added (`205db0a`). WR-04 (CI analyze still pinned
to Phase-2 files) also fixed → repointed to the Phase-4 scan files (`a509ccc`). Open review items:
WR-01 (torch graceful-no-flash dead code — needs on-device/zxing-API resolution), WR-02 (vibrate no
`hasVibrator()` guard), WR-03 (mitigated by `scanDelay`), WR-05 (zero-ML-Kit gate runs only on
`workflow_dispatch`) + 4 INFO — all tracked open in `04-REVIEW.md`.

- **Phase:** 4 of 4 (qr/barcode scan-to-dismiss task) — authorable-complete, on-device gates owed
- **Status:** Authorable work complete + code-review blockers fixed; CI + on-device gates owed (see `.planning/MANUAL-VERIFICATION-LOG.md`)
- **Progress:** [████████░░] 75% (12/14 plans)

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Storage & Boot Reliability | BOOT-01..04, STOR-01..02 (6) | ✅ Done (closed 2026-06-02 by user sign-off; on-device checks accepted, not independently verified) |
| 2 | Snooze Reliability | SNZ-01..05 (5) | ✅ Done (source-complete; CI test/analyze + on-device snooze smoke owed) |
| 3 | Date, Volume & FAB High-Value Fixes | DATE-01..02, VOL-01, FAB-01, PR-01..02 (6) | ✅ Done (source-complete; CI test/analyze + on-device checks owed) |
| 4 | QR/Barcode Scan-to-Dismiss Task | BUILD-01..02, SCAN-01..12 (14) | 🟡 Authorable-complete (4/6 plans + review blockers fixed); 04-03 spike + 04-06 e2e deferred (on-device); CI gates owed |

## Performance Metrics

- **Phases complete:** 3/4 (Phase 4 authorable-complete; on-device gates deferred)
- **Plans complete (source-level):** 12/14 — Phases 1-3 (8) + Phase 4 authorable (04-01, 04-02, 04-04, 04-05)
- **Phase-4 requirements source-complete:** BUILD-01/02, SCAN-08 (04-01); SCAN-03/06/07 (04-02); SCAN-01/04/05/12 source (04-04); SCAN-02/10 (04-05). SCAN-09 + SCAN-11 behavioral confirmation and criterion-#1 lock-screen spike = on-device gates (04-06 / 04-03, deferred).
- **All Phase-4 Flutter gates owed via CI/on-device** — Flutter/Dart toolchain absent locally; no push performed.
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

- **Last action (2026-06-06):** Executed Phase 4 authorable plans via `/gsd-execute-phase 4`. User chose "build authorable, defer both on-device gates." Ran 04-01, 04-02, 04-04, 04-05 sequentially on `master` (no worktree isolation — merge-back reliability), each with atomic commits + own STATE/ROADMAP updates. Ran the code-review gate (quick): 2 BLOCKERs (CR-01 add-path save-gate bypass → un-dismissable alarm; CR-02 ScanTask onSolve re-entrancy) + WR-04 (stale CI analyze scope) verified and FIXED via gsd-code-fixer (`c687226`, `205db0a`, `a509ccc`, REVIEW resolution `7947d1d`). Skipped 04-03 (lock-screen spike) and 04-06 (on-device e2e) per user — neither runnable without a device + Flutter toolchain. Phase NOT marked complete (2 plans remain).
- **Next action:** On hardware: build the dev APK via CI (`test-apk.yml`), then run 04-03 (lock-screen camera spike across ≥2 OEMs → `04-LOCKSCREEN-SPIKE.md` + revert the throwaway scaffold) and 04-06 (full scan-to-dismiss e2e matrix). Then re-run phase verification + `phase.complete`. Any on-device defect → `/gsd-plan-phase 4 --gaps`.
- **Watch (owed CI/human gates — toolchain absent here, NO push performed):** Phase-4 `flutter test` (`tests.yml` — code_match, escape_hatch_controller, alarm_task_scan), `flutter gen-l10n` (new `scan*` ARB getters), `flutter analyze` (now repointed to the Phase-4 scan files), the dev-APK native `flutter_zxing` build, and the BUILD-02 zero-ML-Kit prod-graph gate are all OWED via CI (user authorizes the push/dispatch — both remotes outward-facing). On-device: 04-03 spike + 04-06 e2e (real camera over a fired alarm, torch SCAN-09, camera-release SCAN-11, escape-never-traps, no-go unlock-to-scan). Open code-review items WR-01/02/03/05 + 4 INFO tracked in `04-REVIEW.md`. Prior-phase gates (Phase 1-3 CI test/analyze + on-device smokes) also still owed. See `.planning/MANUAL-VERIFICATION-LOG.md`.

---
*State initialized: 2026-05-30*
*Last updated: 2026-06-06 after executing Phase 4 authorable plans (04-01/02/04/05) + code-review blocker fixes (CR-01/CR-02/WR-04); 04-03 spike + 04-06 e2e deferred (on-device); phase not yet complete; CI/on-device gates owed.*

## Performance Metrics

| Phase | Plan | Duration | Notes |
|-------|------|----------|-------|
| Phase 01 P03 | 6min | 2 tasks | 2 files |
| Phase 02 P01 | 8min | 3 tasks | 3 files |
| Phase 02 P02 | ~7min | 2 tasks | 2 files |
| Phase 3 P1 | 4min | 3 tasks | 3 files |
| Phase 03 P02 | 7min | 3 tasks | 3 files |
| Phase 03 P03 | 2min | 2 tasks | 2 files |
| Phase 04 P01 | ~6min | 3 tasks | 4 files |
| Phase 04 P02 | 3min | 2 tasks | 4 files |
| Phase 04 P04 | 4min | 3 tasks | 5 files |
| Phase 04 P05 | 4min | 4 tasks | 10 files |
| Phase 04 review-fix | 3min | CR-01/CR-02/WR-04 | 3 files |

## Decisions

- [Phase ?]: [02-01] Snooze fixed at source: seconds-based duration shared between _snoozeTime and scheduleSnoozeAlarm; snooze() reads clock.now() (D-B); snapLength:1 on Length slider (D-D).
- [Phase ?]: [02-01] Single _resolveDismiss() (cancelSnooze + canonical update()) deactivates one-shot AND finished-dates schedules (D-C/#457); over-max snooze resolves as a dismiss (D-A); handleDismiss() kept as a public async delegator (D-E); isolate dismiss branch awaits it. update_alarms.dart + alarm_screen.dart reused unchanged.
- [Phase ?]: [02-02] Authored alarm_snooze_test.dart (SNZ-01..05 regression: exact now+30s under withClock from Plan-01 clock.now(); once+finished-dates snooze->dismiss deactivation #457; over-max->dismiss; snoozeCount toJson<->fromJson). Repointed test-apk.yml analyze to the 4 Phase-2 files. No lib/ or pubspec change; flutter test+analyze owed via CI.
- [Phase ?]: [03-01] Specific-date off-by-one fixed at the serialization root: DateTimeSetting persists date-only YYYY-MM-DD strings (D-DATE-FORMAT); loadValueFromJson reads new Strings as local DateTime(y,m,d) and legacy int epochs via isUtc:true UTC reinterpretation (D-DATE-MIGRATION) so broken alarms self-heal; malformed values salvage not crash (BOOT-04). Picker normalizes table_calendar UTC days to local at onDaySelected/onRangeSelected.
- [Phase ?]: [03-01] RangeAlarmSchedule proven by test unaffected by the date-only round-trip — finish boundary identical before/after for in-window and elapsed ranges; no range_alarm_schedule.dart change needed.
- [Phase ?]: [03-02] Rising-volume ramp fixed at root: extracted a pure audio-free VolumeRampController (single owned Timer + injected void Function(double) callback + real cancel()); RingtonePlayer drives it and cancels at stop/pause/_play re-entry. cancel() is the ONLY ramp-stop signal — setVolume no longer kills the ramp (removed _stopRisingVolume). Reimplemented #467 independently, sole credit, no contributor attribution (D-PR-METHOD).
- [Phase ?]: [03-02] Safe default (research Open Q1, for user to confirm at review): a plain mid-ring setVolume() leaves the ramp running and does NOT retarget the ceiling. Used fake_async (transitive) for CI Timer tests — no new dep. flutter test/analyze owed via CI; on-device audio ramp check is the remaining human gate. PR-01/PR-02/ROADMAP criterion #4 still say 'credit the contributor' — reword at next transition (deferred).
- [Phase ?]: [03-03] FAB-01 fixed centrally at the shared list layer (D-FAB-SCOPE): CustomListView's list padding reserves a derived bottom inset = 8 + 56 (FAB tap target 16+24+16, fab.dart:84,88) + 16 (gap, fab.dart:74 / snackbar.dart:57,59) + (useMaterialStyle ? 20 : 0) (fab.dart:67-69) — each term cited inline (Pitfall 4). One edit covers all ~13 FAB screens; persistent_list_view.dart untouched; no nav-bar height. Reimplemented #466 independently, sole credit, no attribution (D-PR-METHOD). Narrow headless fab_clearance_test.dart asserts inset >= FAB extent (+20 material), kept in CI; flutter test/analyze owed via CI; on-device cross-OEM layout is the human gate. PR-02/ROADMAP criterion #4 still say 'credit the contributor' — reword at next transition (deferred).
- [Phase 04]: [04-01] flutter_zxing pinned EXACT 2.2.1 (no caret — ^2.2.0 would resolve into 2.3.0 which needs Flutter >=3.41, breaks Chrono 3.22.2); minSdkVersion 21->23 (plugin android/build.gradle hard-codes 23). ndkVersion left as flutter.ndkVersion — align to 27.0.12077973 ONLY if CI native build complains (contingency, unused).
- [Phase 04]: [04-01] SCAN-08 manifest half: CAMERA permission + camera/autofocus/flash uses-feature all required=false (Play listing not camera-gated). Runtime permission REQUEST deferred to Plan 05 (requested at setup, never fire time).
- [Phase 04]: [04-01] BUILD-02 zero-ML-Kit gate = new blocking dependency-graph job in test-apk.yml; greps prodReleaseRuntimeClasspath for mlkit|play-services|gms, exit 1 on match; NOT continue-on-error; no emulator job. Authoritative in CI only — toolchain absent locally, OWED on push.
- [Phase ?]: [04-02] code_match + EscapeHatchController pure seams (SCAN-03/06/07): normalize strips control chars + case-fold (D-MATCH-NORMALIZE), codesMatch empty-stored floor; escape controller single Timer + idempotent _fired, defaults 10/120s (D-ESC-DEFAULT), fireNow ignores enabled (SCAN-07 asymmetry). Both tests owed-green via CI (toolchain absent).
- [Phase ?]: [04-04] ScanTask ring widget: AlarmTaskType.scan + schema (hidden Registered Code isVisual:false + Escape Hatch default ON); reuses Plan-02 seams by import (codesMatch(normalizeCode) gates onSolve; EscapeHatchController gates Semantics Dismiss) - no logic reimpl. ReaderWidget broad symbology (QR+DataMatrix+EAN/UPC/Code128/Code39/ITF, SCAN-04). no-go = RUNTIME camera-preview failure (onControllerCreated exception) -> fireNow + Surface-4 unlock-to-scan, NOT per-manufacturer; 04-03 spike informs only the doc default (D-LOCK-NOGO-UX). dismissAlarmButton reused; alarm_notification_screen.dart NOT edited; gen-l10n + analyze/test owed via CI; real scan/torch/camera-release/no-go deferred to Plan 06.
- [Phase ?]: [04-05] Setup/registration half of scan task: inline ScanRegisterCard (route B - ScanRegisterSetting marker dispatched in get_setting_widget over sibling Registered Code StringSetting; NO json_serialize factory entry, D-STORE-FORMAT); ScanRegisterScreen normalizeCode(code.text)->setValue->pop (registration IS test scan, SCAN-02/10); camera at SETUP only (SCAN-08), deny->openAppSettings+resume (D-REG-CAMDENIED); status-only (D-REG-DISPLAY); print leak removed (T-04-13).
- [Phase ?]: [04-05] D-REG-REQUIRED real save gate (T-04-20): default-no-op CustomizableListItem.validate + AlarmTask.validate override (scanCodeRequired when type==scan && normalizeCode(Registered Code).isEmpty, reuses 04-02 seam) + CustomizeScreen Save blocks pop & SnackBar+SemanticsService.announce (not a silent dead button); threaded via CustomizeListItemScreen default item.validate(ctx); other items unaffected. gen-l10n/analyze owed via CI; real camera/save-block deferred to Plan 06.
