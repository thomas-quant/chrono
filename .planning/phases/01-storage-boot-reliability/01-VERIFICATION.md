---
phase: 01-storage-boot-reliability
verified: 2026-05-30T18:00:00Z
status: human_needed
score: 10/13 must-haves verified (3 require on-device/toolchain human verification)
overrides_applied: 0
human_verification:
  - test: "On-device: reboot + pre-unlock behavior (BOOT-01 / BOOT-02 / BOOT-03)"
    expected: "adb logcat shows 'handleBoot: device locked ... deferring' and NO IllegalStateException; after unlock the app reaches the normal UI; each enabled alarm re-arms exactly once (no duplicates)"
    why_human: "Requires a PIN/pattern FBE device, adb, and a running Flutter build. Cannot be reproduced by source inspection — the defer path only fires on BOOT_COMPLETED on API 24+ FBE hardware. Defined in 01-02-PLAN.md Task 3."

  - test: "On-device: one-time alarms-reset notice fires only on alarm loss and is TalkBack-announced (BOOT-04 / D-06 / accessibility)"
    expected: "Corrupt one entry in alarms.txt → relaunch shows localized SnackBar exactly once. Second relaunch shows nothing. Blank a settings file → no notice. TalkBack reads the notice content aloud. Swipe dismiss works."
    why_human: "Requires TalkBack, a running Flutter build with gen-l10n executed, and on-device file corruption. Also requires flutter gen-l10n and flutter analyze to pass first (generated AppLocalizations.alarmsResetNotice symbol). Defined in 01-03-PLAN.md Task 3."

  - test: "Toolchain gate: flutter test + flutter analyze"
    expected: "flutter test test/common/utils/list_storage_test.dart test/common/utils/json_serialize_test.dart exits 0 (all 9 tests pass); flutter analyze lib/common/utils/list_storage.dart lib/common/utils/json_serialize.dart lib/settings/types/setting_group.dart lib/common/logic/salvage_report.dart lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart lib/app.dart reports no new errors; flutter gen-l10n exits 0 and resolves AppLocalizations.alarmsResetNotice"
    why_human: "Flutter 3.22.2 toolchain is absent in this environment. Source inspection strongly indicates all tests would pass and analysis would be clean, but runtime confirmation is required before merge."
---

# Phase 1: Storage & Boot Reliability — Verification Report

**Phase Goal:** After any reboot, killed write, or partial/corrupted state, Chrono always launches to its normal UI and re-arms alarms exactly once — the boot black-screen / splash-hang epic is gone. (Also builds the shared idempotent reschedule primitive reused by later phases.)
**Verified:** 2026-05-30T18:00:00Z
**Status:** HUMAN_NEEDED
**Re-verification:** No — initial verification

**Toolchain note:** The Flutter/Dart toolchain (flutter, dart) is absent in this environment. All verification is by source inspection only. `flutter test`, `flutter analyze`, and `flutter gen-l10n` were NOT run and are a required pre-merge gate. Test files were authored but not executed. The generated `AppLocalizations.alarmsResetNotice` getter does not exist on disk until `flutter gen-l10n` runs (the ARB key is present and correct; codegen is required before `lib/app.dart` will analyze/compile).

**Two blocking human checkpoints are intentionally pending** (01-02 Task 3 and 01-03 Task 3). These cannot be performed without a Flutter toolchain and a PIN/pattern FBE Android device.

---

## Goal Achievement

### Observable Truths — ROADMAP Success Criteria

