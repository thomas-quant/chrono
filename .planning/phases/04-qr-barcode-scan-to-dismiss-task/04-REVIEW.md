---
phase: 04-qr-barcode-scan-to-dismiss-task
reviewed: 2026-06-06T00:00:00Z
depth: quick
files_reviewed: 21
files_reviewed_list:
  - .github/workflows/test-apk.yml
  - android/app/build.gradle
  - android/app/src/main/AndroidManifest.xml
  - lib/alarm/data/alarm_task_schemas.dart
  - lib/alarm/logic/code_match.dart
  - lib/alarm/logic/escape_hatch_controller.dart
  - lib/alarm/screens/scan_register_screen.dart
  - lib/alarm/types/alarm_task.dart
  - lib/alarm/widgets/scan_register_card.dart
  - lib/alarm/widgets/tasks/scan_task.dart
  - lib/common/types/list_item.dart
  - lib/common/widgets/customize_screen.dart
  - lib/common/widgets/list/customize_list_item_screen.dart
  - lib/l10n/app_en.arb
  - lib/settings/logic/get_setting_widget.dart
  - lib/settings/types/scan_register_setting.dart
  - lib/settings/widgets/dynamic_toggle_setting_card.dart
  - test/alarm/logic/code_match_test.dart
  - test/alarm/logic/escape_hatch_controller_test.dart
  - test/alarm/types/alarm_task_scan_test.dart
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
resolved:
  - CR-01
  - CR-02
  - WR-04
resolved_at: 2026-06-06
open:
  - WR-01
  - WR-02
  - WR-03
  - WR-05
  - IN-01
  - IN-02
  - IN-03
  - IN-04
---

# Phase 4: Code Review Report

**Reviewed:** 2026-06-06
**Depth:** quick (extended with targeted cross-file tracing of the save-gate and ring-time call chains, because the core safety invariant required it)
**Files Reviewed:** 21
**Status:** issues_found

## Summary

This phase adds a QR/barcode scan-to-dismiss alarm task. The two pure seams
(`code_match.dart`, `escape_hatch_controller.dart`) are well-designed,
dependency-free, and thoroughly tested — the normalize-both-sides invariant, the
empty-stored safety floor, and the enabled-vs-`fireNow` asymmetry are all
correct and CI-covered. Privacy discipline is consistently observed: no scan
payload is ever logged, printed, or rendered.

However, the central safety invariant — "the registered-code save gate must
really block, not just warn" — is **defeated on the add-a-new-task path**, and
the same gap produces an alarm that is un-dismissable by scanning. That is a
core-value failure for an alarm app, so it is filed as a BLOCKER (CR-01). A
second BLOCKER (CR-02) covers a missing re-entrancy guard at ring time that can
advance/dismiss two task steps from a single tap-free double decode.

The escape-hatch logic itself holds, so the "never trap" guarantee survives in
the threshold/camera-fail paths — but CR-01 still lets a user create a task that
only the escape hatch can clear, and which becomes fully un-dismissable the
moment the (default-on) escape hatch is toggled off.

## Critical Issues

### CR-01: Save gate is bypassed when ADDING a scan task — produces an un-dismissable alarm

**File:** `lib/settings/widgets/list_setting_screen.dart:88-90` (add path) vs `lib/common/widgets/list/customize_list_item_screen.dart:43-44` (gate) — root cause spans `lib/alarm/types/alarm_task.dart:114-123`, `lib/alarm/data/alarm_task_schemas.dart:120-155`, `lib/alarm/widgets/tasks/scan_task.dart:88-90`

**Issue:**
The `validate()` save gate (D-REG-REQUIRED) is only invoked inside
`CustomizeScreen`'s Save button, which is only reached via the **edit** path
(`CustomizableListSettingScreen._handleCustomizeItem` → `CustomizeListItemScreen`,
triggered by `onTapItem`). The **add** path never goes through it:

```
FAB.onPressed → _openAddBottomSheet()
  → CustomizableListSettingAddBottomSheet: onTap → Navigator.pop(context, item)
→ _listController.addItem(item.copy());   // added directly, no CustomizeScreen, no validate()
```

So a user can add a `scan` task whose "Registered Code" is the schema default
`""` (`alarm_task_schemas.dart:128-133`) and it lands in the alarm's task list
having never passed `AlarmTask.validate()`. The gate "really blocks" only for
the case where the task already existed and is re-opened.

