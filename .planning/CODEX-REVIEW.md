# Codex Review — Milestone Code (Reliability + QR Dismiss)

**Date:** 2026-07-18
**Reviewer:** Codex CLI 0.144.5 · model `gpt-5.6-sol` · sandbox `read-only`
**Scope:** full milestone diff `1dcffc3~1..HEAD` on `lib/ android/ test/` — 47 files, ~3,118 insertions
(storage/boot/snooze/date/volume/FAB reliability fixes + the QR/barcode scan-to-dismiss task).
**Bar applied:** "the alarm MUST reliably ring and reliably stop" — findings ranked against that.

**Tally:** 2 Critical · 5 High · 4 Medium.
**Clean:** no decoded-scan-payload logging/rendering found; `VolumeRampController` owns and
synchronously cancels a single timer (no verified post-cancel tick).
**Status:** as-reported by the external reviewer; not yet triaged/confirmed against the code or fixed.

---

## Ranked findings

### 1. Consecutive scan tasks make the second task permanently unsolvable
- **Severity:** Critical
- **Location:** `lib/alarm/widgets/tasks/scan_task.dart:121`, `:135`, `:334`; `lib/alarm/screens/alarm_notification_screen.dart:55`
- **Claim:** Flutter reuses `_ScanTaskState` for adjacent unkeyed `ScanTask` widgets, but `didUpdateWidget()` never resets `_solved`.
- **Failure scenario:** Configure two consecutive scan tasks (or duplicate one). Solving the first sets `_solved = true`; the host swaps in another unkeyed `ScanTask`, so Flutter calls `didUpdateWidget()` on the same state. Every scan on the second task returns early at line 138, and its escape button returns at line 335. Full dismiss is now impossible.
- **Suggested fix:** Key each task by `AlarmTask.id` in the host (forcing disposal between tasks), or reset all per-task state when the settings identity changes. Add a widget test that solves two consecutive scan tasks, including escape on the second.

### 2. A transient alarm-file read failure is converted into "no alarms" and persisted destructively
- **Severity:** Critical
- **Location:** `lib/common/utils/list_storage.dart:58`, `lib/alarm/logic/update_alarms.dart:41`
- **Claim:** `loadList()` conflates I/O failure with a successfully decoded empty list, while `updateAlarms()` cancels every OS alarm and then saves that empty result.
- **Failure scenario:** During startup or boot, `alarm_schedule_ids.txt` is readable but `alarms.txt` temporarily throws a `FileSystemException`. `cancelAllAlarms()` removes every registered alarm; `loadList("alarms")` returns `[]`; then `saveList("alarms", [])` permanently overwrites the alarm list. No loss notice is set because this exception never reaches `listFromString()`.
- **Suggested fix:** Return a typed load result distinguishing success / corruption / absence / I/O failure. Load and validate alarms before cancelling anything; abort or retry without writing on I/O failure. Never persist `[]` merely because a read failed.

### 3. Snooze → re-fire → dismiss can still re-arm a once alarm for the next day
- **Severity:** High
- **Location:** `lib/alarm/types/alarm.dart:336`, `:366`; `lib/alarm/types/schedules/once_alarm_schedule.dart:28`; `lib/alarm/logic/alarm_isolate.dart:94`
- **Claim:** Dismissal still infers "already fired" from the once runner's date, but the normal snooze-trigger update can replace that evidence with tomorrow's date before dismiss runs.
- **Failure scenario:** A 07:00 once alarm rings. Its first trigger-time `updateAlarms()` disables it and clears the runner. Snooze re-enables it but does not update the underlying runner date. When the snooze fires, `update()` calls `OnceAlarmSchedule.schedule()` before clearing the expired snooze; the null runner is scheduled for tomorrow at 07:00. Dismiss then sees a future runner, schedules it again, and leaves the alarm enabled. The new test bypasses this production sequence by retaining a past runner throughout.
- **Suggested fix:** Persist an explicit fired/resolved state, or directly disable a once alarm in `_resolveDismiss()` without calling its normal scheduling path. Add an integration-style state test covering initial trigger update → snooze persistence → snooze trigger update → dismiss.

