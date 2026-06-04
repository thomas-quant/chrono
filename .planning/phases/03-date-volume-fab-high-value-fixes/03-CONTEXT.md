# Phase 3: Date, Volume & FAB High-Value Fixes - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Eliminate the three remaining high-value defects:
1. **Specific-date off-by-one (DATE-01/02)** — an alarm set for a specific date rings on exactly
   that **local calendar date**, after restart and regardless of the device's UTC offset, because
   the date is stored/reloaded as a calendar date, not an absolute instant.
2. **Rising volume won't stop cleanly (VOL-01)** — the gradual-volume ramp climbs to the configured
   max and then **stops the instant** the alarm is dismissed/snoozed: no stray volume bumps after
   stop, no bleed into a second alarm.
3. **FAB covers list items (FAB-01)** — floating action buttons no longer hide list items / menu
   buttons on the alarm and other list screens.

Community PRs **#467** (volume) and **#466** (FAB) are the upstream fixes for VOL-01/FAB-01.

**In scope (requirements):** DATE-01, DATE-02, VOL-01, FAB-01, PR-01, PR-02.

**Not in scope:**
- DST/timezone recompute for recurring alarms (#359) — deferred to its own milestone (PROJECT.md).
- Storage re-architecture — Tier-1 minimal-change carried from Phase 1 (D-01).
- Snooze/boot fixes — Phases 1 & 2 (done).
- Adding an Android emulator / `integration_test` CI job — deferred infra (see Deferred Ideas).

**⚠ Requirement deviation locked this discussion (see D-PR-METHOD):** the user chose to take sole
credit for the volume/FAB fixes (reimplement, no contributor attribution). This **inverts PR-01,
PR-02, and ROADMAP Phase-3 success-criterion #4**, which all say "crediting the contributor." Those
artifacts need rewording at the next `/gsd-transition`. Flagged, not silently absorbed.

</domain>

<decisions>
## Implementation Decisions

### Date storage format & migration (DATE-01/DATE-02) — Claude's discretion (user said "you decide")
- **D-DATE-FORMAT:** Persist a specific date as a **date-only ISO-8601 string `YYYY-MM-DD`**, parsed
  back to a local `DateTime(y, m, d)` on load. Normalize the picker output to strip any time/TZ
  component at the source. Rationale: the variant most immune to a device-TZ change between save and
  load, self-documenting, and easiest to migrate. Touches `DateTimeSetting.valueToJson` /
  `loadValueFromJson` (`lib/settings/types/setting.dart:957-967`) and the picker boundary.
  **Note:** `DateTimeSetting` is **also reused by the date-range schedule** — the format change must
  be verified to not break `RangeAlarmSchedule` (`lib/alarm/types/schedules/range_alarm_schedule.dart`).
- **D-DATE-MIGRATION:** **Auto-correct on upgrade.** `loadValueFromJson` must tolerate **legacy `int`
  epoch elements** (never crash on old data) and reinterpret each by reading it in **UTC**
  (`DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)` → `.year/.month/.day`) to recover the
  *originally-picked* calendar day — because `table_calendar` historically emitted **UTC-midnight**
  days. New string elements parse directly. Result: already-broken specific-date alarms self-heal on
  update. **CONTINGENT on the researcher confirming `table_calendar`'s day normalization (midnight-UTC
  vs noon-UTC) on the pinned version** — if noon-UTC, the reinterpretation simplifies. See Research items.

### Community PR incorporation & credit (PR-01/PR-02) — user decision
- **D-PR-METHOD:** **Take sole credit — reimplement independently.** Do **NOT** cherry-pick the
  contributors' commits and do **NOT** carry contributor attribution. Implement the volume and FAB
  fixes from scratch using standard techniques (cancellable `Timer` ramp controller; list bottom
  clearance) — *do not copy-then-strip* the PRs' diffs. (User confirmed twice after I flagged the
  conflict with the locked "credit the contributor" requirements and OSS-attribution etiquette; it is
  the user's fork and their informed call.) **Downstream consequence:** PR-01, PR-02, and ROADMAP
  success-criterion #4 must be reworded away from "crediting the contributor" at the next transition.
  Researcher MAY skim the PRs only to confirm our reimplementation covers the same cases — never to copy.
