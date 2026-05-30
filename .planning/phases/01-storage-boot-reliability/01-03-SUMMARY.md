---
phase: 01-storage-boot-reliability
plan: 03
subsystem: ui-notice
tags: [l10n, arb, snackbar, semantics, accessibility, post-frame-callback, salvage-report, boot-recovery]

# Dependency graph
requires:
  - "SalvageReport.alarmsWereLost / clear() — the alarm-only loss flag from Plan 01-01 (D-06)"
  - "App._messangerKey ScaffoldMessenger + AppLocalizations wiring already present in app.dart"
provides:
  - "Localized alarmsResetNotice string (English baseline; other locales via Weblate) — BOOT-04 / D-06"
  - "One-time, dismissible, Semantics-wrapped notice on the post-onboarding route when boot recovery dropped/reset alarms — BOOT-04 / D-06"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Post-frame callback (WidgetsBinding.addPostFrameCallback) reading a module-level recovery flag — no state-management library"
    - "Semantics(liveRegion: true)-wrapped localized SnackBar via the existing ScaffoldMessenger key"
    - "Strict gating on an alarm-only flag so routine recovery stays silent (Pitfall 5)"

key-files:
  created: []
  modified:
    - lib/l10n/app_en.arb
    - lib/app.dart

key-decisions:
  - "Rendered the notice as a floating SnackBar with swipe-to-dismiss (DismissDirection.horizontal) rather than a SnackBarAction button — avoids inventing an untranslated 'OK'/'Dismiss' label, keeps it dismissible and Semantics-reachable (SnackBar vs banner was Claude's discretion per the plan)"
  - "Gated the notice with the same GetStorage().read('onboarded') check used in onGenerateRoute so it never fires on the onboarding screen"
  - "Resolved AppLocalizations from _messangerKey.currentContext (inside MaterialApp's localization scope) in the post-frame callback rather than App's own outer context"

patterns-established:
  - "Pattern: one-time user-facing recovery notice = post-frame callback + module-level flag + clear-after-show, surfaced through the app-level ScaffoldMessenger"

requirements-completed: [BOOT-04, STOR-02]

# Metrics
duration: ~6min
completed: 2026-05-30
---

# Phase 1 Plan 03: Alarms-Lost One-Time Notice Summary

**A one-time, dismissible, screen-reader-reachable, localized "alarms were reset" notice that surfaces via the existing ScaffoldMessenger on the next normal launch — and only — when boot recovery actually dropped or reset one or more alarms (SalvageReport.alarmsWereLost); routine recovery stays silent.**

> **Status: autonomous tasks complete and committed; Task 3 is a BLOCKING on-device checkpoint (`checkpoint:human-verify`) returned to the orchestrator, NOT self-approved.**

## Performance

- **Duration:** ~6 min (autonomous tasks)
- **Started:** 2026-05-30
- **Completed (autonomous tasks):** 2026-05-30
- **Tasks:** 3 (2 autonomous done + committed; 1 blocking on-device checkpoint pending)
- **Files modified:** 2 (`lib/l10n/app_en.arb`, `lib/app.dart`)

## Accomplishments

