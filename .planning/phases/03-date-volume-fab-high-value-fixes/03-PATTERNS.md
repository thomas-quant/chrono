# Phase 3: Date, Volume & FAB High-Value Fixes - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 8 (5 source modified, 1 source new, 3 tests new)
**Analogs found:** 9 / 9

This phase is **subtractive bug-fixing inside an existing, mature codebase** — every target either has its own current code as the analog (modified files) or a near-identical sibling already in the tree (new files). No file needs a RESEARCH.md fallback; every pattern below is a concrete in-repo excerpt with line numbers. The planner should treat the "current state" excerpts as the exact code each plan edits.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/settings/types/setting.dart` (`DateTimeSetting.valueToJson`/`loadValueFromJson`, 956-967) | model / serializer | transform (JSON round-trip) | itself (current code) + sibling `DurationSetting`/`DateSchedule.toJson` ISO idiom | self (modify) |
| `lib/common/widgets/fields/date_picker_bottom_sheet.dart` (onDaySelected 145-172, onRangeSelected 175-202) | component (UI boundary) | transform (picker output) | itself (current code) | self (modify) |
| `lib/audio/types/ringtone_player.dart` (82-161) | service (static audio wiring) | streaming / event-driven | itself (current code) | self (modify) |
| `lib/audio/types/volume_ramp_controller.dart` **(NEW)** | utility / controller (pure seam) | event-driven (timer ticks) | `lib/alarm/types/alarm_runner.dart` (small stateful holder) + research Pattern 1 | role-match (new) |
| `lib/common/widgets/list/custom_list_view.dart` (390-391 padding) | component (shared list) | request-response (layout) | itself + `snackbar.dart:getSnackbar` clearance math + `fab.dart:67-69` | self (modify) + precedent |
| `test/settings/types/date_time_setting_test.dart` **(NEW)** | test | transform (round-trip) | `test/alarm/types/alarm_snooze_test.dart` + `test/common/utils/date_time_utils_test.dart` | role+flow match |
| `test/audio/types/volume_ramp_controller_test.dart` **(NEW)** | test | event-driven (fake_async ticks) | `test/alarm/types/alarm_snooze_test.dart` (frozen-time pattern) | role-match |
| `test/common/widgets/list/fab_clearance_test.dart` **(NEW)** | test (headless widget) | request-response (layout) | `test/common/widgets/fields/*_test.dart` (headless `pumpWidget`) | role-match |

**Note — `lib/common/widgets/list/persistent_list_view.dart`** is the wrapper, NOT an edit site. Verified at `persistent_list_view.dart:179` it delegates straight to `CustomListView<Item>(...)` and passes **no** padding argument. Therefore the FAB fix belongs in `custom_list_view.dart` (the single point where padding is actually set and forwarded to the scrollable). The planner should NOT add a padding param to `PersistentListView` unless the central edit proves insufficient.

---

## Pattern Assignments

### `lib/settings/types/setting.dart` — `DateTimeSetting` (model / serializer, transform)

**Analog:** itself (current code), plus the sibling ISO-8601 idiom in `DateSchedule.toJson` / `fromJson` (`dates_alarm_schedule.dart:18,24`) which already proves the codebase parses dates with `DateTime.parse(...)` / serializes with `toIso8601String()`.

**Current state — the exact two methods to replace** (`setting.dart:956-967`):
```dart
@override
dynamic valueToJson() {
  return _value.map((e) => e.millisecondsSinceEpoch).toList();   // <-- DATE-01 root cause: epoch instant
}

@override
void loadValueFromJson(dynamic value) {
  if (value == null) return;
  _value = (value as List)
      .map((e) => DateTime.fromMillisecondsSinceEpoch(e))         // <-- reads epoch in LOCAL tz (off-by-one)
      .toList();
}
```

**Pattern to copy for the FIX** (research Pattern 2, `03-RESEARCH.md:220-242`): emit `YYYY-MM-DD` strings from `valueToJson`; in `loadValueFromJson` branch on element type — `String` → split/parse → `DateTime(y,m,d)` (local midnight); legacy `int` → `DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)` then take `.year/.month/.day`. The UTC read is **load-bearing** (table_calendar 3.1.1 = midnight-UTC, confirmed `03-RESEARCH.md:60,479`).

**Sibling ISO idiom already in repo** (`dates_alarm_schedule.dart:18,24` — DO NOT copy the full-ISO form, it re-introduces a time component; shown only to confirm `DateTime.parse` is the house style for string dates):
```dart
date = json['date'] != null ? DateTime.parse(json['date']) : DateTime.now();
// ...
'date': date.toIso8601String(),
```

**Error-handling / validation pattern to apply** (from `03-RESEARCH.md:464,471` Security V5 + Phase-1 salvage principle): guard `split('-')` / `int.parse` against malformed strings — fall back to a safe default date + `logger.e(...)` rather than throw. A corrupt date must never lose the whole alarm list. Use the existing `logger` singleton (`lib/developer/logic/logger.dart`) at `logger.i`/`logger.t` for the legacy-epoch migration trace, `logger.e` for the malformed-value salvage.

**Construction note for the test:** `DateTimeSetting._value` is mutated via `setValueWithoutNotify(...)` / read via `.value`; the constructor uses `valueCopyGetter: List.from` (`setting.dart:938`). The setting is reused by both `DatesAlarmSchedule` (`dates_alarm_schedule.dart:48`) and `RangeAlarmSchedule` (`range_alarm_schedule.dart:32`) — both cast `Setting → DateTimeSetting`.

---

### `lib/common/widgets/fields/date_picker_bottom_sheet.dart` — picker output normalization (component, transform)

**Analog:** itself. The fix is a one-line normalization at the `onDaySelected` and `onRangeSelected` boundaries — strip any time/TZ component to a local calendar date *at the source* (`03-RESEARCH.md:122-123`).

**Current state — `onDaySelected`** (`date_picker_bottom_sheet.dart:145-172`): `table_calendar` hands `newSelectedDate` as **`DateTime.utc(y,m,d)`** (midnight UTC, confirmed). It is stored raw into `_selectedDates` (lines 147, 165) and emitted via `widget.onChanged(_selectedDates)` (line 170). The fix normalizes `newSelectedDate` to `DateTime(newSelectedDate.year, newSelectedDate.month, newSelectedDate.day)` (local) before it enters `_selectedDates`.

**Current state — `onRangeSelected`** (`date_picker_bottom_sheet.dart:175-202`): same raw-UTC dates flow into `_selectedDates` for both range-only (`[startDate, endDate]`, line 185) and the day-by-day expansion loop (lines 190-195). Normalize `startDate`/`endDate` here too so `RangeAlarmSchedule` receives local calendar dates.

**Pre-existing local/UTC mix to be aware of** (line 30, 134, 136): `_focusedDate = DateTime.now()` (local) and `firstDay: DateTime.now()` are mixed with the calendar's UTC days. `isSameDay(...)` (table_calendar, compares y/m/d only) is used for predicate/dedup (lines 142-143, 151) so it is offset-tolerant — but the *stored* value is the UTC one. Only the stored/emitted value needs normalization, not the predicate.

---

### `lib/audio/types/ringtone_player.dart` — static audio wiring (service, streaming/event-driven)

**Analog:** itself. The phase keeps the static class (Tier-1, `03-CONTEXT.md:177-178`) and only swaps the ramp mechanism.

**Current state — the VOL-01 root cause** (`ringtone_player.dart:82-86`, the conflation):
```dart
static Future<void> setVolume(double volume) async {
  logger.t("Setting volume to $volume");
  _stopRisingVolume = true;        // <-- kills the ramp on EVERY volume write (the bug)
  await activePlayer?.setVolume(volume);
}
```

**Current state — the fire-and-forget ramp to REPLACE** (`ringtone_player.dart:118-130`):
```dart
// Gradually increase the volume
if (secondsToMaxVolume > 0) {
  for (int i = 0; i <= 10; i++) {
    Future.delayed(                       // <-- 11 untracked, uncancellable futures -> cross-alarm bleed
      Duration(milliseconds: i * (secondsToMaxVolume * 100)),
      () {
        if (!_stopRisingVolume) {         // <-- shared static flag, the only (broken) cancel signal
          setVolume((i / 10) * volume);
        }
      },
    );
  }
}
```

**Cancel points the new controller must be wired into** (all read in source):
- `playAlarm` (`:45-64`) and `playTimer` (`:66-80`) → call `_play(... secondsToMaxVolume: N ...)`; re-entry must cancel the prior ramp.
- `_play` re-entry (`:88-143`): currently resets `_stopRisingVolume = false` at `:98`; replace with `_rampController.cancel()` then `start(...)`.
- `pause()` (`:145-150`) and `stop()` (`:152-161`): currently `stop()` resets `_stopRisingVolume = false` at `:160`; replace with `_rampController.cancel()`. **These are the dismiss/snooze terminus** — the Phase-2 dismiss paths funnel here (`03-CONTEXT.md:181-183`).

**Decoupling rule to apply** (`03-RESEARCH.md:261,294-298` Pitfall 1): a plain `setVolume(userVol)` (e.g. the live volume port lowering audio while a dismiss task is solved, `alarm_isolate.dart:177-179`) must NOT cancel the ramp. `cancel()` becomes the *only* ramp-stop signal. Remove `_stopRisingVolume = true` from `setVolume`. Default behavior: a volume write does not retarget the ramp (`03-RESEARCH.md:393-396` Open Q1 — minimal correct fix).

---

### `lib/audio/types/volume_ramp_controller.dart` **(NEW)** — pure cancellable ramp (utility/controller, event-driven)

**Analog:** No identical pure timer-controller exists in the codebase, but the closest *structural* template is a small stateful holder with explicit lifecycle. The nearest in-repo shapes:

1. **`lib/alarm/types/alarm_runner.dart`** — a small class owning an external resource (the OS alarm id) with `schedule()` / `cancel()` lifecycle methods and `toJson`/`fromJson`; mirror its "single owned resource + cancel()" shape (but the ramp controller needs **no** JSON — it is transient).
2. **Research Pattern 1 shape** (`03-RESEARCH.md:189-213`) — the planner's design template: injected `void Function(double)` volume callback, single `Timer? _timer`, `start({targetVolume, duration, steps})` that calls `cancel()` first (single-ramp invariant → no cross-alarm bleed), `cancel()` that nulls the timer, `isRunning` getter.

**Class/file conventions to copy** (from CLAUDE.md + repo): `snake_case.dart` filename matching the `UpperCamelCase` class (`volume_ramp_controller.dart` → `VolumeRampController`); `camelCase` methods; `is`-prefixed boolean getter (`isRunning`); `///` doc comment on non-obvious public methods; use the `logger` singleton for lifecycle (`logger.t`).

**Time-injection seam for testability** (`03-RESEARCH.md:214,384` A1): the `clock` package governs `DateTime.now()` only, NOT `Timer` firing. For deterministic unit tests use **`package:fake_async`** — **confirmed available** transitively via `flutter_test` (`pubspec.lock:285-288`). The controller can use a plain `Timer.periodic` and the test wraps it in `fakeAsync((async) { ... async.elapse(...); })`. Fallback (if needed): inject a tick callback. Do **not** add a dependency.

**Volume callback prod wiring:** `(v) => RingtonePlayer.activePlayer?.setVolume(v)` — `activePlayer` is the existing static `AudioPlayer?` (`ringtone_player.dart:18`); `setVolume` on `just_audio`'s `AudioPlayer` returns a `Future` (the callback may ignore the future or be `void` per research Pattern 1; planner to finalize against the `just_audio` signature).

---

### `lib/common/widgets/list/custom_list_view.dart` — central FAB bottom clearance (component, layout)

**Analog:** itself for the injection point; **`snackbar.dart:getSnackbar` (41-69)** for the exact clearance math precedent; **`fab.dart:67-69`** for the Material `+20` rule.

**Current state — the single injection point** (`custom_list_view.dart:383-401`, the hardcoded padding forwarded to the real scrollable):
```dart
SlidableAutoCloseBehavior(
  child: AnimatedReorderableListView(
    longPressDraggable: false,
    buildDefaultDragHandles: false,
    proxyDecorator: (widget, index, animation) =>
        reorderableListDecorator(context, widget),
    items: currentList,
    padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),   // <-- INJECT bottom inset HERE
    isSameItem: (a, b) => a.id == b.id,
    // ...
  ),
)
```
Verified the padding is forwarded to the underlying scrollable: `animated_reorderable_listview.dart:250` → `padding: padding ?? EdgeInsets.zero` (`03-RESEARCH.md:357-358`). Editing this one `EdgeInsets` reserves clearance for **all ~13 FAB screens** (every list renders through `CustomListView`, directly or via `PersistentListView`).

**Clearance math precedent — copy the constants from `getSnackbar`** (`snackbar.dart:51-69`):
```dart
if (fab) {
  // ...
  right = 64 + 16;          // FAB extent (64) + gap (16)
}
if (useMaterialStyle) {
  bottom += 20;             // Material-style extra offset
}
```

**The Material `+20` rule — copy from `fab.dart:67-69`** (the FAB's own bottom offset, must be matched so the inset clears it):
```dart
double bottomPadding = themeSettings.useMaterialStyle
    ? widget.bottomPadding + 20
    : widget.bottomPadding;
```

**How to read `useMaterialStyle` inside `CustomListView`** (it does NOT currently read theme extensions — add the same access `fab.dart:58-59` and `snackbar.dart:30-31` use):
```dart
ThemeSettingExtension themeSettings = theme.extension<ThemeSettingExtension>()!;
// then:  bottom = 8 + <FAB extent> + (themeSettings.useMaterialStyle ? 20 : 0)
```
Import: `package:clock_app/theme/types/theme_extension.dart`.

**Derivation guidance** (`03-RESEARCH.md:251-258,312-315` Pitfall 4): FAB tap target ≈ `16 (pad) + 24 (icon) + 16 (pad)` = 56 (from `fab.dart:84,88`); add the gap and the Material `+20`. Orientation: in landscape there is no `bottomNavigationBar` (`nav_scaffold.dart:230`) and `SafeArea` already wraps the body (`nav_scaffold.dart:252`) — the inset must still clear the FAB but needn't add nav-bar height. Do NOT guess the constant; derive it.

---

### `test/settings/types/date_time_setting_test.dart` **(NEW)** — date round-trip + migration + range safety

**Primary analog:** `test/alarm/types/alarm_snooze_test.dart` (the Phase-2 regression template).
**Secondary analog:** `test/common/utils/date_time_utils_test.dart` (minimal pure-value unit test — `group`/`test`/`expect`, no widget binding).

**Pattern to copy — binding + frozen-clock harness** (`alarm_snooze_test.dart:38,57`):
```dart
// Required so the statically-constructed appSettings schema is reachable.
TestWidgetsFlutterBinding.ensureInitialized();
// ...
await withClock(Clock.fixed(fixedNow), () async { ... });   // pin time the model reads
```

**Pattern to copy — assert on objects/flags only** (`alarm_snooze_test.dart:62-68`): the schedule/OS calls no-op under `FLUTTER_TEST`, so assert on the recovered `.year/.month/.day` and on the `DateTimeSetting.value` list — never on `AndroidAlarmManager`.

**Three required cases** (`03-RESEARCH.md:432-434,446`):
1. **Round-trip:** set a `DateTimeSetting` value → `valueToJson()` → `loadValueFromJson(...)` → assert `.year/.month/.day` preserved. **Assert against `.year/.month/.day`, not `==`**, so the test is TZ-agnostic (CI runs UTC; a `==` test would hide the bug).
2. **Legacy-epoch migration:** feed `loadValueFromJson([DateTime.utc(2026, 6, 7).millisecondsSinceEpoch])` and assert the recovered day is `2026-06-07` regardless of test TZ (`03-RESEARCH.md:309`).
3. **RangeAlarmSchedule safety (TOP regression risk — mandatory):** exercise a range schedule across the date-only round-trip and assert the same fire-date set before/after (`03-RESEARCH.md:300-304,398-401` Pitfall 2). Use `RangeAlarmSchedule(datesRangeSetting, intervalSetting)` (`range_alarm_schedule.dart:31`); it reads `startDate = value.first` / `endDate = value.last` (`:16-17`) and compares `alarmDate.isAfter(endDate)` (`:51`). The `Type`-setting-by-index gotcha from `alarm_snooze_test.dart:105-110` applies if exercising via `Alarm`.

---

### `test/audio/types/volume_ramp_controller_test.dart` **(NEW)** — ramp cancellation, no-bleed, reaches-max

**Analog:** `test/alarm/types/alarm_snooze_test.dart` for the assert-on-flags discipline; **`package:fake_async`** for virtual-time `Timer` control (confirmed available, `pubspec.lock:285-288`).

**Pattern to copy — record callback values, advance virtual time, assert** (`03-RESEARCH.md:435-437,447`):
```dart
// Pseudocode shape — record every volume the callback receives:
final values = <double>[];
final controller = VolumeRampController((v) => values.add(v));
fakeAsync((async) {
  controller.start(targetVolume: 1.0, duration: const Duration(seconds: 10));
  async.elapse(const Duration(seconds: 3));
  controller.cancel();
  final countAtCancel = values.length;
  async.elapse(const Duration(seconds: 10));      // drain any leftover timers
  expect(values.length, countAtCancel);            // NO callback fired after cancel()
});
```

**Three required cases** (`03-RESEARCH.md:435-437`): (1) no callback after `cancel()`/stop/snooze; (2) no cross-alarm bleed — start ramp A, start ramp B, assert no further A-tick after B started (the `start()`-calls-`cancel()`-first invariant); (3) ramp ends at the configured target volume.

---

### `test/common/widgets/list/fab_clearance_test.dart` **(NEW)** — headless list/FAB layout seam

**Analog:** the headless widget tests under `test/common/widgets/fields/*_test.dart` (e.g. `date_picker_field_test.dart`, `switch_field_test.dart`) — they `pumpWidget` a narrowly-scoped widget and assert on layout/finders without the full app shell.

**Pattern to copy — keep it narrow** (`03-CONTEXT.md:88-91`, `03-RESEARCH.md:448`): scope the test to the list/FAB layout seam only (assert the list reserves bottom clearance ≥ FAB extent / the last item is not occluded). Keep minimal to avoid the `appSettings`/storage/l10n singletons that make full-screen widget tests flaky. **Degrades to on-device-only if too flaky** — document if so (D-TEST-COVERAGE). Note the seam reads `theme.extension<ThemeSettingExtension>()` once the central fix lands, so the test must `pumpWidget` with a theme carrying that extension (mirror how `fab.dart`'s tests / any theme-extension widget test sets it up).

---

## Shared Patterns

### Logging (migration / lifecycle)
**Source:** `lib/developer/logic/logger.dart` (the `logger` singleton), levels per CLAUDE.md.
**Apply to:** `setting.dart` (date migration), `ringtone_player.dart` + `volume_ramp_controller.dart` (ramp lifecycle).
```dart
logger.t("Setting volume to $volume");   // ringtone_player.dart:83 — existing usage
// use: logger.i/.t for legacy-epoch migration trace; logger.e for malformed-value salvage.
```

### Tolerant deserialization / salvage (never crash the list)
**Source:** Phase-1 BOOT-04 salvage principle + `03-RESEARCH.md:464,471`; existing tolerant load in `dates_alarm_schedule.dart:18` (`json['date'] != null ? ... : DateTime.now()`).
**Apply to:** `DateTimeSetting.loadValueFromJson` — accept both `String` and legacy `int`, catch parse errors, fall back to a safe default + `logger.e`. A corrupt date must never lose the whole alarm list.

### Frozen-clock / headless-binding test harness
**Source:** `test/alarm/types/alarm_snooze_test.dart:38,57`.
**Apply to:** all three new tests (binding for `appSettings`-reachable construction; `withClock(Clock.fixed(...))` where the model reads `clock.now()` — note the ramp `Timer` needs `fake_async`, NOT `clock`).
```dart
TestWidgetsFlutterBinding.ensureInitialized();
await withClock(Clock.fixed(fixedNow), () async { ... });
```

### Theme-extension access (for the FAB clearance math)
**Source:** `fab.dart:58-59`, `snackbar.dart:30-31`.
**Apply to:** `custom_list_view.dart` (to read `useMaterialStyle` for the `+20` inset).
```dart
ThemeSettingExtension themeSettings = theme.extension<ThemeSettingExtension>()!;
```

### Material `+20` clearance constant
**Source:** `fab.dart:67-69` (FAB's own bottom offset) + `snackbar.dart:67-69` (snackbar mirror).
**Apply to:** the `custom_list_view.dart` bottom inset — must match the FAB's offset so the inset clears it.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | Every target has either its own current code (modified files) or a near-identical in-repo sibling (new files). `volume_ramp_controller.dart` is the only genuinely *new* concept, but `alarm_runner.dart`'s "single owned resource + `cancel()`" shape plus research Pattern 1 fully template it. No file falls back to RESEARCH.md-only patterns. |

---

## Metadata

**Analog search scope:** `lib/settings/types/`, `lib/audio/types/`, `lib/common/widgets/fields/`, `lib/common/widgets/list/`, `lib/common/utils/`, `lib/alarm/types/schedules/`, `lib/alarm/logic/`, `test/` (full tree listed).
**Files scanned (read in full or targeted ranges):** `setting.dart` (920-999), `ringtone_player.dart` (full), `date_picker_bottom_sheet.dart` (full), `fab.dart` (full), `snackbar.dart` (full), `custom_list_view.dart` (1-120, 370-408), `range_alarm_schedule.dart` (full), `dates_alarm_schedule.dart` (full), `alarm_time.dart` (full), `alarm_snooze_test.dart` (full), `date_time_utils_test.dart` (1-32); `pubspec.lock` grep (fake_async/clock/table_calendar); `test/` tree enumeration.
**Pattern extraction date:** 2026-06-05