| # | Truth (Roadmap SC) | Status | Evidence |
|---|---|---|---|
| SC-1 | Rebooting (including pre-unlock on FBE) lands on normal UI — no black screen, no boot crash from CE storage | ? UNCERTAIN (human_needed) | Source: `isDeviceLocked()` guard at head of `handleBoot()` (line 26); early return + `logger.i` log on lock; `initializeIsolate()` inside try/catch; `runApp` always reached in main.dart (line 74); 8s timeout on storage segment (line 61). Runtime behavior unconfirmable without device. |
| SC-2 | After reboot+unlock, every alarm/timer rescheduled exactly once — no duplicates, no missed reschedules | ? UNCERTAIN (human_needed) | Source: `updateAlarms`/`updateTimers` called in both `handleBoot` and `main()`; `schedule_alarm.dart` cancels by stable `scheduleId` before `oneShotAt` (cancel-then-schedule = idempotent). Confirmed by source read. Runtime "exactly once" cannot be verified without device. |
| SC-3 | A missing/half-written/invalid-JSON settings or list file recovers to safe default and is logged, not crashing | VERIFIED | `listFromString`: guarded top-level decode → `SalvageReport.markListReset<T>()` + return `[]`; per-entry try/catch → `markEntryDropped<T>()` + continue; no rethrow. `SettingGroup.load()`: `String? value`, null/empty guard, `json.decode` in try/catch, never rethrows. `loadList` wraps `listFromString` in try/catch returning `[]`. All confirmed by source inspection of `json_serialize.dart`, `setting_group.dart`, and `list_storage.dart`. |
| SC-4 | An interrupted write never leaves a half-written file — the previous good file survives | VERIFIED | `saveTextFile`: writes `$key.txt.tmp` then `rename(target.path)` inside `queue.add()`. `saveRingtone`: same pattern with `.tmp` sibling + `rename`. No `FileMode.writeOnly` remains. Rename is POSIX-atomic on a single filesystem; same-dir temp guaranteed. Confirmed by source inspection of `list_storage.dart` lines 91–125. |

**Score:** 2 VERIFIED / 4 ROADMAP SCs (2 require on-device human verification)

---

### Observable Truths — Plan Frontmatter Must-Haves

#### Plan 01-01 Must-Haves (STOR-01, STOR-02, BOOT-04)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | A write killed mid-save never leaves a half-written file; the previous good file survives (STOR-01 / D-02) | VERIFIED | `saveTextFile` writes `.tmp` then renames inside `queue.add`. `saveRingtone` identical. No `FileMode.writeOnly` in codebase (grep returns nothing). Rename is atomic. |
| 2 | A null/empty/invalid-JSON stored value recovers to a safe default and is logged, never throws (STOR-02 / D-03 / D-05) | VERIFIED | `SettingGroup.load()`: `String? value` declared at line 262; null/empty guard at line 270; `json.decode` in try/catch at line 275-279; comment "never rethrow". GetStorage fallback retained at line 267. |
| 3 | A single corrupt alarm entry in alarms.txt loads all OTHER alarms; only the bad one is skipped and logged (BOOT-04 / D-04) | VERIFIED | `listFromString`: per-element try/catch loop (lines 68-74); on failure: `logger.e("Skipping corrupt $T entry")` + `SalvageReport.markEntryDropped<T>()` + continue; good entries accumulate in `list`. |
| 4 | Top-level unparseable alarm list recovers to empty list, logs it, sets alarms-lost flag (BOOT-04 / D-04) | VERIFIED | `listFromString`: outer try/catch on `json.decode(encodedItems) as List<dynamic>` (lines 59-65); on failure: `logger.e(...)` + `SalvageReport.markListReset<T>()` + `return <T>[]`; no rethrow. |
| 5 | Loss of one or more Alarm entries is recorded in SalvageReport; routine recovery does NOT set the flag (D-06) | VERIFIED | `SalvageReport.markEntryDropped<T>()` and `markListReset<T>()` both gate on `T == Alarm` (lines 26-28, 34-36). Timer/City/etc loss leaves `_alarmsWereLost` false. `clear()` resets to false. |

#### Plan 01-02 Must-Haves (BOOT-01, BOOT-02, BOOT-03)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 6 | Boot code does not touch CE storage before device unlock — no IllegalStateException on LOCKED_BOOT_COMPLETED (BOOT-02 / D-07) | ? UNCERTAIN (human_needed) | Source: `isDeviceLocked()` uses probe-and-catch (`getApplicationDocumentsDirectory()` throw = locked); called before any storage touch at line 26 of `handle_boot.dart`. LOCKED_BOOT_COMPLETED removed from Chrono's BootBroadcastReceiver intent-filter (manifest lines 144-149). Runtime behavior on FBE hardware unverifiable. |
| 7 | When locked at boot, handleBoot logs and returns early (BOOT-02 / D-07) | VERIFIED | Lines 26-30 of `handle_boot.dart`: `if (await isDeviceLocked()) { logger.i("handleBoot: device locked ... deferring reschedule until unlock"); return; }`. Control flow: early return before any `initializeIsolate` call. |
| 8 | After reboot+unlock, every alarm/timer rescheduled exactly once (BOOT-03 / D-08) | ? UNCERTAIN (human_needed) | Source: idempotency confirmed — `schedule_alarm.dart` cancel-then-schedule by stable `scheduleId`; `updateAlarms`/`updateTimers` called in both paths. "Exactly once" runtime proof requires device. |
| 9 | `main()` always reaches `runApp(App())` — slow/failed init cannot become permanent splash hang (BOOT-01 / D-06) | VERIFIED | `main.dart` lines 54-67: storage+reschedule segment in try/catch with `.timeout(const Duration(seconds: 8))`; `TimeoutException` caught and logged; general catch logged; `runApp(const App())` at line 74 is unconditionally after the try/catch. `Future.wait(initializeData)` at line 45 is outside the timeout. |
| 10 | `initializeIsolate()` runs INSIDE `handleBoot`'s try/catch (BOOT-01 / BOOT-02) | VERIFIED | `handle_boot.dart` line 32: `try {`; line 36: `await initializeIsolate();`. `initializeIsolate` appears lexically after the `try {` opening. The `@pragma('vm:entry-point')` annotation at line 8 is preserved. |

