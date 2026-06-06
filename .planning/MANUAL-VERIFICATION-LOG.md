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

## Phase 4 — QR/Barcode Scan-to-Dismiss Task (authorable-complete 2026-06-06; NOT closed)

Authorable plans 04-01, 04-02, 04-04, 04-05 landed on `master`. 04-03 (lock-screen spike) and 04-06
(end-to-end e2e) are inherently on-device and were **deferred** — no device or Flutter/Dart toolchain in
the execution environment, so nothing here was run or claimed locally. Code-review BLOCKERs CR-01
(add-path save-gate bypass) and CR-02 (ScanTask re-entrancy) were found and fixed; WR-04 (CI analyze
scope) fixed; WR-01/02/03/05 + INFO left open.
Source: `04-01..05-SUMMARY.md`, `04-REVIEW.md`, `04-03-PLAN.md`, `04-06-PLAN.md`.

### A. CI gates owed (authoritative — run on next push; user authorizes, both remotes outward-facing)
- [ ] **`tests.yml` green** on the new pure-seam + round-trip tests:
  `test/alarm/logic/code_match_test.dart`, `test/alarm/logic/escape_hatch_controller_test.dart`,
  `test/alarm/types/alarm_task_scan_test.dart`. (SCAN-03/06/07 + SCAN-01 behavioral GREEN.)
  Observed (CI run link / result): …
- [ ] **`flutter gen-l10n` succeeds** — the new `scan*` ARB keys generate their `AppLocalizations`
  getters (referenced by `scan_task.dart` / `alarm_task_schemas.dart` / registration UI) before compile.
  Observed: …
- [ ] **`flutter analyze` (test-apk.yml, now repointed to the Phase-4 scan files)** — read the log for
  NEW issues (incl. WR-01 torch dead-code). Informational/continue-on-error.
  Observed: …
- [ ] **Dev-APK native build compiles `flutter_zxing`** (FFI/NDK). If CI flags an NDK/CMake mismatch,
  set `ndkVersion 27.0.12077973` (recorded contingency, currently `flutter.ndkVersion`).
  Observed: …
- [ ] **BUILD-02 zero-ML-Kit prod-graph gate PASSES** (blocking job greps `prodReleaseRuntimeClasspath`
  for `mlkit|play-services|gms`, expects none). NOTE WR-05: this job currently triggers only on
  `workflow_dispatch`, not push/PR — run it explicitly until/unless that's changed.
  Observed: …

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