- **D-PR-QUALITY:** **Hold to our correctness criteria.** The volume fix must achieve VOL-01's clean
  cancellation (no stray bumps after stop, **no cross-alarm bleed**); the FAB fix must fully clear
  FAB-01's no-overlap. Treat the upstream fixes as a starting reference, not the finish line — extend
  until our criteria are met. (Volume is a core-value "alarm won't stop cleanly" bug — hold the line.)

### FAB fix scope (FAB-01) — user decision
- **D-FAB-SCOPE:** **Fix once at the shared list/FAB layer.** Add bottom scroll-clearance centrally
  (in the common `PersistentListView` / wherever the FAB + list compose) so **every** screen using the
  floating FAB overlay inherits clearance and the last item is never hidden. The FAB is a custom
  `Positioned` widget stacked over the list (`lib/common/widgets/fab.dart`) — **not** a Material
  `Scaffold.floatingActionButton` — so standard FAB-notch padding does not apply; clearance must be an
  explicit bottom inset on the scroll content (account for nav bar + FAB height + the Material-style
  `+20` px in `fab.dart:67-69`). **Planner/researcher to confirm a clean central injection point;**
  per-screen fallback only if it can't be cleanly centralized (then cover at least alarm + the primary
  lists: timer, clock, stopwatch). Satisfies FAB-01's "alarm and other list screens" most fully.

### Test coverage (this phase) — Claude's discretion per user's standing directive "maximize CI"
- **D-TEST-COVERAGE:** **All three fixes get CI-runnable coverage** (see new project Testing Policy):
  - **Date** → unit test: local-date serialize/parse round-trip, **legacy-epoch migration**, and that
    `RangeAlarmSchedule` (reuses `DateTimeSetting`) still works. Reuse the Phase-2 pattern
    (`withClock(Clock.fixed(...))`, assert on objects/flags, OS no-ops under `FLUTTER_TEST`).
  - **Volume cancellation** → unit test by **extracting a pure, audio-free ramp controller** from
    `RingtonePlayer` (injectable `Timer`/clock + a "set volume" callback). Assert **no volume callback
    fires after stop/dismiss/snooze** and no cross-alarm bleed. Real `just_audio` playback = on-device.
  - **FAB** → a **headless widget test** scoped to the list/FAB **layout seam** (assert the list reserves
    bottom clearance ≥ FAB extent / the last item is not occluded), kept narrow to avoid full-screen
    singleton (`appSettings`/storage/l10n) brittleness. If it proves too flaky during execution it
    degrades to on-device-only, documented. Real-device cross-OEM layout = on-device.

### Project-wide policy change made this discussion
- **D-CI-TESTING-POLICY:** Added a **Testing Policy** to project `CLAUDE.md` (`CLAUDE.md`, hand-maintained
  block outside GSD markers): default **all CI-runnable testing — unit AND headless widget tests — to
  GitHub Actions for every phase/plan**; refactor pure seams to make more testable; on-device only for
  what CI genuinely cannot run; no emulator/`integration_test` job today (deferrable). Applies to all
  future phases, not just Phase 3.

### Carried forward from earlier phases (not re-asked)
- **Tier-1 minimal-change** — harden/extend the existing path, no rewrites (Phase 1 D-01).
- **CI is the authoritative test gate; Flutter toolchain absent locally** — tests authored in-repo,
  confirmed green via CI, never faked as locally passing (Phase 1/2 pattern; now codified in CLAUDE.md).