#### Plan 01-03 Must-Haves (BOOT-04, STOR-02 — UI notice)

| # | Truth | Status | Evidence |
|---|---|---|---|
| 11 | After boot recovery dropped ≥1 alarm, user sees one-time, dismissible, localized notice on next normal launch (D-06 / BOOT-04) | ? UNCERTAIN (human_needed) | Source: `_showAlarmsResetNoticeIfNeeded()` in `app.dart` wired via `addPostFrameCallback` in `initState`; reads `SalvageReport.alarmsWereLost`; shows SnackBar with `localizations.alarmsResetNotice`; calls `SalvageReport.clear()` after. Logic verified by source. Requires `flutter gen-l10n` + on-device test to confirm end-to-end. |
| 12 | Routine recovery shows NO notice — stays silent + logged (D-06 / Pitfall 5) | VERIFIED | `_showAlarmsResetNoticeIfNeeded()` line 109: `if (!SalvageReport.alarmsWereLost) return;`. Flag is Alarm-only by `SalvageReport` design. Onboarding gate at line 113-114 prevents pre-onboarding fire. |
| 13 | Notice is Semantics-wrapped and uses localized ARB string, not hardcoded literal (D-06 / accessibility) | VERIFIED (source only; TalkBack needs device) | `app.dart` lines 126-131: `Semantics(liveRegion: true, label: message, child: Text(message))` where `message = localizations.alarmsResetNotice`. ARB key `"alarmsResetNotice"` with `@alarmsResetNotice` description present in `app_en.arb` lines 779-782. No hardcoded English literal in the SnackBar content (grep confirms `alarmsResetNotice` is the only getter referenced). TalkBack announcement requires device. |
| 14 | Notice shows exactly once — salvage flag is cleared after shown (D-06) | VERIFIED | `app.dart` line 141: `SalvageReport.clear()` called unconditionally after `showSnackBar`. Flag is module-level static; cleared to false; subsequent `addPostFrameCallback` calls would gate on `alarmsWereLost == false` and return early. |

