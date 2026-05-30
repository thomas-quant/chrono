# Chrono — Reliability + QR Dismiss Task Milestone

## What This Is

Chrono is a feature-rich, open-source (vicolo-dev) alarm, timer, stopwatch, and world-clock app for Android, built in Flutter with Material You theming and 20+ translations. This milestone has two thrusts: (1) add a **QR/barcode scan-to-dismiss** alarm task — scan a pre-registered code to turn the alarm off, inspired by Alarmy — and (2) fix the **reliability bugs** that are currently causing missed alarms and lost users.

## Core Value

The alarm must reliably ring and reliably stop. An alarm app that crashes on boot, fails to ring, or won't snooze/dismiss correctly has failed at its one job — that comes before any new feature.

## Requirements

### Validated

<!-- Existing shipped capabilities, inferred from the codebase map. -->

- ✓ Alarms with flexible schedules (once/daily/weekly/specific-dates/range) — existing
- ✓ Pluggable alarm-dismissal **task** system (math, retype, sequence, memory; `shake` stubbed) — existing
- ✓ Timers, stopwatch with laps, world clock with favorite cities — existing
- ✓ Snooze with configurable length and max-count — existing (currently buggy)
- ✓ Rising/gradual alarm volume — existing (currently buggy)
- ✓ Background alarm firing via Android AlarmManager + Dart isolates — existing
- ✓ Reschedule alarms after device reboot (boot receiver) — existing
- ✓ Home-screen widgets, Material You dynamic color, 20+ locales — existing
- ✓ Per-alarm settings persisted as JSON (SettingGroup) — existing

### Active

<!-- This milestone's scope. -->

**Feature — QR/barcode dismiss task:**
- [ ] User can add a "Scan code to dismiss" task to an alarm (new `AlarmTaskType`)
- [ ] During setup, user scans and registers a specific QR/barcode; the alarm only dismisses when that exact code is scanned again
- [ ] Scanner accepts QR codes and common 1D barcodes (EAN/UPC/Code128 etc.) so any physical product code can be registered
- [ ] Task gates full dismiss only (snooze remains a normal tap)
- [ ] Escape-hatch fallback is ON by default and configurable: after a threshold (failed attempts / elapsed time) a plain dismiss is allowed; user can tighten or disable
- [ ] Scoped to alarms only (not timers) for this milestone
- [ ] Camera permission requested/handled; `CAMERA` added to manifest
- [ ] New strings localized (at least English; others via Weblate)