This is not merely a cosmetic gate miss — it directly breaks the core invariant
that the alarm must remain dismissable:
- At ring time `_storedNormalized = normalizeCode("") == ""`
  (`scan_task.dart:88-90`), and `codesMatch(_, "")` returns `false` by design
  (`code_match.dart:43`). **No scan can ever dismiss this task.**
- The only remaining exit is the escape hatch. The escape hatch defaults ON, but
  it is a user-facing on/off toggle (`scanEscapeHatch`, default true). If the
  user adds an unregistered scan task **and** turns the escape hatch off, the
  alarm becomes **completely un-dismissable by any in-task path** — exactly the
  "trapped user" outcome the phase is meant to prevent.

**Fix:** Make registration a precondition of adding, not just of editing. The
cleanest options:

1. Route the add path through the same gate by opening the customize screen for a
   newly-added scan task before committing it (and only `addItem` on a clean
   `validate()`):
   ```dart
   // list_setting_screen.dart FAB handler
   Item? item = await _openAddBottomSheet();
   if (item == null) return;
   final newItem = item.copy();
   final saved = await openCustomizeScreen<Item>(
     context,
     CustomizeListItemScreen<Item>(item: newItem, isNewItem: true),
   );
   if (saved == null) return;          // cancelled or gate blocked → not added
   _listController.addItem(saved);
   ```
   `CustomizeScreen` already blocks the pop when `validate()` returns non-null
   (`customize_screen.dart:73-87`), so a never-registered scan task can never be
   saved/added.

2. As defense-in-depth regardless of which UI fix is chosen, the ring-time host
   should treat an unregistered scan task as auto-escaped: in `ScanTask._initialize`,
   if `_storedNormalized.isEmpty` call `_escapeHatch?.fireNow()` so the Dismiss
   affordance is shown even when the escape toggle is off — a misconfigured task
   must never be a trap.

Add a widget/integration test that exercises the **add** flow (not just
`AlarmTask.validate()` in isolation) and asserts the task is not committed while
the code is empty.

**Resolution (2026-06-06, commit c687226 — RESOLVED):** Applied option 1. The
FAB `onPressed` in `lib/settings/widgets/list_setting_screen.dart` now checks
`newItem.validate(context)` after the add bottom sheet returns: items that fail
their gate (the scan task with no registered code) are routed through
`openCustomizeScreen` + `CustomizeListItemScreen(isNewItem: true)` and are only
committed via the `onSave` callback, which fires solely when `CustomizeScreen`
pops on a clean `validate()`. Items whose `validate()` returns null (every other
type) keep the unchanged direct-add path. The post-await `context` use is guarded
with a `mounted` check. NOTE (owed gate): the add-flow widget test and
`flutter analyze` are NOT run locally (Flutter toolchain absent in this env) —
they are owed CI/on-device gates; the WR-04 analyze repoint now covers
`list_setting_screen.dart` in CI.

### CR-02: No re-entrancy guard in `ScanTask._onScan` — a second match decode double-advances/dismisses

**File:** `lib/alarm/widgets/tasks/scan_task.dart:127-147`

**Issue:**
`_onScan` calls `widget.onSolve()` on a match with no "already solved" guard.
`ReaderWidget` can deliver another frame before the widget is torn down
(`scanDelaySuccess` is only a 1000 ms throttle, not a one-shot latch), and
`onScan` is wired as `async`, so two matching decodes in quick succession can
both reach `onSolve()`. At ring time `onSolve` is `_setNextWidget`
(`alarm_notification_screen.dart:59`), which increments `_currentIndex` and
advances to the next task — or dismisses the alarm if this was the last task. A
double-fire therefore **skips a subsequent task** or **double-dismisses**
(calling `dismissAlarmNotification` / `Navigator.pop(true)` twice).

The companion `ScanRegisterScreen` already recognized this exact hazard and
guards it with a `_registered` bool (`scan_register_screen.dart:34-37,54`); the
ring widget omits the equivalent guard.

**Fix:** Add a one-shot latch mirroring the register screen:
```dart
bool _solved = false;
void _onScan(Code code) {
  if (_solved) return;
  if (codesMatch(normalizeCode(code.text), _storedNormalized)) {
    _solved = true;
    widget.onSolve();
    return;
  }
  ...
}
```

