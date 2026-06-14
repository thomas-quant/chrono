---
phase: 04-qr-barcode-scan-to-dismiss-task
verified: 2026-06-14T06:00:00Z
status: gaps_found
score: 11/13 must-haves verified (2 on-device gaps block the dismiss flow)
source: on-device UAT (04-06) + CI (tests.yml run 27051911662, test-apk.yml run 27489898566)
---

# Phase 4: QR/Barcode Scan-to-Dismiss — Verification Report

**Phase Goal:** A user can add a "scan a registered code to dismiss" task to an alarm; at ring time the alarm only turns off when the registered QR/barcode is scanned, with a default-on escape hatch that guarantees the alarm can never become un-dismissable — all on an F-Droid-clean scanner.
**Verified:** 2026-06-14 (first on-device hardware run)
**Status:** gaps_found

**How this report was produced:** This phase's source/CI dimensions verified GREEN in CI, and the
human ran the dev APK on a physical device (the 04-06 gate). The two gaps below are runtime/on-device
defects that source-level review could not surface (GAP-A in particular: the code is locally correct —
`ScanTask` uses `Expanded`, valid in isolation — the defect only appears from the host↔widget layout
interaction at runtime, silent in a release build). This is why they were found by hardware UAT, not the
verifier.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | F-Droid-clean scanner; zero ML Kit / Play Services in prod release graph | ✓ VERIFIED | BUILD-02 CI gate PASS (run 27489898566) |
| 2 | Pure matching/escape seams behave (normalize, empty-floor, escape threshold/fireNow) | ✓ VERIFIED | tests.yml 212/212 (code_match, escape_hatch_controller) |
| 3 | `AlarmTask(scan)` JSON round-trips; schema registered; escape-hatch default ON | ✓ VERIFIED | tests.yml alarm_task_scan_test pass |
| 4 | Dev APK builds + installs (native flutter_zxing + camera) | ✓ VERIFIED | test-apk.yml "Build release dev APK" success; installed on device |
| 5 | Register at setup: camera permission AT SETUP, scan + store, status-only display | ✓ VERIFIED (device) | Registration screen renders camera + decodes a barcode on hardware |
| 6 | Code-less scan task cannot be saved (D-REG-REQUIRED, both add + edit paths) | ✓ VERIFIED (source) | CR-01 fix; on-device re-confirm folded into the re-test |
| 7 | **Ring-time: scanning the registered code dismisses the alarm** | ✗ FAILED | GAP-A — the ring-time scanner renders NO camera, so a match can't be performed |
| 8 | "Try out" / test-scan exercises the ring widget | ✗ FAILED | GAP-A — same no-camera failure (it runs `ScanTask`) |
| 9 | Wrong-scan feedback + escape hatch surfaces (never trap) | ? UNCERTAIN | Blocked by GAP-A (scanner never renders to exercise wrong-scan) |
| 10 | Torch toggles / degrades (SCAN-09) | ? UNCERTAIN | Blocked by GAP-A |
| 11 | Camera released on every exit; no stuck indicator (SCAN-11) | ? UNCERTAIN | Blocked by GAP-A |
| 12 | Snooze stays a normal swipe (no scanner) | ✓ VERIFIED (source) | SCAN-05; no snooze path in ScanTask |
| 13 | Alarm screen appears over a secure lock screen | ✗ FAILED | GAP-B — alarm did not surface over the keyguard; user had to unlock + tap the notification |

**Score:** 8 verified, 2 failed (GAP-A, GAP-B), 3 uncertain (blocked by GAP-A).

## Gaps Summary

### Critical Gaps (Block Progress)

1. **GAP-A — `ScanTask` renders no camera at ring-time and in "try out"** 🛑 Blocker
   - Missing: a visible camera preview in the ring-time dismiss step (and the "try task" preview). Without
     it, the registered code can never be scanned → the alarm cannot be dismissed by the intended path.
   - Root cause (CONFIRMED, static analysis): `ScanTask` (`lib/alarm/widgets/tasks/scan_task.dart`)
     sizes its scanner with an internal `Expanded`. Both hosts place the task widget as a NON-flex child
     of a `Column`, giving it unbounded height: `try_alarm_task_screen.dart:14-20`
     (`body: Column(children:[builder()])`) and `alarm_notification_screen.dart:150-157`
     (`Expanded > Column > [_currentWidget]`). An `Expanded` under unbounded height collapses the
     `ReaderWidget` to zero height → no camera. Silent in a release APK (no red layout-error overlay).
     Registration is unaffected (ReaderWidget is the `Scaffold` body → bounded); the math task is
     unaffected (intrinsic height, no `Expanded`).
   - Fix: make `ScanTask` self-sizing instead of relying on a bounded-Flex host — replace
     `Expanded(child: scanner)` with a definite-height box, e.g.
     `SizedBox(height: MediaQuery.of(context).size.height * 0.6, child: scanner)` (apply to the
     unlock-to-scan branch too). ScanTask-ONLY change — do NOT modify the shared hosts (would risk the
     math task and other task widgets). Re-verify on device: try-out + ring-time render the camera, a
     matching scan dismisses, then exercise the GAP-A-blocked truths #9/#10/#11.

