# Phase 2: Snooze Reliability - Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 5 modified source files + 1 new test file (+ 1 optional setting-schema tweak)
**Analogs found:** 6 / 6 (brownfield bug-fix phase — every "analog" is either the *current implementation of the same file* or an in-repo correct-path exemplar)

> **Orientation for the planner:** This phase predominantly **MODIFIES existing files** — there is **no greenfield "copy this whole file" work** except one new test file. For each change, the **Current source** excerpt is the code being fixed, and the **Pattern to follow** excerpt is the in-repo correct path the fix must mirror. The defining insight (confirmed against live `0.6.0+28` source): the **user-list dismiss** (`alarm_screen.dart:188`) already does snooze/dismiss correctly — the **isolate dismiss** (`alarm_isolate.dart:194`) does not. The fix is mostly *wiring the isolate path to the methods the list path already calls*, plus two `.floor()` arithmetic fixes and one missing gate. Do NOT build a new reschedule primitive (reuse the Phase-1 `updateAlarmById`/`updateAlarms` funnel unchanged). Do NOT add a state-management library.

**Line numbers below were re-verified against the live source this session** — they match RESEARCH.md within ±2 lines. Exact confirmed lines are given.

---

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `lib/alarm/types/alarm.dart` (`snooze()` :218-229, `_scheduleSnooze()` :231-238, `handleDismiss()` :309-315, `cancelSnooze()` :240-243, `update()` :323-355) | model (snooze/dismiss state machine) | event-driven (state transitions) | itself + `alarm_screen.dart:188-192` (the correct dismiss) + `cancelSnooze()`/`update()` (the correct building blocks already on the same class) | self / exact |
| `lib/alarm/logic/alarm_isolate.dart` (`stopAlarm` dismiss branch :194, snooze branch :184, `triggerAlarm` re-arm :98) | service (isolate dismiss/snooze path) | event-driven (cross-isolate) | `alarm_screen.dart:188-192 _handleDismissAlarm` (the list dismiss it must mirror) | role-match (cross-path mirror) |
| `lib/alarm/data/alarm_settings_schema.dart` (`Length` SliderSetting :248-257) | config (settings schema) | n/a | the sibling `Max Snoozes` SliderSetting (:258-270) which DOES set `snapLength: 1` | self / exact (in-file sibling) |
| `lib/alarm/screens/alarm_screen.dart` (`_handleDismissAlarm` :188-192) | component (UI dismiss entry point) | request-response | itself — **REFERENCE ONLY, do NOT modify.** This is the correct template the isolate path copies. | reference / exact |
| `lib/alarm/logic/update_alarms.dart` (`updateAlarmById` :62-82, `updateAlarms` :41-60) | service (reschedule + persist funnel) | batch / event-driven | itself — **already idempotent; reuse unchanged**, do NOT edit (Phase-1 spine) | self / exact (preserve) |
| `test/alarm/types/alarm_snooze_test.dart` (NEW) | test (unit) | n/a | `test/alarm/types/schedules/once_alarm_schedule_test.dart` (structure) + `test/alarm/logic/alarm_time.dart` (`withClock`) + `test/alarm/widgets/alarm_card_test.dart` (`Alarm(const Time(...))` construction) | new / multi-analog |

---

## Pattern Assignments

### `lib/alarm/types/alarm.dart` (model, event-driven) — SNZ-02 / SNZ-03 / SNZ-04 (the core of the phase)

**Analog:** itself + the correct dismiss in `alarm_screen.dart:188-192` + the already-correct methods on this same class (`cancelSnooze()` :240-243, `update()` :323-355).

#### SNZ-02 — the two `.floor()` sites (confirmed `:225-227` and `:234`)

**Current source — `snooze()` (`:218-229`), `_scheduleSnooze()` (`:231-238`):**
```dart
Future<void> snooze() async {
  // The alarm can only be snoozed the number of times specified in the settings
  _snoozeCount++;                                   // :220 — NO MAX GATE (SNZ-04)
  // When the alarm rang, it was disabled, so we need to enable it again if the user presses snooze
  _isEnabled = true;                                // :222
  // Snoozing should cancel any skip
  _skippedTime = null;                              // :224
  _snoozeTime = DateTime.now().add(
    Duration(minutes: snoozeLength.floor()),        // :226 — floors 0.5 → 0 (SNZ-02)
  );
  await _scheduleSnooze();                          // :228
}

Future<void> _scheduleSnooze() async {
  await scheduleSnoozeAlarm(
    id,
    Duration(minutes: snoozeLength.floor()),        // :234 — SAME bug, second site (SNZ-02)
    ScheduledNotificationType.alarm,
    "_scheduleSnooze(): Alarm snoozed for $snoozeLength minutes",
  );
}
```

