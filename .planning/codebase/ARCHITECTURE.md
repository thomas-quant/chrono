<!-- refreshed: 2026-05-30 -->
# Architecture

**Analysis Date:** 2026-05-30

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                         Flutter UI Layer                                 │
│    NavScaffold (PageView)  →  4 Feature Tabs                            │
│    `lib/navigation/screens/nav_scaffold.dart`                            │
├──────────────┬──────────────┬──────────────┬──────────────────────────┤
│   Alarm       │    Timer      │  Stopwatch   │    Clock                  │
│`lib/alarm/`   │`lib/timer/`   │`lib/stopwatch/`│`lib/clock/`             │
│screens/       │screens/       │screens/       │screens/                  │
│widgets/       │widgets/       │widgets/       │widgets/                  │
└──────┬────────┴──────┬────────┴──────────────┴──────────────────────────┘
       │               │
       ▼               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              Business Logic / Domain Layer                               │
│  Alarm: `lib/alarm/logic/`    Timer: `lib/timer/logic/`                 │
│  Types: `lib/alarm/types/`    Types: `lib/timer/types/`                 │
│  Settings system: `lib/settings/types/`                                  │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │
       ┌───────────────────────────┼────────────────────────┐
       ▼                           ▼                        ▼
┌────────────────┐   ┌─────────────────────────┐  ┌────────────────────┐
│  Android Alarm │   │  File System Storage     │  │  Notifications     │
│  Manager Plus  │   │  `lib/common/utils/      │  │  `lib/notifications/`│
│  (scheduleAlarm│   │   list_storage.dart`      │  │  awesome_notifications│
│  via isolate)  │   │  JSON text files on disk  │  │  android_alarm_mgr │
└────────────────┘   └─────────────────────────┘  └────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `App` | Root widget, theme configuration, route management | `lib/app.dart` |
| `NavScaffold` | Bottom nav + PageView container for 4 tabs | `lib/navigation/screens/nav_scaffold.dart` |
| `AlarmScreen` | List of alarms with filters/sort, FAB to create | `lib/alarm/screens/alarm_screen.dart` |
| `TimerScreen` | Countdown timer list management | `lib/timer/screens/timer_screen.dart` |
| `StopwatchScreen` | Single stopwatch with lap tracking | `lib/stopwatch/screens/stopwatch_screen.dart` |
| `ClockScreen` | World clock with favorite city timezone list | `lib/clock/screens/clock_screen.dart` |
| `Alarm` | Full alarm entity with schedule, settings, snooze logic | `lib/alarm/types/alarm.dart` |
| `ClockTimer` | Countdown timer entity with state machine | `lib/timer/types/timer.dart` |
| `ClockStopwatch` | Stopwatch entity with lap tracking | `lib/stopwatch/types/stopwatch.dart` |
| `AlarmSchedule` | Abstract schedule contract (once/daily/weekly/dates/range) | `lib/alarm/types/schedules/alarm_schedule.dart` |
| `SettingGroup` | Hierarchical settings container (serialize/deserialize) | `lib/settings/types/setting_group.dart` |
| `Setting<T>` | Typed setting value with change listeners | `lib/settings/types/setting.dart` |
| `RingtonePlayer` | Static audio player wrapping `just_audio` | `lib/audio/types/ringtone_player.dart` |
| `RingingManager` | In-memory tracker of currently ringing alarms/timers | `lib/alarm/types/ringing_manager.dart` |
| `Routes` | Static route registry with push/pop tracking | `lib/navigation/types/routes.dart` |

## Pattern Overview

**Overall:** Feature-sliced monolith with isolate-based background execution

**Key Characteristics:**
- Each feature (`alarm`, `timer`, `stopwatch`, `clock`) owns its `data/`, `logic/`, `types/`, `screens/`, and `widgets/` subdirectories
- Settings are a first-class data model: each entity (`Alarm`, `ClockTimer`) embeds a `SettingGroup` that serializes to/from JSON
- Background alarm firing runs in a separate Dart isolate spawned by `android_alarm_manager_plus`; isolates communicate via named `IsolateNameServer` ports
- Persistence is plain JSON text files in the app documents directory (no SQLite except for timezone data)
- No state management library (no Riverpod, Bloc, Provider); UI reloads driven by `setState` + a custom `ListenerManager`

## Layers

**UI Layer (screens + widgets):**
- Purpose: Flutter widget tree, user interaction
- Location: `lib/{feature}/screens/`, `lib/{feature}/widgets/`
- Contains: `StatefulWidget`/`StatelessWidget` classes, settings UI cards
- Depends on: domain types, logic functions, `common/widgets/`
- Used by: Flutter framework

