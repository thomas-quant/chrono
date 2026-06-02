# Requirements: Chrono — Reliability + QR Dismiss Task Milestone

**Defined:** 2026-05-30
**Core Value:** The alarm must reliably ring and reliably stop — reliability before any new feature.

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Reliability — Boot & Storage (CRITICAL)

- [ ] **BOOT-01**: App launches to its normal UI (never a permanent black/splash hang) even after a reboot, a killed boot write, or partial/corrupted stored state
- [ ] **BOOT-02**: Boot-time code does not access credential-encrypted storage before the user has unlocked the device (no `IllegalStateException` crash on `LOCKED_BOOT_COMPLETED`)
- [ ] **BOOT-03**: Alarms/timers are correctly rescheduled after reboot once the device is unlocked, idempotently (no duplicates, no missed reschedules)
- [x] **BOOT-04**: A corrupted or unreadable settings/list file recovers to a safe default and is logged, instead of crashing or hanging the app
- [x] **STOR-01**: List/settings writes are atomic (temp-write + rename) so an interrupted write cannot leave a half-written file
- [x] **STOR-02**: Storage reads guard against null/invalid JSON before decoding (no unguarded `json.decode`)

### Reliability — Snooze (CRITICAL)

- [x] **SNZ-01**: Snoozing an alarm reliably re-rings it after the configured snooze length (snooze never silently fails to re-fire)
- [x] **SNZ-02**: Fractional snooze lengths are honored (no flooring a sub-minute/decimal value to zero)
- [x] **SNZ-03**: A one-shot alarm that is snoozed and then dismissed becomes inactive and does NOT reschedule for the next day (#457)
- [x] **SNZ-04**: The configured maximum snooze count is enforced and the snooze count persists correctly across the alarm/main isolate boundary
- [x] **SNZ-05**: Snoozing re-rings the alarm without unintentionally dismissing it (#495)

### Reliability — Date & Volume (HIGH)

- [ ] **DATE-01**: An alarm set for a specific date rings on exactly that calendar date, including after an app restart, regardless of the device's UTC offset (fixes the off-by-one rollback: #340/#455/#472)
- [ ] **DATE-02**: A "specific date" is stored and reloaded as a local calendar date (not an absolute instant), so DST/timezone offsets cannot shift it by a day
- [ ] **VOL-01**: The rising/gradual volume ramp increases volume up to the configured maximum and stops cleanly when the alarm is dismissed/snoozed (no stray volume bumps after stop; no cross-alarm bleed) (#407/#506)
- [ ] **FAB-01**: Floating action buttons no longer cover list items / menu buttons in the alarm and other list screens (#417)

### Feature — QR/Barcode Scan-to-Dismiss Task

- [ ] **SCAN-01**: User can add a "Scan code to dismiss" task to an alarm, selectable alongside the existing dismiss tasks (math/retype/sequence/memory)
- [ ] **SCAN-02**: During setup, the user scans and registers a specific QR or 1D barcode; the registered code value is stored in the task's settings
- [ ] **SCAN-03**: At ring time, a live camera scanner opens and the alarm only dismisses when the scanned code matches the registered code (matching normalizes both sides identically — trim/control-char/case — so a trailing newline can't cause a false reject)
- [ ] **SCAN-04**: The scanner accepts QR codes and common 1D barcodes (EAN/UPC/Code128, etc.)
- [ ] **SCAN-05**: The scan task gates full dismiss only; snooze remains a normal tap
- [ ] **SCAN-06**: An escape-hatch fallback is ON by default — after a configurable threshold (failed attempts and/or elapsed time) a plain dismiss becomes available — and the user can tighten or disable it
- [ ] **SCAN-07**: The escape hatch also triggers on camera-permission-denied and camera-unavailable, so a scan alarm can never become permanently un-dismissable; the fallback is screen-reader reachable
- [ ] **SCAN-08**: Camera permission is requested at setup (never at fire time); `CAMERA` is declared in the manifest with `uses-feature` camera `required="false"`
- [ ] **SCAN-09**: A torch/flashlight toggle is available in the scanner for dark rooms
- [ ] **SCAN-10**: A "test scan" is available during setup so the user can confirm the registered code scans before relying on it
- [ ] **SCAN-11**: The camera is released on every exit path (success, escape hatch, screen background) — no stuck camera/privacy indicator
- [ ] **SCAN-12**: New user-facing strings are localized (English baseline; other locales via Weblate)

### Platform / Build

- [ ] **BUILD-01**: minSdk is raised from 21 to 23 (Android 6.0+) to support the F-Droid-clean scanner
- [ ] **BUILD-02**: The scanner uses `flutter_zxing` (exact-pinned 2.2.x, not a caret range); the F-Droid (`prod`) build compiles with zero `mlkit`/`gms`/`play-services` in the Gradle dependency graph

### Community PRs (review & merge)

- [ ] **PR-01**: Review and merge (or adapt) PR #467 to satisfy VOL-01, crediting the contributor
- [ ] **PR-02**: Review and merge (or adapt) PR #466 to satisfy FAB-01, crediting the contributor

## v2 Requirements

Deferred to a future milestone. Tracked but not in current roadmap.

### Scheduling correctness

- **DST-01**: Recurring alarms recompute correctly across DST / timezone changes (#359)

### Scan task enhancements

- **SCAN-V2-01**: Registered-item label hint shown at ring time ("You registered: Toothpaste")
- **SCAN-V2-02**: Configurable escape-hatch thresholds exposed as explicit time/attempt knobs (beyond the v1 single sane default)
- **SCAN-V2-03**: Downloadable/printable default QR code offered (never required)
- **SCAN-V2-04**: Scan-to-dismiss extended to timers

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Android 5.0 / 5.1 (API 21–22) support | F-Droid-clean scanner needs minSdk 23; 5.1 is a negligible base |
| Decompiling Alarmy's APK | Clean-room only; avoid copyright/license contamination |
| Gating snooze behind the scan task | Dismiss-only for v1 |
| Pre-first-unlock alarm firing (device-protected storage) | Out unless validated as required in the boot phase; default is defer-until-unlock |
| ML Kit / Play-Services scanners (mobile_scanner etc.) | Break F-Droid distribution |
| New community tasks #450 (Squat/Light), record-ringtone #451 | Need separate review → backlog |
| Snooze-feature PRs #515 (Custom Snooze), #475 (fat snooze button) | Don't layer features on a broken snooze core; revisit after SNZ-* fixes |
| Long-tail feature requests (multiple snooze durations, widgets, NFC task, Spotify, etc.) | Backlog |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BOOT-01 | Phase 1 | Pending |
| BOOT-02 | Phase 1 | Pending |
| BOOT-03 | Phase 1 | Pending |
| BOOT-04 | Phase 1 | Complete |
| STOR-01 | Phase 1 | Complete |
| STOR-02 | Phase 1 | Complete |
| SNZ-01 | Phase 2 | Complete |
| SNZ-02 | Phase 2 | Complete |
| SNZ-03 | Phase 2 | Complete |
| SNZ-04 | Phase 2 | Complete |
| SNZ-05 | Phase 2 | Complete |
| DATE-01 | Phase 3 | Pending |
| DATE-02 | Phase 3 | Pending |
| VOL-01 | Phase 3 | Pending |
| FAB-01 | Phase 3 | Pending |
| PR-01 | Phase 3 | Pending |
| PR-02 | Phase 3 | Pending |
| BUILD-01 | Phase 4 | Pending |
| BUILD-02 | Phase 4 | Pending |
| SCAN-01 | Phase 4 | Pending |
| SCAN-02 | Phase 4 | Pending |
| SCAN-03 | Phase 4 | Pending |
| SCAN-04 | Phase 4 | Pending |
| SCAN-05 | Phase 4 | Pending |
| SCAN-06 | Phase 4 | Pending |
| SCAN-07 | Phase 4 | Pending |
| SCAN-08 | Phase 4 | Pending |
| SCAN-09 | Phase 4 | Pending |
| SCAN-10 | Phase 4 | Pending |
| SCAN-11 | Phase 4 | Pending |
| SCAN-12 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 31 total (BOOT 4, STOR 2, SNZ 5, DATE 2, VOL 1, FAB 1, SCAN 12, BUILD 2, PR 2)
- Mapped to phases: 31 ✓ (Phase 1: 6, Phase 2: 5, Phase 3: 6, Phase 4: 14)
- Unmapped: 0 ✓ (every v1 requirement maps to exactly one phase; no orphans, no duplicates)

---
*Requirements defined: 2026-05-30*
*Last updated: 2026-05-30 after roadmap traceability mapping*