**Score:** 10/14 truths VERIFIED; 3 UNCERTAIN (human_needed); 1 UNCERTAIN-source-only (notice display, human needed for TalkBack)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `lib/common/utils/list_storage.dart` | Atomic temp-write + rename; loadList never throws | VERIFIED | `.rename(` present (lines 102, 121); `queue.add(` wraps rename; no `FileMode.writeOnly`; `loadList` wrapped in try/catch returning `[]` |
| `lib/common/utils/json_serialize.dart` | Per-entry salvage; SalvageReport calls; no rethrow in listFromString | VERIFIED | `SalvageReport.mark` calls present; top-level try/catch + per-element loop; comment "Never rethrow"; grep confirms no `rethrow;` statement (only a comment on line 57) |
| `lib/settings/types/setting_group.dart` | Null-safe load(); GetStorage fallback kept | VERIFIED | `String? value` at line 262; null/empty guard at 270; `json.decode` in try/catch at 275-279; `GetStorage().read(id)` fallback at line 267 |
| `lib/common/logic/salvage_report.dart` | alarmsWereLost, markEntryDropped, markListReset, clear | VERIFIED | All four symbols present; `T == Alarm` gate on each mark method; static class matching `RingingManager` style |
| `lib/system/logic/device_lock.dart` | isDeviceLocked() — probe-and-catch, API-gated no-op < API 24 | VERIFIED | Function exists; `FLUTTER_TEST` guard; `sdkInt < 24 → return false`; probe-and-catch on `getApplicationDocumentsDirectory()`; mechanism A rejection documented |
| `lib/system/logic/handle_boot.dart` | isDeviceLocked() guard at head; initializeIsolate inside try/catch | VERIFIED | `isDeviceLocked()` at line 26; early return at line 29; `try {` at line 32; `initializeIsolate()` at line 36 (inside try); `@pragma('vm:entry-point')` at line 8 |
| `lib/main.dart` | Time-boxed storage+reschedule segment; runApp always reached | VERIFIED | `.timeout(const Duration(seconds: 8))` at line 61; `TimeoutException` catch at line 62; general catch at line 65; `runApp(const App())` at line 74 (after try/catch); `Future.wait` at line 45 (outside timeout) |
| `lib/app.dart` | SalvageReport check; Semantics-wrapped SnackBar; flag cleared | VERIFIED | `SalvageReport.alarmsWereLost` at line 109; `Semantics(liveRegion: true, ...)` at line 126; `SalvageReport.clear()` at line 141; `alarmsResetNotice` getter used (no hardcoded literal); onboarding gate at line 113 |
| `lib/l10n/app_en.arb` | `alarmsResetNotice` key + `@alarmsResetNotice` with description | VERIFIED | Key at line 779; `@alarmsResetNotice` with non-empty `description` at lines 780-782; only `app_en.arb` modified (other locale files untouched) |
| `android/app/src/main/AndroidManifest.xml` | LOCKED_BOOT_COMPLETED removed from Chrono's BootBroadcastReceiver | VERIFIED | Manifest lines 128-150: `BootBroadcastReceiver` intent-filter has `BOOT_COMPLETED` and `QUICKBOOT_POWERON` only; explanatory comment at lines 135-143 confirms intentional removal; aamp `RebootBroadcastReceiver` retains `LOCKED_BOOT_COMPLETED` (intentional) |
| `test/common/utils/list_storage_test.dart` | Round-trip, no leftover .tmp, full replace | VERIFIED (source only) | File exists; covers all 3 required behaviors; uses `setAppDataDirectoryPathForTesting`; NOT executed (toolchain absent) |
| `test/common/utils/json_serialize_test.dart` | SalvageReport flag transitions, per-entry salvage, unparseable list | VERIFIED (source only) | File exists; covers all 6 required behaviors from plan; `setUp` calls `SalvageReport.clear()`; NOT executed (toolchain absent) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `json_serialize.dart` | `salvage_report.dart` | `SalvageReport.markEntryDropped<T>()` / `markListReset<T>()` called only when T == Alarm | VERIFIED | Both calls present in `listFromString`; `T == Alarm` gate confirmed in `salvage_report.dart` |
| `list_storage.dart` | temp file | write `$key.txt.tmp` then `rename` over `$key.txt`, inside `queue.add` | VERIFIED | `File tmp = File(path.join(appDataDirectory, '$key.txt.tmp'))` + `await tmp.rename(target.path)` inside `queue.add(() async {...})` |
| `handle_boot.dart` | `device_lock.dart` | `await isDeviceLocked()` guard before any storage touch | VERIFIED | `isDeviceLocked()` call at line 26 of `handle_boot.dart`; precedes any `initializeIsolate` call |
| `main.dart` | `updateAlarms` / `updateTimers` | same idempotent reschedule funnel as handleBoot, wrapped in `.timeout()` | VERIFIED | Lines 58-60: `await updateAlarms(...)` and `await updateTimers(...)` inside the `.timeout()` closure |
| `handle_boot.dart` | `updateAlarms` / `updateTimers` | single shared idempotent reschedule funnel (D-08) | VERIFIED | Lines 37-38 of `handle_boot.dart`: `await updateAlarms(...)` and `await updateTimers(...)` inside the try block |
| `app.dart` | `salvage_report.dart` | reads `SalvageReport.alarmsWereLost`, clears after showing | VERIFIED | `import 'package:clock_app/common/logic/salvage_report.dart'` at line 3; reads at line 109; clears at line 141 |
| `app.dart` | `app_en.arb` | `AppLocalizations.of(context).alarmsResetNotice` in Semantics-wrapped SnackBar | VERIFIED (source + ARB) | `localizations.alarmsResetNotice` at line 122; ARB key present; symbol will resolve after `flutter gen-l10n` |

---

### Specific Acceptance Criteria Checks

#### Critical check: `rethrow` in `listFromString` (per constraint in verification instructions)

`json_serialize.dart` contains exactly one occurrence of the word "rethrow" — on line 57, which is a **comment** (`// Never rethrow — the load path must not crash or hang on bad data.`). There is no `rethrow;` statement anywhere in the file. The acceptance criterion "no rethrow inside listFromString" is met.