**`snoozeLength` is a `double`** (`:87 double get snoozeLength => _settings.getSetting("Length").value;`), and the `Length` `SliderSetting` has **no `snapLength`** (see schema below) → fractional values are genuinely reachable.

**Fix shape (RESEARCH Pattern 2):** convert to **seconds**, never floor minutes, at **both** sites — change them in the **same edit** or the displayed `_snoozeTime` and the real `AndroidAlarmManager` delay diverge (RESEARCH Pitfall 1). Compute the `Duration` once and pass it down:
```dart
// AFTER (both sites, identical arithmetic):
final seconds = (snoozeLength * 60).round();              // 0.5 → 30, not 0
final delay = Duration(seconds: seconds < 1 ? 1 : seconds); // clamp <= 0 (Claude's discretion on the floor)
```

> **Load-bearing caveat for the test (verified this session):** `snooze()` uses `DateTime.now()` **directly** (`:225`, `:334`), NOT the injectable `clock.now()` from `package:clock`. So `withClock(Clock.fixed(...))` will **not** pin `_snoozeTime` deterministically. The SNZ-02 test must EITHER assert on a tolerance window (`_snoozeTime` is ~30s ahead of `DateTime.now()`, within a few hundred ms) OR the planner may choose to switch `snooze()`'s `DateTime.now()` to `clock.now()` (a small in-scope change that makes the test exact — `package:clock` is already a dependency). Flag this decision to the planner.

#### SNZ-04 — missing max-count gate (confirmed `:220`, gate reads at `:110-113`)

**Current source — `snooze()` increments with no guard** (`:220` above). The only enforcement is UI-display:
```dart
// alarm.dart:110-113 — read at UI display time only, NOT in the mutation:
bool get maxSnoozeIsReached => _snoozeCount >= maxSnoozes;
bool get canBeSnoozed =>
    !maxSnoozeIsReached &&
    _settings.getGroup("Snooze").getSetting("Enabled").value;
// consumed at: alarm_isolate.dart:170 (showSnoozeButton: alarm.canBeSnoozed)
//              alarm_notification_screen.dart (canBeSnoozed ? _snoozeAlarm : null)
```
`maxSnoozes` (`:90`) reads `"Max Snoozes"` (default **3**, schema `:258-270`).

