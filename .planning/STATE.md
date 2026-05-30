---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-30T15:37:58.058Z"
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 3
  completed_plans: 0
  percent: 0
---

# Project State: Chrono — Reliability + QR Dismiss Task Milestone

## Project Reference

- **Core value:** The alarm must reliably ring and reliably stop — reliability before any new feature.
- **Current focus:** Phase 1 — Storage & Boot Reliability (foundation; builds the shared idempotent reschedule primitive).
- **Type:** Brownfield (bug-fix + feature work on an existing, mature Flutter/Android alarm app).
- **Key docs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/research/`, `.planning/codebase/`.

## Current Position

- **Phase:** 1 of 4 — Storage & Boot Reliability
- **Plan:** None yet (phase not planned)
- **Status:** Ready to execute
- **Progress:** `[----------------]` 0/4 phases complete (0%)

## Phase Map

| Phase | Name | Requirements | Status |
|-------|------|--------------|--------|
| 1 | Storage & Boot Reliability | BOOT-01..04, STOR-01..02 (6) | Not started |
| 2 | Snooze Reliability | SNZ-01..05 (5) | Not started |
| 3 | Date, Volume & FAB High-Value Fixes | DATE-01..02, VOL-01, FAB-01, PR-01..02 (6) | Not started |
| 4 | QR/Barcode Scan-to-Dismiss Task | BUILD-01..02, SCAN-01..12 (14) | Not started |

## Performance Metrics

- **Phases complete:** 0/4
- **Requirements delivered:** 0/31
- **Plans executed:** 0
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

- None currently.

## Session Continuity

- **Last action:** Roadmap and STATE.md created from PROJECT.md, REQUIREMENTS.md, and research (SUMMARY/ARCHITECTURE/PITFALLS). 31/31 v1 requirements mapped across 4 phases; REQUIREMENTS.md traceability updated.
- **Next action:** `/gsd-plan-phase 1` to decompose Phase 1 (Storage & Boot Reliability) into executable plans.
- **Watch:** Phase 1 may need `--research-phase 1` for the Direct-Boot / `flutter_boot_receiver` plumbing question.

---
*State initialized: 2026-05-30*
*Last updated: 2026-05-30 after roadmap creation*
