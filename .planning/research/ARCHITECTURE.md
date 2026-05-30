# Architecture Patterns

**Domain:** Flutter Android alarm app — milestone: camera scan-to-dismiss alarm task + boot/storage/snooze/date reliability fixes
**Researched:** 2026-05-30
**Scope note:** Subsequent-milestone doc. The base architecture (feature-sliced monolith, alarm firing isolate, `IsolateNameServer` named ports, JSON-file persistence via a `Queue`, string-keyed `SettingGroup`s) is documented in `.planning/codebase/ARCHITECTURE.md` and is NOT re-described. This file covers only the integration points for THIS milestone, grounded in the actual source.

**Confidence basis:** Source files read this session (line-level evidence, HIGH): `alarm/types/alarm_task.dart`, `alarm/data/alarm_task_schemas.dart`, `alarm/screens/alarm_notification_screen.dart`, `alarm/widgets/tasks/math_task.dart`, `alarm/types/alarm.dart`, `system/logic/handle_boot.dart`, `system/logic/initialize_isolate.dart`, `settings/types/setting_group.dart`, `common/utils/list_storage.dart`, plus all `.planning/codebase/*` and `PROJECT.md`. External library/Android-API/on-device behavior NOT verified this session is marked **[VERIFY]**.

---

## Part A — Camera Scan-to-Dismiss Task

### A.1 Task contract (confirmed from source)

A task is fully described by an `AlarmTaskSchema` registered in `alarmTaskSchemasMap` keyed by an `AlarmTaskType` enum value (`alarm_task.dart:8-14`, `alarm_task_schemas.dart:10`). Builder signature (`alarm_task.dart:16-17`):

```dart
typedef AlarmTaskBuilder = Widget Function(Function() onSolve, SettingGroup settings);
```

`AlarmTaskSchema` carries a localized-name getter, a `SettingGroup` (the task config), and the builder. Config serializes via `settings.valueToJson()` / `settings.loadValueFromJson(json['settings'])` (`alarm_task.dart:35-49`). The `AlarmTask` (one per alarm) serializes `{id, schema, type}` inline inside the alarm's JSON (`alarm_task.dart:100-108`); the alarm's `SettingGroup` holds the task list under the `"Tasks"` setting (`alarm.dart:88`). **No `json_serialize.dart` factory entry is needed for the new task** — that registry is only for top-level `ListItem`s; tasks ride the alarm's inline serialization. Confidence: HIGH.

Ring-screen orchestration (`alarm_notification_screen.dart:41-63`): `_setNextWidget()` builds `alarm.tasks[_currentIndex].builder(_setNextWidget)` and increments the index; the builder is given `_setNextWidget` AS its `onSolve`. **Calling `onSolve()` once = "task solved, advance; past the last task → `dismissAlarmNotification(...)`."** Orchestration needs ZERO changes for a new task type. Confidence: HIGH (read directly).

Existing task widgets are the template: `MathTask` (`math_task.dart:68-80`) is a `StatefulWidget` taking `{required VoidCallback onSolve, required SettingGroup settings}`, reads its config in `initState`/`initialize()` via `widget.settings.getSetting("…").value`, and calls `widget.onSolve()` when complete (`math_task.dart:111`). ScanTask copies this shape exactly. Note `MathTask` also implements `didUpdateWidget` (`math_task.dart:98-101`) — do the same for ScanTask so it re-initializes if the framework rebuilds it.

### A.2 What to add (minimal, concrete)

| Change | File | Nature |
|--------|------|--------|
| `scan` enum value | `alarm_task.dart:8-14` | add `scan,` to `AlarmTaskType` (a stub `shake` value already exists) |
| Schema entry | `alarm_task_schemas.dart` map | `AlarmTaskType.scan: AlarmTaskSchema((ctx)=>l10n.scanTask, SettingGroup("Scan Settings", …, [ <registered code>, <escape hatch> ]), (onSolve, settings)=>ScanTask(onSolve:onSolve, settings:settings))` |
| ScanTask widget | NEW `alarm/widgets/tasks/scan_task.dart` | `StatefulWidget` per `MathTask` shape; camera lifecycle, decode, match, escape hatch, `onSolve()` |
| Registration UI | task-config flow (the `SettingGroup` editor used by `CustomizableListSetting<AlarmTask>`) | a custom `Setting`/action that opens a one-shot scanner and writes the decoded value into the task `SettingGroup` |
| `CodeScanner` interface + dep | NEW thin interface + scanner package | see A.5 |
| `CAMERA` permission + l10n | `AndroidManifest.xml`, ARB (`app_en.arb`) | manifest + strings |