**Fix shape (RESEARCH Pattern 5):** add a **hard gate inside `snooze()`** before `_snoozeCount++`. Per Open Question #1, recommended resolution for over-max is **resolve-as-dismiss** (never leave it ringing — RESEARCH Pitfall 5), not a silent no-op:
```dart
Future<void> snooze() async {
  if (maxSnoozeIsReached) {     // authoritative gate, independent of the hidden button
    await _resolveDismiss();    // treat over-max as a dismiss (safe; see SNZ-03 below)
    return;
  }
  _snoozeCount++;
  // ...
}
```
**Persistence is already correct (SNZ-04 disk side):** `snooze()` runs inside `updateAlarmById` → `saveList("alarms")` (`update_alarms.dart:78`) before the isolate returns; `_snoozeCount` is serialized (`toJson` `:447`) and reloaded (`fromJson` `:410 _snoozeCount = json['snoozeCount'] ?? 0`). The defect is the missing gate, NOT a persistence loss. **Do not** add a new persistence mechanism (RESEARCH Don't-Hand-Roll).

#### SNZ-03 / #457 — the incomplete `handleDismiss()` (confirmed `:309-315`)

**Current source — does NOT cancel snooze, does NOT clear `_snoozeTime`, does NOT disable; marks-for-deletion only if `Delete After Ringing` (default `false`):**
```dart
void handleDismiss() {                                       // :309 — synchronous void
  _snoozeCount = 0;                                          // :310
  if (scheduleType == OnceAlarmSchedule && shouldDeleteAfterRinging ||
      shouldDeleteAfterFinish && isFinished) {               // :311-312
    _markedForDeletion = true;                               // :313
  }
  // ← NO cancelSnooze(); NO _unSnooze(); NO _isEnabled=false; NO update()
}
```
Because `snooze()` set `_isEnabled = true` (`:222`), a snoozed-then-dismissed one-shot survives as enabled, and `triggerAlarm`'s `updateAlarms("...on trigger")` (`alarm_isolate.dart:98`) re-arms it on the next ring — the #457 mechanism.

**Pattern to follow — the list dismiss already does it right (`alarm_screen.dart:188-192`, REFERENCE ONLY):**
```dart
Future<void> _handleDismissAlarm(Alarm alarm) async {
  await alarm.cancelSnooze();                                          // :189 — cancelAlarm(id) + _unSnooze() (alarm.dart:240-243)
  await alarm.update("_handleDismissAlarm(): Alarm dismissed by user"); // :190 — re-evaluates schedule → disables resolved one-shot
  _listController.changeItems((alarms) {});
}
```
**The existing correct building blocks (on `Alarm` itself):**
```dart
// alarm.dart:240-243
Future<void> cancelSnooze() async {
  await cancelAlarm(id, ScheduledNotificationType.alarm);  // cancels the pending OS snooze
  _unSnooze();                                              // _snoozeTime = null (:245-247)
}

// alarm.dart:323-355 — update() already deactivates a resolved schedule:
if (activeSchedule.isDisabled && !isSnoozed) { await disable(); }  // :348 — one-shot disable
if (isFinished) { await finish(); }                                // :351 — DatesAlarmSchedule path
```

**Fix shape (RESEARCH Pattern 3, Open Question #2):** introduce a single `Future<void> _resolveDismiss()` on `Alarm` that does `cancelSnooze()` then `update(...)` (then preserves the existing `_snoozeCount = 0` + mark-for-deletion logic), and call it from BOTH the over-max snooze case (above) and the isolate dismiss branch. Because `handleDismiss()` is currently **`void`** and called **un-awaited** at `alarm_isolate.dart:194`, converting to async REQUIRES updating that call site to `await` (RESEARCH Pitfall 2). `updateAlarmById` already `await`s its callback (`update_alarms.dart:71`), so the change is contained.
- **Covers `DatesAlarmSchedule` too** (#457 generalizes): `DatesAlarmSchedule.isDisabled` is always `false` (`dates_alarm_schedule.dart:36`) — it uses `isFinished` (`:39`). Running `update()` (which calls `finish()` at `:351` when `isFinished`) is what deactivates a finished-dates alarm. This is exactly why the fix must call `update()`, not a hand-rolled one-shot-only branch (RESEARCH Pitfall 4).

---

### `lib/alarm/logic/alarm_isolate.dart` (service, event-driven) — SNZ-03 / SNZ-01 (wire the dismiss path)

**Analog:** `alarm_screen.dart:188-192` (the list dismiss — what this path must become).

**Current source — `stopAlarm` (`:181-197`):**
```dart
void stopAlarm(int scheduleId, AlarmStopAction action) async {
  logger.i("[stopAlarm] Stopping alarm $scheduleId with action: ${action.name}");
  if (action == AlarmStopAction.snooze) {
    await updateAlarmById(scheduleId, (alarm) async => await alarm.snooze());  // :184 — snooze branch (correct funnel)
  } else if (action == AlarmStopAction.dismiss) {
    if (RingingManager.isTimerRinging) { /* resume timer :188-193 */ }
    await updateAlarmById(scheduleId, (alarm) async => alarm.handleDismiss());  // :194 — NOT awaited inside, incomplete dismiss
  }
  RingingManager.stopAlarm();                                                   // :196
}
```
**The #457 re-arm vector — `triggerAlarm` (`:98`):**
```dart
// Note: this won't effect the variable `alarm` as we have already retrieved that
await updateAlarms("triggerAlarm(): Updating all alarms on trigger");           // :98 — re-evaluates EVERY alarm on every ring
```

**Fix shape:** change the dismiss branch callback to `(alarm) async => await alarm._resolveDismiss()` (or the chosen awaited async dismiss). Keep the snooze branch as-is (it already correctly funnels through `updateAlarmById` → `snooze()` → `saveList`). The `triggerAlarm` `updateAlarms("...on trigger")` at `:98` stays unchanged — once dismiss sets `_isEnabled = false`, the re-arm is impossible by construction (the `alarm.isEnabled == false` skip at `:105` then short-circuits). **Mutation MUST stay inside the `updateAlarmById` callback** so `saveList` persists state before isolate teardown (RESEARCH Landmine 1).

---

### `lib/alarm/data/alarm_settings_schema.dart` (config) — SNZ-02 (optional UI hardening, secondary)

**Analog:** the in-file sibling `Max Snoozes` SliderSetting (`:258-270`), which sets `snapLength: 1`.

**Current source — `Length` slider has NO `snapLength` (confirmed `:248-257`):**
```dart
SliderSetting(
    "Length",
    (context) => AppLocalizations.of(context)!.snoozeLengthSetting,
    1,    // min
    30,   // max
    5,    // default
    unit: "minutes",
    // ← NO snapLength → divisions:null → slider_field.dart uses toStringAsFixed(1), fractional reachable
    enableConditions: [
      ValueCondition(["Enabled"], (value) => value == true)
    ]),
```
**Sibling that does it right (`:258-270`):** `Max Snoozes` passes `snapLength: 1`.

**Fix shape (SECONDARY — the model fix in `alarm.dart` is the PRIMARY and mandatory fix):** the model `(snoozeLength*60).round()` correction handles fractional values regardless. Whether to ALSO add `snapLength: 1` (or e.g. `0.5`) to the `Length` slider to constrain the UI is **Claude's discretion** — RESEARCH A2 notes the model fix is correct even if the UI keeps fractional input. Do NOT rely on the slider as the fix.

---

### `lib/alarm/screens/alarm_screen.dart` (component) — REFERENCE ONLY, do NOT modify

**Analog:** itself. `_handleDismissAlarm` (`:188-192`) is the **correct dismiss template** the isolate path mirrors (excerpt above). **No edit to this file is in scope for Phase 2** — it is the source of truth the fix copies. Listed so the planner cites it as the pattern, not as a change target.

---

### `lib/alarm/logic/update_alarms.dart` (service, batch) — REUSE UNCHANGED (Phase-1 spine)

**Analog:** itself — already idempotent; **do NOT edit.** The snooze/dismiss fixes ride this funnel. Confirmed structure:
```dart
// updateAlarmById (:62-82) — the load → mutate-in-callback → save → port-notify primitive:
Future<void> updateAlarmById(int scheduleId, Future<void> Function(Alarm) callback) async {
  List<Alarm> alarms = await loadList("alarms");                 // :64
  int alarmIndex = alarms.indexWhere((a) => a.hasScheduleWithId(scheduleId));
  if (alarmIndex == -1) { return; }                              // :67-69
  Alarm alarm = alarms[alarmIndex];
  await callback(alarm);                                         // :71 — awaits the async mutation (snooze/dismiss)
  if (alarm.isMarkedForDeletion) { await alarm.disable(); alarms.removeAt(alarmIndex); }  // :72-74
  else { alarms[alarmIndex] = alarm; }                          // :75-76
  await saveList("alarms", alarms);                             // :78 — persists BEFORE return (the cross-isolate durability)
  SendPort? sendPort = IsolateNameServer.lookupPortByName(updatePortName);  // :80
  sendPort?.send("updateAlarms");                               // :81
}
```
**Why no edit:** `await callback(alarm)` at `:71` already awaits an async dismiss — so converting `handleDismiss`→`_resolveDismiss` (async) needs NO change here; the callback just becomes `(a) async => await a._resolveDismiss()`. `updateAlarms` (`:41-60`, the `triggerAlarm` re-arm funnel) is also unchanged.

---

### `test/alarm/types/alarm_snooze_test.dart` (NEW unit test) — SNZ-01..05 regression

**No existing snooze unit test** — `grep` confirms snooze is referenced only in `schedule_description_test.dart` and `once_alarm_schedule_test.dart`. This is a Wave-0 gap (new file). Three analogs combine:

**Structure analog — `test/alarm/types/schedules/once_alarm_schedule_test.dart`** (`group`/`setUp`/`test`, `TestWidgetsFlutterBinding.ensureInitialized()`):
```dart
import 'package:flutter_test/flutter_test.dart';
// ...
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();          // required for settings/asset access
  group('Alarm snooze', () {
    setUp(() { /* fresh Alarm per test */ });
    test('...', () async { /* drive snooze()/dismiss, assert on flags */ });
  });
}
```

**Construction analog — `test/alarm/widgets/alarm_card_test.dart:10,16`** (builds a full `Alarm` directly, no storage init — `appSettings` is statically constructed at module load, confirmed RESEARCH §Wave-0):
```dart
var sampleAlarm = Alarm(const Time(hour: 2, minute: 30));   // builds without initializeStorage()
```

**Frozen-clock analog — `test/alarm/logic/alarm_time.dart:1,12-14`** (the ONLY test using `package:clock`):
```dart
import 'package:clock/clock.dart';
withClock(Clock.fixed(currentDate), () { /* ... assertions ... */ });
```
> **Caveat (repeated, load-bearing):** `withClock` only works for code that reads `clock.now()`. `Alarm.snooze()` reads `DateTime.now()` directly — so for SNZ-02 either assert a tolerance window OR switch `snooze()` to `clock.now()` first (see SNZ-02 above).

**Why it runs WITHOUT a device:** `scheduleAlarm`/`cancelAlarm`/`scheduleSnoozeAlarm` short-circuit under `FLUTTER_TEST` (confirmed `schedule_alarm.dart:28,101,136`; `scheduleSnoozeAlarm` also guards `createSnoozeNotification` at `:136`). Tests drive `snooze()`/`_resolveDismiss()` and assert on `Alarm` flags (`snoozeCount`/`isEnabled`/`isSnoozed`/`snoozeTime`), never on the OS (RESEARCH Landmine 6).

**Test matrix to author (from RESEARCH Test Strategy — assert on flags, run in CI):**

| Req | Setup | Assertion |
|-----|-------|-----------|
| SNZ-02 | `Length`=0.5, `snooze()` | `_snoozeTime` ≈ now+30s (tolerance, or exact if switched to `clock.now()`); delay is 30s, not 0 |
| SNZ-03 | OnceAlarm: `snooze()` → dismiss → (`update()` runs inside) | `isEnabled == false` (or `isMarkedForDeletion`), `isSnoozed == false`, no future re-arm |
| SNZ-03 (dates) | `DatesAlarmSchedule` with only past/today date: snooze → dismiss | `isFinished`/disabled; no next-day re-arm |
| SNZ-04 | `Max Snoozes`=2, `snooze()` ×3 | 3rd call does NOT increment to 3 / resolves as dismiss; never leaves ringing |
| SNZ-04 (persist) | `snooze()` → `toJson` → `fromJson` | `snoozeCount` round-trips to incremented value (proves disk durability) |
| SNZ-01/05 | snooze a task-required alarm → `update()` while still before `_snoozeTime` | pending snooze re-scheduled (`update()` `:337`), still `isEnabled && isSnoozed`; never silently disabled |

> Set settings in-test via `alarm.setSettingWithoutNotify("Length", 0.5)` / `setSettingWithoutNotify("Max Snoozes", 2)` (the no-notify mutator, `alarm.dart:175-177`) — or set on the `"Snooze"` subgroup as the getters read (`maxSnoozes` reads `"Max Snoozes"` :90; `snoozeLength` reads `"Length"` :87). The planner should verify the setting path during authoring.

---

## Shared Patterns

### Reuse the Phase-1 idempotent reschedule funnel (do NOT reinvent)
**Source:** `lib/alarm/logic/update_alarms.dart` (`updateAlarmById` :62-82, `updateAlarms` :41-60)
**Apply to:** every snooze/dismiss mutation. All `Alarm` state changes flow through `updateAlarmById(id, (alarm) async => ...)` so they `saveList` + `IsolateNameServer` notify atomically. The dismiss branch becomes `(a) async => await a._resolveDismiss()`; the snooze branch stays `(a) async => await a.snooze()`. **Never mutate an `Alarm` outside this callback** (RESEARCH Landmine 1 — a mutation that forgets `saveList` silently resets `_snoozeCount` on the next ring).

### The list-dismiss is the canonical dismiss
**Source:** `lib/alarm/screens/alarm_screen.dart:188-192` (`cancelSnooze()` then `update()`)
**Apply to:** the isolate dismiss path and the over-max snooze resolution — both must perform the same `cancelSnooze()` + `update()` sequence (factored into `Alarm._resolveDismiss()`). This single shared resolution is what fixes #457 for ALL dismiss entry points.

### Recovery / lifecycle logging (CONVENTIONS.md levels)
**Source:** singleton `logger` (`lib/developer/logic/logger.dart`); existing isolate logs at `alarm_isolate.dart:182,88`
**Apply to:** any new branch — `logger.i` for lifecycle ("[stopAlarm] dismissing / over-max → resolving as dismiss"), `logger.t` for low-level scheduling detail, `logger.f` for isolate-fatal. Reuse the singleton; add NO new logging infra.

### `clock` for deterministic time in tests (with the `DateTime.now()` caveat)
**Source:** `test/alarm/logic/alarm_time.dart:1,12-14` (`withClock(Clock.fixed(...))`)
**Apply to:** the new snooze test — BUT only after deciding whether to switch `Alarm.snooze()`'s `DateTime.now()` (`:225`) to `clock.now()`. If not switched, assert tolerance windows, not exact equality.

### `FLUTTER_TEST` guards make the model unit-testable without a device
**Source:** `lib/alarm/logic/schedule_alarm.dart:28,101,136`
**Apply to:** the new test — drive `snooze()`/`_resolveDismiss()` directly; assert on `Alarm` flags, never on `AndroidAlarmManager` (which no-ops under test).

---

## No Analog Found

None. Every change maps to the current implementation of the same file plus an in-repo correct-path exemplar (`alarm_screen.dart:188` is the dismiss template; `update_alarms.dart` is the reschedule spine; `Max Snoozes` is the `snapLength` sibling). RESEARCH.md patterns supplement, not replace, these.

**The only genuinely new artifact** is the test file `test/alarm/types/alarm_snooze_test.dart` — and even it composes three existing test analogs (structure / construction / frozen-clock). No new fixtures or conftest needed (`Alarm()` builds without storage init).

---

## Open Decisions Surfaced for the Planner (from RESEARCH, confirmed against source)

1. **Over-max snooze → dismiss or no-op?** RESEARCH Open Q1 recommends **dismiss** (never leaves it ringing). The `_resolveDismiss()` factoring assumes this.
2. **`handleDismiss` → async `_resolveDismiss()` vs. fix at the `stopAlarm` call site?** RESEARCH Open Q2 recommends `_resolveDismiss()` on `Alarm` (model owns the state machine, per CLAUDE.md). Requires `await` at `alarm_isolate.dart:194`.
3. **Switch `snooze()` to `clock.now()` for exact tests?** Not in RESEARCH as a requirement, but surfaced here: `snooze()` uses `DateTime.now()` (`:225`), so a frozen-clock SNZ-02 test is inexact unless switched. Cheap (`package:clock` already a dep) and improves testability. Planner's call.
4. **Add `snapLength` to the `Length` slider?** Secondary UI hardening; the model fix is authoritative. Claude's discretion (RESEARCH A2).

---

## Metadata

**Analog search scope:** `lib/alarm/types/`, `lib/alarm/logic/`, `lib/alarm/screens/`, `lib/alarm/data/`, `lib/alarm/utils/`, `test/alarm/` (types, logic, widgets)
**Files read (verified this session):** `alarm.dart` (full), `alarm_isolate.dart` (full), `alarm_screen.dart` (:170-209), `alarm_settings_schema.dart` (:120-299), `update_alarms.dart` (full), `schedule_alarm.dart` (:130-142 + guards), `dates_alarm_schedule.dart` (grep), `alarm_id.dart` (grep), `once_alarm_schedule_test.dart` (full), `alarm_time.dart` (full), `alarm_card_test.dart` (:1-50); test-tree listing; grep for `FLUTTER_TEST` / `clock` / `DateTime.now()`
**Pattern extraction date:** 2026-06-02