### Non-Critical Gaps (investigate; feature still ships per D-LOCK-SHIP)

2. **GAP-B — alarm does not appear over the secure lock screen** ⚠️ Warning
   - Issue: on the test device the fired alarm did not surface over the keyguard; the user had to unlock
     and tap the notification. Separate subsystem from GAP-A: the full-screen-intent / `showWhenLocked`
     path (`FlutterShowWhenLocked().show()` + the awesome_notifications full-screen intent).
   - Likely cause: Android 14+ restricts `USE_FULL_SCREEN_INTENT` (often must be granted per-app), and/or
     OEM keyguard policy blocks activity/camera over a secure lock screen — this is exactly the question
     the deferred 04-03 spike was meant to measure.
   - Impact: limited — by design (D-LOCK-SHIP) the feature still ships; the escape hatch + "unlock to
     scan" degradation cover no-go devices. But reliability matters (an alarm that doesn't show over the
     lock screen is a weaker alarm).
   - Recommendation: investigate whether it's a grantable-permission/manifest fix (request
     `USE_FULL_SCREEN_INTENT`, surface a one-time grant prompt) vs. expected OEM behavior. May fold into,
     or replace, the 04-03 spike. Confirm GAP-A first (it gates re-testing the whole dismiss flow).

## Human Verification Required

Re-run the 04-06 on-device matrix (`.planning/MANUAL-VERIFICATION-LOG.md` §B/§C) AFTER the GAP-A fix +
a fresh dev APK — truths #9/#10/#11 are currently blocked because the scanner never renders.

## Recommended Fix Plans

### 04-07-PLAN.md: Fix ScanTask camera rendering (GAP-A)
**Objective:** Make the ring-time + "try out" scanner render the camera by giving `ScanTask` a definite
height independent of its host.
**Tasks:**
1. In `scan_task.dart`, replace the scanner `Expanded` with a `MediaQuery`-derived `SizedBox` (apply to
   both the scanner and the unlock-to-scan branch); keep the instruction text + escape Dismiss intact.
2. Add a CI-runnable headless widget test that mounts `ScanTask` as a non-flex child of a `Column`
   (unbounded height — the exact host condition) and asserts it lays out without an overflow/zero-size
   (regression guard for the host↔widget contract).
3. Re-verify on device (fresh APK): try-out + ring-time render the camera; a registered-code scan
   dismisses; then exercise truths #9/#10/#11 (wrong-scan+escape, torch, camera-release).
**Estimated scope:** Small.

### 04-08-PLAN.md: Lock-screen full-screen-intent investigation (GAP-B)
**Objective:** Determine and fix why the alarm doesn't surface over a secure keyguard.
**Tasks:**
1. Audit the full-screen-intent path: `USE_FULL_SCREEN_INTENT` in the manifest, the awesome_notifications
   full-screen config, and `FlutterShowWhenLocked().show()`; check Android 14+ permission state.
2. If grantable: request/surface the `USE_FULL_SCREEN_INTENT` permission (one-time prompt) and/or fix the
   notification config; if OEM-blocked: document as expected no-go behavior (the escape hatch covers it).
3. Re-verify on device over a PIN/pattern keyguard.
**Estimated scope:** Small–Medium (investigation-led). May subsume the deferred 04-03 spike.

## Verification Metadata

**Verification approach:** CI (source/build) + on-device UAT (04-06 human gate).
**Automated checks:** tests.yml 212/212; test-apk.yml BUILD-02 + dev-APK build PASS.
**On-device:** registration PASS; ring-time/try-out scan FAILED (GAP-A); lock-screen FAILED (GAP-B).
**Note:** Deferred plans 04-03 (lock-screen spike) and 04-06 (full e2e) remain open; GAP-B may replace 04-03.

---
*Verified: 2026-06-14 — on-device UAT + CI. Gaps routed to /gsd-plan-phase 4 --gaps.*
