# Manual Verification Log — "things I said I'd double-check"

A running, cross-phase list of checks the user accepted on faith at completion time
(on-device behavior, CI runs, and design-decision sign-offs that automated checks
can't cover locally). When you test something, fill in **Observed** and flip the box.
If you hit an error, compare it against the **Expected** line here first — a mismatch
points straight at the suspect change.

- Per-phase structured versions live in each phase's `*-HUMAN-UAT.md`; `/gsd-audit-uat`
  aggregates them. This file is the curated human-readable running list.
- Status keys: `[ ]` pending · `[x]` verified OK · `[!]` mismatch/error (note it)

_Last updated: 2026-06-05 (after Phase 3 completion)_

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