### 4. Atomic writes are not atomic across Chrono's isolates
- **Severity:** High
- **Location:** `lib/common/utils/list_storage.dart:14`, `:91`
- **Claim:** Each isolate owns a separate `Queue`, while every writer uses the same fixed `$key.txt.tmp` path.
- **Failure scenario:** The firing isolate saves snooze state while the main or headless-background isolate saves an alarm edit. Both can open `alarms.txt.tmp`; one truncates or writes it while the other renames it. The target can become partially visible, one rename can fail because the temp path was already moved, or a stale whole-list write can overwrite the snooze count. An OS snooze may then fire against JSON that still says the alarm is disabled, causing the re-ring to be skipped.
- **Suggested fix:** Serialize full read-modify-write transactions through one storage-owning isolate or an OS-visible lock. Use unique temp files and a revision/CAS check; unique names alone do not prevent stale-list overwrites.

### 5. The boot defer branch has no reliable retry
- **Severity:** High
- **Location:** `lib/system/logic/device_lock.dart:48`, `lib/system/logic/handle_boot.dart:26`, `android/app/src/main/AndroidManifest.xml:137`
- **Claim:** Any path-provider exception is treated as "locked," after which `handleBoot()` returns without registering an unlock retry or durable pending-reschedule marker.
- **Failure scenario:** A post-unlock `BOOT_COMPLETED` callback encounters a transient platform-channel/path-provider failure — or an OEM delivers it before CE storage is usable. `isDeviceLocked()` returns true and the callback exits. `BOOT_COMPLETED` is not guaranteed to be delivered again during that boot, so Chrono's reschedule pass is skipped until another unrelated foreground/background run.
- **Suggested fix:** Check `UserManager.isUserUnlocked()` natively, distinguish probe failure from actual lock state, and register `ACTION_USER_UNLOCKED` or a durable bounded retry when deferring. Audit the still-direct-boot-aware `android_alarm_manager_plus` receiver as part of the same end-to-end boot path.

### 6. Silent camera failure can bypass the mandatory immediate escape
- **Severity:** High
- **Location:** `lib/alarm/widgets/tasks/scan_task.dart:96`, `:162`
- **Claim:** Camera-unavailable escape fires only when `onControllerCreated` supplies an exception; successful initialization followed by a black, frozen, or disabled feed has no liveness detection.
- **Failure scenario:** Android's camera privacy toggle or a CameraX/keyguard failure produces a controller but only black/stalled frames. If the user disabled the threshold escape, `EscapeHatchController.start()` arms no timer, `fireNow()` is never called, no code can decode, and no dismiss button ever appears.
- **Suggested fix:** Add a camera-start/liveness watchdog whose failure path cannot be disabled, explicitly check permission/privacy/availability at ring time without requesting permission, and retain a permanent non-disableable emergency dismiss floor.

### 7. The 60%-of-screen scanner can push the escape button outside the usable screen
- **Severity:** High
- **Location:** `lib/alarm/widgets/tasks/scan_task.dart:193`, `:206`, `:215`; `lib/alarm/screens/alarm_notification_screen.dart:111`
- **Claim:** Scanner height is calculated without reserving room for the instruction, padding, system insets, or the dynamically revealed escape button.
- **Failure scenario:** In landscape or at a large accessibility text scale, `0.6 × MediaQuery.height` plus the headline, 32 px outer padding, spacing, and dismiss control exceeds the task slot. The host's `SingleChildScrollView` contains a fixed-height `SizedBox`, so the overflow does not increase scroll extent; the escape button can paint outside hit-testable bounds and be unusable by touch or TalkBack. The layout test never reveals the escape button or exercises landscape/text scaling.
- **Suggested fix:** Use bounded `LayoutBuilder` constraints, reserve/pin space for the escape control, and make the remaining scanner area flexible or scrollable inside `SafeArea`. Test camera-failure/escape-visible states at small landscape sizes and large text scales.

### 8. Chrono does not release the scanner on app backgrounding
- **Severity:** Medium
- **Location:** `lib/alarm/widgets/tasks/scan_task.dart:127`, `:162`; `lib/alarm/screens/scan_register_screen.dart:33`
- **Claim:** Both scanner screens discard the camera controller and implement no lifecycle observer; backgrounding does not remove `ReaderWidget` from the tree, contrary to the disposal assumption.
- **Failure scenario:** Open the ring-time scanner and press Home or let another activity cover Chrono. `ScanTask.dispose()` is not called, so Chrono has no way to stop/unmount the camera. Depending on the pinned `ReaderWidget` behavior, the privacy indicator can remain active and a later scanner can find the camera busy.
- **Suggested fix:** Handle `AppLifecycleState.inactive/paused/detached` in the main isolate, retain a typed controller or conditionally unmount `ReaderWidget`, and restart on resume. Apply the same handling to registration.

