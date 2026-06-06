# Manual Verification Log — "things I said I'd double-check"

A running, cross-phase list of checks the user accepted on faith at completion time
(on-device behavior, CI runs, and design-decision sign-offs that automated checks
can't cover locally). When you test something, fill in **Observed** and flip the box.
If you hit an error, compare it against the **Expected** line here first — a mismatch
points straight at the suspect change.

- Per-phase structured versions live in each phase's `*-HUMAN-UAT.md`; `/gsd-audit-uat`
  aggregates them. This file is the curated human-readable running list.
- Status keys: `[ ]` pending · `[x]` verified OK · `[!]` mismatch/error (note it)

_Last updated: 2026-06-06 (after Phase 4 authorable execution — on-device gates deferred)_

---

## Phase 4 — QR/Barcode Scan-to-Dismiss Task (authorable-complete + CI-green 2026-06-06; NOT closed)

Authorable plans 04-01, 04-02, 04-04, 04-05 landed on `master` and were pushed to the user's fork
(thomas-quant/chrono); **CI is now green** (see §A — 212 tests, BUILD-02 F-Droid gate, dev APK builds).
04-03 (lock-screen spike) and 04-06 (end-to-end e2e) remain inherently on-device and **deferred** — no
device in the execution environment. Code-review BLOCKERs CR-01 (add-path save-gate bypass) and CR-02
(ScanTask re-entrancy) were found and fixed; WR-04 (CI analyze scope) fixed; WR-01/02/03/05 + INFO left
open. CI surfaced and fixed three more issues during the push: a Phase-3 DATE-02 wall-clock-fragile test,
the BUILD-02 gate exit-127 (missing `gradlew`), and the dev-APK `camera_android_camerax` SurfaceProducer
build failure (debug session, resolved).
Source: `04-01..05-SUMMARY.md`, `04-REVIEW.md`, `04-03-PLAN.md`, `04-06-PLAN.md`,
`.planning/debug/resolved/camerax-apk-build-fail.md`.

### A. CI gates — VERIFIED GREEN 2026-06-06 (pushed to thomas-quant/chrono master; user-authorized)
- [x] **`tests.yml` green** on the new pure-seam + round-trip tests
  (`code_match_test`, `escape_hatch_controller_test`, `alarm_task_scan_test` — SCAN-03/06/07 + SCAN-01).
  Observed: run 27051911662 — success, **🎉 212 tests passed** (also fixed a pre-existing Phase-3
  DATE-02 wall-clock-fragile test along the way; commit 6780bf5).
- [x] **`flutter gen-l10n` succeeds** — new `scan*` ARB getters generate.
  Observed: ran clean as a step in both CI jobs (run 27051911373).
- [x] **`flutter analyze` (test-apk.yml, repointed to the Phase-4 scan files)** — informational/continue-on-error.
  Observed: step success in run 27051911373. (WR-01 torch dead-code still open — see §D.)
- [x] **Dev-APK build compiles** (`flutter_zxing` FFI/NDK + the camera federation).
  Observed: run 27051911373 "Build release dev APK" = success; artifact `chrono-dev-release-apk`
  (59.7 MB) uploaded (expires 2026-06-13) — **this is the APK to install for §B/§C on-device testing.**
  NOTE: required a fix — `camera_android_camerax` (pulled transitively by flutter_zxing) floated to
  0.6.8+2 which uses the engine `SurfaceProducer` API absent in Flutter 3.22.2 → javac failure.
  Capped via `dependency_overrides: camera_android_camerax: '>=0.6.5 <0.6.6'` (commit 21a7f11;
  debug session `.planning/debug/resolved/camerax-apk-build-fail.md`).
- [x] **BUILD-02 zero-ML-Kit prod-graph gate PASSES** (greps `prodReleaseRuntimeClasspath` for
  `mlkit|play-services|gms`, found none — F-Droid-clean confirmed; the camerax cap stays pure androidx).
  Observed: run 27051911373 BUILD-02 job = success. Also fixed: the gate was exit-127 (no `gradlew`);
  now uses `--config-only` + the wrapper jar (commit a509ccc/5964e4b). NOTE WR-05: this job still
  triggers only on `workflow_dispatch`, not push/PR — dispatch it explicitly each time.

### A2. CI follow-up (not a blocker)
- [ ] **Commit the CI-regenerated `pubspec.lock`.** It is currently stale (pre-Phase-4) so CI re-resolves
  the camera/zxing federation every run; committing the lock hardens the `camera_android_camerax` cap and
  the `flutter_zxing 2.2.1` pin against future float. (Needs a Flutter toolchain or pulling the lock CI
  produces.) Tracked here per the camerax debug session follow_up.

### B. On-device gate — 04-03 lock-screen camera spike (criterion #1; never auto-approvable)
- [ ] **Live `flutter_zxing` `ReaderWidget` preview over a SECURE keyguard, ≥2 OEMs.** Add the throwaway
  `// SPIKE` scaffold (04-03 Task 1), build the dev APK, fire a real alarm over a PIN/pattern lock, and
  record per device: does the preview render (frames moving)? does `onScan` decode? → GO / NO-GO /
  REQUIRES-UNLOCK. Write `04-LOCKSCREEN-SPIKE.md` (one row per device + verdict), then REVERT the
  scaffold (`git diff alarm_notification_screen.dart` empty). Per D-LOCK-SHIP the feature ships
  regardless — the verdict only sets the expected default per device class.
  Observed: …

### C. On-device gate — 04-06 end-to-end scan-to-dismiss (SCAN-09/11 + assembled flow; never auto-approvable)
- [ ] **Register at setup (SCAN-02/08/10):** add the "Scan code to dismiss" task → camera permission
  requested AT SETUP → scan a QR + a 1D barcode → card shows "✓ Code registered" (never the raw value).
  Deny-then-deep-link-to-settings path resumes. **Also confirm CR-01 fix:** a scan task with NO
  registered code cannot be saved on EITHER the add or the edit path.
  Observed: …
- [ ] **Match → dismiss (SCAN-03/05):** real alarm fires → swipe → scanner opens → registered code
  dismisses; a trailing-newline/case variant still dismisses; snooze works WITHOUT entering the scanner.
  **Also confirm CR-02 fix:** a held/duplicate matching frame dismisses exactly once (no double-advance).
  Observed: …
- [ ] **Wrong scan + escape (SCAN-06/07):** wrong code → haptic + transient feedback, no dismiss; after
  ~120s or ~10 wrong attempts a TalkBack-reachable Dismiss appears; camera denied/disabled → escape
  Dismiss appears INSTANTLY.
  Observed: …
- [ ] **Torch (SCAN-09):** toggles in a dark room; on a no-flash device degrades gracefully
  (scanner keeps running). NOTE WR-01: the graceful-no-flash message is currently unreachable code —
  confirm actual torch behavior and decide whether a custom torch control is needed.
  Observed: …
- [ ] **Camera release (SCAN-11):** after every exit (match-dismiss, escape-dismiss, background) the OS
  privacy indicator clears and the next alarm's scanner can acquire the camera.
  Observed: …
- [ ] **No-go OEM degradation (D-LOCK-NOGO-UX):** on a spike-flagged no-go device the "unlock to scan"
  prompt shows over the keyguard, the alarm keeps ringing until unlocked, and the escape hatch still
  fires underneath (never trapped).
  Observed: …

### D. Open code-review items (tracked in 04-REVIEW.md — not blockers)
- [ ] WR-01 torch graceful-no-flash is dead code (needs on-device/zxing-API resolution — see C torch).
- [ ] WR-02 `Vibration.vibrate` has no `hasVibrator()` guard.
- [ ] WR-03 overlapping wrong-code `Future.delayed` flashes (mitigated by `scanDelay` 1000ms > 600ms).
- [ ] WR-05 BUILD-02 zero-ML-Kit gate triggers only on `workflow_dispatch` (see A) — decide push/PR trigger.

---

## Phase 3 — Date, Volume & FAB High-Value Fixes (completed 2026-06-05)

Code changed: `setting.dart`, `date_picker_bottom_sheet.dart`, `volume_ramp_controller.dart`,
`ringtone_player.dart`, `custom_list_view.dart`, `fab.dart` (+ 3 test files).
Source: `03-HUMAN-UAT.md`, `03-VERIFICATION.md`, `03-REVIEW.md`, `03-REVIEW-FIX.md`.

### A. Date off-by-one (DATE-01, DATE-02)
- [ ] **Specific-date alarm fires on the right day, non-UTC device, after restart.**
  Create a specific-date alarm for tomorrow on a UTC+9 or UTC-5 device, restart the app.
  Expected: still the picked local calendar date — not shifted by a day.
  Observed: …
- [ ] **Legacy-epoch alarms self-heal on upgrade.**
  An alarm whose dates were saved as old epoch ints (pre-update) is reloaded.
  Expected: recovers the originally-picked day; list does not crash.
  Observed: …
- [ ] **(Logic change WR-02) DST-boundary date range.** Select a multi-month date *range*
  that straddles a DST transition (spring-forward or fall-back).
  Expected: the right number of days selected — no day dropped or duplicated at the boundary.
  (Fix advances the fill cursor via `DateTime(y,m,day+1)` instead of `+24h`.)
  Observed: …
- [ ] **(Logic change WR-04) Reversed range guard.** If any flow can hand the picker a range
  with end before start, confirm it still produces a sensible multi-day range (not a 1-day stub).
  Observed: …

### B. Rising volume (VOL-01, PR-01)
- [ ] **Ramp climbs then stops clean on dismiss/snooze.** Rising-volume alarm, let it climb,
  dismiss. Expected: smooth climb to max, stops instantly on dismiss/snooze, no stray bump after.
  Observed: …
- [ ] **No full-volume blip at start (WR-01).** Expected: alarm starts quiet and rises — it does
  NOT briefly blast full volume at t=0 before ramping. (Fix seeds volume to 0 when a ramp runs.)
  Observed: …
- [ ] **Lowering volume mid-ring does NOT kill the ramp.** Press volume-down while ringing.
  Expected: ramp keeps climbing toward max (setVolume decoupled from ramp-stop).
  Observed: …
- [ ] **(Design sign-off, 03-02) Safe default to confirm:** a plain mid-ring `setVolume()` leaves
  the ramp running and does **not** retarget the ceiling. If you'd rather a manual volume change
  *cap* the ramp, that's a separate product call — flag it.
  Decision: …
- [ ] **No cross-alarm volume bleed.** Ring alarm A, then alarm B before A ends.
  Expected: no stray ticks from A's ramp after B starts.
  Observed: …

### C. FAB clearance (FAB-01, PR-02)
- [ ] **FAB doesn't cover the last item/menu — one device, both orientations + styles.**
  Alarm list, portrait + landscape, Material and non-Material.
  Expected: last alarm's menu button fully visible above the FAB.
  Observed: …
- [ ] **FAB clearance holds on a second OEM** (e.g. Samsung + Pixel / Pixel + OnePlus).
  Observed: …

### D. CI gate (toolchain absent locally — never run/faked here)
- [ ] **CI `tests.yml` green on the 3 new test files** on next push:
  `date_time_setting_test.dart`, `volume_ramp_controller_test.dart`, `fab_clearance_test.dart`.
  Observed (CI run link / result): …
- [ ] **`fab_clearance_test.dart` stability.** If the headless pump throws because `appSettings`
  reaches storage under CI, degrade it to on-device-only + document (per D-TEST-COVERAGE);
  otherwise confirm non-flaky over 3 runs.
  Observed: …

### Deferred (not a check — tracked TODO)
- [ ] At the next `/gsd-transition`: reword PR-01, PR-02, and ROADMAP success-criterion #4 to drop
  "crediting the contributor" — D-PR-METHOD reframed these as independent/sole-credit. Wording is
  stale in ROADMAP + REQUIREMENTS; code is already correct (no attribution present).

---

## Earlier phases — accepted on-device gates (reference)

These were accepted at sign-off; listed so an error here is easy to trace back.

### Phase 1 — Storage & Boot Reliability (closed 2026-06-02)
- [ ] Boot/unlock guard + corrupted-state recovery behave on real devices (no boot crash, no splash hang).

### Phase 2 — Snooze Reliability (closed 2026-06-03)
- [ ] Snooze re-fires correctly; one-shot alarm does not wrongly reschedule after snooze→dismiss;
  fractional snooze length works. (CI regression suite was green: tests.yml 176 passed; on-device smoke was the accepted gate.)