**Domain / Business Logic:**
- Purpose: Entity state machines, schedule computation, schedule/cancel calls
- Location: `lib/{feature}/types/`, `lib/{feature}/logic/`
- Contains: `Alarm`, `ClockTimer`, `ClockStopwatch`, `AlarmSchedule` subtypes, helper functions
- Depends on: storage utils, `android_alarm_manager_plus`, notifications
- Used by: screens, isolate entry points

**Settings System:**
- Purpose: Typed hierarchical key-value store, persisted as JSON, with listeners
- Location: `lib/settings/types/`, `lib/settings/data/`
- Contains: `SettingGroup`, `Setting<T>` subtypes, schema definitions
- Depends on: `list_storage.dart` (file I/O), `get_storage` (migration fallback)
- Used by: all features — each `Alarm`/`ClockTimer` embeds a `SettingGroup`

**Storage Layer:**
- Purpose: Serialise/deserialise lists and text to JSON files on disk
- Location: `lib/common/utils/list_storage.dart`
- Contains: `loadList`, `saveList`, `loadTextFile`, `saveTextFile`; a `Queue` to serialize concurrent writes
- Depends on: `path_provider`, `path`, file system
- Used by: alarm/timer update functions, settings group `load()`/`save()`

**Notifications Layer:**
- Purpose: Display and respond to full-screen alarm/timer notifications
- Location: `lib/notifications/`
- Contains: notification channel config, `showAlarmNotification`, listener/action handlers
- Depends on: `awesome_notifications`, `android_alarm_manager_plus`
- Used by: alarm isolate, main isolate

**System / Platform:**
- Purpose: App boot, background service, device info, intent handling, permissions
- Location: `lib/system/`
- Contains: `handleBoot`, `initializeIsolate`, `initializeIsolatePorts`, background service
- Depends on: `flutter_foreground_task`, `flutter_boot_receiver`, `receive_intent`
- Used by: `main.dart`, `NavScaffold`

**Theme System:**
- Purpose: Dynamic theming with Material You support, color schemes, style themes
- Location: `lib/theme/`
- Contains: `ThemeData` factory (`getTheme`), `ColorSchemeData`, `StyleTheme`, widget-level theme components
- Depends on: `dynamic_color`, `material_color_utilities`
- Used by: `App` widget root

## Data Flow

### Alarm Trigger Path (primary background flow)

1. `AndroidAlarmManager.oneShotAt()` fires, spawning a Dart isolate (`lib/alarm/logic/schedule_alarm.dart:79`)
2. Isolate entry point `triggerScheduledNotification()` is called (`lib/alarm/logic/alarm_isolate.dart:28`)
3. `initializeIsolate()` runs: initialises storage, settings, notifications, audio (`lib/system/logic/initialize_isolate.dart:12`)
4. `triggerAlarm()` loads the `Alarm` from disk, validates timing, plays ringtone via `RingtonePlayer.playAlarm()` (`lib/alarm/logic/alarm_isolate.dart:87`)
5. `showAlarmNotification()` displays full-screen notification via `awesome_notifications` (`lib/notifications/alarm_notifications.dart:25`)
6. User action (dismiss/snooze) sends a message over `stopAlarmPortName` IsolateNameServer port back to the alarm isolate
7. `stopAlarm()` / `stopTimer()` in the alarm isolate calls `alarm.handleDismiss()` or `alarm.snooze()`, writes updated state to disk
8. `sendPort.send("updateAlarms")` is posted to the main isolate via `updatePortName`; `ListenerManager.notifyListeners("alarms")` triggers UI rebuild

### User Creating an Alarm (UI flow)

1. User taps FAB → `AlarmScreen` opens time picker (`lib/alarm/screens/alarm_screen.dart`)
2. `Alarm` object created with default settings from `appSettings.getGroup("Alarm").getGroup("Default Settings")`
3. `alarm.schedule()` called → `activeSchedule.schedule()` → `scheduleAlarm()` → `AndroidAlarmManager.oneShotAt()` (`lib/alarm/logic/schedule_alarm.dart:79`)
4. Updated alarm list saved via `saveList("alarms", alarms)` to `{appDocuments}/Clock/alarms.txt`
5. UI re-renders from `PersistentListView` reload

### App Boot

1. `main()` initialises platform bindings, timezone data, notifications, alarm manager, audio session (`lib/main.dart:24`)
2. `initializeStorage()` seeds JSON files for first launch, initialises `GetStorage` (`lib/settings/logic/initialize_settings.dart:55`)
3. `updateAlarms()` + `updateTimers()` re-schedule any alarms/timers that may have been missed while the app was closed
4. `runApp(const App())` renders the widget tree

**State Management:**
- No centralized state management library
- `setState` for widget-local state
- `Setting.addListener` / `removeListener` for cross-widget setting changes
- `ListenerManager.notifyListeners(key)` for cross-isolate updates (alarm/timer list changes)
- `PersistentListController` + `PersistentListView` for list state

## Key Abstractions