### 9. Legacy epoch migration shifts valid locally-created dates
- **Severity:** Medium
- **Location:** `lib/settings/types/setting.dart:995`
- **Claim:** Every legacy integer is interpreted as a UTC calendar date, although old alarms also persisted locally-created `DateTime.now()` defaults.
- **Failure scenario:** A user in UTC+10 accepts a range alarm's locally-created default dates. A legacy instant such as local July 19 shortly after midnight is July 18 in UTC; migration rebuilds local July 18, moving the range boundary and potentially the firing day back by one.
- **Suggested fix:** Distinguish old picker-produced UTC-midnight epochs from locally-created instants. For example, treat exact UTC-midnight values as picker dates and otherwise recover local `year/month/day`, backed by migration tests for both origins and positive/negative offsets.

### 10. Alarm-loss reporting does not cross the isolate boundary
- **Severity:** Medium
- **Location:** `lib/common/logic/salvage_report.dart:18`, `lib/app.dart:108`, `lib/system/logic/handle_boot.dart:37`
- **Claim:** `SalvageReport` is isolate-local static memory, so losses detected by boot, firing, or headless isolates are invisible to the UI isolate.
- **Failure scenario:** Boot-time salvage drops one corrupt alarm and saves the surviving list. The boot isolate sets its own `_alarmsWereLost` and exits. On the next app launch, the now-clean file loads without another salvage event, the main isolate's flag remains false, and the user is never warned that an alarm disappeared.
- **Suggested fix:** Persist a durable "alarm recovery occurred" marker or send it over an isolate port when the UI is alive. Clear the persisted marker only after the UI actually displays the notice.

### 11. The UI change disables the fractional snooze durations that the state-machine fix claims to support
- **Severity:** Medium
- **Location:** `lib/alarm/data/alarm_settings_schema.dart:248`, `lib/common/widgets/fields/slider_field.dart:58`
- **Claim:** Adding `snapLength: 1` makes the snooze field integer-only even though `Alarm.snooze()` and its regression test target fractional minutes.
- **Failure scenario:** A stored 1.5-minute snooze still schedules 90 seconds, but the edited field renders it as `1` and accepts digits only. The test's 0.5-minute value is also below the schema's minimum of 1, so it cannot be configured through the shipped UI.
- **Suggested fix:** Use a fractional division such as `0.1` or `0.5`, lower the minimum if sub-minute snoozes are supported, and add a widget/schema test proving the value is selectable and displayed accurately.

---

## Top 3 to fix first (reviewer's call)