- **BOOT-04 / D-06 (the localized string):** Added a single flat key `alarmsResetNotice` ("Some alarms could not be restored and were reset. Please check your alarms.") plus a matching `@alarmsResetNotice` metadata object with a non-empty `description` to `lib/l10n/app_en.arb`, matching the file's existing flat-key + `@key`-metadata style. **Only** `app_en.arb` was touched — other locales come via Weblate per D-06 / SCAN-12 baseline policy. The ARB file remains valid JSON (validated with a parser).
- **BOOT-04 / D-06 (the notice logic):** In `_AppState`, registered a `WidgetsBinding.instance.addPostFrameCallback` from `initState` that calls a new `_showAlarmsResetNoticeIfNeeded()`. The method:
  - Returns immediately unless `SalvageReport.alarmsWereLost` is true (strict gate — Pitfall 5: routine recovery never shows the notice; the flag is already Alarm-only by Plan 01-01's design).
  - Returns on the onboarding route (mirrors the existing `GetStorage().read('onboarded')` check in `onGenerateRoute`) so it only surfaces on the normal app route.
  - No-ops until the `_messangerKey` ScaffoldMessenger state and context are mounted, and until `AppLocalizations` resolves.
  - Shows a dismissible, floating `SnackBar` whose content is a `Semantics(liveRegion: true, label: …, child: Text(…))` using `AppLocalizations.of(context).alarmsResetNotice` — no hardcoded English literal — so it is screen-reader reachable.
  - Calls `SalvageReport.clear()` after showing so the notice appears exactly once.
  - Uses no state-management library — a post-frame callback reading the module-level flag, per the CLAUDE.md architecture constraint / D-01.

## Task Commits

Each autonomous task was committed atomically:

1. **Task 1: Add the localized `alarmsResetNotice` string (D-06)** — `d7f9de2` (feat) — `lib/l10n/app_en.arb`
2. **Task 2: Show the one-time, Semantics-wrapped notice on alarm loss (D-06 / Pitfall 5)** — `98d028b` (feat) — `lib/app.dart`
3. **Task 3: On-device verification (notice fires only on alarm loss, is TalkBack-announced, dismissible)** — **BLOCKING `checkpoint:human-verify` — pending human sign-off (not self-approved).**

## Files Created/Modified

- `lib/l10n/app_en.arb` — added `alarmsResetNotice` + `@alarmsResetNotice` (with `description`); English baseline only.
- `lib/app.dart` — added `import 'package:clock_app/common/logic/salvage_report.dart';`; registered a post-frame callback in `initState`; added `_showAlarmsResetNoticeIfNeeded()` that shows the one-time, gated, Semantics-wrapped, localized SnackBar and clears the flag.

## Decisions Made

- **Swipe-to-dismiss instead of a SnackBarAction button.** The plan allowed either a `SnackBarAction` or default swipe-to-dismiss for the dismiss affordance (SnackBar vs banner was Claude's discretion). There is no existing generic "OK"/"Dismiss" ARB key (`dismissAlarmButton` is semantically "dismiss the alarm", not "dismiss this notice"). Rather than invent and ship an untranslated action label or misuse an alarm-specific string, the notice uses `dismissDirection: DismissDirection.horizontal` (swipe) on a floating SnackBar with a 10s duration (long enough for a screen-reader user to hear it). This keeps the notice dismissible, localized-only, and adds no surplus ARB key.
- **Localizations resolved from `_messangerKey.currentContext`.** In the post-frame callback the messenger's own context is guaranteed to be under the `MaterialApp` localization scope, giving a valid `AppLocalizations`. A defensive null-guard is kept regardless of whether the generated `AppLocalizations.of` signature is nullable.
- **Onboarding gate mirrors `onGenerateRoute`.** Used the same `GetStorage().read('onboarded')` truthiness check the route table uses, so the notice and the route resolution agree on what "the normal route" means.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed a reference to a non-existent `localizations.ok` action label**
- **Found during:** Task 2 (writing the SnackBar)
- **Issue:** An initial draft added a `SnackBarAction(label: localizations.ok, …)`. There is no `ok` (or generic dismiss/close) key in `app_en.arb`, so `AppLocalizations.alarmsResetNotice`'s sibling `ok` getter would not exist — `flutter analyze`/build would fail to resolve the symbol, blocking Task 2.
- **Fix:** Dropped the action button and relied on the plan-sanctioned default swipe-to-dismiss (`DismissDirection.horizontal` on a floating SnackBar), which keeps the notice dismissible without a hardcoded or out-of-scope ARB key.
- **Files modified:** `lib/app.dart`
- **Verification:** Source review + grep (no `localizations.ok` remains); the only `AppLocalizations` getter referenced is `alarmsResetNotice`, which the new ARB key generates.
- **Committed in:** `98d028b` (Task 2 commit — the broken draft was never committed)

---

**Total deviations:** 1 auto-fixed (1 blocking, Rule 3)
**Impact on plan:** Avoids shipping an unresolvable symbol / an untranslated label; the dismiss affordance is the plan's explicitly-allowed alternative. No scope change.

## Issues Encountered

**Flutter/Dart toolchain unavailable — automated verification not run (carried from 01-01/01-02).**
The execution environment has no `flutter` or `dart` binary. The plan's automated verification steps could **not** be executed and are **deferred — toolchain unavailable; requires Flutter 3.22.2 before merge**:
- `flutter gen-l10n` — **NOT RUN.** Consequence: the generated `AppLocalizations.alarmsResetNotice` getter referenced in `lib/app.dart` does **not yet exist on disk** — codegen must run (via `flutter gen-l10n` or a normal `flutter` build with `generate: true`) before `lib/app.dart` will analyze/compile. The ARB key is present and valid, so the getter will be generated on the next build.
- `flutter analyze lib/app.dart` — **NOT RUN.** Expected clean once codegen has produced the `alarmsResetNotice` getter.

What was done instead (toolchain-free verification — all pass):
- `lib/l10n/app_en.arb` parses as valid JSON; both `alarmsResetNotice` and `@alarmsResetNotice` (with a non-empty `description`) are present; `git status lib/l10n/` shows **only** `app_en.arb` modified.
- `lib/app.dart` source assertions: imports `salvage_report.dart`; reads `SalvageReport.alarmsWereLost`; calls `SalvageReport.clear()`; uses `_messangerKey.currentState…showSnackBar`; content is `Semantics`-wrapped; references `alarmsResetNotice` (no hardcoded English literal — grep count 0); uses `addPostFrameCallback` (no state-mgmt lib — grep for provider/riverpod/bloc/getx/mobx = 0); gated on `read('onboarded')`. Braces/parens in the new method are balanced.

**Action required:** a developer with Flutter 3.22.2 must run `flutter gen-l10n` then `flutter analyze lib/app.dart` to confirm GREEN before merge, and complete the Task 3 on-device checkpoint below.

## User Setup Required

None — no external service configuration, no new dependencies, no `pubspec.yaml` change.

## Pending Checkpoint (Task 3 — BLOCKING, on-device)

Task 3 is a blocking `checkpoint:human-verify` and was **returned to the orchestrator, not self-approved.** It requires a real device/emulator and TalkBack, which cannot be automated here. Verification steps (from the plan):
1. Run dev flavor (`flutter run --flavor dev`).
2. **Positive:** corrupt `Clock/alarms.txt` so per-entry salvage drops ≥1 entry (or make the top-level list invalid), relaunch → the localized notice appears exactly once; relaunch again → it does not reappear (flag cleared).
3. **Accessibility:** with TalkBack on, confirm the notice is announced (Semantics reachable).
4. **Negative:** blank a SETTINGS group file (not alarms) or launch with valid alarms → NO notice (silent + logged only).
5. **Dismiss:** confirm the SnackBar can be dismissed (swipe) and does not reappear.

## Next Phase Readiness

- **Closes the user-facing half of D-06 / BOOT-04** (paired with 01-01's `SalvageReport` flag and 01-02's time-boxed boot). Once `flutter gen-l10n` + analyze are green and Task 3 is approved on-device, Phase 1's storage+boot reliability requirements (BOOT-01..04, STOR-01..02) are delivered at source level.
- **Concern / blocker:** codegen + analyze not run (toolchain absent); Task 3 on-device checkpoint pending human sign-off.

## Self-Check: PASSED

- Modified files exist on disk: `lib/l10n/app_en.arb`, `lib/app.dart`, and this SUMMARY.
- Both autonomous task commits exist in git history: `d7f9de2` (Task 1), `98d028b` (Task 2).

---
*Phase: 01-storage-boot-reliability*
*Completed (autonomous tasks): 2026-05-30 — Task 3 blocking checkpoint pending*