**Resolution (2026-06-06, commit 205db0a — RESOLVED):** Added the `bool _solved`
one-shot latch to `_ScanTaskState` in `lib/alarm/widgets/tasks/scan_task.dart`.
`_onScan` returns early when `_solved` is set and latches `_solved = true` BEFORE
calling `widget.onSolve()` on the match branch. The escape-hatch Dismiss button's
`onPressed` (`_buildDismissButton`) is guarded with the same latch so a
double-tap cannot double-fire `onSolve()`. Mirrors `ScanRegisterScreen`'s
`_registered` guard. NOTE (owed gate): not exercised by a local test run
(toolchain absent) — owed CI/on-device gate.

## Warnings

### WR-01: Dead torch-failure UI — `_torchUnavailable` is never set to `true`

**File:** `lib/alarm/widgets/tasks/scan_task.dart:73, 215-227`

**Issue:** `_torchUnavailable` is declared `false` and read in `build` to show
the `scanTorchUnavailable` message, but nothing ever assigns it `true` (verified
across the whole file — only a declaration and a read exist). The graceful
no-flash branch (SCAN-09) is therefore unreachable dead code: a torch-enable
failure will never surface the copy. `ReaderWidget`'s built-in `showFlashlight`
toggle owns the torch, so there is no callback wired to detect its failure.

**Fix:** Either wire a real torch-failure signal (if `flutter_zxing` exposes a
torch-error callback/result, set `_torchUnavailable = true` in it via
`setState`), or remove the dead state field and its `build` branch and downgrade
SCAN-09 to "torch is best-effort via the library toggle" with the unused string
deleted. Do not ship state + UI that can never activate.

### WR-02: `Vibration.vibrate` called without a `hasVibrator()` capability check

**File:** `lib/alarm/widgets/tasks/scan_task.dart:139`

**Issue:** `Vibration.vibrate(duration: 200)` is fire-and-forget with no guard.
On devices without a vibrator (the manifest declares the app installable on
minimal hardware, and `android.hardware.camera` is `required="false"`), and on
some OEMs where the plugin throws on the platform channel, this can surface an
unhandled async platform exception on the wrong-code path. The result return is
also un-awaited, so any rejection becomes an unhandled future.

**Fix:** Guard and isolate failures:
```dart
if (await Vibration.hasVibrator() ?? false) {
  await Vibration.vibrate(duration: 200);
}
```
or wrap in a `try/catch` that swallows platform errors — haptics must never
break the wrong-code feedback path.

### WR-03: Overlapping wrong-code flashes truncate each other (raw `Future.delayed`, no timer ownership)

**File:** `lib/alarm/widgets/tasks/scan_task.dart:142-146`

**Issue:** Each non-matching decode schedules an independent
`Future.delayed(600ms)` that flips `_showWrongCode` back to `false`. With
1 decode/sec throttling this is usually benign, but two decodes ~500 ms apart
will have the first delayed callback clear the flash while the second is still
"active," causing the error border to disappear early / strobe — the very thing
the comment claims it is "tuned so it never strobes." The pending futures are
also not cancelled on `dispose` (the `mounted` checks prevent a crash but the
pattern leaks a pending timer per failed scan).

**Fix:** Own a single `Timer?` (cancel-and-restart on each failed decode, cancel
in `dispose`) instead of unmanaged `Future.delayed` calls, so the flash window
is deterministic and torn down with the widget.

### WR-04: CI `flutter analyze` does not cover any of the new scan files — lints (incl. the WR-01 dead code) are never gated

**File:** `.github/workflows/test-apk.yml:48-55`

**Issue:** The `Analyze changed files (informational)` step hard-codes the
Phase-2 file list (`alarm.dart`, `alarm_isolate.dart`,
`alarm_settings_schema.dart`, `alarm_snooze_test.dart`) and is
`continue-on-error: true`. None of the Phase-4 files (`scan_task.dart`,
`code_match.dart`, `escape_hatch_controller.dart`, etc.) are analyzed, so
unused-field / dead-code / deprecation lints in the new code (e.g. WR-01) are
never surfaced by CI. The comment still references "the Phase 2 changed files
(the snooze fix)," confirming the list was copied and not updated for this phase.

**Fix:** Add the Phase-4 source + test paths to the analyze invocation (or switch
to analyzing the whole `lib/` and reading the log for new issues). At minimum
include `lib/alarm/widgets/tasks/scan_task.dart`,
`lib/alarm/logic/code_match.dart`,
`lib/alarm/logic/escape_hatch_controller.dart`,
`lib/alarm/screens/scan_register_screen.dart`,
`lib/alarm/widgets/scan_register_card.dart`,
`lib/alarm/types/alarm_task.dart`, and the three new test files.

