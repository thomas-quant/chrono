# Phase 3: Date, Volume & FAB High-Value Fixes - Research

**Researched:** 2026-06-05
**Domain:** Flutter/Dart — DateTime serialization & timezone correctness, cancellable timer-based ramp control, custom-overlay FAB layout clearance, CI-runnable unit/widget tests
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Date storage format & migration (DATE-01/DATE-02) — Claude's discretion ("you decide"):**
- **D-DATE-FORMAT:** Persist a specific date as a **date-only ISO-8601 string `YYYY-MM-DD`**, parsed back to a local `DateTime(y, m, d)` on load. Normalize the picker output to strip any time/TZ component at the source. Touches `DateTimeSetting.valueToJson` / `loadValueFromJson` (`lib/settings/types/setting.dart:957-967`) and the picker boundary. **Note:** `DateTimeSetting` is **also reused by the date-range schedule** — the format change must be verified to not break `RangeAlarmSchedule`.
- **D-DATE-MIGRATION:** **Auto-correct on upgrade.** `loadValueFromJson` must tolerate **legacy `int` epoch elements** (never crash on old data) and reinterpret each by reading it in **UTC** (`DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)` → `.year/.month/.day`) to recover the *originally-picked* calendar day. New string elements parse directly. **CONTINGENT on the researcher confirming `table_calendar`'s day normalization (midnight-UTC vs noon-UTC).** → **RESOLVED below: midnight-UTC confirmed at pinned 3.1.1. The UTC reinterpretation is correct.**

**Community PR incorporation & credit (PR-01/PR-02) — user decision:**
- **D-PR-METHOD:** **Take sole credit — reimplement independently.** Do **NOT** cherry-pick the contributors' commits and do **NOT** carry contributor attribution. Implement volume and FAB fixes from scratch using standard techniques. Researcher MAY skim the PRs only to confirm our reimplementation covers the same cases — never to copy. **Downstream:** PR-01, PR-02, and ROADMAP success-criterion #4 must be reworded away from "crediting the contributor" at the next transition.
- **D-PR-QUALITY:** **Hold to our correctness criteria.** Volume fix must achieve VOL-01's clean cancellation (no stray bumps after stop, **no cross-alarm bleed**); FAB fix must fully clear FAB-01's no-overlap. Treat upstream as a starting reference, not the finish line.

**FAB fix scope (FAB-01) — user decision:**
- **D-FAB-SCOPE:** **Fix once at the shared list/FAB layer.** Add bottom scroll-clearance centrally so **every** screen using the floating FAB overlay inherits clearance. The FAB is a custom `Positioned` widget (`lib/common/widgets/fab.dart`) — **not** a Material `Scaffold.floatingActionButton` — so clearance must be an explicit bottom inset on the scroll content (account for nav bar + FAB height + the Material-style `+20` px in `fab.dart:67-69`). Per-screen fallback only if it can't be cleanly centralized (then cover at least alarm + timer + clock + stopwatch). → **RESOLVED below: a single clean central injection point exists in `CustomListView`.**

**Test coverage (this phase) — Claude's discretion per "maximize CI":**
- **D-TEST-COVERAGE:** All three fixes get CI-runnable coverage. Date → unit test: local-date serialize/parse round-trip, legacy-epoch migration, and that `RangeAlarmSchedule` still works. Volume → unit test by **extracting a pure, audio-free ramp controller** (injectable `Timer`/clock + "set volume" callback); assert **no volume callback fires after stop/dismiss/snooze** and no cross-alarm bleed. FAB → a **headless widget test** scoped to the list/FAB layout seam; degrades to on-device-only if too flaky.
- **D-CI-TESTING-POLICY:** Project `CLAUDE.md` now defaults all CI-runnable testing (unit AND headless widget tests) to GitHub Actions for every phase/plan.

**Carried forward:**
- **Tier-1 minimal-change** — harden/extend the existing path, no rewrites (Phase 1 D-01).
- **CI is the authoritative test gate; Flutter toolchain absent locally** — tests authored in-repo, confirmed green via CI, never faked as locally passing.
- **Localized strings** — English baseline + Weblate for any new user-facing text (likely none new this phase — all three are bug fixes).

### Claude's Discretion
- Exact date storage format (locked to `YYYY-MM-DD` above), migration mechanics, test structure, the central-vs-fallback FAB decision, and the ramp-controller shape are all Claude's discretion within the locked constraints.