1. Reset/key consecutive `ScanTask` state so the second task cannot become permanently unsolvable. (#1)
2. Stop treating alarm-file I/O failures as a valid empty list before destructive rescheduling. (#2)
3. Make once-alarm dismissal explicitly terminal after a snooze re-fire, independent of runner timestamps. (#3)

---

## Owner-priority cross-reference (per the 2026-07-18 pivot)

- **Camera-dismiss feature (priority):** #1, #6, #7, #8 all live in the scan task. #6 (black/frozen feed bypasses the escape hatch) is the same failure class as the observed on-device black preview — worth folding into the camera re-verify.
- **Alarm-must-work baseline:** #2 (read glitch wipes alarms), #5 (no reschedule retry after reboot), #3 (once alarm re-rings), #4 (snooze state clobbered) are the reliability-critical set.
- Volume: the force-max-volume feature is not yet built, so it is out of this review's scope (no findings).

---

## Triage — verified against HEAD (2026-07-19)

**Verifier:** Claude Code (Opus 4.8) · 5 parallel read-only verification agents · against HEAD `1b91b5f`.
**Method:** each finding re-checked against *current* code — not the review's 2026-07-18 line numbers — with exact `file:line` at HEAD, a mechanical walk-through of the failure scenario, and inspection of any guarding test. **No code was changed.**
**Result:** **11 / 11 CONFIRMED.** Zero false positives; zero already-fixed-since-review. (The review's `1dcffc3~1..HEAD` scope already included the GAP-A/GAP-B commits that landed 2026-06-14, so the reviewer saw essentially current `scan_task.dart`; every commit after is docs/ci/test only.)

| # | Sev | Finding | Verdict | Confidence | Current location(s) & verified nuance |
|---|-----|---------|---------|-----------|----------------------------------------|
| 1 | Crit | Consecutive `ScanTask` → 2nd undismissable | **CONFIRMED** | High | `didUpdateWidget`→`_initialize()` resets `_storedNormalized`/escape but **never `_solved`** (`scan_task.dart:121`,`96`). Host mounts tasks unkeyed (`alarm_notification_screen.dart:59`); Tasks list exposes an explicit **Duplicate** action (`alarm_settings_schema.dart:306-310`). `_escapeAvailable` also persists, so the dead Dismiss button even renders on task 2. Cleanest, highest-impact. |
| 2 | Crit | Transient read failure wipes alarms | **CONFIRMED** | High | `loadList` swallows *any* throw → `[]` (`list_storage.dart:58-69`); `updateAlarms` order is cancel→load→save (`update_alarms.dart:41-55`), so a transient `alarms.txt` read failure atomically overwrites the real list with `[]`. Reachable from `main()` startup (`main.dart:58`), not just boot. Exception never reaches `listFromString`, so no salvage notice fires either. Shares root with #10. |
| 3 | High | Once-alarm re-arms after snooze | **CONFIRMED** | High | Full 4-step trace: step-1 `disable()`→`cancel()` **nulls** the runner; a null runner is indistinguishable from "never scheduled", so snooze-fire `update()` calls `OnceAlarmSchedule.schedule()` (`alarm.dart:374`) *before* clearing the expired snooze → arms **tomorrow 07:00**, `_isDisabled=false`; dismiss then sees a future runner and leaves it enabled. Existing SNZ-03 test injects a **past** (not null) runner and skips the intervening snooze-fire `updateAlarms` — its own docstring (`alarm_snooze_test.dart:20-26`) admits the gap. |
| 4 | High | Atomic writes not atomic across isolates | **CONFIRMED** | High | `queue` is a top-level (per-isolate) var (`list_storage.dart:14`); `saveTextFile` writes a fixed `$key.txt.tmp` with no isolate/random suffix and no lock/CAS (`:91-104`). Concurrent firing-vs-main writes to one key can corrupt bytes, throw on the second rename (ENOENT), or lose-update a snooze count. Narrower window — needs genuinely overlapping cross-isolate writes. |
| 5 | High | Boot defer has no reliable retry | **CONFIRMED** | High | `isDeviceLocked()` maps *any* throw → "locked" (`device_lock.dart:50-57`); defer branch just returns, no unlock-receiver/retry/marker (`handle_boot.dart:26-30`). **Cushion the review omits:** alarms are armed `rescheduleOnReboot:true` (`schedule_alarm.dart:87`), so aamp's own reboot receiver re-arms already-scheduled alarms — the real loss is Chrono's *schedule recomputation* (recurrence advance, `isMarkedForDeletion`, missed-while-off), not guaranteed silence of the next alarm. Reviewer's native `UserManager.isUserUnlocked()` fix is **unreachable** in the boot isolate (no MainActivity/FlutterEngine — `device_lock.dart:24-31`); needs a durable defer marker + retry instead. |
| 6 | High | Silent camera failure bypasses escape | **CONFIRMED** | High (mech) / Med (downstream) | Escape fires only on a non-null `onControllerCreated` exception (`scan_task.dart:162-173`); no liveness/frame watchdog, no non-disableable floor (`escape_hatch_controller.dart:67-84`). Black/frozen feed + escape-hatch-off = user trapped (`_escapeAvailable` stays false → Dismiss never rendered at `:215`). **Same failure class as the owner's observed black preview.** Downstream frequency (no-exception + dead feed) is plugin/OEM-dependent, unverifiable headlessly. |
| 7 | High | 60%-screen scanner pushes escape off-screen | **CONFIRMED** | High (mech) / Med (pixels) | **GAP-A *introduced* this** — `05a2ef2` replaced the collapsing `Expanded` with the fixed `SizedBox(0.6·h)` (`scan_task.dart:193`,`206`), reserving no room for headline/padding/insets/revealed Dismiss. Host pins the scroll child to viewport height (`alarm_notification_screen.dart:111-113`), so overflow **clips** rather than scrolls, pushing the bottom Dismiss button outside hit-test/TalkBack bounds in landscape or large text scale. Guard test (`scan_task_layout_test.dart`) pumps portrait-only, never landscape/text-scale, never reveals the escape button. |
| 8 | Med | Scanner not released on backgrounding | **CONFIRMED** | High (mech) / Med (downstream) | No `WidgetsBindingObserver`/`AppLifecycleState`/`flutter_fgbg` handling in either scanner screen (grep clean); `ScanTask.dispose()` only runs on tree removal, which backgrounding doesn't trigger (`scan_task.dart:127-133`), and `scan_register_screen.dart` has no `dispose()` at all. Whether the camera stays powered depends on `flutter_zxing` 2.2.1's internal lifecycle handling (source absent locally — unverifiable). Chrono-side claim fully verified. |
| 9 | Med | Epoch migration shifts local dates | **CONFIRMED** | High | `setting.dart:997-1007` reads *every* legacy int `isUtc:true` (line 1003) then rebuilds a local `DateTime(y,m,d)`. Correct for old midnight-UTC picker values, wrong for locally-created `DateTime.now()` schedule defaults (`range_alarm_schedule.dart:39-40`, `dates_alarm_schedule.dart:53`) → back-a-day for positive UTC offsets when local time-of-day < offset. Inherent to a lossy epoch→date migration, not a regression; untested for the non-midnight origin (`date_time_setting_test.dart` only exercises a midnight-UTC epoch). |
| 10 | Med | Alarm-loss reporting doesn't cross isolate | **CONFIRMED** | High | `SalvageReport` is `static` = per-isolate (`salvage_report.dart:16-17`). Boot/firing salvage sets its own flag and `updateAlarms` immediately persists the cleaned list (`update_alarms.dart:55`); that isolate exits, and the UI isolate later loads an already-clean file → `app.dart:109` returns early → user never warned. No durable marker or port bridges it. Same `updateAlarms` load→save root as #2. `salvage_report_test.dart` only exercises the single-isolate case. |
| 11 | Med | `snapLength:1` disables fractional snooze | **CONFIRMED** | High | Snooze Length slider is integer-only via `snapLength:1` + `min=1` (`alarm_settings_schema.dart:248-258`; `slider_field.dart:58-59` integer-only, digits-only field, `toInt()` display), while `Alarm.snooze()` (`alarm.dart:240`) and SNZ-02 (`alarm_snooze_test.dart:48-70`) target `0.5`. **Nuance:** the fractional `.round()`+≥1s-clamp in `snooze()` reads as *defensive* (guard near-zero length → instant re-fire), so this is a design/test tension, not user-facing data loss. Lowest-stakes item; realistic action is lower the min or accept the seam-only test. |

### Cross-cutting observations (what the triage adds beyond "all confirmed")

- **Two findings are entangled with prior fixes.** #7 is a **side effect of the GAP-A fix** — `05a2ef2` closed the zero-height `Expanded` collapse but introduced the fixed `0.6·h` box, and its regression test doesn't cover the axes that actually break (landscape, large text scale, escape-visible). #1's `_solved` latch is the CR-02 fix (`205db0a`) — correct for double-tap, never reset across task identity.
- **#2 + #10 share one root:** `updateAlarms` cancels/saves around an unguarded `loadList`. One fix — guard the save on load failure / typed load result distinguishing empty-vs-error — addresses both.
- **#5's worst case is cushioned** by `rescheduleOnReboot:true`, which lowers its "missed alarm" severity while leaving the recomputation gap real and unretried.
- **#11 is arguably by-design** — the only finding where "bug" framing is debatable; the fractional path is defensive and unit-tested precisely because it isn't UI-reachable.
- **Not re-verified (out of triage scope):** the review's "Clean" notes (no decoded-payload logging/rendering; `VolumeRampController` single-timer synchronous cancel) were accepted as-reported, not independently re-confirmed here.

### Suggested fix sequencing (owner-pivot aligned; not yet executed)

1. **#1** (Critical, camera-dismiss priority) — key tasks on `AlarmTask.id` at `alarm_notification_screen.dart:59`, or reset `_solved`/`_escapeAvailable`/`_cameraFailed` in `didUpdateWidget`.
2. **#2 (+#10)** (Critical, alarm baseline) — never persist `[]` because a read threw; typed load result + skip-save-on-error guard in `updateAlarms`.
3. **#3** (High, alarm baseline) — make `OnceAlarmSchedule` distinguish "already fired" from "never scheduled" independent of the runner date; or disable the once alarm directly in `_resolveDismiss()`.
4. **#6, #7** (High, camera-dismiss) — fold into the GAP-A on-device camera re-verify (they share the black-feed / layout surface).
5. **#4, #5, #8, #9** — reliability/robustness follow-ups.
6. **#11** — lowest stakes; lower the slider min or accept the seam-only test.
