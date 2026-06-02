# Phase 2: Snooze Reliability - Research

**Researched:** 2026-06-02
**Domain:** Flutter/Dart Android alarm app — snooze state machine across an alarm-firing isolate ↔ main isolate boundary
**Confidence:** HIGH (every root cause confirmed at file:line against the actual 0.6.0+28 source; both GitHub issues #457 and #495 read directly via the REST API)

## Summary

Phase 2 fixes the snooze cluster (SNZ-01..05) in Chrono's alarm engine. Unlike a greenfield phase, every defect here is a *diagnosed* bug with a named file and line — confirmed this session against the live source (`lib/alarm/types/alarm.dart`, `lib/alarm/logic/alarm_isolate.dart`, `lib/notifications/logic/alarm_notifications.dart`, `lib/alarm/logic/schedule_alarm.dart`, and the five `AlarmSchedule` subtypes). The app version on disk (`pubspec.yaml: 0.6.0+28`) exactly matches the version both issue reporters filed against (0.6.0), so the code being read is the code that exhibits the bugs.

The dominant structural finding is that Chrono has **two different dismiss paths that do different things**: the user-facing list dismiss (`alarm_screen.dart:188 _handleDismissAlarm`) correctly calls `cancelSnooze()` THEN `update()`, whereas the notification/isolate dismiss path (`alarm_isolate.dart:194 stopAlarm` → `handleDismiss()`) cancels nothing and re-arms nothing. `handleDismiss()` (`alarm.dart:309-315`) only sets `_snoozeCount=0` and *conditionally* marks-for-deletion (gated on `Delete After Ringing`, which defaults to **false**). It never cancels the pending snooze alarm in `AndroidAlarmManager`, never clears `_snoozeTime`, and never sets `_isEnabled=false`. Because `snooze()` set `_isEnabled=true`, a snoozed-then-dismissed one-shot survives as "enabled," and the next `updateAlarms()` (which `triggerAlarm` calls on *every* ring, `alarm_isolate.dart:98`) re-evaluates and re-arms it — this is the exact #457 mechanism, and it generalizes to `DatesAlarmSchedule` ("On Specified Days") just as the reporter observed.

The other four findings are tightly localized: `snoozeLength.floor()` at `alarm.dart:226` and `:234` floors a fractional `Length` slider value to whole minutes (SNZ-02) — and the `Length` slider has **no `snapLength`** (`alarm_settings_schema.dart:248-257`), so fractional values are genuinely reachable through the existing UI; `snooze()` (`alarm.dart:218-229`) has **no max-count gate** — the only enforcement is hiding the snooze *button* via `canBeSnoozed`, a UI-display check, with no guard in the mutation itself (SNZ-04); and the snooze-vs-dismiss action routing (SNZ-01/SNZ-05) is correct in the notification action handlers but the *effect* of dismiss is broken (#495's "snoozing just disables my alarm" is the symptom of the dismiss-path/re-arm interaction, not a misrouted button).

**Primary recommendation:** Treat snooze as a small explicit state machine and fix it at three sites — (1) replace both `.floor()` calls with `Duration(seconds: (snoozeLength * 60).round())` clamped to a sane minimum; (2) make the isolate **dismiss** path do what the user-list dismiss already does — `cancelSnooze()` + deactivate/`update()` — branching one-shot/dates schedules to inactive instead of re-arm; (3) add a hard `maxSnoozeIsReached` gate **inside** `snooze()` (not just on the button). Reuse Phase 1's idempotent reschedule funnel (`updateAlarms`/`updateAlarmById` → `saveList` → `IsolateNameServer` notify) unchanged — do NOT build a new reschedule primitive.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SNZ-01 | Snoozing reliably re-rings after the configured length (snooze never silently fails to re-fire) | Root cause is the dismiss/re-arm interaction (not action misrouting). The snooze action IS routed correctly (`alarm_notifications.dart:230` → `snoozeAlarm` → `stopAlarm(...snooze)` → `alarm.snooze()` → `scheduleSnoozeAlarm`). Fix: keep snooze a separate pending one-shot; ensure `_scheduleSnooze` uses a non-zero duration (see SNZ-02) so it doesn't "snooze to now." Pattern §1, §3. |
| SNZ-02 | Fractional snooze lengths honored (no flooring sub-minute/decimal to zero) | `alarm.dart:226` and `:234` both call `Duration(minutes: snoozeLength.floor())`; `snoozeLength` is a `double` (`alarm.dart:87`) backed by a `SliderSetting` with NO `snapLength` (`alarm_settings_schema.dart:248-257`, min 1 / max 30 / default 5). Fix: `Duration(seconds: (snoozeLength * 60).round())` at both sites, clamp `<= 0`. Pattern §2. |
| SNZ-03 | One-shot snoozed-then-dismissed becomes inactive, does NOT reschedule next day (#457) | `handleDismiss()` (`alarm.dart:309-315`) does not cancel the pending snooze, does not clear `_snoozeTime`, does not set `_isEnabled=false`; marks-for-deletion only if `Delete After Ringing` (default **false**, `alarm_settings_schema.dart:131-138`). Snoozed alarm has `_isEnabled=true` (`alarm.dart:222`). Next `updateAlarms()` (`alarm_isolate.dart:98`) re-arms it. Also affects `DatesAlarmSchedule` per the issue. Fix: branch dismiss to deactivate one-shot/finished-dates + cancel pending snooze. Pattern §3, §4. |
| SNZ-04 | Max snooze count enforced AND persists across the alarm/main isolate boundary | `snooze()` (`alarm.dart:218-229`) does `_snoozeCount++` with **no gate**. `canBeSnoozed`/`maxSnoozeIsReached` (`alarm.dart:110-113`) are only read at UI-display time (`alarm_isolate.dart:170`, `alarm_notification_screen.dart:82,87`). Persistence: `_snoozeCount` IS serialized (`alarm.dart:447`) and reloaded (`:410`), and `snooze()` saves via `updateAlarmById`→`saveList` (`update_alarms.dart:78`) — so it persists on disk; the bug is the missing hard gate, plus a reset path to verify. Fix: gate inside `snooze()`. Pattern §5. |
| SNZ-05 | Snoozing re-rings without unintentionally dismissing (#495) | Action routing is correct (`snoozeActionKey`/`dismissActionKey` distinct, `alarm_notifications.dart:229-236`; snooze excluded from the task-gate at `:212`). #495 ("snoozing just disables my alarm, never rings again") is the *downstream* symptom of the same dismiss/re-arm/`.floor()` cluster, not a misrouted intent. Fix is the union of SNZ-01/02/03; add a guard so a snooze can never resolve to a disabled-and-not-rescheduled state. Pattern §1, §6 (Landmines). |
</phase_requirements>

## User Constraints

> No `02-CONTEXT.md` exists yet (Phase 2 has not been through `/gsd-discuss-phase`). The constraints below are carried from CLAUDE.md, the milestone research, and the STATE.md decision log — the planner should treat these as locked unless a CONTEXT.md supersedes them.

### Locked Decisions (from CLAUDE.md + STATE.md)
- **Reliability before feature** — snooze must do its one job; no new features layered on (Out-of-Scope: PRs #515 custom snooze, #475 fat button — `REQUIREMENTS.md:86`).
- **No state-management library** — `setState` + `ListenerManager` + `IsolateNameServer` ports only. The snooze state machine lives on the `Alarm` model + the existing ports; introduce NO Riverpod/Bloc/Provider.
- **Settings are string-keyed `SettingGroup`s serialized to JSON** — `_snoozeCount`/`_snoozeTime` already ride the `Alarm` JSON; keep that contract (no schema migration).
- **Reuse Phase 1's idempotent reschedule primitive** (`updateAlarms`/`updateTimers`/`updateAlarmById` → cancel-by-stable-id then schedule → `saveList` → port notify). Confirmed idempotent and preserved unchanged in Phase 1 (01-02-SUMMARY). Do NOT build a parallel reschedule path.
- **Background execution boundary** — the snooze decision originates in the notification UI (main isolate) but the mutation runs in the alarm-firing isolate (`alarm_isolate.dart`). State must be persisted to disk inside the isolate callback before `RingingManager.stopAlarm()` so it survives the isolate teardown.
- **minSdk 23 / Flutter 3.22.x / Dart 3.4+** — no new deps needed for this phase (pure code fix).
- **No toolchain in this environment** — `flutter analyze`/`flutter test`/`dart` are CI/human gates, NOT runnable here. Tests may be *authored* but not *executed* locally. (`config.json: nyquist_validation=false` — no formal Validation Architecture section required, but Phase 2 is highly testable; see Test Strategy below.)

### Claude's Discretion
- The exact shape of the "deactivate on dismiss" branch (a new method vs. inlining into `handleDismiss`, and whether to call `update()` or a narrower deactivate).
- The clamp minimum for a fractional snooze (e.g. floor at 1s, or reject `< some threshold`).
- Whether the max-count gate lives in `snooze()` (recommended) and/or is also surfaced as a no-op early-return.

### Deferred Ideas (OUT OF SCOPE)
- Custom snooze durations (#515), fat snooze button (#475) — explicitly out (`REQUIREMENTS.md:86`).
- DST recurring-alarm recompute (#359) — deferred to v2.
- Date off-by-one (DATE-01/02), rising volume (VOL-01), FAB (FAB-01) — Phase 3.
- Any scanner/camera work — Phase 4.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Snooze duration → `Duration` conversion | Domain model (`Alarm.snooze`/`_scheduleSnooze`) | — | The `snoozeLength` double lives on the alarm's `SettingGroup`; conversion belongs on the model, not the UI or scheduler. |
| Scheduling the pending snooze re-ring | Scheduler (`schedule_alarm.dart scheduleSnoozeAlarm`) → `AndroidAlarmManager` | OS alarm manager | One-shot `oneShotAt` under the alarm's stable `scheduleId`; the scheduler already cancels-then-sets by id (idempotent). |
| Snooze ↔ dismiss action routing | Notification handlers (`alarm_notifications.dart`) | Notification screen (main isolate) | Distinct action keys; the handler maps button → `AlarmDismissType`; correct today. |
| Mutating snooze count / snooze time / enabled flag | Domain model (`Alarm`), executed in **alarm-firing isolate** via `updateAlarmById` | Persistence (`saveList`) | Mutation runs in the firing isolate (`stopAlarm`), must persist before isolate teardown. This is the isolate-boundary landmine. |
| Deactivating a resolved one-shot/dates schedule on dismiss | Domain model (`Alarm.handleDismiss` + schedule subtype) | Scheduler (cancel) | The schedule-type branch (one-shot/dates → inactive) is a model concern; cancellation flows to the scheduler. |
| Max-count enforcement | Domain model (`Alarm.snooze` gate) | UI (button visibility — secondary, not authoritative) | The authoritative gate must be in the mutation, not the button. |

## Standard Stack

No new dependencies. This is a pure code fix on existing primitives.

### Core (existing, reused)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `android_alarm_manager_plus` (git fork) | 4.0.1 | `oneShotAt` exact alarm scheduling for the snooze re-ring | Already the app's alarm backbone; `scheduleSnoozeAlarm` wraps it. |
| Dart `dart:isolate` / `IsolateNameServer` | SDK | Cross-isolate `stopAlarmPort` / `updatePort` signalling | The app's established isolate-boundary mechanism (CLAUDE.md). |
| `clock` | ^1.1.1 | Mockable `DateTime.now()` for snooze-time tests | Already a dependency; enables frozen-time snooze tests without a device. |
| `flutter_test` | SDK | Unit tests for snooze duration / dismiss state machine | Existing test framework; `test/alarm/types/schedules/once_alarm_schedule_test.dart` is the template. |

**Installation:** none.

## Package Legitimacy Audit

Not applicable — Phase 2 installs **zero** external packages. No `pubspec.yaml` change. (slopcheck/registry verification N/A by construction.)

## Architecture Patterns

### Snooze/Dismiss Data Flow (current — with defect annotations)

```
                          ALARM-FIRING ISOLATE                         MAIN ISOLATE
                          (triggerScheduledNotification)               (UI / notification screen)

  AndroidAlarmManager fires  ──►  triggerAlarm(scheduleId)
                                    │ updateAlarms("...on trigger")  ◄── (alarm_isolate.dart:98)
                                    │      ▲ RE-ARM VECTOR for #457 (re-evaluates a
                                    │      │ snoozed-then-dismissed enabled one-shot)
                                    │ RingtonePlayer.playAlarm + showAlarmNotification
                                    │   showSnoozeButton: alarm.canBeSnoozed  (UI-only gate, :170)
                                    ▼
                          registers stopAlarmPort (ReceivePort)
                                    │
                                    │   user taps SNOOZE/DISMISS button ──► handleAlarmNotificationAction
                                    │                                        (alarm_notifications.dart:220)
                                    │                                          snoozeActionKey → snooze
                                    │                                          dismissActionKey → dismiss
                                    │   ◄── stopAlarmPort.send([id,type,action]) ── stopAlarm(...) (:144)
                                    ▼
                          stopScheduledNotification → stopAlarm(id, action)  (alarm_isolate.dart:181)
                            │
              SNOOZE branch │ updateAlarmById(id, alarm.snooze())            (:184)
                            │   snooze(): _snoozeCount++  ◄── NO MAX GATE (SNZ-04)   (alarm.dart:220)
                            │            _isEnabled = true                          (:222)
                            │            _snoozeTime = now + Duration(minutes: snoozeLength.floor())
                            │                                  ▲ .floor() → 0 for fractional (SNZ-02) (:226)
                            │            _scheduleSnooze()  → Duration(minutes: snoozeLength.floor())  (:234)
                            │   saveList("alarms")  ◄── persists _snoozeCount (SNZ-04 OK on disk)
                            │
             DISMISS branch │ updateAlarmById(id, alarm.handleDismiss())     (:194)
                            │   handleDismiss(): _snoozeCount = 0                   (alarm.dart:310)
                            │     marks-for-deletion ONLY if Delete-After-Ringing (default FALSE) (:311)
                            │     ▲ DOES NOT cancelSnooze(), DOES NOT _unSnooze(),
                            │       DOES NOT set _isEnabled=false  ◄── SNZ-03 / #457 ROOT CAUSE
                            ▼
                          RingingManager.stopAlarm()
```

Contrast — the **user-list dismiss** does it correctly (`alarm_screen.dart:188`):
```dart
Future<void> _handleDismissAlarm(Alarm alarm) async {
  await alarm.cancelSnooze();                 // cancels pending snooze + _unSnooze()
  await alarm.update("...dismissed by user"); // re-evaluates schedule → disables resolved one-shot
}
```
The fix for SNZ-03 is essentially: **make the isolate dismiss path do what the list dismiss path already does.**

### Pattern 1: Snooze as an explicit state machine (the target shape)

**What:** Model post-ring transitions as `ringing → (snooze[count<max] → snoozed → ringing)* → dismissed/inactive`. Make the illegal transition (re-arm a dismissed one-shot) impossible by construction.
**When to use:** All of SNZ-01..05 — every fix is a transition in this machine.
**Example (sketch, grounded in existing methods):**
```dart
// In snooze(): gate the transition (SNZ-04)
Future<void> snooze() async {
  if (maxSnoozeIsReached) {            // hard gate, not just the hidden button
    await _resolveDismiss();           // treat over-max snooze as a dismiss
    return;
  }
  _snoozeCount++;
  _isEnabled = true;
  _skippedTime = null;
  final seconds = (snoozeLength * 60).round();        // SNZ-02: seconds, not floored minutes
  final delay = Duration(seconds: seconds < 1 ? 1 : seconds);  // clamp (SNZ-02 discretion)
  _snoozeTime = DateTime.now().add(delay);
  await scheduleSnoozeAlarm(id, delay, ScheduledNotificationType.alarm,
      "_scheduleSnooze(): Alarm snoozed for $snoozeLength minutes");
}

// New explicit dismiss resolution shared by the isolate path (SNZ-03/#457)
Future<void> _resolveDismiss() async {
  _snoozeCount = 0;
  await cancelSnooze();                 // cancels the pending AndroidAlarmManager snooze + _unSnooze()
  // Deactivate a resolved one-shot / finished-dates so it never re-arms:
  await update("handleDismiss(): re-evaluate schedule after dismiss");
  // update() already disables when activeSchedule.isDisabled && !isSnoozed (alarm.dart:348)
  if (scheduleType == OnceAlarmSchedule && shouldDeleteAfterRinging ||
      shouldDeleteAfterFinish && isFinished) {
    _markedForDeletion = true;
  }
}
```
> Note: `cancelAlarm`/`scheduleSnoozeAlarm`/`update` are all no-ops or guarded under `FLUTTER_TEST` (`schedule_alarm.dart:28,101,136`), so this is unit-testable without a device — assert on the resulting `Alarm` flags, not on `AndroidAlarmManager`.

### Pattern 2: Fractional duration conversion (SNZ-02)
**What:** Convert the `double` minutes to integer **seconds**, never floor to integer minutes.
**Source:** `alarm.dart:226` and `:234` (the two `.floor()` sites).
```dart
// BEFORE (both sites):  Duration(minutes: snoozeLength.floor())
// AFTER:                Duration(seconds: (snoozeLength * 60).round())   // 0.5 → 30s, not 0
```
Both sites must change together — `snooze()` (for the displayed `_snoozeTime`) and `_scheduleSnooze()` (for the actual `AndroidAlarmManager` delay), or the displayed re-ring time and the real re-ring time diverge.

### Pattern 3: Make the isolate dismiss path deactivate (SNZ-03)
**What:** The notification/isolate dismiss must cancel the pending snooze AND deactivate a resolved one-shot/dates schedule — the list-dismiss already does (`alarm_screen.dart:189-190`).
**Where:** Either fix `handleDismiss()` to be `async` and do the cancel+update (and update the caller `alarm_isolate.dart:194` to `await`), OR add the cancel+update at the `stopAlarm` dismiss branch (`alarm_isolate.dart:186-195`). Recommended: a single `_resolveDismiss()` (Pattern 1) called from both the isolate dismiss branch and reused by the over-max snooze case.
**Caveat:** `handleDismiss()` is currently synchronous (`void`, `alarm.dart:309`) and called as `alarm.handleDismiss()` (no await) at `alarm_isolate.dart:194`. Converting it to `Future<void>` requires updating that call site to `await`. `updateAlarmById` already awaits its callback (`update_alarms.dart:71`), so the change is contained.

### Pattern 4: One re-arm funnel, reused (Phase 1 spine)
**What:** Do NOT add a new reschedule path. `update()` → `schedule()` already cancels-then-schedules the active schedule and disables a resolved one-shot (`alarm.dart:348`). `updateAlarmById`/`updateAlarms` already `saveList` + notify via `IsolateNameServer` (`updatePortName`). Phase 1 confirmed this funnel idempotent and preserved it (01-02-SUMMARY: "the D-08 spine Phases 2 and 4 reuse").
**Reuse targets (exact names):**
- `updateAlarmById(int, Future<void> Function(Alarm))` — `lib/alarm/logic/update_alarms.dart:62` (load → mutate → save → port-notify; already handles `isMarkedForDeletion`).
- `updateAlarms(String)` — `update_alarms.dart:41` (cancel-all → reschedule-all → save → notify).
- `cancelAlarm(int, type)` / `scheduleAlarm(...)` / `scheduleSnoozeAlarm(...)` — `lib/alarm/logic/schedule_alarm.dart` (cancel-by-id then `oneShotAt`).
- `Alarm.cancelSnooze()` / `Alarm.update()` — `alarm.dart:240` / `:323` (the correct dismiss building blocks).

### Pattern 5: Authoritative max-count gate (SNZ-04)
**What:** Move enforcement from the UI (button visibility) into the mutation. `canBeSnoozed` (`alarm.dart:111`) stays as the button-visibility hint, but `snooze()` must independently refuse (or resolve-to-dismiss) when `maxSnoozeIsReached`. Belt-and-suspenders: the notification screen / notification already hide the button when `!canBeSnoozed`, but the gate must not *rely* on the UI.

### Anti-Patterns to Avoid
- **Mutating the recurring schedule to implement snooze** — snooze is a *separate pending one-shot* under the alarm's `scheduleId`; it must not alter `OnceAlarmSchedule._isDisabled` or the recurring schedules. (Today `snooze()` correctly schedules a separate alarm via `scheduleSnoozeAlarm`; preserve that.)
- **Relying on the hidden snooze button as the max-count enforcement** — the gate must be in `snooze()` (SNZ-04).
- **Flooring fractional minutes** — `(snoozeLength*60).round()` seconds, never `.floor()` minutes.
- **Leaving `handleDismiss()` synchronous and incomplete** — it must cancel the pending snooze and deactivate resolved schedules; doing only `_snoozeCount=0` is the #457 bug.
- **Adding a second reschedule path** — reuse `update()`/`updateAlarmById`; do not reinvent cancel-then-schedule.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Re-scheduling the snooze re-ring | A bespoke `Timer`/`Future.delayed` in the isolate | `scheduleSnoozeAlarm` → `AndroidAlarmManager.oneShotAt` (`schedule_alarm.dart:132`) | Survives process death / Doze; a Dart `Timer` dies with the isolate. |
| Cancel-then-reschedule by id | A new idempotent primitive | `update()`/`updateAlarmById`/`updateAlarms` (Phase 1 spine) | Already idempotent (cancel-by-stable-id then set), already saves + notifies. |
| Persisting snooze count across isolates | A new shared-memory/port-state mechanism | The existing `Alarm` JSON (`snoozeCount` field, `alarm.dart:447`/`:410`) saved via `saveList` | Already serialized; the disk is the cross-isolate source of truth. |
| Cancelling the pending snooze on dismiss | New cancellation bookkeeping | `Alarm.cancelSnooze()` (`alarm.dart:240`) — already cancels by id + `_unSnooze()` | Exists and is used by the list-dismiss path. |
| Deactivating a resolved one-shot | Schedule-type if/else scattered in the isolate | `Alarm.update()` (`alarm.dart:323`) — disables when `activeSchedule.isDisabled && !isSnoozed` | The deactivation logic already exists; the dismiss path just isn't calling it. |

**Key insight:** Every building block for a correct snooze already exists in the codebase — the list-dismiss path proves it. The bugs are almost entirely *the isolate dismiss path not calling the right existing methods*, plus two `.floor()` calls and a missing gate. This is a wiring + arithmetic fix, not new machinery.

## Runtime State Inventory

> Rename/refactor-style audit. Phase 2 changes *behavior*, not stored shapes, so most categories are empty — but the snooze-count-across-isolates question demands explicit answers.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | `Alarm` JSON in `<appdocs>/alarms.txt`: `snoozeCount` (int), `snoozeTime` (epoch ms or null), `enabled` (bool), per-schedule `isDisabled`/`isFinished`, `markedForDeletion`. All already serialized (`alarm.dart:441-452`). **No schema change needed** — the fix changes *when/how* these are written, not their shape. | Code edit only. No data migration. Old persisted alarms load unchanged (fields already present; `snoozeCount` defaults to 0 via `?? 0`). |
| **Live service config** | `AndroidAlarmManager` pending alarms keyed by `scheduleId` (the snooze re-ring is a real OS-registered `oneShotAt`). A snoozed-then-dismissed alarm currently leaves a **pending OS alarm uncancelled** (the SNZ-03 leak). | The dismiss fix (`cancelSnooze()` → `cancelAlarm` → `AndroidAlarmManager.cancel`) cancels it. No manual ops; happens via the code fix at runtime. |
| **OS-registered state** | None beyond the `AndroidAlarmManager` entries above. No Task Scheduler / launchd / pm2 equivalents (Android alarm app). | None. |
| **Secrets/env vars** | None — snooze touches no secrets/keys. | None. |
| **Build artifacts** | None — pure Dart change, no package rename, no codegen. (Unlike Phase 1's `alarmsResetNotice` ARB key, Phase 2 needs no new l10n string unless a user-facing snooze message is added — none required by SNZ-01..05.) | None, unless the planner adds a user-facing string (then `flutter gen-l10n` is a CI gate). |

**Cross-isolate snooze-count persistence (the load-bearing question for SNZ-04):** The count IS durable on disk — `snooze()` runs inside `updateAlarmById`, which calls `saveList("alarms", alarms)` (`update_alarms.dart:78`) **before** the isolate returns, and `triggerAlarm` re-loads from disk on the next ring (`getAlarmById` → `loadListSync`, `alarm_id.dart:6`). So the count does NOT live only in isolate memory. The genuine SNZ-04 defect is the **missing hard gate in `snooze()`**, not a persistence loss. See Landmines for the one scenario where persistence *could* be at risk.

## Common Pitfalls

### Pitfall 1: Fixing only one `.floor()` site
**What goes wrong:** Changing `_scheduleSnooze()` (`:234`) but not `snooze()` (`:226`) makes the alarm re-ring at the right time but display the wrong `snoozeTime`, or vice versa.
**Why it happens:** The duration is computed twice, independently.
**How to avoid:** Change both `alarm.dart:226` and `:234` in the same edit; ideally compute the `Duration` once and pass it to `_scheduleSnooze`.
**Warning signs:** The "Snoozed until HH:MM" notification time disagrees with when it actually rings.

### Pitfall 2: Making `handleDismiss()` async without updating its call site
**What goes wrong:** `handleDismiss()` is `void` today and called without `await` (`alarm_isolate.dart:194`). If made `Future<void>` and the call isn't awaited, the save in `updateAlarmById` races the dismiss mutation.
**How to avoid:** Convert the call to `await alarm.handleDismiss()` (or `_resolveDismiss()`); `updateAlarmById` already `await`s the callback, so wrap the async dismiss in the callback.
**Warning signs:** Intermittent #457 recurrence — sometimes deactivates, sometimes re-arms.

### Pitfall 3: Treating SNZ-05/#495 as an action-routing bug
**What goes wrong:** You search for a snooze button that calls dismiss and find none (because there isn't one — routing is correct). Time lost.
**Why it happens:** The symptom ("snoozing disables my alarm") sounds like misrouting but is the dismiss/re-arm/`.floor()` cluster. #495's reporter had a **math task** and 5-min snooze; the snooze interplay with `update()`'s snooze-reschedule (`alarm.dart:333-339`) plus a correct duration is what matters.
**How to avoid:** Verify routing once (it's fine), then fix the state machine. Add a regression test: snooze a task-alarm, advance time, assert it re-rings (re-arms a pending snooze) and is still `isEnabled` with `isSnoozed==true`.

### Pitfall 4: Forgetting `DatesAlarmSchedule` (#457 generalizes)
**What goes wrong:** Fixing only `OnceAlarmSchedule` deactivation; the reporter explicitly hit it on "On Specified Days" too.
**How to avoid:** The deactivation branch should cover "resolved/finished" schedules generally — `OnceAlarmSchedule` (disabled when its single time has passed) and `DatesAlarmSchedule` (`isFinished` when no future dates). `update()` already handles `isFinished → finish()` (`alarm.dart:351`); ensure the dismiss path runs `update()` so both get evaluated.

### Pitfall 5: Over-max snooze leaves the alarm ringing forever
**What goes wrong:** If `snooze()` simply early-returns when `maxSnoozeIsReached`, but the UI still allowed the tap, the alarm neither snoozes nor stops.
**How to avoid:** When `maxSnoozeIsReached`, resolve as a **dismiss** (stop + deactivate), not a silent no-op. The notification already hides the snooze button past max (`canBeSnoozed`, `alarm_isolate.dart:170`), so this is a belt-and-suspenders path — but it must be safe.

## Code Examples

### The two `.floor()` sites (SNZ-02) — exact current source
```dart
// lib/alarm/types/alarm.dart:225-227  (in snooze())
_snoozeTime = DateTime.now().add(
  Duration(minutes: snoozeLength.floor()),   // ← floors 0.5 → 0
);

// lib/alarm/types/alarm.dart:231-238  (in _scheduleSnooze())
Future<void> _scheduleSnooze() async {
  await scheduleSnoozeAlarm(
    id,
    Duration(minutes: snoozeLength.floor()),  // ← same bug
    ScheduledNotificationType.alarm,
    "_scheduleSnooze(): Alarm snoozed for $snoozeLength minutes",
  );
}
```

### The incomplete dismiss (SNZ-03/#457) — exact current source
```dart
// lib/alarm/types/alarm.dart:309-315
void handleDismiss() {
  _snoozeCount = 0;
  if (scheduleType == OnceAlarmSchedule && shouldDeleteAfterRinging ||
      shouldDeleteAfterFinish && isFinished) {
    _markedForDeletion = true;
  }
  // ← NO cancelSnooze(); NO _unSnooze(); NO _isEnabled=false; NO update()
}

// lib/alarm/logic/alarm_isolate.dart:186-195  (dismiss branch)
} else if (action == AlarmStopAction.dismiss) {
  if (RingingManager.isTimerRinging) { /* resume timer */ }
  await updateAlarmById(scheduleId, (alarm) async => alarm.handleDismiss()); // not awaited inside
}
```

### The CORRECT dismiss already exists (the template) — `alarm_screen.dart:188-192`
```dart
Future<void> _handleDismissAlarm(Alarm alarm) async {
  await alarm.cancelSnooze();                                  // cancels pending snooze
  await alarm.update("_handleDismissAlarm(): Alarm dismissed by user"); // re-evaluates → disables resolved one-shot
  _listController.changeItems((alarms) {});
}
```

### The missing max-count gate (SNZ-04) — exact current source
```dart
// lib/alarm/types/alarm.dart:218-229
Future<void> snooze() async {
  _snoozeCount++;          // ← no `if (maxSnoozeIsReached)` guard before this
  _isEnabled = true;
  _skippedTime = null;
  _snoozeTime = DateTime.now().add(Duration(minutes: snoozeLength.floor()));
  await _scheduleSnooze();
}

// canBeSnoozed is only consulted at UI display time:
//   alarm_isolate.dart:170     showSnoozeButton: alarm.canBeSnoozed
//   alarm_notification_screen.dart:82,87   ... alarm.canBeSnoozed ? _snoozeAlarm : null
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Snooze count enforced by hiding the button | Enforce in the mutation (`snooze()` gate) | This phase | Count can't be bypassed by a stale UI or a second isolate. |
| Two divergent dismiss paths (list vs notification) | One shared dismiss resolution (`cancelSnooze` + `update`) | This phase | #457 fixed for all dismiss entry points (button, notification, upcoming-alarm). |
| `Duration(minutes: x.floor())` | `Duration(seconds: (x*60).round())` clamped | This phase | Sub-minute snooze honored; no instant re-fire. |

**Deprecated/outdated:** none — Chrono's snooze code has not been refactored; the bugs are original. (Last touches to these files: `5fb5574` "Change notification action type to background", `df9fe07` "Make alarm notification not dismissed on button press" — neither touched the snooze math or the dismiss deactivation.)

## Test Strategy (authored, run in CI — toolchain absent locally)

> `config.json: nyquist_validation=false`, so no formal Validation Architecture section is required. But Phase 2 is exceptionally unit-testable because `schedule_alarm.dart` guards all `AndroidAlarmManager` calls behind `FLUTTER_TEST` — assert on `Alarm` flags, not on the OS. Template: `test/alarm/types/schedules/once_alarm_schedule_test.dart` (already in repo) and `clock`'s `withClock(Clock.fixed(...))` for snooze-time assertions.

| Req | Test (author; run in CI) | Assertion |
|-----|--------------------------|-----------|
| SNZ-02 | Set `Length`=0.5, call `snooze()` under frozen clock | `_snoozeTime == now + 30s` (not `now`); delay passed to `scheduleSnoozeAlarm` is 30s, not 0. |
| SNZ-03 | Once-alarm: `snooze()` then dismiss (`handleDismiss`/`_resolveDismiss`) then `update()` | `isEnabled == false` (or `isMarkedForDeletion`), `isSnoozed == false`, schedule does NOT re-arm a future time. |
| SNZ-03 (dates) | DatesAlarmSchedule with only a past/today date: snooze→dismiss | `isFinished`/disabled; no next-day re-arm. |
| SNZ-04 | Set `Max Snoozes`=2; call `snooze()` three times | Third call does NOT increment to 3 / does not schedule; resolves as dismiss or no-ops safely. `snoozeCount` survives a `toJson→fromJson` round-trip. |
| SNZ-04 (persist) | `snooze()`, serialize alarm, deserialize, read `snoozeCount` | Round-trips to the incremented value (proves disk persistence across the isolate boundary). |
| SNZ-01/05 | Snooze a task-required alarm; advance past `_snoozeTime`; `update()` | Pending snooze re-scheduled (`update()` branch `alarm.dart:337`), alarm still enabled+snoozed; never silently disabled. |

**Wave 0 gap:** new `test/alarm/types/alarm_snooze_test.dart` (no existing snooze unit test — `grep` found snooze referenced only in `schedule_description_test.dart` and the once-schedule test). No fixture/conftest changes needed; `appSettings` is statically constructed at module load (per 01-01-SUMMARY), so `Alarm()` builds without storage init.

## Environment Availability

> Phase 2 is a code-only change. The only "dependency" is the Flutter/Dart toolchain for analyze/test/build.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK / Dart | `flutter analyze`, `flutter test`, build | ✗ (this env) | — | Author tests + source-assert here; run analyze/test on CI (Flutter 3.22.2) before merge — same protocol Phase 1 used. |
| `android_alarm_manager_plus` (fork) | snooze re-ring scheduling | ✓ (in pubspec.lock) | 4.0.1 | — |
| `clock` | frozen-time snooze tests | ✓ (in pubspec) | ^1.1.1 | — |
| On-device Android (FBE, API 24+) | true end-to-end snooze→dismiss validation | ✗ | — | Unit tests cover the model logic without a device; an on-device smoke check (snooze a once-alarm, dismiss the re-ring, confirm it doesn't reappear) is a human gate, like Phase 1's Task 3. |

**Missing dependencies with no fallback:** none that block planning — the model logic is fully unit-testable without the toolchain or a device; only end-to-end confirmation needs hardware (human/CI gate, consistent with the milestone's no-toolchain constraint).
**Missing dependencies with fallback:** the toolchain (author + CI-gate) and the device (unit tests + a human smoke gate).

## Pitfalls / Landmines — Isolate-Boundary Snooze-Count Persistence (SNZ-04 focus)

This is the single subtlest area; the planner must get the read/write ordering right.

1. **The disk is the source of truth, not isolate memory.** `_snoozeCount` lives on the in-memory `Alarm` *and* is serialized. The firing isolate and the main isolate each load their own `Alarm` instance from `alarms.txt`. The count survives **only because** `updateAlarmById` calls `saveList` before returning (`update_alarms.dart:78`). Any new snooze-mutation path MUST go through `updateAlarmById` (or otherwise `saveList`) — a mutation that forgets to save will silently reset the count on the next ring (the originally-feared SNZ-04 failure mode). **Do not** mutate the `Alarm` outside the `updateAlarmById` callback.

2. **`triggerAlarm` calls `updateAlarms("...on trigger")` on every ring (`alarm_isolate.dart:98`) — and `updateAlarms` calls `alarm.update()` for every alarm (`update_alarms.dart:47`).** `update()` reschedules a pending snooze (`alarm.dart:337`) when `isSnoozed` and `now < _snoozeTime`, or `_unSnooze()`s when the snooze time has passed (`:334`). This is fine, but it means: (a) the snoozed alarm's state is re-touched on unrelated triggers — so the count and snooze flags must already be persisted; (b) a snoozed-then-dismissed **enabled** one-shot gets re-armed here — the #457 vector. The dismiss fix (deactivate `_isEnabled=false`) is what stops this re-arm.

3. **Read-modify-write race window.** `getAlarmById` (used by the notification screen and `createSnoozeNotification`) does `loadListSync` (`alarm_id.dart:6`), while the isolate dismiss/snooze does an async `loadList`→mutate→`saveList`. If the UI reads `canBeSnoozed` from a slightly stale instance (count not yet saved by a concurrent snooze), it could show the snooze button one time too many. The **authoritative gate inside `snooze()` (SNZ-04 fix)** closes this — even if the button is shown, the mutation refuses past max. This is the core reason the gate must be in the model, not the UI.

4. **`handleDismiss` resets `_snoozeCount=0` (`alarm.dart:310`).** Correct on a real dismiss. But if the over-max case is routed through a dismiss-like resolution, ensure the count reset is intentional (a fresh ring should start at 0). Don't reset the count on a *snooze* — only on dismiss/finish.

5. **`Alarm.fromAlarm`/`copyFrom` copy `_snoozeCount` (`alarm.dart:142,154`).** `updateAlarmById` mutates the loaded instance in place and writes it back (`alarms[alarmIndex] = alarm`), so copies aren't in the hot path — but any new code that `copy()`s an alarm mid-snooze must carry the count (it already does). No action; noted so a refactor doesn't drop it.

6. **`FLUTTER_TEST` guards make this testable.** `scheduleAlarm`/`cancelAlarm`/`scheduleSnoozeAlarm` short-circuit under `FLUTTER_TEST` (`schedule_alarm.dart:28,101,136`), so tests can drive `snooze()`/dismiss and assert on `snoozeCount`/`isEnabled`/`isSnoozed`/`snoozeTime` without a device or real OS alarms. Use this — it's the whole reason SNZ-04 persistence can be proven in CI via a `toJson→fromJson` round-trip.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Delete After Ringing` default is `false`, so a default once-alarm is NOT marked-for-deletion on dismiss | SNZ-03 root cause | Low — confirmed at `alarm_settings_schema.dart:131-138` (literal `false`). If a user enabled it, #457 *still* reproduces per the issue ("Even happens if Delete After Dismiss is enabled... rescheduled for the following day") — so the fix can't rely on deletion; it must deactivate. [VERIFIED: source] |
| A2 | The `Length` slider can actually produce fractional values through the UI (so SNZ-02 is reachable, not theoretical) | SNZ-02 | Low — `SliderSetting "Length"` has no `snapLength` (`alarm_settings_schema.dart:248-257`); the slider widget uses `divisions: null` and `toStringAsFixed(1)` when `snapLength==null` (`slider_field.dart:78,60`), i.e. one-decimal fractional values. Even if a future UI snapped it, the model fix is still correct. [VERIFIED: source] |
| A3 | The snooze count persists on disk because `snooze()` runs inside `updateAlarmById`→`saveList` | SNZ-04 / Landmines | Low — confirmed at `update_alarms.dart:62-78`. The residual SNZ-04 defect is the missing *gate*, which is independent of persistence. [VERIFIED: source] |
| A4 | #495 ("snoozing just disables my alarm") is the dismiss/re-arm/`.floor()` cluster, not a misrouted snooze→dismiss intent | SNZ-05 | Medium — action routing is provably correct (distinct keys, snooze excluded from the task gate). The exact reporter repro wasn't run on-device; the on-device human smoke check (snooze a task-alarm, confirm it re-rings) is the validation. If a device repro surfaces a *different* cause, revisit. [VERIFIED: routing source; CITED: issue #495 body] |

## Open Questions

1. **Should over-max snooze resolve as a dismiss or a no-op?**
   - What we know: the notification hides the snooze button past max (`canBeSnoozed`), so the over-max tap is an edge case (custom UIs, races).
   - What's unclear: whether product wants "alarm stops" (dismiss) or "alarm keeps ringing, ignore the tap."
   - Recommendation: resolve as **dismiss** (safer — never leaves it ringing); a no-op risks Pitfall 5. Flag for the planner / discuss-phase.

2. **Convert `handleDismiss()` to async + `_resolveDismiss()`, or fix at the `stopAlarm` call site?**
   - What we know: `handleDismiss` is `void`, called un-awaited at `alarm_isolate.dart:194`; the correct work (`cancelSnooze`+`update`) is async.
   - Recommendation: introduce `Future<void> _resolveDismiss()` on `Alarm`, call it (awaited) from the isolate dismiss branch, and have `handleDismiss` either delegate to it or be replaced. Keeps the model the owner of the state machine (matches CLAUDE.md architecture). Claude's discretion.

3. **Does `update()`'s snooze-reschedule (`alarm.dart:333-339`) double-schedule when combined with `triggerAlarm`'s `updateAlarms`?**
   - What we know: `update()` calls `_scheduleSnooze()` again when still snoozed; `scheduleSnoozeAlarm`→`scheduleAlarm` cancels the prior id before re-scheduling (`schedule_alarm.dart:41,47`), so it's idempotent by id.
   - Recommendation: no change; but add a test asserting a snoozed alarm survives an unrelated `updateAlarms` without losing its `_snoozeTime` or doubling the pending alarm. (Confirms the Phase-1 idempotency spine holds for the snooze case.)

## Sources

### Primary (HIGH confidence — read this session, line-level)
- `lib/alarm/types/alarm.dart` — `snooze()`/`_scheduleSnooze()`/`cancelSnooze()`/`handleDismiss()`/`update()`/`schedule()`, `_snoozeCount`/`maxSnoozes`/`canBeSnoozed`, toJson/fromJson (`:218-247`, `:309-355`, `:441-452`, `:87-113`).
- `lib/alarm/logic/alarm_isolate.dart` — `stopAlarm` snooze/dismiss branches (`:181-197`), `triggerAlarm` (`:87-175`, note `updateAlarms` at `:98`), `stopAlarmPort` plumbing.
- `lib/notifications/logic/alarm_notifications.dart` — `handleAlarmNotificationAction`/`handleAlarmNotificationDismiss` action routing (`:200-243`), `stopAlarm` port send (`:140-146`), task-gate (`:212`).
- `lib/alarm/logic/schedule_alarm.dart` — `scheduleAlarm`/`cancelAlarm`/`scheduleSnoozeAlarm`, `FLUTTER_TEST` guards (`:14,100,132`).
- `lib/alarm/logic/update_alarms.dart` — `updateAlarms`/`updateAlarm`/`updateAlarmById` (`:21-82`) — the Phase-1 idempotent funnel.
- `lib/alarm/types/schedules/once_alarm_schedule.dart`, `dates_alarm_schedule.dart`, `alarm_schedule.dart`, `alarm_runner.dart` — schedule re-arm/disable semantics.
- `lib/alarm/screens/alarm_notification_screen.dart` (`:36-101`) and `lib/alarm/screens/alarm_screen.dart` (`:188-192`) — the two dismiss entry points (notification vs list).
- `lib/alarm/data/alarm_settings_schema.dart` — `Length`/`Max Snoozes`/`Enabled`/`Delete After Ringing` definitions (`:131-295`); `lib/common/widgets/fields/slider_field.dart` (`:55-83`) and `lib/settings/types/setting.dart` (`:411-457`, `SliderSetting`).
- `lib/alarm/utils/alarm_id.dart` (`getAlarmById`→`loadListSync`).
- `pubspec.yaml` (`version: 0.6.0+28`); `git log` on the snooze files (last touches `5fb5574`, `df9fe07`).
- GitHub issues **#457** and **#495** — full bodies via `gh api repos/vicolo-dev/chrono/issues/{n}` (REST; the GraphQL `gh issue view` path errored on projects-classic deprecation, REST succeeded).

### Secondary (HIGH — prior milestone/phase docs)
- `.planning/research/{SUMMARY,ARCHITECTURE,PITFALLS}.md` — milestone-level snooze diagnosis (corroborates `.floor()` sites and the dismiss-gap; this phase confirmed + extended them with the two-dismiss-paths finding and the SNZ-04 gate location).
- `.planning/phases/01-storage-boot-reliability/01-01-SUMMARY.md`, `01-02-SUMMARY.md`, `01-PATTERNS.md` — the reused idempotent reschedule funnel and storage hardening Phase 2 depends on.
- `.planning/STATE.md` — known root causes (line-level) and the no-toolchain blocker.

### Tertiary (LOW — not independently verified this session)
- On-device snooze→dismiss end-to-end behavior across OEMs — requires hardware; covered by a human smoke gate, not doc-readable.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new deps; all reused primitives read at file:line.
- Architecture / root causes: HIGH — every SNZ-01..05 cause confirmed in the live 0.6.0+28 source; both issues read directly.
- Pitfalls / isolate persistence: HIGH — read/write ordering traced through `updateAlarmById`→`saveList` and `triggerAlarm`→`updateAlarms`.
- SNZ-05/#495 exact reporter repro: MEDIUM — routing proven correct; the precise device repro is a human gate.

**Research date:** 2026-06-02
**Valid until:** ~2026-07-02 (stable — internal codebase, no fast-moving external deps; re-verify only if `alarm.dart`/`alarm_isolate.dart`/`schedule_alarm.dart` change before planning).
