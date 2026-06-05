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
- [ ] Torch/flashlight toggle + setup "test scan" (table stakes per research)
- [ ] New strings localized (at least English; others via Weblate)

**Bugs — Reliability (CRITICAL):**
- [ ] Fix startup-crash / black-screen epic (#442, #420, #448, #489, #498, #516, #514, #483, #289): boot isolate accesses encrypted SharedPreferences before device unlock → boot crash + half-written state → next launch hangs on splash. Guard storage until user-unlocked; make corrupted/partial state load non-fatal (recover, don't hang)
- [ ] Fix snooze cluster (#439, #495, #445, #457): snooze never re-fires or just dismisses; one-shot alarm reschedules wrongly after snooze→dismiss (#457); handle fractional `snoozeLength`

**Bugs — High-value (HIGH):** — *Validated in Phase 3 (Date, Volume & FAB High-Value Fixes), 2026-06-05; on-device + CI gates tracked in `03-HUMAN-UAT.md`.*
- [x] Fix specific-date off-by-one (#340, #455, #472): root cause fixed at serialization — `DateTimeSetting` persists date-only `YYYY-MM-DD`, picker normalized to local `DateTime(y,m,d)`, legacy epochs self-heal via UTC read (DATE-01, DATE-02)
- [x] Fix rising volume (#407, #506): reimplemented independently as a pure cancellable `VolumeRampController` (sole credit per D-PR-METHOD, not a PR #467 merge); `setVolume` decoupled from ramp-stop; cancels cleanly on stop/pause/snooze (VOL-01, PR-01)
- [x] Fix FAB covering list items (#417, #463): one central derived bottom-inset in `CustomListView` clears the FAB across all ~13 list screens; reimplemented independently (sole credit, not a PR #466 merge) (FAB-01, PR-02)

### Out of Scope

- **Android 5.0 / 5.1 (API 21–22) support** — dropped this milestone. The F-Droid-clean scanner (flutter_zxing 2.2.x) requires minSdk 23. Product decision: bump minSdk 21 → 23 (Android 6.0+); 5.1 is a negligible install base.
- DST/timezone recompute for recurring alarms (#359) — HIGH but genuinely tricky (timezone-aware recompute); deserves its own scoped milestone → backlog
- Decompiling Alarmy's APK — clean-room implementation against Chrono's own task interface instead; avoids license/copyright risk
- QR/scan task for timers — timers use a separate dismiss path; alarms-only this milestone
- Gating snooze (in addition to dismiss) behind the scan task — dismiss-only for v1
- Pre-first-unlock alarm firing (device-protected storage) — assumed out unless validated as needed in the boot phase; default is defer-until-unlock
- New community-contributed tasks (#450 Squat/Light), record-ringtone (#451) — need separate review → backlog
- Snooze-feature PRs (#515 Custom Snooze, #475 fat snooze button) — must not layer features on a broken snooze core; revisit after snooze cluster is fixed → backlog
- The long tail of feature requests (multiple snooze durations, widgets, NFC task, Spotify, etc.) → backlog

## Context

- **Existing task framework** (key enabler): `lib/alarm/types/alarm_task.dart` (`AlarmTask`, `AlarmTaskType` enum, `AlarmTaskSchema`), registry in `lib/alarm/data/alarm_task_schemas.dart` (`alarmTaskSchemasMap`), task widgets in `lib/alarm/widgets/tasks/`, config UI via `CustomizableListSetting<AlarmTask>` in `lib/alarm/data/alarm_settings_schema.dart`. The ringing screen `lib/alarm/screens/alarm_notification_screen.dart` iterates tasks and calls `onSolve` → dismiss automatically; new task types are picked up without touching orchestration. Task config rides the existing `SettingGroup` JSON serialization (a `StringSetting` already exists for the registered code — no `json_serialize.dart` factory entry needed).
- **Scanner decision (research-backed):** `flutter_zxing` is the only F-Droid-clean Flutter scanner (native ZXing via FFI, zero Google ML Kit / Play Services). All ML-Kit options (`mobile_scanner`, etc.) break F-Droid. With minSdk now 23, pin **`flutter_zxing` 2.2.x exactly** (NOT `^` — 2.3.0 needs Flutter ≥3.41, incompatible with Chrono's 3.22.2). `ReaderWidget` provides camera + torch + scan frame; native build needs CMake/NDK. Camera permission reuses existing `permission_handler ^11.3.1`. A user already requested scan-to-dismiss (#206).
- **Reliability root causes** confirmed at line level (see research + `.planning/codebase/CONCERNS.md`): boot path `handle_boot.dart:20` calls `initializeIsolate()` outside try/catch and reads credential-encrypted `get_storage` pre-unlock; unguarded `json.decode` at `setting_group.dart:265`; non-atomic `saveTextFile` (`list_storage.dart:82-90`); snooze `.floor()` at `alarm.dart:226,234`; `handleDismiss()` (`alarm.dart:309-315`) leaves a one-shot enabled (#457); `DateTimeSetting` epoch round-trip (`setting.dart:957-966`); rising-volume uncancellable `Future.delayed` ramp in `ringtone_player.dart`. No new deps needed for any reliability fix.
- **Community PRs** worth merging this milestone: #467 (rising volume), #466 (FAB), possibly #513 (one-shot timers, self-contained). Credits contributors and avoids duplicate work.
- Codebase already mapped: see `.planning/codebase/` (ARCHITECTURE, STACK, STRUCTURE, CONVENTIONS, INTEGRATIONS, TESTING, CONCERNS). Domain research in `.planning/research/` (STACK, FEATURES, ARCHITECTURE, PITFALLS, SUMMARY).

## Constraints

- **Tech stack**: Flutter 3.22.x / Dart 3.4+, Android-only; Kotlin 1.8, Java 17. **minSdk 23** (raised from 21 this milestone), compileSdk 34. New deps must support this toolchain.
- **Architecture**: No state-management library; `setState` + `ListenerManager` + isolate `IsolateNameServer` ports. Settings are string-keyed `SettingGroup`s serialized to JSON. New task config must follow this pattern.
- **Background execution**: Alarm firing runs in a separate Dart isolate; the scan task UI runs in the alarm notification screen (main isolate) — camera lifecycle must be handled there, not in the firing isolate.
- **Licensing**: Open-source project — clean-room only; no decompiled or copied Alarmy code/assets.
- **Accessibility / ethics**: Dismiss challenges must not trap users — escape hatch on by default; keep tasks optional; escape hatch must be screen-reader-reachable (it is also the accessibility path).
- **Distribution**: Google Play (AAB) + GitHub Releases (APK) + F-Droid. F-Droid forbids proprietary blobs — the scanner library MUST be FOSS-clean (verified exit criterion: zero `mlkit`/`gms`/`play-services` in the Gradle graph).

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
| `flutter_zxing` as the scanner (not ML Kit) | Only F-Droid-clean option; ML Kit breaks F-Droid distribution | — Pending |
| **Bump minSdk 21 → 23; pin flutter_zxing 2.2.x** | 2.2.x is F-Droid-clean but needs API 23; Android 5.0/5.1 is a negligible base. Overrides STACK.md's keep-21 lean | — Pending |
| Reliability bugs share this milestone with the feature | An unreliable alarm app fails its core value; fix it alongside | — Pending |
| Defer DST (#359) to its own milestone | Timezone-aware recompute is tricky and deserves focus | — Pending |
| Merge good community PRs (#467/#466) rather than reimplement | Credits contributors, less duplicate work | — Pending |
| Pull lock-screen camera spike forward | Camera-over-keyguard is the biggest unknown; a black preview reshapes the feature | — Pending |

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
*Last updated: 2026-06-05 — Phase 3 (Date, Volume & FAB High-Value Fixes) complete: DATE-01/02, VOL-01, FAB-01, PR-01/02 fixed at source (date-only serialization, cancellable VolumeRampController, central FAB clearance); volume + FAB PRs reimplemented independently with sole credit (D-PR-METHOD). A post-execution code review found 5 warnings, all fixed. CI tests authored + structurally verified (toolchain absent locally — CI is the gate); on-device + CI checks tracked in 03-HUMAN-UAT.md. 3/4 phases done — only Phase 4 (QR/Barcode Scan-to-Dismiss) remains.*