The registered code + escape-hatch config are `Setting<T>` entries inside the schema `SettingGroup` (same mechanism as `SelectSetting`/`SliderSetting`/`SwitchSetting` in the other tasks, `alarm_task_schemas.dart:15-39`). `SettingGroup.valueToJson()` serializes all child settings (`setting_group.dart:178-186`), so the registered code persists for free. A string-valued setting type already exists — `StringSetting extends Setting<String>` (`setting.dart:383`) — use it for the Registered Code; for value+symbology use `CustomSetting<T extends JsonSerializable>` (`setting.dart:223`). Confidence: HIGH.

### A.3 Component boundaries

```
┌─ MAIN ISOLATE — AlarmNotificationScreen (over lock screen) ──────────────┐
│ _setNextWidget(): _currentWidget = alarm.tasks[i].builder(_setNextWidget) │
│        │ builder == AlarmTaskSchema.getBuilder (alarm_task.dart:31-33)    │
│        ▼                                                                  │
│   ScanTask(onSolve: _setNextWidget, settings: schema.settings)  ◄── NEW  │
│        │ onSolve() → advance/dismiss (orchestration UNCHANGED)           │
└────────┼─────────────────────────────────────────────────────────────────┘
         ▼ owns
┌─ ScanTask (NEW) ─────────────────────────────────────────────────────────┐
│  initState: start scanner via CodeScanner; read Registered Code +        │
│             escape-hatch settings from widget.settings                    │
│  on decode: payload == registered ? onSolve() : attempt++                │
│  escape-hatch Timer/counter trips → onSolve()                            │
│  dispose: release controller                                            │
│  WidgetsBindingObserver: pause on background, resume on foreground       │
└────────┼─────────────────────────────────────────────────────────────────┘
         ▼ depends on (injected, flavor-swappable)
┌─ CodeScanner abstraction (NEW) ── ML Kit (Play) | ZXing/FOSS (F-Droid) ──┘

Registration (settings, unlocked):
  CustomizableListSetting<AlarmTask> config → "Scan to register"
    → one-shot scanner → write Registered Code into task SettingGroup
    → saveList("alarms", …) (existing path; SettingGroup serialized inline)
```

**Hard boundary (PROJECT.md, confirmed by isolate split):** the camera is MAIN-ISOLATE ONLY. `initializeIsolate()` (`initialize_isolate.dart:12-24`) sets up storage/settings/notifications/audio/alarm-manager — no camera. The firing isolate plays audio + posts the full-screen notification that launches the main-isolate ring screen, where ScanTask mounts. Confidence: HIGH.

### A.4 Camera lifecycle (the real work)

Bind the controller to the **ScanTask widget**, not the ring screen — other tasks (math/retype) may precede the scan task, so the camera must not be held during them.

- **Init** in `initState()`; re-check `CAMERA` permission (normally granted at task-add time; if denied at ring time, fall through to escape hatch so the user is never trapped — non-predatory requirement).
- **Dispose** in `dispose()` — release immediately on solve/dismiss/snooze; Android holds the camera surface otherwise.
- **Background/screen-off:** implement `WidgetsBindingObserver.didChangeAppLifecycleState` — stop on `inactive`/`paused`, restart on `resumed`. Do not assume the package auto-pauses. **[VERIFY package lifecycle]**
- **Over the lock screen:** ring screen shows over keyguard via `flutter_show_when_locked` (STACK.md:78). Camera preview from a keyguard-visible activity is the biggest unknown; some OEMs restrict it. Needs an early on-device spike across several OEMs/versions. **[VERIFY on device]** Confidence: LOW until tested.

**Anti-pattern:** owning the controller in the ring screen across all tasks. Bind to ScanTask.

### A.5 Scanner library — F-Droid conflict (resolve in STACK)

`mobile_scanner` (PROJECT.md candidate) uses Google ML Kit (proprietary) → breaks F-Droid (PROJECT.md bans proprietary blobs). The app already ships two flavors (`prod`/`dev`, STACK.md:118) and distributes to Play + GitHub + F-Droid — so a **flavor-split decoder** is clean (ML Kit for Play/GitHub, a ZXing-based FOSS scanner e.g. `flutter_zxing` for F-Droid), or pick one FOSS scanner. **Architecture implication:** ScanTask depends on a thin `CodeScanner` interface, not a concrete package, so the backend swaps per flavor. Resolve the exact dep in STACK.md. Confidence: MEDIUM on conflict; **[VERIFY]** ML Kit/F-Droid status + FOSS alternative.