### Deferred Ideas (OUT OF SCOPE)
- **Reword PR-01 / PR-02 / ROADMAP success-criterion #4** to drop "crediting the contributor" — do at the next `/gsd-transition`.
- **Android emulator / `integration_test` CI job** (`reactivecircus/android-emulator-runner`) — deferred infra.
- **Broader `RingtonePlayer` test coverage** (vibration lifecycle, multi-player stop/pause, audio-focus) — beyond VOL-01's cancellation.
- **Replace settings-by-magic-string access** with typed accessors — not this phase.
- **DST/timezone recompute for recurring alarms (#359)** — deferred to its own milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DATE-01 | A specific-date alarm rings on exactly that calendar date, after restart, regardless of device UTC offset (#340/#455/#472) | Date-only `YYYY-MM-DD` string round-trip in `DateTimeSetting`; `DatesAlarmSchedule.schedule()` already reads `.year/.month/.day` (confirmed unaffected). Root cause is the serialization boundary, not schedule logic. |
| DATE-02 | A "specific date" is stored/reloaded as a local calendar date, not an absolute instant | `valueToJson` → date-only string; `loadValueFromJson` → `DateTime(y,m,d)` local. No epoch instant persisted. |
| VOL-01 | Rising-volume ramp climbs to max then stops cleanly on dismiss/snooze (no stray bumps, no cross-alarm bleed) (#407/#506) | Extract a cancellable `Timer`-based `VolumeRampController` from `RingtonePlayer`; decouple the "stop the ramp" signal from `setVolume()`. Confirmed cancel points: `stop()`, `pause()`, `playAlarm()`/`playTimer()` re-entry. |
| FAB-01 | FABs no longer cover list items / menu buttons on alarm and other list screens (#417, also #463) | Single central bottom-inset injection in `CustomListView`'s `AnimatedReorderableListView.padding` — covers all ~13 FAB screens. |
| PR-01 | Reimplement #467 (volume) independently — sole credit per D-PR-METHOD (was "credit the contributor") | #467 touches only `ringtone_player.dart` (+35/-16); fixes #407 (volume not rising / blasts immediately). Case coverage confirmed below. |
| PR-02 | Reimplement #466 (FAB) independently — sole credit per D-PR-METHOD (was "credit the contributor") | #466 is a centralized list-clearance fix across alarm/clock/timer/stopwatch, fixing both text and menu-button occlusion (#417, #463). Case coverage confirmed below. |
</phase_requirements>

## Summary

All three defects are confirmed at line level in source, and the two open research items that gated planning are now resolved with authoritative evidence:

1. **table_calendar day normalization (the single most important finding):** At the **pinned version `3.1.1`** (resolved up from the `^3.0.8` caret in `pubspec.yaml` — verified in `pubspec.lock:1096`), every tappable day in the calendar grid is constructed as **`DateTime.utc(year, month, day)` — midnight UTC**. This is confirmed in the package's authoritative source: `normalizeDate(date) => DateTime.utc(date.year, date.month, date.day)` and the grid builder `_daysInRange(...) => List.generate(n, (i) => DateTime.utc(first.year, first.month, first.day + i))`. `onDaySelected` passes the raw grid day. **Consequence:** D-DATE-MIGRATION's UTC reinterpretation (`DateTime.fromMillisecondsSinceEpoch(e, isUtc: true).year/.month/.day`) is the correct recovery path — it returns the originally-picked calendar day for any legacy epoch. The migration does NOT simplify to offset-stable; the UTC read is load-bearing.

2. **FAB central injection point:** A clean single point exists. Every FAB screen (all ~13) renders its scrollable list through `CustomListView` (`lib/common/widgets/list/custom_list_view.dart`), either via `PersistentListView` (9 screens) or directly (logs, list-setting, stopwatch). `CustomListView` hands a hardcoded `padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)` to `AnimatedReorderableListView`, which forwards it to the underlying scrollable (`padding: padding ?? EdgeInsets.zero`). Injecting a computed bottom inset there reserves clearance for the FAB on **every** screen in one edit. The FAB itself is a sibling `Positioned` in each screen's `Stack` — it does not move; only the scroll content gains bottom room. The project already encodes the exact clearance math in `getSnackbar` (`snackbar.dart:51-69`): FAB width `64+16`, Material-style `+20`, nav-bar adjustment.

3. **Volume ramp:** The bug is confirmed and is worse than "stray bumps." `setVolume()` (`ringtone_player.dart:82-86`) sets the static `_stopRisingVolume = true` on *every* call, and the live alarm-volume isolate port (`alarm_isolate.dart:157-159,177-179`) routes the AlarmNotificationScreen's "lower volume while solving a dismiss task" through `setVolume()` — so **solving a task silently and permanently kills the ramp** while the alarm keeps ringing. The 11 fire-and-forget `Future.delayed` callbacks (`:119-130`) are untracked and bleed across alarms. The fix decouples "stop the ramp" from "set the volume" and uses a cancellable, tracked controller.

**Primary recommendation:** (a) Date — change only `DateTimeSetting`'s two JSON methods to a `YYYY-MM-DD` string with legacy-epoch-via-UTC fallback, and strip the picker output to a local calendar date at the `onDaySelected` boundary; confirm `RangeAlarmSchedule` (which reads `startDate`/`endDate` `.year/.month/.day` indirectly via `getScheduleDateForTime`) is unaffected. (b) Volume — extract a pure `VolumeRampController` (injectable `clock`/`Timer` + `void Function(double)` volume callback + explicit `cancel()`), owned by `RingtonePlayer`, cancelled at `stop()`/`pause()`/play re-entry; stop using `setVolume()` as the ramp's cancel signal. (c) FAB — inject one computed bottom inset into `CustomListView`'s list padding.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Calendar-date serialization (DATE-01/02) | Settings/Persistence (`DateTimeSetting`) | UI boundary (date picker) | The off-by-one is a serialization defect (epoch instant ↔ calendar day). The schedule layer already reads `.year/.month/.day`, so the fix belongs at the JSON round-trip and the picker output normalization, not the schedule. |
| Volume-ramp scheduling & cancellation (VOL-01) | Domain logic (new `VolumeRampController`) | Audio integration (`RingtonePlayer` static wiring) | The ramp is a time-based state machine; extracting it into a pure controller makes it unit-testable and gives a real `cancel()`. The static audio player stays in place (Tier-1). |
| List bottom clearance (FAB-01) | Shared UI layer (`CustomListView` scroll padding) | Per-screen `Stack` (FAB position unchanged) | The scrollable is the only thing that must reserve space; the FAB is an independent overlay. One central padding edit is the minimal correct change. |
| CI test seams | Test layer (`flutter test`, headless) | — | Pure controller + JSON round-trip are directly unit-testable; FAB clearance is a narrow headless widget test. |

## Standard Stack

This phase adds **no new packages**. All mechanisms use the existing toolchain.

### Core
| Library | Version (pinned) | Purpose | Why Standard |
|---------|------------------|---------|--------------|
| `clock` | `1.1.1` [VERIFIED: pubspec.lock] | Mockable clock; `clock.now()` + `withClock(Clock.fixed(...))` in tests | Already adopted Phase 2 (`alarm_time.dart:11`, `alarm_snooze_test.dart`). Use for the ramp controller's injectable time. |
| `table_calendar` | `3.1.1` [VERIFIED: pubspec.lock:1096] | Date picker grid (READ-ONLY for this phase — its UTC-midnight behavior is the migration premise) | Pinned via caret; do not bump. |
| `flutter_test` | SDK (Flutter 3.22.2) | Unit + headless widget tests | The CI gate (`tests.yml` → `flutter test --coverage`). |
| `dart:core` `DateTime` / `Timer` | SDK | Date math + cancellable ramp timer | `Timer.periodic(...).cancel()` is the standard cancellable-ramp primitive (vs. fire-and-forget `Future.delayed`). |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `just_audio` | `0.9.x` (`AudioPlayer.setVolume`) | Real volume application | The ramp controller's volume callback wraps `activePlayer?.setVolume(...)`; not used directly in unit tests. |
| `logger` | `2.4.0` | Migration/recovery logging | `logger.i`/`logger.t` for legacy-epoch migration and ramp lifecycle. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Timer.periodic` cancellable ramp | `CancelableCompleter` / `StreamSubscription` of `Stream.periodic` | `Timer` is simplest, has a direct `cancel()`, needs no extra package, and is trivially unit-testable with a fake-async or injected tick. A stream adds ceremony for no gain here. CONCERNS.md explicitly suggests "a `Timer`-based approach that can be `cancel()`-ed, or use `CancelableCompleter`." |
| Date-only ISO `YYYY-MM-DD` string | `DateTime.toIso8601String()` (full) or a `{y,m,d}` map | Locked to `YYYY-MM-DD` (D-DATE-FORMAT) — most TZ-immune and self-documenting. Full ISO re-introduces a time/offset component (the original bug). |
| Central padding in `CustomListView` | Per-screen `bottomPadding` on each `FAB` + per-list padding | Central is one edit for ~13 screens (D-FAB-SCOPE); per-screen is the fallback only. |

**Installation:** None — no new dependencies.

**Version verification:** `table_calendar` and `clock` versions read directly from `pubspec.lock` (the authoritative resolved versions). No registry lookups were needed because no packages are added or changed. The Flutter toolchain is absent locally (per CLAUDE.md), so versions come from the committed lockfile, which is the correct source of truth.

## Package Legitimacy Audit

> Not applicable — **this phase installs no external packages.** All three fixes use the existing pinned toolchain (`clock`, `flutter_test`, `dart:core`, `just_audio`, `table_calendar` read-only). No `pubspec.yaml` / `pubspec.lock` change is expected. slopcheck / registry verification is therefore moot. If planning later discovers a need for a new package, run the Package Legitimacy Gate before adding it.

## Architecture Patterns

### System Architecture Diagram

**Date fix — data flow (where the off-by-one lives and where the fix goes):**

```
[User taps a day]
   table_calendar 3.1.1 grid cell  ──► DateTime.utc(y,m,d)   (midnight UTC — CONFIRMED)
        │
        ▼
DatePickerBottomSheet.onDaySelected(newSelectedDate, ...)   (date_picker_bottom_sheet.dart:145)
        │   ◄── FIX A: normalize to local calendar date here:
        │        final d = DateTime(newSelectedDate.year, newSelectedDate.month, newSelectedDate.day);
        ▼
DateTimeSetting._value : List<DateTime>
        │
        ▼   valueToJson()  ◄── FIX B (DATE-01/02): emit ["YYYY-MM-DD", ...]   (setting.dart:957-959)
   persisted JSON on disk
        │
        ▼   loadValueFromJson(value)  ◄── FIX C (D-DATE-MIGRATION): (setting.dart:962-967)
        │        • String  -> DateTime.parse / split -> DateTime(y,m,d)  (local)
        │        • int (legacy epoch) -> DateTime.fromMillisecondsSinceEpoch(e, isUtc:true)
        │                                 -> DateTime(utc.year, utc.month, utc.day)  (recover picked day)
        ▼
DatesAlarmSchedule.schedule()  reads dates[i].year/.month/.day   (dates_alarm_schedule.dart:62-69)
        │   (ALREADY correct — rebuilds DateTime(y,m,d,h,m,s) in LOCAL time; unaffected by the fix)
        ▼
[Alarm fires on the right local calendar date]

RangeAlarmSchedule  also holds a DateTimeSetting (range) -> startDate/endDate
        │   -> getScheduleDateForTime(time, scheduleStartDate: startDate)  (alarm_time.dart:6)
        │      rebuilds DateTime(start.year, start.month, start.day, ...)  -> SAFE under date-only too
        ▼   VERIFY: range still computes correctly (see Pitfall 2)
```

**Volume fix — control flow (the conflation to break):**

```
[Alarm fires]
RingtonePlayer.playAlarm(alarm)  ──► _play(... secondsToMaxVolume: N ...)   (ringtone_player.dart:45-64)
        │
        ▼  CURRENT (broken):  for i in 0..10 { Future.delayed(i*step, () { if(!_stopRisingVolume) setVolume((i/10)*vol); }) }
        │                      11 untracked futures; _stopRisingVolume is static and shared.
        │
   ┌────┴─────────────────────── cancel signals (ALL currently funnel through setVolume → _stopRisingVolume=true) ──────────────┐
   │ stop()    pause()    setVolume(userVol)   playAlarm()/playTimer() re-entry   live volume port (solving a task) │
   └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
        │  ◄── alarm_isolate.dart:157-159,177-179 sends user volume over a port -> setVolume() -> kills ramp (BUG)
        ▼
PROPOSED:
   VolumeRampController(setVolume: (v) => activePlayer?.setVolume(v), clock/Timer injected)
        • start(targetVolume, duration) -> Timer.periodic step; each tick calls setVolume callback
        • cancel() -> timer.cancel(); no further callback fires (independent of any setVolume call)
   RingtonePlayer holds one controller; cancel() it in stop()/pause()/_play() re-entry.
   A plain setVolume(userVol) sets the player volume WITHOUT cancelling the ramp.  (decoupled)
```

### Recommended Project Structure
```
lib/audio/
├── types/
│   ├── ringtone_player.dart        # keep static; hold a VolumeRampController; cancel at stop/pause/re-entry
│   └── volume_ramp_controller.dart # NEW — pure, audio-free, injectable clock/Timer + setVolume callback
lib/settings/types/
└── setting.dart                    # DateTimeSetting.valueToJson / loadValueFromJson only
lib/common/widgets/
├── fields/date_picker_bottom_sheet.dart  # normalize onDaySelected output to local calendar date
└── list/custom_list_view.dart      # inject computed bottom inset into AnimatedReorderableListView.padding
test/
├── audio/types/volume_ramp_controller_test.dart   # NEW — VOL-01 cancellation, no late callback, no bleed
├── settings/types/date_time_setting_test.dart     # NEW — round-trip + legacy-epoch migration + RangeAlarmSchedule
└── common/widgets/list/fab_clearance_test.dart     # NEW — narrow headless widget test on the list/FAB seam
```

### Pattern 1: Cancellable Timer-based ramp controller (pure seam)
**What:** A small class that owns a single `Timer.periodic`, steps a volume from a start to a target over N seconds, calls an injected `void Function(double)` each tick, and exposes a real `cancel()` that guarantees no further callback fires.
**When to use:** Replacing the 11 fire-and-forget `Future.delayed` callbacks. This is the testable seam D-TEST-COVERAGE requires.
**Example (shape — Claude to finalize; not copied from any PR):**
```dart
// lib/audio/types/volume_ramp_controller.dart  [ASSUMED — design pattern, verify against just_audio's setVolume async signature]
class VolumeRampController {
  VolumeRampController(this._setVolume);
  final void Function(double volume) _setVolume; // injected; wraps activePlayer?.setVolume in prod
  Timer? _timer;

  /// Ramps from 0 -> targetVolume over [duration] in [steps] increments.
  void start({required double targetVolume, required Duration duration, int steps = 10}) {
    cancel(); // never two ramps at once -> no cross-alarm bleed
    if (duration <= Duration.zero) { _setVolume(targetVolume); return; }
    final stepInterval = Duration(microseconds: duration.inMicroseconds ~/ steps);
    var i = 0;
    _setVolume(0);
    _timer = Timer.periodic(stepInterval, (t) {
      i++;
      _setVolume((i / steps) * targetVolume);
      if (i >= steps) cancel();
    });
  }

  void cancel() { _timer?.cancel(); _timer = null; } // after this NO callback fires
  bool get isRunning => _timer?.isActive ?? false;
}
```
*Note: the `clock` package governs `DateTime` reads, not `Timer` firing. For deterministic unit tests of a `Timer`-based controller, use `package:fake_async` (`fakeAsync((async) { ... async.elapse(...); })`) — `fake_async` is a transitive dep already available via `flutter_test`. Alternatively inject a tick callback. The planner should pick one; `fake_async` is the standard and needs no new dependency.*

### Pattern 2: Date-only serialization with legacy fallback
**What:** `valueToJson` emits `YYYY-MM-DD` strings; `loadValueFromJson` accepts both new strings and legacy ints, reinterpreting ints in UTC.
**When to use:** `DateTimeSetting` only.
**Example (shape):**
```dart
// lib/settings/types/setting.dart:957  [pattern; Claude to finalize]
@override
dynamic valueToJson() => _value
    .map((e) => '${e.year.toString().padLeft(4,'0')}-'
                '${e.month.toString().padLeft(2,'0')}-'
                '${e.day.toString().padLeft(2,'0')}')
    .toList();

@override
void loadValueFromJson(dynamic value) {
  if (value == null) return;
  _value = (value as List).map<DateTime>((e) {
    if (e is String) {
      final p = e.split('-');
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
    // Legacy int epoch: table_calendar stored UTC-midnight, so read in UTC
    // to recover the originally-picked calendar day (D-DATE-MIGRATION).
    final utc = DateTime.fromMillisecondsSinceEpoch(e as int, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day);
  }).toList();
}
```

### Pattern 3: Central FAB bottom clearance
**What:** Compute one bottom inset (FAB extent + Material `+20` + nav-bar allowance) and add it to the list scroll padding in `CustomListView`.
**When to use:** Once, in `CustomListView.build` where `AnimatedReorderableListView(padding: ...)` is set (`custom_list_view.dart:390-391`).
**Example (shape):**
```dart
// custom_list_view.dart:391  — currently: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
// FAB extent: CardContainer(16 padding *2 + 24 icon) = 56; + 16 gap; + Material +20 (matches fab.dart:67-69).
// Mirror the existing precedent in snackbar.dart:51-69 (FAB=64+16, material +20).
padding: EdgeInsets.only(
  left: 16, right: 16, top: 8,
  bottom: 8 + 56 /*FAB*/ + 16 /*gap*/ + (themeSettings.useMaterialStyle ? 20 : 0),
),
```
*The planner should derive the exact constant from `fab.dart` (FAB bottom = `widget.bottomPadding + (material ? 20 : 0)`, FAB tap target = 16+24+16 ≈ 56) and the existing `getSnackbar` math, rather than guessing.*

### Anti-Patterns to Avoid
- **Using `setVolume()` as the ramp's stop signal** (the current bug). The "cancel the ramp" intent must be a separate method (`controller.cancel()`), never coupled to a volume write — otherwise a legitimate live volume change (solving a dismiss task, `alarm_isolate.dart:177-179`) kills the ramp.
- **Per-screen FAB padding when a central point exists** (violates D-FAB-SCOPE; 13 edit sites that drift).
- **Persisting any time/offset component for a specific date** (re-introduces the off-by-one). Date-only string only.
- **Reading legacy epochs in local time** during migration — that re-applies the original off-by-one. Read in UTC (premise: table_calendar UTC-midnight, confirmed).
- **Copying #467/#466 diffs** — D-PR-METHOD requires independent reimplementation; skim for cases only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cancellable timed ramp | A web of `Future.delayed` + a static bool flag (the current bug) | One `Timer.periodic` with `.cancel()` inside a small controller | `Future.delayed` cannot be cancelled; the flag is shared static state that bleeds across alarms. A `Timer` has a real `cancel()`. |
| Deterministic time in tests | `Future.delayed` real-time waits in tests | `package:fake_async` (`fakeAsync` + `async.elapse`) — already transitively available | Real waits are flaky and slow in CI; `fake_async` advances virtual time synchronously. |
| Date comparison ignoring time | Manual `==` on `DateTime` | `DateTime(y,m,d)` construction + compare `.year/.month/.day` (as `DatesAlarmSchedule` already does) | Avoids TZ/time-component traps; matches existing schedule logic. |
| FAB-vs-list clearance | A new layout widget or Scaffold FAB rework | A bottom inset on the existing list padding | The FAB is a `Positioned` overlay; only the scroll content needs to reserve space. Minimal change. |

**Key insight:** Every one of these three bugs is a hand-rolled version of a solved problem (uncancellable timing, instant-vs-calendar date, manual overlay layout). The fixes are subtractive — remove the fragile custom mechanism, use the boring standard one.

## Runtime State Inventory

> This phase changes a serialization format (DATE) — so persisted data is in scope. The other two fixes (volume, FAB) are pure code/UI with no persisted state.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **Specific-date alarms persisted with legacy `int` epoch values** in the on-disk `alarms` JSON list (and `DateTimeSetting` inside range schedules). After the format change, old alarms still hold ints; new ones write `YYYY-MM-DD` strings. | **Data migration via tolerant load** (D-DATE-MIGRATION): `loadValueFromJson` must accept both `int` and `String` and never crash on old data. This is a *code edit that performs migration on read* — no separate batch migration pass. Re-saving (any settings write) upgrades the on-disk value to a string. |
| Live service config | None — no external service stores a Chrono date. | None. |
| OS-registered state | **`AndroidAlarmManager` already-scheduled alarm instants** are not affected by the *storage format* (they were scheduled from the old `.year/.month/.day`). On the next `updateAlarms()` (which Phase 1 confirmed idempotent: cancel-by-id then reschedule), the corrected date drives rescheduling. | **None beyond the normal reschedule.** A specific-date alarm that was previously off-by-one self-heals when the alarm list is next loaded+updated (app launch / boot / any edit), because the corrected calendar day flows into `DatesAlarmSchedule.schedule()`. No manual OS re-registration. |
| Secrets/env vars | None. | None. |
| Build artifacts / installed packages | None — no `pubspec` change, no new package, no codegen for these fixes. (If any new ARB string is added — unlikely — `flutter gen-l10n` is a CI/human gate.) | None expected. |

**Canonical question answered:** After every file in the repo is updated, the only old-state carrier is **persisted specific-date alarm JSON holding legacy epoch ints** — handled by the tolerant `loadValueFromJson` (migrate-on-read). Nothing else (no OS registration, no external service, no secret) carries a stale date format.

## Common Pitfalls

### Pitfall 1: Killing the ramp by reusing `setVolume()` as the cancel signal
**What goes wrong:** A live, legitimate volume change while the alarm is ringing (the AlarmNotificationScreen lowers volume while the user solves a dismiss task — routed through the isolate volume port at `alarm_isolate.dart:157-159` → `setVolume()` at `:177-179`) sets `_stopRisingVolume = true` and silently stops the ramp, even though the alarm is still ringing.
**Why it happens:** `setVolume()` (`ringtone_player.dart:84`) conflates "user/stop set volume" with "cancel the ramp."
**How to avoid:** The new controller's `cancel()` is the *only* ramp-stop signal. A plain volume write must NOT cancel the ramp. Decide deliberately whether a live user volume change *should* retarget the ramp ceiling or leave it running — but it must not be an accidental kill.
**Warning signs:** Ramp stops the moment a task screen opens; volume "sticks" at a partial level.

### Pitfall 2: The date format change breaking `RangeAlarmSchedule`
**What goes wrong:** `DateTimeSetting` is shared. `RangeAlarmSchedule` reads `startDate = value.first` / `endDate = value.last` (`range_alarm_schedule.dart:16-17`) and passes `startDate` to `getScheduleDateForTime(... scheduleStartDate: startDate ...)`, which rebuilds `DateTime(start.year, start.month, start.day, ...)` (`alarm_time.dart:15-16`). It also constructs range defaults with `DateTime.now()` and `DateTime.now().add(Duration(days: 2))` (`:38-40`) and compares `alarmDate.isAfter(endDate)` (`:51`).
**Why it happens:** A range default created as `DateTime.now()` (which has a time component) then serialized as date-only and reloaded as `DateTime(y,m,d)` (midnight) shifts the value by up to a day's worth of time-of-day — and the `isAfter(endDate)` comparison at `:51` compares a *time-bearing* `alarmDate` against a now-*midnight* `endDate`, which can flip the boundary on the last day.
**How to avoid:** (a) Author a CI test that exercises a range schedule across the date-only round-trip and asserts the same set of fire dates before/after. (b) If the boundary flips, normalize the `endDate` comparison to end-of-day or compare on `.year/.month/.day` (as `DatesAlarmSchedule` does). Confirm `DatesAlarmSchedule.schedule()` is genuinely unaffected (it is — it already rebuilds from `.year/.month/.day` at `:62-69`, discarding any time component).
**Warning signs:** A daily/weekly range alarm fires one extra day or stops one day early after the format change. **This is the highest-risk regression in the phase — must have a dedicated test.**

### Pitfall 3: Migrating legacy epochs in local time instead of UTC
**What goes wrong:** Reading a legacy epoch with `DateTime.fromMillisecondsSinceEpoch(e)` (local, the current code at `setting.dart:965`) on a device east/west of UTC recovers the *wrong* calendar day — re-applying the exact off-by-one DATE-01 fixes.
**Why it happens:** table_calendar stored the picked day as UTC-midnight; a local read of a UTC-midnight instant shifts the day by the device offset.
**How to avoid:** Read legacy ints with `isUtc: true` and take `.year/.month/.day` (D-DATE-MIGRATION). **Confirmed correct by this research** (table_calendar 3.1.1 = UTC-midnight). A test must cover an epoch produced by `DateTime.utc(2026, 6, 7).millisecondsSinceEpoch` recovering `2026-06-07` regardless of test TZ.
**Warning signs:** Migrated old alarms are still off by one day on non-UTC devices.

### Pitfall 4: FAB clearance constant guessed instead of derived
**What goes wrong:** Picking an arbitrary bottom inset under/over-clears, especially with Material style (`+20`) vs. non-Material, or in landscape (NavigationRail, no bottom nav bar).
**Why it happens:** The FAB's effective height and the Material `+20` are encoded in `fab.dart:67-69` and `snackbar.dart`, not in the list.
**How to avoid:** Derive the constant from `fab.dart` (FAB tap target ≈ 56, bottom offset = `bottomPadding + (material?20:0)`) and mirror `getSnackbar`'s existing precedent. Account for orientation: in landscape there's no `bottomNavigationBar` (`nav_scaffold.dart:230`), so the inset should still clear the FAB but needn't add nav-bar height. `SafeArea` already wraps the body (`nav_scaffold.dart:252`).
**Warning signs:** Last item still partially hidden, or excessive empty space below the list.

### Pitfall 5: Static state bleeding across alarms (cross-alarm bleed)
**What goes wrong:** Because `RingtonePlayer` is all-static and the old ramp futures are untracked, a second alarm starting before the first's futures drain gets stray volume bumps from the previous ramp.
**Why it happens:** 11 detached `Future.delayed` callbacks outlive the player they were created for.
**How to avoid:** The controller's `start()` calls `cancel()` first (single-ramp invariant), and `_play()` re-entry / `playAlarm` / `playTimer` cancel the prior ramp. Test: start ramp A, start ramp B, advance virtual time, assert no A-tick fired after B started.
**Warning signs:** Volume jumps unexpectedly when one alarm follows another.

## Code Examples

### Verified existing schedule logic that the date fix relies on (already correct)
```dart
// lib/alarm/types/schedules/dates_alarm_schedule.dart:62-69  [VERIFIED: read in source]
DateTime date = DateTime(
  dates[i].year, dates[i].month, dates[i].day,  // discards any time/TZ component
  time.hour, time.minute, time.second,
);
// => fix is purely at serialization + picker boundary; this code is unaffected.
```

### Verified the live-volume conflation (the VOL-01 root cause)
```dart
// lib/audio/types/ringtone_player.dart:82-86  [VERIFIED: read in source]
static Future<void> setVolume(double volume) async {
  logger.t("Setting volume to $volume");
  _stopRisingVolume = true;        // <-- kills the ramp on EVERY volume write
  await activePlayer?.setVolume(volume);
}
// lib/alarm/logic/alarm_isolate.dart:177-179  [VERIFIED]
void setVolume(double volume) { RingtonePlayer.setVolume(volume / 100); } // live port -> ramp death
```

### Verified the central FAB injection point
```dart
// lib/common/widgets/list/custom_list_view.dart:384-401  [VERIFIED]
AnimatedReorderableListView(
  ...
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // <-- inject bottom inset HERE
  controller: _scrollController,
  ...
)
// lib/common/widgets/list/animated_reorderable_list/animated_reorderable_listview.dart:250  [VERIFIED]
padding: padding ?? EdgeInsets.zero,  // forwarded to the actual scrollable
```

### Phase-2 test template to mirror (CI-runnable, no OS, frozen clock)
```dart
// test/alarm/types/alarm_snooze_test.dart:35-69  [VERIFIED]
TestWidgetsFlutterBinding.ensureInitialized();          // reach the static appSettings schema
await withClock(Clock.fixed(fixedNow), () async { ... }); // pin time the model reads
expect(alarm.snoozeTime, fixedNow.add(const Duration(seconds: 30))); // assert on objects/flags only
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|---------|
| Specific date as epoch instant (`millisecondsSinceEpoch`) | Date-only `YYYY-MM-DD` string, local `DateTime(y,m,d)` | This phase | TZ-immune; no off-by-one after restart/offset change. |
| Rising volume via fire-and-forget `Future.delayed` + static flag | Cancellable `Timer`-based controller, decoupled cancel | This phase | Clean stop on dismiss/snooze; no stray bumps; no cross-alarm bleed. |
| FAB overlapping list (no reserved space) | Central bottom inset on the shared list scrollable | This phase (#466 reimplemented) | Last item / menu buttons always visible across all list screens. |

**Deprecated/outdated:**
- `_stopRisingVolume` static bool — replaced by the controller's `cancel()`/`isRunning`. (Keep the static `RingtonePlayer` class per Tier-1; only the ramp mechanism changes.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `package:fake_async` is transitively available via `flutter_test` and is the right tool for deterministic `Timer` tests | Don't Hand-Roll / Pattern 1 | LOW — if absent, inject a tick callback or use a manual fake instead; no new dependency needed either way. The `clock` package does NOT control `Timer` firing, only `DateTime.now()`, so the test strategy must use virtual time for the Timer. |
| A2 | The exact FAB clearance constant (≈56 FAB + 16 gap + 20 material) | Pattern 3 / Pitfall 4 | LOW — visual only; planner should derive from `fab.dart` + `getSnackbar`. Over/under-clear is a cosmetic tweak, not a correctness failure. |
| A3 | A live user volume change during ring should leave the ramp running (not retarget it) | Pitfall 1 | MEDIUM — this is a behavioral choice. The safe default (don't let a volume write kill the ramp) satisfies VOL-01; whether a mid-ring user volume change should *retarget* the ceiling is a product decision the planner/user may want to confirm. The current code's only behavior was "kill the ramp," which is the bug. |
| A4 | `RangeAlarmSchedule` may have a boundary regression under date-only round-trip | Pitfall 2 | MEDIUM — flagged as the top regression risk; mitigated by a mandatory dedicated test. If the test shows no regression, no extra code is needed. |

**Note:** The two items that were explicitly flagged "contingent on research" in CONTEXT.md (table_calendar normalization; FAB central injection point) are **NOT** in this log — they are now `[VERIFIED]` against authoritative source and resolved, not assumed.

## Open Questions (RESOLVED)

1. **Should a live user volume-change during ring retarget the ramp ceiling, or just set the player volume while the ramp continues to its original target?**
   - What we know: The current behavior (kill the ramp) is the bug. VOL-01 only requires the ramp to climb to max and stop cleanly on dismiss/snooze.
   - What's unclear: Whether lowering volume mid-task should cap the ramp's eventual ceiling.
   - Recommendation: Default to "a plain volume write does not cancel the ramp; the ramp continues to its configured target." This is the minimal correct fix. If the user wants mid-ring volume to cap the ramp, that's a small follow-up — surface it to the user at planning/discuss if desired, but it is not required by VOL-01.

2. **Does `RangeAlarmSchedule` actually regress under date-only serialization?**
   - What we know: It reuses `DateTimeSetting`; its defaults use `DateTime.now()` (time-bearing) and it compares `alarmDate.isAfter(endDate)`.
   - What's unclear: Whether stripping time-of-day flips the last-day boundary in practice.
   - Recommendation: Treat as a mandatory test, not an assumption. The plan must include a range round-trip + boundary test (Pitfall 2). If it passes unchanged, ship; if it fails, normalize the comparison to `.year/.month/.day` or end-of-day.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK / `dart`/`flutter` CLI | Authoring + running tests, `gen-l10n`, `analyze` | ✗ (absent locally per CLAUDE.md) | — | **CI is the authoritative gate** (`tests.yml` → `flutter test --coverage`; `test-apk.yml` → `flutter analyze`). Author tests in-repo; confirm green via GitHub Actions. Never report locally-passing. |
| `clock` | Date tests, ramp time | ✓ | 1.1.1 (lockfile) | — |
| `table_calendar` | Date picker (read-only this phase) | ✓ | 3.1.1 (lockfile) | — |
| `flutter_test` (+ transitive `fake_async`) | Unit + headless widget tests | ✓ (SDK) | Flutter 3.22.2 | If `fake_async` proves unavailable, inject a tick callback into the ramp controller. |
| `just_audio` | Real volume application (prod only, not tests) | ✓ | 0.9.x (lockfile) | — |

**Missing dependencies with no fallback:** None that block authoring. The only "missing" item is the local Flutter toolchain, which has a defined fallback (CI is the gate).

**Missing dependencies with fallback:** Flutter CLI → GitHub Actions CI (the project's standing policy).

## Validation Architecture

> `workflow.nyquist_validation` not found in `.planning/config.json`'s read — treated as enabled. (No `config.json` was present at the queried path; this section is included per the default-enabled rule.)

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (SDK, Flutter 3.22.2) |
| Config file | none — discovered by convention (`test/**/*_test.dart`); `analysis_options.yaml` governs lint |
| Quick run command | `flutter test test/audio/types/volume_ramp_controller_test.dart test/settings/types/date_time_setting_test.dart` (CI/human gate — toolchain absent locally) |
| Full suite command | `flutter test --coverage` (exactly what `tests.yml` runs on `ubuntu-latest`, headless) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DATE-01/02 | Date-only round-trip preserves calendar day across TZ | unit | `flutter test test/settings/types/date_time_setting_test.dart` | ❌ Wave 0 |
| DATE-01 (migration) | Legacy UTC-midnight epoch recovers the originally-picked day | unit | (same file) | ❌ Wave 0 |
| DATE-02 (range safety) | `RangeAlarmSchedule` fire-date set unchanged under date-only | unit | (same file, or `test/alarm/types/range_alarm_schedule_test.dart`) | ❌ Wave 0 |
| VOL-01 (cancel) | No volume callback fires after `cancel()` / stop / snooze | unit (`fake_async`) | `flutter test test/audio/types/volume_ramp_controller_test.dart` | ❌ Wave 0 |
| VOL-01 (no bleed) | Starting ramp B emits no further A-ticks | unit | (same file) | ❌ Wave 0 |
| VOL-01 (reaches max) | Ramp ends at configured target volume | unit | (same file) | ❌ Wave 0 |
| FAB-01 | List reserves bottom clearance ≥ FAB extent (last item not occluded) | headless widget | `flutter test test/common/widgets/list/fab_clearance_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the relevant new `*_test.dart` (CI on push — authoritative; not runnable locally).
- **Per wave merge:** `flutter test --coverage` (full suite via `tests.yml`).
- **Phase gate:** full suite green in CI before `/gsd-verify-work`; plus the on-device-only checks below.

### Wave 0 Gaps
- [ ] `test/settings/types/date_time_setting_test.dart` — DATE-01/02 round-trip + legacy-epoch (UTC) migration + RangeAlarmSchedule safety. Mirror `alarm_snooze_test.dart` (`TestWidgetsFlutterBinding.ensureInitialized()`; assert on objects). Force a non-UTC scenario by asserting against `.year/.month/.day` so the test is TZ-agnostic in CI (CI runs UTC — a test that only passes in UTC would hide the bug; assert the recovered calendar day equals the picked day for a constructed `DateTime.utc(...)` epoch).
- [ ] `test/audio/types/volume_ramp_controller_test.dart` — VOL-01 cancellation, no-late-callback, no-bleed, reaches-max. Use `fakeAsync` + `async.elapse(...)`; record callback values in a list; assert none appended after `cancel()`.
- [ ] `test/common/widgets/list/fab_clearance_test.dart` — narrow headless widget test on the list/FAB seam. Keep minimal to avoid `appSettings`/storage/l10n brittleness (the same singletons that make full-screen widget tests flaky). If too flaky in execution, degrade to on-device-only and document (per D-TEST-COVERAGE).
- [ ] No framework install needed — `flutter_test` is SDK-built-in; `fake_async` is transitive.

**On-device-only (CI genuinely cannot run these):** real `just_audio` ramp audibly climbing then stopping on dismiss/snooze; real cross-OEM pixel layout of the FAB over the last list item; an actual specific-date alarm firing on the right local day after a reboot.

## Security Domain

> `security_enforcement` not set in the queried config — treated as enabled. This phase is low-security-surface (no auth, no network, no new input parsing beyond a self-produced date string).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | partial | The only new "input" is the date string we ourselves serialize; `loadValueFromJson` must tolerate malformed/legacy values without crashing (already required by D-DATE-MIGRATION and Phase-1's non-fatal-load principle). Guard the `split('-')`/`int.parse` against malformed strings — fall back to a default date rather than throw, consistent with Phase-1 BOOT-04 recovery. |
| V6 Cryptography | no | — |

### Known Threat Patterns for Flutter/Dart (this phase)

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Crash-on-load from malformed/legacy persisted date (DoS of the alarm list) | Denial of Service | Tolerant `loadValueFromJson`: accept `String` and `int`, catch parse errors, fall back to a safe default + `logger.e` (mirrors Phase-1 per-entry salvage). A corrupt date must never lose the whole alarm list. |
| Log leakage of user data | Information Disclosure | Do not log full alarm contents; `logger.t/i` lifecycle messages only. (Note: an unrelated `print()` leak exists at `dynamic_toggle_setting_card.dart:39` — out of scope here, tracked in STATE.md todos.) |

## Sources

### Primary (HIGH confidence)
- **Codebase (read directly this session):** `lib/settings/types/setting.dart:957-967`, `lib/audio/types/ringtone_player.dart` (full), `lib/common/widgets/fab.dart` (full), `lib/common/widgets/fields/date_picker_bottom_sheet.dart` (full), `lib/alarm/types/schedules/dates_alarm_schedule.dart` (full), `lib/alarm/types/schedules/range_alarm_schedule.dart` (full), `lib/alarm/logic/alarm_time.dart` (full), `lib/common/widgets/list/persistent_list_view.dart` (full), `lib/common/widgets/list/custom_list_view.dart` (full), `lib/alarm/logic/alarm_isolate.dart:60-189`, `lib/alarm/screens/alarm_screen.dart:283-333`, `lib/navigation/screens/nav_scaffold.dart` (full), `lib/common/utils/snackbar.dart` (full), `test/alarm/types/alarm_snooze_test.dart:1-70`.
- **`pubspec.lock:1089-1096`** — `table_calendar` resolved version `3.1.1` (caret `^3.0.8` → 3.1.1); `clock 1.1.1`.
- **table_calendar v3.1.1 authoritative source** (raw.githubusercontent.com, tag `v3.1.1`): `lib/src/shared/utils.dart` — `normalizeDate(date) => DateTime.utc(date.year, date.month, date.day)`, `isSameDay` compares y/m/d; `lib/src/table_calendar.dart` — `onDaySelected` passes the raw grid `day`, inputs normalized; `lib/src/widgets/calendar_core.dart` — `_daysInRange => List.generate(n, (i) => DateTime.utc(first.year, first.month, first.day + i))`. **→ midnight-UTC confirmed.**
- **`gh` CLI (vicolo-dev/chrono):** PR #467 (`Fixes #407`, touches only `lib/audio/types/ringtone_player.dart` +35/-16, title "Fix rising volume not working for alarms"); issue #407 ("rising volume not working" — blasts at full immediately); issue #506 ("Rising Volume feature does not work … does not increase gradually"); issue #463 ("Plus character hides drop-down menu" of the bottommost alarm); PR #466 (FAB, central clearance across alarm/clock/timer/stopwatch, fixes #417 + #463).

### Secondary (MEDIUM confidence)
- PR #466 description summary via WebFetch (page rendered; case coverage extracted). PR #467 page failed to load via WebFetch but was fully resolved via `gh` (Primary above).

### Tertiary (LOW confidence)
- None relied upon. The `fake_async` availability claim is marked `[ASSUMED]` (A1) and has a defined fallback.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; versions read from lockfile.
- Date fix (DATE-01/02) + migration: HIGH — table_calendar UTC-midnight confirmed at the pinned tag from authoritative source; serialization boundary and schedule logic read directly.
- Volume fix (VOL-01): HIGH — conflation and untracked-future bug confirmed at line level; live-port kill path confirmed.
- FAB fix (FAB-01): HIGH — central injection point confirmed; padding forwarding verified; existing clearance precedent (`getSnackbar`) found.
- RangeAlarmSchedule regression risk: MEDIUM — flagged as the top risk; mitigated by a mandatory test rather than left to assumption.
- Test mechanics (`fake_async`): MEDIUM — standard tool, marked assumed with fallback.

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (stable — pinned deps, mature codebase). The table_calendar finding is valid for as long as `pubspec.lock` pins 3.1.1; re-verify if the lockfile bumps `table_calendar`.