The three `rethrow;` statements in `setting_group.dart` (lines 108, 140, 149) are in `getGroup()`, `getSettingItem()`, and `getSetting()` respectively — all are developer-error paths (lookup by name fails) that pre-existed and are intentionally loud. They are not in `load()`. The `load()` function (lines 257-283) has an explicit comment "never rethrow" and no `rethrow;` statement.

#### TODO in `setting_group.dart` (line 199)

`//TODO: Add migration code` is a pre-existing comment inside `loadValueFromJson`'s version-migration block (confirmed by `git show 9edb4bf^` — the comment was in the file before this phase's commit). This phase only modified `load()`. The TODO is informational scaffolding for future migration, not a Phase 1 incompleteness. Not a blocker.

#### Rejected D-01/D-04 ideas not implemented

Grep confirms: no `sqflite` usage, no `per-file` or `alarm-{id}` storage pattern, and no `GetStorage` fallback removal in the modified files. All three decisions honored.

---

### Data-Flow Trace (Level 4)

The dynamic-data artifacts in this phase are infrastructure (storage utilities, boot logic) rather than UI components that render queries. The one UI artifact is `app.dart`'s notice:

| Artifact | Data Variable | Source | Produces Real Data | Status |
|---|---|---|---|---|
| `lib/app.dart` — notice | `SalvageReport.alarmsWereLost` | Module-level static flag set by `listFromString` on Alarm corruption | Yes (non-trivial: set only on actual alarm list/entry corruption) | FLOWING (source-verified) |
| `lib/app.dart` — notice message | `localizations.alarmsResetNotice` | `app_en.arb` key → `flutter gen-l10n` → `AppLocalizations` getter | Yes, once codegen runs | PENDING CODEGEN (ARB key present; getter not yet on disk) |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — no runnable entry points (Flutter toolchain absent; `flutter run` and `flutter test` cannot execute in this environment).

---

### Probe Execution

Step 7c: No probe files found in `scripts/*/tests/probe-*.sh`. SKIPPED.

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| STOR-01 | 01-01 | List/settings writes are atomic (temp-write + rename) | VERIFIED | `saveTextFile`/`saveRingtone` use temp+rename inside queue; no `FileMode.writeOnly` |
| STOR-02 | 01-01, 01-03 | Storage reads guard against null/invalid JSON before decoding | VERIFIED | `SettingGroup.load()` null-safe; `listFromString` guarded; `loadList` never throws |
| BOOT-01 | 01-02 | App launches to normal UI — never permanent black/splash hang after reboot/kill/corrupt state | UNCERTAIN (human_needed) | Source: 8s timeout + always-reached `runApp`; runtime on-device unverifiable |
| BOOT-02 | 01-02 | Boot code does not access CE storage before unlock — no `IllegalStateException` | UNCERTAIN (human_needed) | Source: `isDeviceLocked()` guard + early return in `handleBoot`; `LOCKED_BOOT_COMPLETED` removed from manifest; runtime FBE behavior unverifiable |
| BOOT-03 | 01-02 | Alarms/timers rescheduled exactly once after reboot+unlock, idempotently | UNCERTAIN (human_needed) | Source: idempotent funnel confirmed (cancel-then-schedule by stable id); "exactly once" runtime proof requires device |
| BOOT-04 | 01-01, 01-03 | Corrupt/unreadable file recovers to safe default and is logged | VERIFIED | Per-entry salvage + top-level fallback + null-safe load all confirmed by source |

**All 6 Phase 1 requirements are covered by the three plans.** BOOT-01, BOOT-02, BOOT-03 are source-complete but runtime-unverified (human_needed). BOOT-04, STOR-01, STOR-02 are fully verified by source inspection.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `lib/settings/types/setting_group.dart` | 199 | `//TODO: Add migration code` | INFO | Pre-existing comment from before this phase (confirmed via `git show 9edb4bf^`); in migration scaffolding block, not in Phase 1 modified `load()` code. Not a Phase 1 issue. |

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 1 modified file. The `TODO` is pre-existing and not in Phase 1's changed code.

---

### Human Verification Required

#### 1. On-Device Reboot-Before-Unlock Test (BOOT-01 / BOOT-02 / BOOT-03)

