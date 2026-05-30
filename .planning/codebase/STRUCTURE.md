# Codebase Structure

**Analysis Date:** 2026-05-30

## Directory Layout

```
chrono/
├── lib/                        # All Dart source code (374 files)
│   ├── main.dart               # App entry point
│   ├── app.dart                # Root App widget, theme, routing
│   ├── alarm/                  # Alarm feature
│   │   ├── data/               # Schema definitions, static data, sort/filter options
│   │   ├── logic/              # Business logic functions and isolate entry points
│   │   │   └── tasks/          # Alarm task logic (arithmetic, etc.)
│   │   ├── screens/            # Full-screen alarm UI (list, notification, tasks)
│   │   ├── types/              # Entity types (Alarm, AlarmSchedule subtypes, etc.)
│   │   │   └── schedules/      # AlarmSchedule strategy implementations
│   │   ├── utils/              # Pure helpers (id generation, next alarm calc)
│   │   └── widgets/            # Alarm-specific widgets and task widgets
│   ├── timer/                  # Timer feature (same sub-structure as alarm)
│   ├── stopwatch/              # Stopwatch feature
│   ├── clock/                  # World clock feature
│   ├── audio/                  # Audio playback (ringtones, session management)
│   ├── common/                 # Shared across all features
│   │   ├── data/               # Shared static data (weekdays, paths, animations)
│   │   ├── logic/              # Shared logic helpers
│   │   ├── types/              # Shared abstract types (ListItem, Json, Tag, etc.)
│   │   ├── utils/              # Pure utility functions (duration, datetime, color)
│   │   └── widgets/            # Shared UI components (lists, fields, color picker)
│   │       ├── clock/          # Analog clock widget
│   │       ├── color_picker/   # Color picker widget
│   │       ├── fields/         # Form field widgets (select, date, etc.)
│   │       │   └── select_field/
│   │       └── list/           # Reusable list widgets (PersistentListView, etc.)
│   │           └── animated_reorderable_list/
│   ├── settings/               # Settings system
│   │   ├── data/               # App-wide settings schema definitions
│   │   ├── logic/              # Settings initialization and storage
│   │   ├── screens/            # Settings UI screens
│   │   ├── types/              # Setting/SettingGroup type hierarchy
│   │   ├── utils/              # Settings helpers
│   │   └── widgets/            # Settings card widgets
│   ├── theme/                  # Theming system
│   │   ├── data/               # Color scheme and style theme defaults/schemas
│   │   ├── logic/              # Theme extension helper
│   │   ├── screens/            # Theme picker screen
│   │   ├── types/              # ColorSchemeData, StyleTheme, ThemeExtension
│   │   ├── utils/              # Color scheme/style theme utilities
│   │   └── widgets/            # Theme cards
│   ├── notifications/          # Notification display and handling
│   │   ├── data/               # Channel keys, action keys, notification intervals
│   │   ├── logic/              # showAlarmNotification, listeners, foreground task
│   │   ├── types/              # AlarmNotificationArguments, FullscreenNotificationData
│   │   └── widgets/            # Notification action widgets
│   ├── navigation/             # Navigation scaffolding
│   │   ├── data/               # Tab definitions, route observer
│   │   ├── screens/            # NavScaffold
│   │   ├── types/              # Routes, Tab, QuickActionController, AppVisibility
│   │   └── widgets/            # AppNavigationBar, AppTopBar
│   ├── system/                 # Platform and lifecycle integration
│   │   ├── data/               # App info, device info
│   │   ├── logic/              # Boot handler, intents, permissions, quick actions
│   │   └── types/              # AndroidPlatformFile
│   ├── onboarding/             # First-launch onboarding screen
│   │   └── screens/
│   ├── developer/              # Developer/debug tooling
│   │   ├── data/               # Developer settings schema
│   │   ├── logic/              # Logger setup
│   │   ├── screens/            # Alarm events log screen
│   │   ├── types/              # FileLoggerOutput, log filter
│   │   └── widgets/            # Developer widgets
│   ├── widgets/                # Android home screen widgets
│   │   ├── data/               # Widget settings schema
│   │   └── logic/              # HomeWidget update logic
│   ├── icons/                  # Custom icon font definitions (`FluxIcons`)
│   └── l10n/                   # ARB localisation files (30+ languages)
├── android/                    # Android platform project
│   └── app/src/main/kotlin/com/vicolo/chrono/
│       ├── MainActivity.kt
│       ├── DigitalClockWidgetProvider.kt
│       └── AnalogueClockWidgetProvider.kt
├── assets/                     # Static assets
│   ├── images/                 # App images
│   ├── ringtones/              # Bundled ringtone audio files
│   ├── contributors/avatars/   # Contributor avatar images
│   └── patreons/               # Patron images
├── fonts/Rubik/                # Rubik font files (app default typeface)
├── test/                       # Flutter tests (mirrors lib/ structure)
│   ├── alarm/
│   ├── timer/
│   ├── clock/
│   ├── common/
│   ├── settings/
│   └── theme/
├── scripts/                    # Build/utility scripts
├── fastlane/                   # App store metadata and changelogs
├── pubspec.yaml                # Flutter package manifest
├── analysis_options.yaml       # Dart analysis configuration
└── l10n.yaml                   # Localisation generation config
```

