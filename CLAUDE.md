<!-- GSD:project-start source:PROJECT.md -->
## Project

**Chrono — Reliability + QR Dismiss Task Milestone**

Chrono is a feature-rich, open-source (vicolo-dev) alarm, timer, stopwatch, and world-clock app for Android, built in Flutter with Material You theming and 20+ translations. This milestone has two thrusts: (1) add a **QR/barcode scan-to-dismiss** alarm task — scan a pre-registered code to turn the alarm off, inspired by Alarmy — and (2) fix the **reliability bugs** that are currently causing missed alarms and lost users.

**Core Value:** The alarm must reliably ring and reliably stop. An alarm app that crashes on boot, fails to ring, or won't snooze/dismiss correctly has failed at its one job — that comes before any new feature.

### Constraints

- **Tech stack**: Flutter 3.22.x / Dart 3.4+, Android-only; Kotlin 1.8, Java 17. **minSdk 23** (raised from 21 this milestone), compileSdk 34. New deps must support this toolchain.
- **Architecture**: No state-management library; `setState` + `ListenerManager` + isolate `IsolateNameServer` ports. Settings are string-keyed `SettingGroup`s serialized to JSON. New task config must follow this pattern.
- **Background execution**: Alarm firing runs in a separate Dart isolate; the scan task UI runs in the alarm notification screen (main isolate) — camera lifecycle must be handled there, not in the firing isolate.
- **Licensing**: Open-source project — clean-room only; no decompiled or copied Alarmy code/assets.
- **Accessibility / ethics**: Dismiss challenges must not trap users — escape hatch on by default; keep tasks optional; escape hatch must be screen-reader-reachable (it is also the accessibility path).
- **Distribution**: Google Play (AAB) + GitHub Releases (APK) + F-Droid. F-Droid forbids proprietary blobs — the scanner library MUST be FOSS-clean (verified exit criterion: zero `mlkit`/`gms`/`play-services` in the Gradle graph).
<!-- GSD:project-end -->

<!-- TESTING POLICY (hand-maintained — intentionally OUTSIDE GSD-managed blocks; do not let regeneration clobber it) -->
## Testing Policy — default Flutter/Dart testing to GitHub Actions

**Maximize automated testing in CI, and design code so more of it can run there.** For every phase and every plan, route all testing that *can* run in `flutter test` onto GitHub Actions — not just trivial unit tests.