### A.6 Data flow — registration → storage → match → onSolve → dismiss

```
SETTINGS (unlocked)                       RING TIME (lock screen)
register: decode P                        fire → ring screen → ScanTask
 → task SettingGroup["Registered Code"]=P   R = settings["Registered Code"]
 → saveList("alarms",…) → alarms.txt         camera decodes P'
   (SettingGroup.valueToJson inline in        P'==R ? onSolve() : attempt++
    Alarm JSON, alarm.dart:450)               escape-hatch trip → onSolve()
```

Store the raw decoded string; optionally also symbology (`qr`/`ean13`) so a QR doesn't match a barcode of the same digits (recommend value-only match for v1). Escape-hatch settings (`Enabled` default true, `After attempts`, `After seconds`) live in the same `SettingGroup`; the hatch is just another path to `onSolve()`, so the dismiss contract is untouched. Confidence: HIGH on path, MEDIUM on symbology detail.

---

## Part B — Reliability: Boot isolate / encrypted storage

### B.1 Root cause (confirmed at line level)

`handleBoot()` (`handle_boot.dart:7-27`) unconditionally `await initializeIsolate()`, then `updateAlarms/updateTimers` inside a try/catch that does **NOT** wrap `initializeIsolate()` (the await on line 20 is outside the try on 21-26). `initializeIsolate()` (`initialize_isolate.dart:12-24`) eagerly calls `initializeAppDataDirectory()` → `initializeStorage(false)` → `initializeSettings()`, all touching credential-encrypted (CE) storage (app docs dir, `get_storage`, settings `.txt` files). On Direct Boot delivery before unlock, CE storage throws `IllegalStateException`; nothing in `handleBoot` catches an init throw (only the isolate-level `FlutterError.onError` logs it, `handle_boot.dart:16-18`), and a partial write can be left behind.

The corruption-to-hang chain is confirmed in `SettingGroup.load()` (`setting_group.dart:257-268`):
```dart
try { value = loadTextFileSync(id); }
catch (e) { value = GetStorage().read(id); }   // can return null
loadValueFromJson(json.decode(value));          // NO null-guard, NOT in the try
```
If the file is missing/half-written, `loadTextFileSync` throws → `GetStorage().read(id)` may be `null` → `json.decode(null)` throws **outside any catch here** → undefined settings → splash hang. (`loadValueFromJson` itself swallows errors at `setting_group.dart:246-249`, but the `json.decode` on line 265 runs *before* that and is unguarded.) Additionally `saveTextFile` (`list_storage.dart:82-90`) writes directly to the real file with `FileMode.writeOnly` — **non-atomic**, so a killed boot write genuinely half-writes. Confidence: HIGH (all read directly).

### B.2 Correct architecture (three independent, testable layers)

```
BOOT broadcast → flutter_boot_receiver → handleBoot()
   │
   ▼  GUARD 1 (NEW, above line 20)
   isUserUnlocked? ── NO ─► defer: ensure USER_UNLOCKED hook, return
   │                         (do NOT call initializeIsolate / touch CE storage)
   ▼ YES
   await initializeIsolate()  ── WRAP in try/catch (currently unwrapped, line 20)
   │
   ▼  GUARD 2 (storage): null-guard before json.decode; catch→DEFAULTS
   │   never catch→undefined; contain GetStorage fallback (setting_group.dart:257-268)
   ▼
   GUARD 3 (storage): atomic write — temp file + rename (list_storage.dart:82-90)
   │
   ▼  updateAlarms()/updateTimers()  — idempotent (cancel-by-id then set)
```

1. **Unlock guard (Dart/Android boundary, `handle_boot.dart`).** Check user-unlocked before `initializeIsolate()`. Two shapes:
   - **Defer-until-unlock (recommended, low risk):** if not unlocked (or on `LOCKED_BOOT_COMPLETED`), return without touching CE storage and ensure reschedule runs on `ACTION_USER_UNLOCKED` (native receiver → same Dart entry). Non-Direct-Boot devices get `BOOT_COMPLETED` only post-unlock, so they're unchanged.
   - **Direct Boot DE storage:** move minimal boot-critical state to `createDeviceProtectedStorageContext()` (readable pre-unlock) with `android:directBootAware="true"` on the receiver. Heavier (parallel store + migration); use only if alarms must arm before unlock. Recommend defer-until-unlock for v1; DE storage as a follow-on.
   - **[VERIFY]** `UserManager.isUserUnlocked()`, `createDeviceProtectedStorageContext()`, `directBootAware`, `LOCKED_BOOT_COMPLETED` vs `BOOT_COMPLETED`, and **what `flutter_boot_receiver` actually delivers / whether it exposes unlock state** — it's `^1.1.0` (STACK.md:57) and there's a commented `path:` fork override in `pubspec.yaml:18-19`, so native edits may be required. Approach: MEDIUM–HIGH; exact plumbing: LOW.