## Directory Purposes

**`lib/alarm/`:**
- Purpose: Complete alarm feature — creating, editing, scheduling, ringing
- Contains: Schedule strategies, alarm entity, notification screen, task widgets
- Key files: `types/alarm.dart`, `logic/alarm_isolate.dart`, `logic/schedule_alarm.dart`, `screens/alarm_screen.dart`

**`lib/timer/`:**
- Purpose: Countdown timer feature
- Contains: Timer entity, preset management, timer UI
- Key files: `types/timer.dart`, `logic/update_timers.dart`, `screens/timer_screen.dart`

**`lib/stopwatch/`:**
- Purpose: Single stopwatch with lap tracking
- Contains: Stopwatch entity, lap type, notification logic
- Key files: `types/stopwatch.dart`, `screens/stopwatch_screen.dart`

**`lib/clock/`:**
- Purpose: World clock displaying times in user-selected timezone cities
- Contains: City/timezone types, timezone SQLite database helper, clock widgets
- Key files: `types/city.dart`, `logic/timezone_database.dart`, `screens/clock_screen.dart`

**`lib/common/`:**
- Purpose: Cross-feature shared code that belongs to no single feature
- Contains: Abstract types (`ListItem`, `Tag`, `Json`), utility functions, shared widgets
- Key files: `utils/list_storage.dart`, `types/list_item.dart`, `widgets/list/persistent_list_view.dart`

**`lib/settings/`:**
- Purpose: Typed hierarchical settings system with JSON persistence
- Contains: `Setting<T>` type hierarchy, `SettingGroup`, schema builders, settings UI cards
- Key files: `types/setting.dart`, `types/setting_group.dart`, `data/settings_schema.dart`

**`lib/theme/`:**
- Purpose: App-wide theming: color schemes, style themes, Material You support
- Contains: `ThemeData` factory, `ColorSchemeData`, `StyleTheme`, per-widget theme components
- Key files: `theme.dart`, `types/color_scheme.dart`, `types/style_theme.dart`, `data/appearance_settings_schema.dart`

**`lib/notifications/`:**
- Purpose: All notification creation, handling, and action routing
- Contains: Full-screen alarm/timer notification logic, `awesome_notifications` integration
- Key files: `alarm_notifications.dart`, `notifications_listeners.dart`, `notifications.dart`

**`lib/system/`:**
- Purpose: Android platform lifecycle (boot, intents, foreground service, permissions)
- Contains: Boot handler, isolate port initialiser, intent handler, background service
- Key files: `logic/handle_boot.dart`, `logic/initialize_isolate.dart`, `logic/initialize_isolate_ports.dart`

**`lib/audio/`:**
- Purpose: Audio playback for ringtones (alarms, timers, preview)
- Contains: `RingtonePlayer` (static `just_audio` wrapper), ringtone URI resolution
- Key files: `types/ringtone_player.dart`, `logic/ringtones.dart`, `types/ringtone_manager.dart`

**`lib/navigation/`:**
- Purpose: Top-level navigation shell and route registry
- Contains: `NavScaffold`, tab definitions, `Routes` singleton, `AppNavigationBar`
- Key files: `screens/nav_scaffold.dart`, `data/tabs.dart`, `types/routes.dart`

**`lib/widgets/`:**
- Purpose: Android home screen widget support (Digital Clock widget)
- Contains: Widget settings schema, `HomeWidget` update logic
- Key files: `logic/update_widgets.dart`, `data/widget_settings_schema.dart`

**`test/`:**
- Purpose: Flutter unit and widget tests, mirroring `lib/` directory structure
- Generated: No
- Committed: Yes

## Key File Locations

**Entry Points:**
- `lib/main.dart`: App startup — platform init, storage init, `runApp(App())`
- `lib/system/logic/handle_boot.dart`: BOOT_COMPLETED broadcast receiver entry point
- `lib/alarm/logic/alarm_isolate.dart`: `triggerScheduledNotification()` — AndroidAlarmManager isolate entry

**Configuration:**
- `lib/settings/data/settings_schema.dart`: Root `appSettings` singleton; all feature schemas assembled here
- `lib/alarm/data/alarm_settings_schema.dart`: Per-alarm default settings structure
- `lib/timer/data/timer_settings_schema.dart`: Per-timer default settings structure
- `lib/theme/data/appearance_settings_schema.dart`: Appearance/theme settings schema
- `pubspec.yaml`: Dependencies and asset declarations
- `l10n.yaml`: ARB localisation configuration