**`ListItem` / `CustomizableListItem`:**
- Purpose: Base interface for all persistable list entities (alarms, timers)
- Examples: `lib/alarm/types/alarm.dart`, `lib/timer/types/timer.dart`
- Pattern: Implements `JsonSerializable` (`toJson()` / `fromJson()`), has `id`, `copy()`, `copyFrom()`

**`AlarmSchedule` (abstract):**
- Purpose: Pluggable schedule strategy for alarms
- Examples: `lib/alarm/types/schedules/once_alarm_schedule.dart`, `weekly_alarm_schedule.dart`, `range_alarm_schedule.dart`
- Pattern: Strategy pattern — `Alarm` holds a list of all schedule types and activates the one matching `scheduleType`

**`SettingGroup` / `Setting<T>`:**
- Purpose: Typed, hierarchical, listener-notifying settings with JSON persistence
- Examples: `lib/settings/types/setting_group.dart`, `lib/settings/types/setting.dart`
- Pattern: Composite tree; each entity embeds a copy of the default settings group from `appSettings`

**`PersistentListView<T>`:**
- Purpose: Generic list widget that owns reload, add, delete, reorder, filter, sort
- Examples: Used in `AlarmScreen`, `TimerScreen`
- Pattern: The widget holds a `PersistentListController` that bridges UI actions to disk I/O

## Entry Points

**`main()`:**
- Location: `lib/main.dart`
- Triggers: App launch
- Responsibilities: Platform init, storage init, settings load, alarm/timer reschedule, `runApp`

**`handleBoot()`:**
- Location: `lib/system/logic/handle_boot.dart`
- Triggers: Android BOOT_COMPLETED broadcast (via `flutter_boot_receiver`)
- Responsibilities: `initializeIsolate()`, `updateAlarms()`, `updateTimers()`

**`triggerScheduledNotification()`:**
- Location: `lib/alarm/logic/alarm_isolate.dart:28`
- Triggers: `AndroidAlarmManager` fires a scheduled alarm
- Responsibilities: Initialise isolate, play ringtone, show full-screen notification

## Architectural Constraints

- **Threading:** Dart isolates used for alarm firing; main UI isolate and alarm isolate communicate only via `IsolateNameServer` named ports (`stopAlarmPort`, `updatePort`, `setAlarmVolumePort`)
- **Global state:** `appSettings` (`lib/settings/data/settings_schema.dart`) is a module-level singleton loaded at startup and shared across isolates by re-loading from disk. `RingingManager` is a static class acting as in-isolate singleton (`lib/alarm/types/ringing_manager.dart`). `RingtonePlayer` is a static class (`lib/audio/types/ringtone_player.dart`).
- **Concurrent writes:** All file I/O routes through a `Queue` instance in `lib/common/utils/list_storage.dart` to prevent race conditions
- **Android-only:** The app targets Android exclusively; `Platform.environment.containsKey('FLUTTER_TEST')` guards used to skip alarm scheduling in tests

## Anti-Patterns

### Settings lookup by string name

**What happens:** Settings are retrieved throughout the codebase by string name: `appSettings.getGroup("Alarm").getSetting("Label").value`
**Why it's wrong:** Typos and renames silently fail at runtime (with a logged error and rethrow); no compile-time checking
**Do this instead:** If adding new settings lookups, add typed accessor methods or constants, e.g. reference `lib/alarm/data/alarm_settings_schema.dart` for name strings

### Commented-out migration code left in SettingGroup

**What happens:** Migration stubs and commented SQL-like operations remain in `loadValueFromJson` (`lib/settings/types/setting_group.dart:196-230`)
**Why it's wrong:** Makes the migration path hard to follow; active migration logic (snooze setting rename) is mixed with stale comments
**Do this instead:** Each migration should be a versioned function; stale comments should be removed once migration is deployed

## Error Handling

**Strategy:** Log and continue (non-crashing) for storage/settings errors; rethrow for developer-facing errors during settings tree lookup

**Patterns:**
- Storage errors: caught in `loadList`/`loadTextFile`, logged via `logger.e()`, returns empty list or empty string
- Settings group lookup failures: logged then rethrown (`lib/settings/types/setting_group.dart:103-110`)
- Isolate errors: `FlutterError.onError` set to log via `logger.f()` in isolate entry points
- UI-layer errors: generally surface as missing data (null-safe getters) rather than crashes

## Cross-Cutting Concerns

**Logging:** `logger` singleton from `lib/developer/logic/logger.dart` using `logger` package with `FileLoggerOutput`; log levels: trace (`t`), info (`i`), error (`e`), fatal (`f`)
**Validation:** Alarm scheduling validates `startDate.isBefore(now)` before calling `AndroidAlarmManager`; no form validation library
**Authentication:** Not applicable — local-only app with no accounts or network auth

---

*Architecture analysis: 2026-05-30*