2. **Non-fatal load (storage, `setting_group.dart` + `list_storage.dart`).** Null/empty-guard before the `json.decode` at `setting_group.dart:265`; on any failure load DEFAULTS (and log) instead of leaving undefined; contain/remove the silent `GetStorage` fallback at lines 262-263. Also wrap the `initializeIsolate()` call in `handleBoot:20`. This converts "corrupted state → splash hang" into "recover with defaults." Confidence: HIGH.

3. **Atomic writes (`list_storage.dart:82-90`).** Write to `$key.txt.tmp` then `rename()` over `$key.txt`, so a process kill mid-write can't leave a half file. The `Queue` (`list_storage.dart:14`) serializes writes but does not make them atomic. Confidence: HIGH (current code confirmed non-atomic).

### B.3 Interaction with `initializeIsolate`

`initializeIsolate()` is shared by the firing isolate AND the boot isolate. Keep it dumb; put the unlock guard ABOVE it in `handleBoot()` so the firing-isolate path (always runs while the device is in use/unlocked) is unaffected. Boot reschedule and `main()`'s `updateAlarms()` can both run close together → make reschedule idempotent (cancel-by-id then set). This primitive is shared with Part C. Confidence: HIGH.

---

## Part C — Reliability: Snooze & date serialization

### C.1 Snooze (bugs confirmed in source)