- **What CI runs today:** `tests.yml` → `flutter test --coverage` on a headless `ubuntu-latest` runner (no emulator). This executes **unit tests AND headless widget tests** (`WidgetTester` / `pumpWidget`). `test-apk.yml` additionally runs `flutter analyze` and builds a sideloadable dev APK.
- **Default behavior:** author CI-runnable tests for every fix/feature. When the real behavior is awkward to test directly (audio playback, isolate scheduling, full-screen layout), **extract a pure, dependency-free seam** (a controller/function with an injectable clock/Timer and callbacks) and unit-test that seam in CI. Prefer testability-by-design over "untestable — verify on device."
- **On-device / instrumented testing is a *complementary* gate, never a substitute** for what CI can run. Reserve human/on-device checks only for what CI genuinely cannot do: real alarm firing, real `just_audio` playback, lock-screen, reboot, true cross-OEM pixel layout. There is currently **no emulator / `integration_test` job**; adding one (`reactivecircus/android-emulator-runner`) is a separate, deferrable infra decision — propose it explicitly rather than assuming it.
- **Local toolchain is absent** (`flutter`/`dart` are not installed in the dev environment): tests are *authored in-repo* and confirmed **green via CI** — never reported as locally passing when they were not run. CI is the authoritative gate; `flutter analyze` and `flutter gen-l10n` are likewise CI/human gates.
<!-- END TESTING POLICY -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Dart 3.4.0+ - All Flutter application logic in `lib/`
- Kotlin 1.8.0 - Native Android code in `android/app/src/main/kotlin/com/vicolo/chrono/`
- XML - Android resources, manifests, and widget layouts in `android/app/src/main/res/`
- Python 3.x - Build scripts in `scripts/contributors.py` and `scripts/patreons.py`
## Runtime
- Flutter 3.22.2 (stable channel, pinned in CI workflows)
- Android only — no iOS, web, or desktop targets configured in build workflows
- Pub (Flutter/Dart package manager)
- Lockfile: `pubspec.lock` present and committed
## Frameworks
- Flutter 3.22.x (SDK `>=3.22.0`) - Full UI framework; Material Design 3
- Material Design 3 with `uses-material-design: true` in `pubspec.yaml`
- `flutter_test` (SDK built-in) - Widget and unit tests in `test/`
- No additional test framework required; uses built-in Flutter testing
- Gradle 7.6.4 - Android build system (`android/gradle/wrapper/gradle-wrapper.properties`)
- Kotlin 1.8.0 - JVM target `1.8` (`android/build.gradle`)
- Java 17 - CI build environment (`android-build.yml`, `android-release.yml`)
- `change_app_package_name: ^1.1.0` - Dev utility for renaming the app package
- `dependency_validator: ^3.2.3` - Dev utility for checking unused dependencies
- `dart_code_metrics: ^5.5.1` - Static analysis beyond base linting
- `flutter_lints: ^3.0.1` - Standard Flutter lint rules
- `flutter_localizations` (SDK built-in) - ARB-based l10n
- `intl: 0.19.0` - Internationalization support
- `locale_names: ^1.1.1` - Human-readable locale display names
- ARB files in `lib/l10n/` covering 20+ languages (bn, cs, de, en, es, fa, fr, hu, it, ko, nb, nl, pl, pt, ru, sr, ta, tr, uk, vi, zh)
- Config: `l10n.yaml` (`arb-dir: lib/l10n`, template: `app_en.arb`)
## Key Dependencies
- `android_alarm_manager_plus: 4.0.1` (git fork) - Android exact alarm scheduling; forked at `https://github.com/AhsanSarwar45/plus_plugins` branch `alarm_show_intent`
- `awesome_notifications: ^0.9.3` - Full-screen notifications and alarm notification display
- `flutter_foreground_task: 6.5.0` (git fork) - Foreground service for active alarms/timers; forked at `https://github.com/vicolo-dev/flutter_foreground_task`
- `flutter_boot_receiver: ^1.1.0` - Reschedule alarms after device reboot
- `background_fetch: ^1.3.7` - Periodic background task for alarm/timer updates
- `just_audio: ^0.9.31` - Audio playback for ringtones and alarm sounds
- `sqflite: ^2.2.2` - Local SQLite database for timezone data (`assets/timezones.db`)
- `get_storage: ^2.1.1` - Lightweight key-value persistent storage for settings
- `timezone: ^0.9.1` - Timezone-aware datetime handling; uses bundled `assets/timezones.db`
- `path_provider: ^2.0.11` - Access to app data directories
- `permission_handler: ^11.3.1` - Runtime permission requests (alarms, storage, audio)
- `device_info_plus: ^10.1.0` - Android version detection for permission handling
- `package_info_plus: ^6.0.0` - App version and build info
- `home_widget: 0.7.0` (git fork) - Android home screen widgets; forked at `https://github.com/AhsanSarwar45/home_widget`
- `vibration: ^1.7.6` - Haptic feedback for alarms
- `audio_session: ^0.1.13` - Audio focus management
- `flutter_system_ringtones: ^0.0.6` - Access to system ringtone list
- `file_picker: ^8.0.7` - Custom audio file selection
- `receive_intent: ^0.2.5` - Handle Android intents (SET_ALARM, SHOW_ALARMS, etc.)
- `quick_actions: ^1.0.7` - App shortcut actions on long-press launcher icon
- `auto_start_flutter: ^0.1.1` - Guide users to manufacturer auto-start settings
- `move_to_background: ^1.0.2` - Send app to background on back navigation
- `flutter_show_when_locked: ^0.0.4` - Show alarm screen over lock screen
- `flutter_fgbg: ^0.3.0` - Detect app foreground/background transitions
- `flutter_slidable: ^3.1.0` - Swipe actions on list items
- `flutter_animate: ^4.5.0` - Declarative animation framework
- `dynamic_color: ^1.7.0` - Material You dynamic color (Android 12+)
- `material_color_utilities: ^0.8.0` - HCT color space and tonal palettes
- `flex_color_picker: 3.3.0` (git fork) - Color picker widget; forked at `https://github.com/vicolo-dev/flex_color_picker`
- `table_calendar: ^3.0.8` - Calendar widget for date alarm scheduling
- `timer_builder: ^2.0.0` - Reactive widgets that rebuild on a timer
- `analog_clock: ^0.1.1` - Static analog clock face widget
- `animated_analog_clock: ^0.1.0` - Animated analog clock face widget
- `introduction_screen: ^3.1.12` - Onboarding flow screens
- `app_settings: ^5.1.1` - Deep links into system settings screens
- `flutter_html: ^3.0.0-beta.2` - Render HTML content (used for reliability instructions)
- `url_launcher: ^6.2.2` - Open URLs in browser/apps
- `flutter_oss_licenses: ^3.0.2` - Display OSS license information in-app
- `watcher: ^1.1.0` - File system watching
- `queue: ^3.1.0+2` - Task queuing
- `fuzzywuzzy: ^1.1.2` - Fuzzy string matching (timezone city search)
- `vector_math: ^2.1.4` - Vector mathematics for UI animations
- `mime: ^1.0.6` - MIME type detection for audio files
- `clock: ^1.1.1` - Mockable clock abstraction for testing
- `http: ^0.13.6` - HTTP client (imported, currently only used in commented-out code)
- `logger: ^2.4.0` - Structured logging
## Configuration
- No `.env` files used
- Signing configured via `android/key.properties` (gitignored) and `android/app/release-key.jks` (gitignored)
- CI secrets: `KEY_PASSWORD`, `KEY_STORE_PASSWORD`, `KEY_ALIAS`, `KEYSTORE_JKS_RELEASE` in GitHub Actions secrets
- `pubspec.yaml` - Dart/Flutter dependencies and asset declarations
- `analysis_options.yaml` - Linting config (extends `package:flutter_lints/flutter.yaml`)
- `android/build.gradle` - Root Gradle config, Kotlin version `1.8.0`
- `android/app/build.gradle` - App Gradle config; compileSdk 34, minSdk 21, two flavors: `prod` (app name "Chrono") and `dev` (app name "Chrono Dev", suffix `.dev`)
- `l10n.yaml` - Localization config
- `.vscode/settings.json` - VS Code project settings
## Platform Requirements
- Flutter SDK 3.22.x (stable)
- Java 17 JDK (for Gradle)
- Android SDK with compile SDK 34
- NDK version managed by Flutter
- Android only (minSdk 21 = Android 5.0+, targeting SDK 34)
- Distributed via: Google Play Store (AAB, `prod` flavor) and GitHub Releases (APK, `prod` flavor)
- F-Droid compatible (fastlane metadata present in `fastlane/metadata/android/`)
- Two flavors: `prod` for release distribution, `dev` for development/testing
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- `snake_case.dart` for all Dart source files (e.g., `alarm_card.dart`, `switch_field.dart`, `date_time.dart`)
- Filenames match their primary class or concept (e.g., `alarm_runner.dart` contains `AlarmRunner`)
- Test files mirror source structure: `lib/alarm/types/alarm_runner.dart` → `test/alarm/types/alarm_runner_test.dart`
- `UpperCamelCase` for all classes, enums, abstract classes, and mixins
- Widget classes: `AlarmCard`, `SwitchField`, `SliderField`, `ToggleField`
- State classes: `_AlarmCardState`, `_SwitchFieldState` (prefixed with `_` and suffixed with `State`)
- Abstract base classes: `AlarmSchedule`, `JsonSerializable`, `ListItem`, `SettingItem`
- Generic settings typed by their value: `Setting<T>`, `SwitchSetting`, `SliderSetting`, `SelectSetting<T>`, `ToggleSetting<T>`
- `camelCase` for all functions, methods, and local variables
- Utility functions are top-level, not static class members: `getScheduleDateForTime()`, `scheduleAlarm()`, `cancelAlarm()`
- Boolean getters use `is`/`can`/`has`/`should` prefixes: `isEnabled`, `isFinished`, `canBeSnoozed`, `hasId()`, `shouldSkipNextAlarm`
- JSON round-trip methods always named exactly `toJson()` and `fromJson()`
- Named constructors follow the `ClassName.fromX()` / `ClassName.fromJson()` pattern
- `camelCase` for local and instance variables
- Private fields prefixed with `_`: `_isEnabled`, `_snoozeTime`, `_schedules`
- Constants use `camelCase` in `const` declarations (e.g., `const testKey = Key('key')`)
- Type alias at `lib/common/types/json.dart`: `typedef Json = Map<String, dynamic>?`
## Code Style
- Tool: Dart formatter (`dart format`) via `flutter analyze` / VS Code
- Config: `analysis_options.yaml` — extends `package:flutter_lints/flutter.yaml`
- No additional lint rules are enabled beyond the flutter_lints defaults
- Single-quotes are NOT enforced (double-quote strings appear throughout)
- `flutter_lints ^3.0.1` — standard Flutter recommended ruleset
- `dart_code_metrics ^5.5.1` — installed as dev dependency (metrics analysis)
- Inline suppression via `// ignore: rule_name` where needed
## Import Organization
- `lib/main.dart`: `dart:core` → third-party packages → `clock_app/*` → `flutter/material.dart`
- `lib/notifications/logic/alarm_notifications.dart`: `dart:*` → third-party → `clock_app/*`
- No path aliases configured. All imports use full `package:clock_app/...` paths.
- Generated l10n: `package:flutter_gen/gen_l10n/app_localizations.dart`
## Error Handling
## Logging
- `logger.t()` — trace: low-level scheduling details
- `logger.i()` — info: significant lifecycle events (alarm triggered, canceled)
- `logger.e()` — error: caught exceptions with context message
- `logger.f()` — fatal: isolate-level crash handler
- `logger.d()` — debug: filter evaluation, non-critical paths
## Comments
- `///` doc comments on public getters/methods that have non-obvious semantics:
- `//` inline comments for intentional no-ops, guarded platform code, or migration stubs
- Commented-out code blocks appear with no surrounding explanation — accepted but not preferred
- `///` triple-slash style for public API documentation
- Used selectively on complex types (`Alarm`, `Setting`), not on every getter
## Function Design
- `Future<void>` for async operations that produce side effects
- Nullable return (`DateTime?`, `Json?`) when absence is semantically meaningful
- Extension methods for type-specific conversions: `DateTime.toHours()`, `DateTime.toTimeOfDay()`
## Module Design
- `lib/common/utils/date_time.dart` — `extension DateTimeUtils on DateTime`
- `lib/common/utils/duration.dart` — `extension DurationUtils on Duration`
- `lib/common/utils/list.dart` — `extension ListUtils<T> on List<T>`
- `lib/common/utils/time_of_day.dart` — `extension TimeOfDayUtils on TimeOfDay`
- `JsonSerializable` — `lib/common/types/json.dart` (toJson / fromJson contract)
- `ListItem` — `lib/common/types/list_item.dart`
- `AlarmSchedule` — `lib/alarm/types/schedules/alarm_schedule.dart`
- `Setting<T>` — `lib/settings/types/setting.dart`
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
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
- Each feature (`alarm`, `timer`, `stopwatch`, `clock`) owns its `data/`, `logic/`, `types/`, `screens/`, and `widgets/` subdirectories
- Settings are a first-class data model: each entity (`Alarm`, `ClockTimer`) embeds a `SettingGroup` that serializes to/from JSON
- Background alarm firing runs in a separate Dart isolate spawned by `android_alarm_manager_plus`; isolates communicate via named `IsolateNameServer` ports
- Persistence is plain JSON text files in the app documents directory (no SQLite except for timezone data)
- No state management library (no Riverpod, Bloc, Provider); UI reloads driven by `setState` + a custom `ListenerManager`
## Layers
- Purpose: Flutter widget tree, user interaction
- Location: `lib/{feature}/screens/`, `lib/{feature}/widgets/`
- Contains: `StatefulWidget`/`StatelessWidget` classes, settings UI cards
- Depends on: domain types, logic functions, `common/widgets/`
- Used by: Flutter framework
- Purpose: Entity state machines, schedule computation, schedule/cancel calls
- Location: `lib/{feature}/types/`, `lib/{feature}/logic/`
- Contains: `Alarm`, `ClockTimer`, `ClockStopwatch`, `AlarmSchedule` subtypes, helper functions
- Depends on: storage utils, `android_alarm_manager_plus`, notifications
- Used by: screens, isolate entry points
- Purpose: Typed hierarchical key-value store, persisted as JSON, with listeners
- Location: `lib/settings/types/`, `lib/settings/data/`
- Contains: `SettingGroup`, `Setting<T>` subtypes, schema definitions
- Depends on: `list_storage.dart` (file I/O), `get_storage` (migration fallback)
- Used by: all features — each `Alarm`/`ClockTimer` embeds a `SettingGroup`
- Purpose: Serialise/deserialise lists and text to JSON files on disk
- Location: `lib/common/utils/list_storage.dart`
- Contains: `loadList`, `saveList`, `loadTextFile`, `saveTextFile`; a `Queue` to serialize concurrent writes
- Depends on: `path_provider`, `path`, file system
- Used by: alarm/timer update functions, settings group `load()`/`save()`
- Purpose: Display and respond to full-screen alarm/timer notifications
- Location: `lib/notifications/`
- Contains: notification channel config, `showAlarmNotification`, listener/action handlers
- Depends on: `awesome_notifications`, `android_alarm_manager_plus`
- Used by: alarm isolate, main isolate
- Purpose: App boot, background service, device info, intent handling, permissions
- Location: `lib/system/`
- Contains: `handleBoot`, `initializeIsolate`, `initializeIsolatePorts`, background service
- Depends on: `flutter_foreground_task`, `flutter_boot_receiver`, `receive_intent`
- Used by: `main.dart`, `NavScaffold`
- Purpose: Dynamic theming with Material You support, color schemes, style themes
- Location: `lib/theme/`
- Contains: `ThemeData` factory (`getTheme`), `ColorSchemeData`, `StyleTheme`, widget-level theme components
- Depends on: `dynamic_color`, `material_color_utilities`
- Used by: `App` widget root
## Data Flow
### Alarm Trigger Path (primary background flow)
### User Creating an Alarm (UI flow)
### App Boot
- No centralized state management library
- `setState` for widget-local state
- `Setting.addListener` / `removeListener` for cross-widget setting changes
- `ListenerManager.notifyListeners(key)` for cross-isolate updates (alarm/timer list changes)
- `PersistentListController` + `PersistentListView` for list state
## Key Abstractions
- Purpose: Base interface for all persistable list entities (alarms, timers)
- Examples: `lib/alarm/types/alarm.dart`, `lib/timer/types/timer.dart`
- Pattern: Implements `JsonSerializable` (`toJson()` / `fromJson()`), has `id`, `copy()`, `copyFrom()`
- Purpose: Pluggable schedule strategy for alarms
- Examples: `lib/alarm/types/schedules/once_alarm_schedule.dart`, `weekly_alarm_schedule.dart`, `range_alarm_schedule.dart`
- Pattern: Strategy pattern — `Alarm` holds a list of all schedule types and activates the one matching `scheduleType`
- Purpose: Typed, hierarchical, listener-notifying settings with JSON persistence
- Examples: `lib/settings/types/setting_group.dart`, `lib/settings/types/setting.dart`
- Pattern: Composite tree; each entity embeds a copy of the default settings group from `appSettings`
- Purpose: Generic list widget that owns reload, add, delete, reorder, filter, sort
- Examples: Used in `AlarmScreen`, `TimerScreen`
- Pattern: The widget holds a `PersistentListController` that bridges UI actions to disk I/O
## Entry Points
- Location: `lib/main.dart`
- Triggers: App launch
- Responsibilities: Platform init, storage init, settings load, alarm/timer reschedule, `runApp`
- Location: `lib/system/logic/handle_boot.dart`
- Triggers: Android BOOT_COMPLETED broadcast (via `flutter_boot_receiver`)
- Responsibilities: `initializeIsolate()`, `updateAlarms()`, `updateTimers()`
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
### Commented-out migration code left in SettingGroup
## Error Handling
- Storage errors: caught in `loadList`/`loadTextFile`, logged via `logger.e()`, returns empty list or empty string
- Settings group lookup failures: logged then rethrown (`lib/settings/types/setting_group.dart:103-110`)
- Isolate errors: `FlutterError.onError` set to log via `logger.f()` in isolate entry points
- UI-layer errors: generally surface as missing data (null-safe getters) rather than crashes
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