**Test:** Build and install the dev flavor on an API 24+ PIN/pattern FBE Android device/emulator. Create ≥2 alarms (one enabled, near-future) and 1 timer. Run `adb reboot`. While still on the lock screen, check: `adb logcat | grep -iE 'handleBoot|deferring|IllegalStateException|credential'`. Unlock. Open Chrono. Optionally repeat the reboot to confirm no alarm accumulation.

**Expected:**
- Pre-unlock: log shows `"handleBoot: device locked (pre-unlock) — deferring reschedule until unlock"`, NO `IllegalStateException`, no boot-attributable black screen.
- Post-unlock: app reaches normal UI (no permanent splash hang); alarms and timers are still armed; each appears exactly once in the alarm list.
- Force-stop via `adb shell am force-stop com.vicolo.chrono.dev` + reopen: app reaches normal UI.

**Why human:** Requires a physical Android device or emulator with PIN/pattern lock and FBE, plus a Flutter build. No software substitute — the pre-unlock crash only fires on real BOOT_COMPLETED delivery before the user unlocks. Defined in 01-02-PLAN.md Task 3.

#### 2. One-Time Alarms-Lost Notice — On-Device + TalkBack Test (BOOT-04 / D-06 / accessibility)

**Prerequisite:** Run `flutter gen-l10n` and `flutter analyze lib/app.dart` first (confirm 0 errors — the `alarmsResetNotice` symbol must be generated).

**Test:**
1. Install dev flavor. Run `flutter run --flavor dev`.
2. Positive — corrupt alarms.txt: via `adb shell run-as com.vicolo.chrono.dev`, edit `Clock/alarms.txt` to make one array element invalid JSON (keep top-level `[...]` valid) OR replace the whole file with `{not a list`. Relaunch the app.
3. Relaunch again (second launch).
4. Accessibility: with TalkBack enabled, repeat positive case.
5. Negative: blank a settings group file (not alarms), relaunch.
6. Dismiss test: confirm SnackBar can be dismissed by swipe.

**Expected:**
- Step 2: localized SnackBar "Some alarms could not be restored and were reset. Please check your alarms." appears exactly once.
- Step 3: no SnackBar (flag cleared after step 2).
- Step 4: TalkBack announces the notice text.
- Step 5: no SnackBar (flag not set by settings recovery — Pitfall 5 honored).
- Step 6: SnackBar dismisses on horizontal swipe; does not reappear.

**Why human:** Requires TalkBack, on-device file corruption, and `flutter gen-l10n` execution. Defined in 01-03-PLAN.md Task 3.

#### 3. Toolchain Gate: flutter test + flutter analyze + flutter gen-l10n

**Test:** On a machine with Flutter 3.22.2:
```
flutter gen-l10n
flutter analyze lib/common/utils/list_storage.dart lib/common/utils/json_serialize.dart lib/settings/types/setting_group.dart lib/common/logic/salvage_report.dart lib/system/logic/device_lock.dart lib/system/logic/handle_boot.dart lib/main.dart lib/app.dart
flutter test test/common/utils/list_storage_test.dart test/common/utils/json_serialize_test.dart
```

**Expected:** All three commands exit 0. `flutter analyze` reports no new errors. Test suite shows 9 passing tests (3 in `list_storage_test.dart`, 6 in `json_serialize_test.dart` covering all SalvageReport flag transitions, per-entry salvage, unparseable-list recovery, and non-alarm silence).

**Why human:** Flutter/Dart toolchain absent in this environment (WSL, no flutter/dart binary). The generated `AppLocalizations.alarmsResetNotice` getter used in `app.dart` does not exist on disk until `flutter gen-l10n` runs.

---

### Gaps Summary

No source-level gaps identified. All Phase 1 source changes are present, substantive, and correctly wired:

- STOR-01/STOR-02/BOOT-04: fully implemented and source-verified.
- BOOT-01/BOOT-02/BOOT-03: source implementation complete (guard, try/catch, timeout, manifest narrowing); runtime behavior awaits two planned blocking on-device checkpoints from 01-02-PLAN.md Task 3 and 01-03-PLAN.md Task 3. These were explicitly flagged as blocking human-verify checkpoints in the plans and are not regressions.
- The `alarmsResetNotice` ARB key is present and valid; `app.dart` references it correctly; the generated getter will exist once `flutter gen-l10n` runs.

**The phase is source-complete. Three items require human verification before the phase can be closed: the two on-device checkpoints and the toolchain test gate.**

---

*Verified: 2026-05-30T18:00:00Z*
*Verifier: Claude (gsd-verifier)*