- **Localized strings** — English baseline + Weblate for any new user-facing text (Phase 1 D-06).
  (Likely none new this phase — all three are bug fixes, not new UI copy.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone planning docs
- `.planning/PROJECT.md` — milestone scope, constraints, key decisions (incl. "merge community PRs"
  decision that D-PR-METHOD now deviates from).
- `.planning/REQUIREMENTS.md` — DATE-01, DATE-02, VOL-01, FAB-01, PR-01, PR-02 exact wording (this
  phase's contract; PR-01/PR-02 need rewording per D-PR-METHOD).
- `.planning/ROADMAP.md` §"Phase 3" (goal + success criteria; criterion #4 needs rewording) + §"Research
  Flags" (Phase 3 notes: epoch round-trip; `Future.delayed` + static flag; PRs #467/#466).

### Reliability root causes (line-level — primary source for what to fix)
- `.planning/codebase/CONCERNS.md` — rising-volume `Future.delayed`-without-cancellation writeup
  (`ringtone_player.dart:119-129`); settings-magic-string fragility; no `RingtonePlayer` test coverage.
- `.planning/codebase/CONVENTIONS.md` — naming, logging levels (`logger.t/i/e/f`), `toJson`/`fromJson`
  serialization, file layout to match when adding code/tests.
- `.planning/codebase/ARCHITECTURE.md` — settings/`SettingGroup` JSON persistence, isolate boundaries.

### Source files to change (root causes confirmed)
- `lib/settings/types/setting.dart:957-967` — `DateTimeSetting.valueToJson`/`loadValueFromJson` epoch
  round-trip (DATE-01/02, D-DATE-FORMAT, D-DATE-MIGRATION).
- `lib/common/widgets/fields/date_picker_bottom_sheet.dart:133-202` — `table_calendar` picker; emits
  UTC-midnight `DateTime`s; `_focusedDate` mixes `DateTime.now()` (local). Normalize output here.
- `lib/alarm/types/schedules/dates_alarm_schedule.dart:57-82` — `schedule()` already reads `.year/.month/.day`
  (so fix is at the serialization/picker boundary, not here); confirm unaffected.
- `lib/alarm/types/schedules/range_alarm_schedule.dart` — **also reuses `DateTimeSetting`**; verify the
  format change doesn't break ranges.
- `lib/audio/types/ringtone_player.dart:82-161` — `setVolume()` sets `_stopRisingVolume = true`
  (conflates user/stop set-volume with the ramp); fire-and-forget `Future.delayed` ramp at `:118-130`;
  `stop()`/`pause()` at `:145-161` (VOL-01, D-PR-QUALITY, D-TEST-COVERAGE volume controller).
- `lib/common/widgets/fab.dart` — custom `Positioned` FAB overlay (NOT Scaffold FAB); `:67-69` Material
  `+20` bottom padding (FAB-01, D-FAB-SCOPE).
- `lib/alarm/screens/alarm_screen.dart:285-330` — `Stack` of `PersistentListView` + `FAB`(s).
- `lib/common/widgets/list/persistent_list_view.dart` — shared list widget; **candidate central
  injection point** for the bottom-clearance fix (D-FAB-SCOPE).

### CI / testing
- `.github/workflows/tests.yml` — `flutter test --coverage` on `ubuntu-latest` (the authoritative gate;
  unit + headless widget tests; no emulator).
- `.github/workflows/test-apk.yml` — `flutter analyze` (informational) + sideloadable dev APK build.
- `CLAUDE.md` §"Testing Policy" — **new** project-wide rule: default CI-runnable testing to GitHub Actions.
- `test/alarm/types/alarm_snooze_test.dart` — Phase-2 regression suite; the **pattern to mirror** for the
  date + volume-controller tests.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase-2 test pattern** (`test/alarm/types/alarm_snooze_test.dart`): CI-runnable regression style with
  `withClock(Clock.fixed(...))`, asserting on Dart objects/flags while OS scheduling no-ops under
  `FLUTTER_TEST`. Direct template for the date round-trip and volume-controller tests.
- **`clock` package (`clock.now()`)** — already adopted in Phase 2; use an injectable clock/`Timer` for the
  new cancellable volume-ramp controller so the cancel logic is unit-testable without real audio.
- **`PersistentListView` / `PersistentListController`** — shared list infrastructure used by all FAB
  screens; the natural single place to add bottom scroll-clearance (D-FAB-SCOPE).
- **`logger` singleton** — use existing `logger.e/i/t` for any recovery/migration logging (date migration).

### Established Patterns
- **`SettingGroup` JSON round-trip** — settings persist via `valueToJson`/`loadValueFromJson`; the date fix
  changes only `DateTimeSetting`'s two methods while staying backward-compatible with legacy `int` values.
- **Custom FAB over `Stack`** — screens compose `[ list, FAB, ...]` in a `Stack`; the FAB floats via
  `Positioned`. Because it is not a Material `Scaffold.floatingActionButton`, the list does not auto-reserve
  space — hence the overlap. Fix = explicit bottom inset on the scrollable, not a Scaffold property.
- **Static-class players** — `RingtonePlayer` is all-static (`activePlayer`, `_stopRisingVolume`). The ramp
  refactor should extract the *scheduling/cancellation* concern into a testable unit while leaving the
  static audio-player wiring in place (Tier-1 minimal change).

### Integration Points
- **Volume:** `playAlarm`/`playTimer` → `_play()` → ramp; `stop()`/`pause()`/`setVolume()` are the cancel
  points. The dismiss/snooze paths (Phase-2 `_resolveDismiss`, isolate dismiss branch) ultimately call
  `RingtonePlayer.stop()` — the ramp controller must be cancelled there with no late callbacks.
- **Date:** picker (`DatePickerBottomSheet`) → `DateTimeSetting` value → `DatesAlarmSchedule.schedule()`.
- **FAB:** every list screen (alarm, timer, clock, stopwatch, presets, ringtones, themes, tags, alarm-events,
  logs, list-filter, list-setting) composes `FAB` over a list — all inherit the central clearance fix.

</code_context>

<specifics>
## Specific Ideas

- **Volume bug nuance confirmed in source:** `setVolume()` (`ringtone_player.dart:82-86`) sets
  `_stopRisingVolume = true`, and the ramp's own steps call `setVolume()` — so the rising-volume flag is
  tangled with every legitimate volume set, and the 11 `Future.delayed` callbacks are untracked /
  uncancellable. The reimplementation should **decouple** the "stop the ramp" signal from a plain volume set
  and use a **cancellable, tracked** Timer/controller.
- **Date bug nuance confirmed in source:** the off-by-one originates at the **serialization boundary**, not
  the schedule logic — `DatesAlarmSchedule.schedule()` already rebuilds the alarm time from `.year/.month/.day`.
  So the minimal correct fix is "store/reload a calendar date," exactly DATE-02's wording.

</specifics>

<deferred>
## Deferred Ideas

- **Reword PR-01 / PR-02 / ROADMAP success-criterion #4** to drop "crediting the contributor" — required
  consequence of D-PR-METHOD (sole-credit). Do at the next `/gsd-transition`.
- **Android emulator / `integration_test` CI job** (`reactivecircus/android-emulator-runner`) — would let CI
  run instrumented/on-device-class tests (real layout, real audio behaviors). New, slower CI infra; out of
  scope for a bug-fix phase. Propose explicitly in a future milestone if the on-device gate burden grows.
- **Broader `RingtonePlayer` test coverage** (vibration lifecycle, multi-player stop/pause, audio-focus) —
  beyond VOL-01's cancellation; candidate for a future audio-hardening pass.
- **Replace settings-by-magic-string access** with typed accessors (CONCERNS.md tech debt) — not this phase.

</deferred>

<research_items>
## Open Items for the Researcher

1. **`table_calendar` day normalization on the pinned version** — confirm whether `onDaySelected` emits
   **midnight-UTC** or **noon-UTC** days. Determines the exact legacy-epoch reinterpretation in
   D-DATE-MIGRATION (UTC `.year/.month/.day` recovers the intended day only if midnight-UTC; noon-UTC is
   offset-stable and simplifies migration).
2. **Clean central injection point for FAB bottom-clearance** — confirm `PersistentListView` (or the shared
   list/FAB composition) can host a single bottom-inset change that all ~12 screens inherit, including
   nav-bar + FAB-height + Material `+20` px; otherwise scope the per-screen fallback.
3. **PRs #467 / #466 case coverage (reference only)** — skim to ensure our independent reimplementation
   covers the same scenarios (e.g. cross-alarm volume bleed, FAB over menu buttons). **Do not copy** — we
   take sole credit (D-PR-METHOD).

</research_items>

---

*Phase: 3-Date, Volume & FAB High-Value Fixes*
*Context gathered: 2026-06-05*