- **Fractional length dropped twice:** `snooze()` does `_snoozeTime = DateTime.now().add(Duration(minutes: snoozeLength.floor()))` (`alarm.dart:225-227`) AND `_scheduleSnooze()` schedules `Duration(minutes: snoozeLength.floor())` (`alarm.dart:234`). `snoozeLength` is a `double` (`alarm.dart:87`). **Fix:** use `Duration(seconds: (snoozeLength*60).round())` at BOTH sites. Confidence: HIGH (read).
- **One-shot reschedules after snooze→dismiss (#457):** `handleDismiss()` (`alarm.dart:309-315`) resets `_snoozeCount` and marks-for-deletion only when `OnceAlarmSchedule && shouldDeleteAfterRinging` — it does **NOT** cancel a pending snooze runner, and a snoozed one-shot has `_isEnabled=true` (set in `snooze()`, line 222). On dismiss the pending snooze alarm survives and the one-shot is treated as active → re-fires. **Fix:** on dismiss, cancel the pending snooze (`cancelSnooze()` exists, lines 240-243) and ensure a one-shot deactivates and does not re-arm. Confidence: HIGH on the gap.
- **"Never re-fires / just dismisses":** lives in the `snooze()` / schedule interplay (`scheduleSnoozeAlarm` vs the active `OnceAlarmSchedule`); confirm against `once_alarm_schedule.dart` + `schedule_alarm.dart`. **[VERIFY]** those two files (not opened this session).
- **Clean shape:** model post-ring transitions as one idempotent function — `ring→snooze` schedules a separate pending one-shot WITHOUT mutating the recurring schedule (track `_snoozeCount` vs `maxSnoozes`, both already present, lines 90/109-110); `snooze→dismiss` cancels the pending snooze then runs the SAME dismiss/advance (one-shot deactivates, recurring advances). This lets the backlogged snooze PRs layer onto a correct core. Confidence: HIGH.

### C.2 Date drift (off-by-one), confirmed mechanism

Dates are stored as `millisecondsSinceEpoch` throughout `Alarm`: `_snoozeTime`/`_skippedTime` (`alarm.dart:446,451`, read back at 405-409), and the `Dates`/`Date Range` `DateTimeSetting`s (accessed at `alarm.dart:376-386`). `table_calendar` emits UTC-midnight `DateTime`; persisting that as epoch and reloading as local time rolls the day back for negative-UTC users (PROJECT.md #340/#455/#472). **Clean fix = separate "a date" from "an instant":**
- Normalize at the picker→model boundary (`date_picker_bottom_sheet.dart:145`): produce `DateTime(y,m,d)` local, or store a date-only `yyyy-MM-dd` string / Y-M-D triple — never persist a UTC-midnight instant as a calendar date.
- Make the calendar-date `Setting` serialization date-aware (local Y/M/D) distinct from instant settings. Confirmed site: `DateTimeSetting` (`setting.dart:916`) `valueToJson()` maps to `millisecondsSinceEpoch` (`setting.dart:957-958`) and `loadValueFromJson` maps back via `DateTime.fromMillisecondsSinceEpoch` (`setting.dart:962-966`) — the exact UTC-midnight-epoch round-trip. The off-by-one fix lives here plus the picker boundary.
Confidence: HIGH (epoch round-trip confirmed in both `alarm.dart` and `setting.dart`).

**Shared primitive:** snooze reschedule and boot reschedule both want one idempotent cancel-by-id-then-set path. Build once.

---

## Part D — Build order & dependencies

Reflects PROJECT.md core-value priority ("reliably ring and stop … before any new feature") and the confirmed dependency graph.

```
Phase 1  STORAGE HARDENING (prerequisite for everything)
  1a non-fatal load: null-guard before json.decode (setting_group.dart:265),
     catch→defaults, contain GetStorage fallback (257-263),
     wrap initializeIsolate() in handleBoot (handle_boot.dart:20)
  1b atomic writes: temp+rename (list_storage.dart:82-90)
  1c idempotent reschedule primitive (cancel-by-id then set)  ← shared by 2,3
        depends on: nothing

Phase 2  BOOT / DIRECT-BOOT GUARD
  2a unlock guard in handleBoot (isUserUnlocked / defer to USER_UNLOCKED)
  2b (optional) device-protected storage for pre-unlock arming
        depends on: 1a/1b, 1c

Phase 3  SNOOZE STATE MACHINE
  3a fractional length (drop .floor() at alarm.dart:226 & :234);
     #457 cancel pending snooze + one-shot deactivation in handleDismiss;
     "never re-fires" via once_alarm_schedule interplay
        depends on: 1c

Phase 4  DATE SERIALIZATION
  4a local-date normalization at picker boundary + date-aware DateTimeSetting
        depends on: 1a (load must tolerate old epoch values during migration);
        largely independent of 2/3

Phase 5  SCAN-TO-DISMISS FEATURE (only after alarm reliably rings/stops)
  5e LOCK-SCREEN/BACKGROUND CAMERA SPIKE  ← pull EARLY as a risk probe;
     can invalidate the approach / force native work
  5a CodeScanner abstraction + backend choice (ML Kit vs F-Droid — STACK)
  5b scan enum value + schema entry + SettingGroup fields (Registered Code, escape hatch)
  5c registration UI in task config (one-shot scan → write Registered Code)
  5d ScanTask widget: camera lifecycle, match, escape-hatch, onSolve()
        5b reuses the JSON path hardened in 1a; functionally independent of 1-4
        but sequenced after reliability per core-value priority
```

**Why this order:** 1 first because every change reads/writes storage and the boot fix is meaningless if a late load still corrupts (the corruption chain is in the load/save layer). 1c (idempotent reschedule) is the spine for 2 and 3 — build once, depend twice. 2 is the highest-severity user-facing bug (boot black-screen) → early. 5 last per product priority, EXCEPT 5e (camera-over-lockscreen spike) pulled forward as a standalone de-risking probe — biggest unknown, could change the feature design or force native work.

**Shared artifacts:** idempotent reschedule (1c) → 2,3; hardened JSON load/save (1a/1b) → 4,5b; `CodeScanner` abstraction (5a) → isolates the F-Droid/ML Kit decision.

---

## Patterns to Follow

- **Reuse the task framework; touch orchestration zero times.** Add enum value + schema entry + a `StatefulWidget` taking `{onSolve, settings}` (per `MathTask`); call `onSolve()` once to advance/dismiss (`alarm_notification_screen.dart:41-63`). HIGH.
- **Store task config as `Setting<T>` in the schema `SettingGroup`** — serializes for free via `valueToJson()` (`setting_group.dart:178-186`); no `json_serialize.dart` factory needed. HIGH.
- **Implement `didUpdateWidget`** in ScanTask (mirror `math_task.dart:98-101`) to re-init on rebuild. HIGH.
- **Bind camera to ScanTask `initState`/`dispose` + `WidgetsBindingObserver`** for pause/resume. MEDIUM **[VERIFY package]**.
- **Inject a `CodeScanner` abstraction**, not a concrete scanner, for the F-Droid flavor split. MEDIUM.
- **Guard CE storage ABOVE `initializeIsolate()`** in `handleBoot`; keep init dumb. HIGH.
- **Null-guard before every `json.decode`; catch→defaults, never catch→undefined.** HIGH.
- **Atomic temp+rename writes.** HIGH.
- **Use fractional snooze duration** (`(snoozeLength*60).round()` seconds), not `.floor()` minutes. HIGH.
- **Separate "a date" from "an instant"** in setting serialization. HIGH.
- **One idempotent reschedule** (cancel-by-id then set) shared by boot + snooze. HIGH.

## Anti-Patterns to Avoid

- Camera controller owned by the ring screen across all tasks (holds camera during math/retype) → bind to ScanTask.
- Camera in the firing isolate → forbidden; main-isolate only.
- `mobile_scanner`/any ML-Kit scanner as a direct dep of feature code → breaks F-Droid; use the abstraction + flavor split.
- Accessing CE storage in the pre-unlock boot path (current `handleBoot:20` does exactly this) → `IllegalStateException`.
- `json.decode` on possibly-null/half-written data without a guard (`setting_group.dart:265`) → splash hang.
- Silent `GetStorage` fallback masking load failure (`setting_group.dart:262-263`).
- Non-atomic `FileMode.writeOnly` writes (`list_storage.dart:89`) → half-written files on kill.
- `.floor()` on snooze length (`alarm.dart:226,234`) → drops fractional minutes.
- `handleDismiss()` not cancelling a pending snooze runner (`alarm.dart:309-315`) → one-shot re-fires (#457).
- Persisting a UTC-midnight instant as a calendar date (epoch round-trip in `alarm.dart`) → off-by-one day.
- Mutating a recurring schedule to implement snooze → snooze should be a separate pending one-shot.

## Scalability Considerations

Single-device, local-only, low item counts — not data-scale-driven. The real axes are device/OS fragmentation:

| Concern | Reality |
|---------|---------|
| OEM lock-screen camera | Varies widely; 5e spike must cover several OEMs/versions. **[VERIFY on device]** |
| Direct Boot availability | Android 7+ (`directBootAware`); pre-7/non-FBE behaves as "unlocked at BOOT_COMPLETED." Guard must handle both. **[VERIFY]** |
| Alarm count | Small (tens); cancel-then-set per id is fine. |

## Gaps to Address (verify before/within phases)

1. **[VERIFY] Scanner package** — lifecycle/dispose semantics; F-Droid-safe path; FOSS alternative (`flutter_zxing` or similar). → STACK.md.
2. **[VERIFY] Lock-screen camera spike (5e)** — does preview work from the keyguard-visible ring activity across OEMs? Highest risk; do early.
3. **[VERIFY] Direct Boot plumbing through `flutter_boot_receiver`** — does it expose unlock state / `LOCKED_BOOT_COMPLETED`, or is a native `directBootAware` + `USER_UNLOCKED` receiver required (forked dep)? Confirm `UserManager.isUserUnlocked`, `createDeviceProtectedStorageContext`, manifest attrs.
4. **[VERIFY] Snooze/date "never re-fires" files** — `once_alarm_schedule.dart` + `schedule_alarm.dart` for the "never re-fires" path; `date_picker_bottom_sheet.dart:145` (not opened this session). (`DateTimeSetting` lines now confirmed — see C.2.)

## Sources

- `lib/alarm/types/alarm_task.dart`, `lib/alarm/data/alarm_task_schemas.dart`, `lib/alarm/screens/alarm_notification_screen.dart`, `lib/alarm/widgets/tasks/math_task.dart`, `lib/alarm/types/alarm.dart`, `lib/system/logic/handle_boot.dart`, `lib/system/logic/initialize_isolate.dart`, `lib/settings/types/setting_group.dart`, `lib/common/utils/list_storage.dart` — read this session, line-level, HIGH.
- `.planning/PROJECT.md`, `.planning/codebase/{ARCHITECTURE,STRUCTURE,STACK,CONCERNS}.md` — read this session, HIGH.
- External library/Android-API behavior and on-device lock-screen camera — NOT verified this session; see **[VERIFY]** items.

---

*Architecture research for milestone: scan-to-dismiss + reliability. HIGH where grounded in read source (line-level evidence cited); MEDIUM/LOW where dependent on external library/Android-API behavior or unread file regions (flagged inline).*