**Bugs — Reliability (CRITICAL):**
- [ ] Fix startup-crash / black-screen epic (#442, #420, #448, #489, #498, #516, #514, #483, #289): boot isolate accesses encrypted SharedPreferences before device unlock → boot crash + half-written state → next launch hangs on splash. Guard storage until user-unlocked; make corrupted/partial state load non-fatal (recover, don't hang)
- [ ] Fix snooze cluster (#439, #495, #445, #457): snooze never re-fires or just dismisses; one-shot alarm reschedules wrongly after snooze→dismiss (#457); handle fractional `snoozeLength`

**Bugs — High-value (HIGH):**
- [ ] Fix specific-date off-by-one (#340, #455, #472): `table_calendar` emits UTC-midnight, saved as epoch and reloaded as local → date rolls back a day for negative-UTC users. Normalize picker output / serialization to local date
- [ ] Fix rising volume (#407, #506) — review and merge PR #467 (or equivalent fix); verify cancellation on stop
- [ ] Fix FAB covering list items (#417) — review and merge PR #466

### Out of Scope

- DST/timezone recompute for recurring alarms (#359) — HIGH but genuinely tricky (timezone-aware recompute); deserves its own scoped milestone → backlog
- Decompiling Alarmy's APK — clean-room implementation against Chrono's own task interface instead; avoids license/copyright risk
- QR/scan task for timers — timers use a separate dismiss path; alarms-only this milestone
- Gating snooze (in addition to dismiss) behind the scan task — dismiss-only for v1
- New community-contributed tasks (#450 Squat/Light), record-ringtone (#451) — need separate review → backlog
- Snooze-feature PRs (#515 Custom Snooze, #475 fat snooze button) — must not layer features on a broken snooze core; revisit after snooze cluster is fixed → backlog
- The long tail of feature requests (multiple snooze durations, widgets, NFC task, Spotify, etc.) → backlog

## Context

- **Existing task framework** (key enabler): `lib/alarm/types/alarm_task.dart` (`AlarmTask`, `AlarmTaskType` enum, `AlarmTaskSchema`), registry in `lib/alarm/data/alarm_task_schemas.dart` (`alarmTaskSchemasMap`), task widgets in `lib/alarm/widgets/tasks/`, config UI via `CustomizableListSetting<AlarmTask>` in `lib/alarm/data/alarm_settings_schema.dart`. The ringing screen `lib/alarm/screens/alarm_notification_screen.dart` iterates tasks and calls `onSolve` → dismiss automatically; new task types are picked up without touching orchestration.
- **Adding a task type** requires: new enum value, schema-map entry, a `*_task.dart` widget calling `onSolve()`, a scanner dependency (`mobile_scanner` is the modern candidate), `CAMERA` permission, and l10n strings. A user already requested scan-to-dismiss (#206).
- **Reliability root causes** independently corroborated in `.planning/codebase/CONCERNS.md`: rising-volume cancellation flaw, silent storage fallbacks (GetStorage), dual-storage drift, no null-guard before `json.decode`. Suspected files: `lib/system/logic/handle_boot.dart`, `lib/alarm/logic/alarm_isolate.dart`, `lib/alarm/types/alarm.dart` (snooze ~lines 218–247), `lib/settings/types/setting.dart` (DateTimeSetting ~957–967), `lib/common/widgets/fields/date_picker_bottom_sheet.dart:145`, `lib/audio/types/ringtone_player.dart`.
- **Community PRs** worth merging this milestone: #467 (rising volume), #466 (FAB), possibly #513 (one-shot timers, self-contained). Credits contributors and avoids duplicate work.
- Codebase already mapped: see `.planning/codebase/` (ARCHITECTURE, STACK, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS).

## Constraints

- **Tech stack**: Flutter 3.22.x / Dart 3.4+, Android-only (minSdk 21, compileSdk 34); Kotlin 1.8, Java 17. New deps must support this toolchain.
- **Architecture**: No state-management library; `setState` + `ListenerManager` + isolate `IsolateNameServer` ports. Settings are string-keyed `SettingGroup`s serialized to JSON. New task config must follow this pattern.
- **Background execution**: Alarm firing runs in a separate Dart isolate; the scan task UI runs in the alarm notification screen (main isolate) — camera lifecycle must be handled there, not in the firing isolate.
- **Licensing**: Open-source project — clean-room only; no decompiled or copied Alarmy code/assets.
- **Accessibility / ethics**: Dismiss challenges must not trap users — escape hatch on by default; keep tasks optional.
- **Distribution**: Google Play (AAB) + GitHub Releases (APK) + F-Droid. F-Droid forbids proprietary blobs — the scanner library must be FOSS-compatible (rules out anything pulling Google ML Kit's proprietary models if F-Droid builds must keep working; verify during research).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| QR/barcode as a new `AlarmTask` type, not a new subsystem | App already has a pluggable task framework; reuse it | — Pending |
| Clean-room implementation, do not decompile Alarmy | Avoid copyright/license contamination in an OSS project | — Pending |
| Match a pre-registered code (not "any code") | A saved screenshot defeats "any code"; registered code forces the user out of bed | — Pending |
| Gate dismiss only, not snooze | Matches Chrono's separate snooze/dismiss actions; gentler default | — Pending |
| Escape hatch ON by default, configurable | Non-predatory, accessible; an OSS app shouldn't trap users | — Pending |
| Accept QR + common 1D barcodes | Lets users register any physical product code, not just printed QR | — Pending |
| Alarms only (not timers) this milestone | Task framework is alarm-specific; keeps v1 tight | — Pending |
| Reliability bugs share this milestone with the feature | An unreliable alarm app fails its core value; fix it alongside | — Pending |
| Defer DST (#359) to its own milestone | Timezone-aware recompute is tricky and deserves focus | — Pending |
| Merge good community PRs (#467/#466) rather than reimplement | Credits contributors, less duplicate work | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-30 after initialization*