**Resolution (2026-06-06, commit a509ccc — RESOLVED):** The "Analyze changed
files (informational)" step in `.github/workflows/test-apk.yml` is repointed from
the Phase-2 file list to the Phase-4 scan source + test set (15 files:
`code_match.dart`, `escape_hatch_controller.dart`, `alarm_task.dart`,
`alarm_task_schemas.dart`, `scan_task.dart`, `scan_register_screen.dart`,
`scan_register_card.dart`, `scan_register_setting.dart`, `get_setting_widget.dart`,
`customize_screen.dart`, `customize_list_item_screen.dart`,
`list_setting_screen.dart`, and the three new test files). The step keeps
`continue-on-error: true` and remains informational; the comment block now
references Phase 4. NOTE: this is a CI-only gate — `flutter analyze` was NOT run
locally (toolchain absent); the repoint takes effect on the next CI run.

### WR-05: BUILD-02 FOSS-clean gate runs only on `workflow_dispatch` — never on push/PR

**File:** `.github/workflows/test-apk.yml:12-13, 94-147`

**Issue:** The F-Droid hard exit criterion ("zero `mlkit`/`gms`/`play-services`
in the prod release classpath") lives in the `dependency-graph` job of a workflow
whose only trigger is `workflow_dispatch`. A transitive dependency of
`flutter_zxing` (camera / image_picker) could pull a non-FOSS Android artifact
in a future bump and **no automatic run would catch it** — the gate only fires
when a human manually clicks "Run workflow." For a HARD distribution-blocking
criterion this is effectively un-enforced in normal CI.

**Fix:** Move the `dependency-graph` job into a push/PR-triggered workflow (it is
already self-contained and needs no secrets), or add `pull_request` / `push`
triggers so the FOSS-clean invariant is checked on every change that can alter
the dependency graph (notably `pubspec.yaml` / `pubspec.lock`).

## Info

### IN-01: `BuildContext` used after an `await` gap in the permission-denied resume

**File:** `lib/alarm/widgets/scan_register_card.dart:99-104`

**Issue:** After `await AppSettings.openAppSettings()` the code re-enters
`_handleScanToRegister()` (guarded by `if (mounted)`), which then uses `context`
for `Navigator`/`Permission` UI. The `mounted` check makes this safe at runtime,
but `_showPermissionDeniedPrompt` also captured `localizations`/`colorScheme`
from `context` before the dialog await; if the locale/theme changes while the
system-settings screen is foregrounded, stale strings/colors are used on resume.

**Fix:** Re-read `localizations`/`colorScheme` after the await, or pass them
freshly. Low impact; cosmetic on a rare path.

### IN-02: `code.text` nullability is assumed by `normalizeCode(String?)` but not documented at the call site

**File:** `lib/alarm/widgets/tasks/scan_task.dart:130`, `lib/alarm/screens/scan_register_screen.dart:57`

**Issue:** `normalizeCode` correctly accepts `String?` and maps null → `""`,
so a null `code.text` is handled. Good defensiveness — but note that a null/empty
decode at registration would store `""`, which the gate then rejects (correct),
while at ring time it can never match (correct). Worth an inline comment so a
future reader does not "tighten" the signature to non-null and reintroduce a NPE
risk.

**Fix:** Add a one-line comment noting `code.text` may be null and the empty
result is intentionally unregisterable / unmatchable.

### IN-03: Directly importing the transitive `fake_async` package in tests

**File:** `test/alarm/logic/escape_hatch_controller_test.dart:2`

**Issue:** `fake_async` is imported directly but is only present transitively via
`flutter_test` (it is in `pubspec.lock`, not `dev_dependencies`). This works
today but is fragile — a future `flutter_test` that stops re-exporting it would
break the suite with no local signal (toolchain absent).

**Fix:** Add `fake_async` explicitly under `dev_dependencies` in `pubspec.yaml`
to make the dependency intentional and pinned.

### IN-04: `pubspec.yaml` change (flutter_zxing) is outside the reviewed file set

**File:** `pubspec.yaml:77` (not in the review scope list, noted for completeness)

**Issue:** The phase diff adds `flutter_zxing: 2.2.1`. The exact-pin rationale is
sound and the BUILD-02 gate is the right guard, but the pin was not in the
explicit review list. Flagged only so the reviewer-of-record knows the dependency
addition exists and is covered (functionally) by WR-05's concern about when that
gate actually runs.

**Fix:** None required here; ensure WR-05 is addressed so the pin's FOSS-clean
property is continuously verified.

---

_Reviewed: 2026-06-06_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: quick_