**Core Logic:**
- `lib/alarm/logic/alarm_isolate.dart`: Isolate-side alarm trigger/stop handling
- `lib/alarm/logic/schedule_alarm.dart`: `scheduleAlarm()` / `cancelAlarm()` via AndroidAlarmManager
- `lib/alarm/logic/update_alarms.dart`: `updateAlarms()` — reschedule all alarms on boot/trigger
- `lib/timer/logic/update_timers.dart`: `updateTimers()` — mirror of alarm update pattern
- `lib/common/utils/list_storage.dart`: All file-based persistence (load/save lists and text files)
- `lib/settings/logic/initialize_settings.dart`: `initializeStorage()` + `initializeSettings()`

**Theme:**
- `lib/theme/theme.dart`: `defaultTheme` and `getTheme()` factory
- `lib/theme/data/default_color_schemes.dart`: Built-in color palette options
- `lib/theme/data/default_style_themes.dart`: Built-in style theme options

**Notifications:**
- `lib/notifications/logic/alarm_notifications.dart`: `showAlarmNotification()`, `dismissAlarm()`, `snoozeAlarm()`
- `lib/notifications/logic/notifications_listeners.dart`: `AwesomeNotifications` action listener setup

**Android Native:**
- `android/app/src/main/kotlin/com/vicolo/chrono/MainActivity.kt`: Flutter host activity
- `android/app/src/main/kotlin/com/vicolo/chrono/DigitalClockWidgetProvider.kt`: Home screen widget
- `android/app/src/main/kotlin/com/vicolo/chrono/AnalogueClockWidgetProvider.kt`: Analogue home screen widget

## Naming Conventions

**Files:**
- `snake_case.dart` for all Dart files (e.g., `alarm_screen.dart`, `list_storage.dart`)
- `_schema` suffix for setting schema definitions (e.g., `alarm_settings_schema.dart`)
- `_type` or plural nouns for data-only constant files (e.g., `time_icons.dart`, `weekdays.dart`)
- `update_` prefix for functions that persist mutated state (e.g., `update_alarms.dart`)

**Directories:**
- Feature directories at `lib/{feature}/` in lowercase (e.g., `alarm`, `timer`, `clock`)
- Consistent subdirectory names across all features: `data/`, `logic/`, `types/`, `screens/`, `widgets/`

**Classes:**
- PascalCase: `Alarm`, `ClockTimer`, `AlarmSchedule`, `SettingGroup`
- Screen classes: `{Feature}Screen` (e.g., `AlarmScreen`, `TimerScreen`)
- Notification screen classes: `{Feature}NotificationScreen`
- Type/entity classes: plain domain noun (e.g., `Alarm`, `ClockTimer`, `ClockStopwatch`)
- Schedule strategy classes: `{Type}AlarmSchedule` (e.g., `DailyAlarmSchedule`, `WeeklyAlarmSchedule`)

**Functions:**
- camelCase: `scheduleAlarm`, `updateAlarms`, `triggerScheduledNotification`
- Async functions that interact with disk or platform: `async`/`await` throughout

## Where to Add New Code

**New Feature (e.g., a new app tab):**
- Create `lib/{feature}/` with `data/`, `logic/`, `types/`, `screens/`, `widgets/`
- Add tab entry in `lib/navigation/data/tabs.dart`
- Add feature settings schema to `lib/settings/data/settings_schema.dart`

**New Setting:**
- Define the `Setting<T>` instance in the relevant `lib/{feature}/data/{feature}_settings_schema.dart`
- Access it via `appSettings.getGroup("{Feature}").getSetting("{Name}").value` in logic/UI

**New Alarm Schedule Type:**
- Create `lib/alarm/types/schedules/{type}_alarm_schedule.dart` implementing `AlarmSchedule`
- Add to `createSchedules()` in `lib/alarm/types/alarm.dart`
- Add `fromJson` branch in `Alarm.fromJson()`

**New Widget Card (UI):**
- Place in `lib/{feature}/widgets/{name}_card.dart`
- For shared widgets usable across features: `lib/common/widgets/`

**New Setting Card Widget:**
- Place in `lib/settings/widgets/{type}_setting_card.dart`

**New Utility Function:**
- Feature-specific: `lib/{feature}/utils/{name}.dart`
- Shared across features: `lib/common/utils/{name}.dart`

**New Notification Action:**
- Add action key in `lib/notifications/data/action_keys.dart`
- Handle in `handleAlarmNotificationAction()` in `lib/notifications/logic/alarm_notifications.dart`

**Tests:**
- Mirror the `lib/` path under `test/` (e.g., `lib/alarm/logic/foo.dart` → `test/alarm/logic/foo_test.dart`)

## Special Directories

**`lib/l10n/`:**
- Purpose: ARB (Application Resource Bundle) localisation strings for 30+ languages
- Generated: Dart code generated to `lib/flutter_gen/gen_l10n/` (gitignored)
- Committed: Yes (the ARB source files are committed)

**`fastlane/metadata/`:**
- Purpose: F-Droid and Play Store store listing metadata and changelogs per locale
- Generated: No
- Committed: Yes

**`assets/ringtones/`:**
- Purpose: Bundled audio files for default alarm/timer ringtones
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-05-30*
