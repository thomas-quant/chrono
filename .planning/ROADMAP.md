# Roadmap: Chrono — Reliability + QR Dismiss Task Milestone

**Created:** 2026-05-30
**Granularity:** coarse
**Core Value:** The alarm must reliably ring and reliably stop — reliability before any new feature.

## Overview

This is brownfield bug-fix + feature work on an existing, mature Flutter alarm app. The
milestone has two thrusts: (1) fix the reliability cluster that is actively losing users
(boot black-screen, broken snooze, specific-date off-by-one, rising-volume-won't-stop), and
(2) add an Alarmy-style QR/barcode scan-to-dismiss alarm task.

Phases follow the project's core value (reliability before feature) and the confirmed
dependency spine from research: storage hardening + a shared idempotent reschedule primitive
underpin both the boot fix and the snooze fix, so storage/boot reliability comes first. The
HIGH-value bug batch (date, volume, FAB) plus the two community PRs land next. The scanner
feature comes last, with its biggest unknown — camera preview over a secure lock screen —
pulled forward as an explicit early de-risk inside that phase, and gated behind the minSdk
21→23 bump and the F-Droid/zero-ML-Kit verification.

## Phases

- [x] **Phase 1: Storage & Boot Reliability** - Kill the boot black-screen / splash-hang epic with non-fatal loads, atomic writes, an idempotent reschedule primitive, and an unlock-guarded boot path (all 3 plans complete; CLOSED 2026-06-02 by user sign-off — on-device reboot check accepted without independent verification; Test 2 converted to committed CI tests pending first green run)
- [ ] **Phase 2: Snooze Reliability** - Make snooze reliably re-ring, honor fractional lengths, enforce max-count across the isolate boundary, and stop one-shot alarms re-firing after snooze→dismiss
- [ ] **Phase 3: Date, Volume & FAB High-Value Fixes** - Fix specific-date off-by-one, make the rising-volume ramp stop cleanly, and free list items from FAB overlap (merging community PRs #467 and #466)
- [ ] **Phase 4: QR/Barcode Scan-to-Dismiss Task** - Ship a registered-code scan-to-dismiss alarm task on an F-Droid-clean scanner, with a default-on escape hatch, after de-risking the lock-screen camera

## Phase Details

### Phase 1: Storage & Boot Reliability

**Goal**: After any reboot, killed write, or partial/corrupted state, Chrono always launches to its normal UI and re-arms alarms exactly once — the boot black-screen / splash-hang epic is gone.
**Depends on**: Nothing (foundation — builds the shared idempotent reschedule primitive Phases 2 and 4 reuse)
**Requirements**: BOOT-01, BOOT-02, BOOT-03, BOOT-04, STOR-01, STOR-02
**Success Criteria** (what must be TRUE):

  1. Rebooting the device (including opening the app before unlock on an FBE device) lands the user on the normal UI — never a permanent black screen or splash hang — with no boot crash from touching credential-encrypted storage before unlock.
  2. After a reboot and unlock, every alarm and timer is rescheduled exactly once — no duplicates, no missed reschedules — even if the boot path and app launch both run.
  3. A settings/list file that is missing, half-written, or contains invalid JSON recovers to a safe default (and is logged), instead of crashing or hanging the app.
  4. A write that is interrupted (e.g. process killed mid-save) never leaves a half-written file — the previous good file survives until the new one is fully written.**Plans**: 3 plans

**Wave 1**

- [x] 01-01-PLAN.md — Harden the text storage path: atomic temp-write+rename, per-entry salvage, null-safe SettingGroup.load, alarm-loss flag (STOR-01/02, BOOT-04)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Defer-until-unlock boot guard, time-boxed splash, idempotent reschedule funnel (BOOT-01/02/03) — code complete & committed; on-device reboot-before-unlock check ACCEPTED (not independently verified) at phase closure 2026-06-02
- [x] 01-03-PLAN.md — One-time localized, screen-reader-reachable "alarms were reset" notice gated on actual alarm loss (BOOT-04, STOR-02) — code complete & committed; on-device repro + TalkBack check converted to committed CI tests (commit 3e8bd01, pending first green run)

### Phase 2: Snooze Reliability

**Goal**: Snooze does exactly what the user expects — it always re-rings after the set delay, respects the max count, and a snoozed one-shot alarm that gets dismissed stays off for good.
**Depends on**: Phase 1 (reuses the idempotent reschedule primitive; relies on snooze state persisting through the hardened storage layer)
**Requirements**: SNZ-01, SNZ-02, SNZ-03, SNZ-04, SNZ-05
**Success Criteria** (what must be TRUE):

  1. Snoozing an alarm reliably re-rings it after the configured snooze length, and snoozing never accidentally dismisses the alarm instead.
  2. A fractional snooze length (e.g. a sub-minute or decimal value) is honored to the second — it is never floored to zero and never re-fires instantly.
  3. A one-shot ("once") alarm that is snoozed and then dismissed becomes inactive and does NOT reappear/re-fire the next day.
  4. The configured maximum snooze count is enforced, and the snooze count persists correctly across the alarm/main isolate boundary (it does not silently reset between rings).

**Plans**: 2 plans

**Wave 1**

- [x] 02-01-PLAN.md — Fix the snooze state machine at source: seconds-based fractional duration + clock.now(), max-count gate (over-max resolves as dismiss), schedule-agnostic _resolveDismiss() wired into the isolate dismiss path (SNZ-01..05)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 02-02-PLAN.md — Author alarm_snooze_test.dart: CI-runnable regression coverage for SNZ-01..05 (fractional, once+dates dismiss deactivation, max gate, snoozeCount JSON round-trip, snooze-survives-update)

### Phase 3: Date, Volume & FAB High-Value Fixes

**Goal**: The remaining high-value defects are gone — specific-date alarms ring on the right calendar day everywhere, rising volume stops cleanly on dismiss/snooze, and floating action buttons no longer hide list items — crediting the community PRs that fix two of them.
**Depends on**: Phase 1 (date load must tolerate old epoch values during migration); largely independent of Phase 2
**Requirements**: DATE-01, DATE-02, VOL-01, FAB-01, PR-01, PR-02
**Success Criteria** (what must be TRUE):

  1. An alarm set for a specific date rings on exactly that calendar date — including after an app restart and regardless of the device's UTC offset — because the date is stored and reloaded as a local calendar date, not an absolute instant.
  2. The rising/gradual volume ramp climbs to the configured maximum and then stops cleanly the instant the alarm is dismissed or snoozed — no stray volume bumps afterward and no bleed into a second alarm.
  3. Floating action buttons no longer cover list items or menu buttons on the alarm and other list screens.
  4. Community PRs #467 (rising volume → VOL-01) and #466 (FAB → FAB-01) are reviewed, merged or adapted, and credited to their contributors.

**Plans**: TBD
**UI hint**: yes

### Phase 4: QR/Barcode Scan-to-Dismiss Task

**Goal**: A user can add a "scan a registered code to dismiss" task to an alarm; at ring time the alarm only turns off when the registered QR/barcode is scanned, with a default-on escape hatch that guarantees the alarm can never become un-dismissable — all on an F-Droid-clean scanner.
**Depends on**: Phase 1 (scan task config rides the hardened JSON storage path); reliability phases 1–3 sequenced first per core value. Internally gated: the minSdk 21→23 bump, the flutter_zxing exact-pin + zero-ML-Kit verification, and the lock-screen camera de-risk must all clear before the scan-task UI is built.
**Requirements**: BUILD-01, BUILD-02, SCAN-01, SCAN-02, SCAN-03, SCAN-04, SCAN-05, SCAN-06, SCAN-07, SCAN-08, SCAN-09, SCAN-10, SCAN-11, SCAN-12
**Success Criteria** (what must be TRUE):

  1. **(De-risk, do first)** A live camera preview is verified to render and scan from the over-the-lock-screen ring activity on a secure (PIN/pattern) lock screen across at least two OEMs — producing a documented go / no-go / "requires unlock first" decision before the scan-task UI is committed.
  2. **(Build gate)** minSdk is raised to 23 and the scanner uses `flutter_zxing` (exact-pinned 2.2.x, not a caret); the F-Droid (`prod`) build compiles with zero `mlkit`/`gms`/`play-services` entries in the Gradle dependency graph (verified, e.g. via `./gradlew app:dependencies`).
  3. A user can add a "Scan code to dismiss" task to an alarm alongside the existing tasks, register a specific QR or 1D barcode (QR / EAN / UPC / Code128 etc.) at setup, run a "test scan" to confirm it scans, and at ring time the alarm dismisses only when the scanned code matches the registered one (matching normalizes both sides identically so whitespace/case can't cause a false reject). The task gates full dismiss only — snooze stays a normal tap.
  4. The alarm can never become un-dismissable: an escape-hatch fallback is ON by default (a plain dismiss after a configurable failed-attempt and/or elapsed-time threshold), it also triggers on camera-permission-denied and camera-unavailable, it is screen-reader reachable, camera permission is requested at setup (never at fire time) with `CAMERA` + `uses-feature required="false"` in the manifest, and the camera is released on every exit path (no stuck privacy indicator).
  5. A torch/flashlight toggle is available in the scanner for dark rooms, and all new user-facing strings are localized (English baseline; other locales via Weblate).

**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Storage & Boot Reliability | 3/3 | Done (closed 2026-06-02 by user sign-off; on-device checks accepted) | 2026-06-02 |
| 2. Snooze Reliability | 1/2 | In Progress|  |
| 3. Date, Volume & FAB High-Value Fixes | 0/0 | Not started | - |
| 4. QR/Barcode Scan-to-Dismiss Task | 0/0 | Not started | - |

## Coverage

All 31 v1 requirements mapped to exactly one phase. No orphans, no duplicates.

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | BOOT-01, BOOT-02, BOOT-03, BOOT-04, STOR-01, STOR-02 | 6 |
| 2 | SNZ-01, SNZ-02, SNZ-03, SNZ-04, SNZ-05 | 5 |
| 3 | DATE-01, DATE-02, VOL-01, FAB-01, PR-01, PR-02 | 6 |
| 4 | BUILD-01, BUILD-02, SCAN-01..SCAN-12 | 14 |
| **Total** | | **31** |

## Research Flags (for `/gsd-plan-phase --research-phase N`)

- **Phase 1 (Boot Guard):** Direct-Boot plumbing through `flutter_boot_receiver` — does it expose unlock state / `LOCKED_BOOT_COMPLETED`, or is a native `directBootAware` + `USER_UNLOCKED` receiver required? Confirm which manifest `directBootAware` lines are Chrono-owned vs plugin-supplied (note the commented `path:` fork override in `pubspec.yaml`). Also: pre-unlock firing in scope? (default assumption: no / defer-until-unlock.)
- **Phase 4 (Lock-Screen Camera + Scan UI):** The lock-screen camera behavior is inherently a hardware spike — no doc-reading substitutes for on-device testing across OEMs. Also verify `flutter_zxing` `ReaderWidget` lifecycle/dispose semantics on the pinned (pre-2.3.0) line and confirm the result-callback shape for normalized matching.

Phases with standard, line-level-confirmed patterns (research-phase optional):

- **Phase 2 (Snooze):** `.floor()` sites and the dismiss-path gap are confirmed in source; the state machine is small and specified.
- **Phase 3 (Date/Volume/FAB):** Mechanisms confirmed (epoch round-trip; `Future.delayed` + static flag); two community PRs (#467, #466) to review against the stated cancellation/correctness criteria.

---
*Roadmap created: 2026-05-30*
*Last updated: 2026-06-02 after planning Phase 2 (Snooze Reliability) — 2 plans, 2 waves*
