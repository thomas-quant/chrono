# Coding Conventions

**Analysis Date:** 2026-05-30

## Naming Patterns

**Files:**
- `snake_case.dart` for all Dart source files (e.g., `alarm_card.dart`, `switch_field.dart`, `date_time.dart`)
- Filenames match their primary class or concept (e.g., `alarm_runner.dart` contains `AlarmRunner`)
- Test files mirror source structure: `lib/alarm/types/alarm_runner.dart` → `test/alarm/types/alarm_runner_test.dart`

**Classes:**
- `UpperCamelCase` for all classes, enums, abstract classes, and mixins
- Widget classes: `AlarmCard`, `SwitchField`, `SliderField`, `ToggleField`
- State classes: `_AlarmCardState`, `_SwitchFieldState` (prefixed with `_` and suffixed with `State`)
- Abstract base classes: `AlarmSchedule`, `JsonSerializable`, `ListItem`, `SettingItem`
- Generic settings typed by their value: `Setting<T>`, `SwitchSetting`, `SliderSetting`, `SelectSetting<T>`, `ToggleSetting<T>`

**Functions and Methods:**
- `camelCase` for all functions, methods, and local variables
- Utility functions are top-level, not static class members: `getScheduleDateForTime()`, `scheduleAlarm()`, `cancelAlarm()`
- Boolean getters use `is`/`can`/`has`/`should` prefixes: `isEnabled`, `isFinished`, `canBeSnoozed`, `hasId()`, `shouldSkipNextAlarm`
- JSON round-trip methods always named exactly `toJson()` and `fromJson()`
- Named constructors follow the `ClassName.fromX()` / `ClassName.fromJson()` pattern

**Variables:**
- `camelCase` for local and instance variables
- Private fields prefixed with `_`: `_isEnabled`, `_snoozeTime`, `_schedules`
- Constants use `camelCase` in `const` declarations (e.g., `const testKey = Key('key')`)

**Types:**
- Type alias at `lib/common/types/json.dart`: `typedef Json = Map<String, dynamic>?`

## Code Style

**Formatting:**
- Tool: Dart formatter (`dart format`) via `flutter analyze` / VS Code
- Config: `analysis_options.yaml` — extends `package:flutter_lints/flutter.yaml`
- No additional lint rules are enabled beyond the flutter_lints defaults
- Single-quotes are NOT enforced (double-quote strings appear throughout)

**Linting:**
- `flutter_lints ^3.0.1` — standard Flutter recommended ruleset
- `dart_code_metrics ^5.5.1` — installed as dev dependency (metrics analysis)
- Inline suppression via `// ignore: rule_name` where needed

## Import Organization

Imports are grouped in this order within each file, with a blank line between groups:

1. `dart:*` — Dart core libraries (`dart:core`, `dart:io`, `dart:async`, `dart:convert`)
2. Third-party packages — alphabetical (`package:android_alarm_manager_plus/...`, `package:awesome_notifications/...`)
3. Project imports — alphabetical by feature module (`package:clock_app/alarm/...`, then `package:clock_app/common/...`, then `package:clock_app/settings/...`)
4. Flutter/generated imports — `package:flutter/material.dart`, `package:flutter_gen/gen_l10n/app_localizations.dart`

Examples:
- `lib/main.dart`: `dart:core` → third-party packages → `clock_app/*` → `flutter/material.dart`
- `lib/notifications/logic/alarm_notifications.dart`: `dart:*` → third-party → `clock_app/*`

**Path Aliases:**
- No path aliases configured. All imports use full `package:clock_app/...` paths.
- Generated l10n: `package:flutter_gen/gen_l10n/app_localizations.dart`

## Error Handling

**General pattern — catch, log with `logger`, then recover or rethrow:**

```dart
} catch (e) {
  logger.e("Error loading list ($key): $e");
  return [];
}
```

**Throw on precondition failure:**

```dart
if (startDate.isBefore(now)) {
  throw Exception(
      'Attempted to schedule alarm in the past. Schedule time: $startDate, current time: $now');
}
```

**Rethrow when caller must handle:**

```dart
} catch (e) {
  logger.e("Error decoding string: ${e.toString()}");
  rethrow;
}
// lib/common/utils/json_serialize.dart
```

**Test environment guarding** — platform-specific code checks `FLUTTER_TEST` env var before executing device calls:

```dart
if (!Platform.environment.containsKey('FLUTTER_TEST')) {
  AndroidAlarmManager.cancel(scheduleId);
}
// lib/alarm/logic/schedule_alarm.dart
```

**Flutter error handler** — used in isolates:

```dart
FlutterError.onError = (FlutterErrorDetails details) {
  logger.f("Error in triggerScheduledNotification isolate: ${details.exception.toString()}");
};
// lib/alarm/logic/alarm_isolate.dart
```

## Logging

**Framework:** `logger` package (`^2.4.0`) via a singleton at `lib/developer/logic/logger.dart`

```dart
var logger = Logger(
  filter: FileLogFilter(),
  output: FileLoggerOutput(),
  printer: PrettyPrinter(methodCount: 100, errorMethodCount: 100, ...),
);
```

**Log levels used:**
- `logger.t()` — trace: low-level scheduling details
- `logger.i()` — info: significant lifecycle events (alarm triggered, canceled)
- `logger.e()` — error: caught exceptions with context message
- `logger.f()` — fatal: isolate-level crash handler
- `logger.d()` — debug: filter evaluation, non-critical paths

**Pattern:**
```dart
logger.e("Error loading melody from directory: $e");
logger.i("Alarm triggered $scheduleId");
```

Log messages always include context (variable values, operation name). No bare `print()` in production code.

## Comments

**When to comment:**
- `///` doc comments on public getters/methods that have non-obvious semantics:
  ```dart
  /// If an alarm is enabled, it has an active schedule.
  bool get isEnabled => _isEnabled;

  /// The date and time when the snoozed alarm will ring again.
  /// Will return null if the alarm is not snoozed.
  DateTime? get snoozeTime => _snoozeTime;
  // lib/alarm/types/alarm.dart
  ```
- `//` inline comments for intentional no-ops, guarded platform code, or migration stubs
- Commented-out code blocks appear with no surrounding explanation — accepted but not preferred

**TSDoc/Dartdoc:**
- `///` triple-slash style for public API documentation
- Used selectively on complex types (`Alarm`, `Setting`), not on every getter

## Function Design

**Size:** Generally small, single-responsibility. Top-level logic functions (`scheduleAlarm`, `updateAlarms`) are larger (60–140 lines) but clearly scoped.

**Parameters:** Named parameters used for all widget constructors with `required` where mandatory. Optional parameters use default values:

```dart
Future<void> scheduleAlarm(
  int scheduleId,
  DateTime startDate,
  String description, {
  ScheduledNotificationType type = ScheduledNotificationType.alarm,
  bool alarmClock = true,
  bool snooze = false,
}) async { ... }
```

**Return Values:**
- `Future<void>` for async operations that produce side effects
- Nullable return (`DateTime?`, `Json?`) when absence is semantically meaningful
- Extension methods for type-specific conversions: `DateTime.toHours()`, `DateTime.toTimeOfDay()`

## Module Design

**Exports:** No barrel files. Each file exports only its own declarations. Consumers import the specific file directly.

**Extension Methods:** Used for utility grouping on built-in types:
- `lib/common/utils/date_time.dart` — `extension DateTimeUtils on DateTime`
- `lib/common/utils/duration.dart` — `extension DurationUtils on Duration`
- `lib/common/utils/list.dart` — `extension ListUtils<T> on List<T>`
- `lib/common/utils/time_of_day.dart` — `extension TimeOfDayUtils on TimeOfDay`

**Abstract Base Classes:** Core domain abstractions:
- `JsonSerializable` — `lib/common/types/json.dart` (toJson / fromJson contract)
- `ListItem` — `lib/common/types/list_item.dart`
- `AlarmSchedule` — `lib/alarm/types/schedules/alarm_schedule.dart`
- `Setting<T>` — `lib/settings/types/setting.dart`

**`const` constructors:** Used consistently on widget constructors and immutable value types:
```dart
const SwitchField({super.key, required this.value, ...});
const TimeDuration({this.hours = 0, ...});
const EdgeInsets.symmetric(horizontal: 16.0);
```

**`late` fields in StatefulWidget State:** Used for settings listeners and controllers that are initialized in `initState()`:
```dart
late Setting dateFormatSetting;
late Setting timeFormatSetting;
// lib/alarm/widgets/alarm_card.dart
```

**StatefulWidget pattern:** Always split into `WidgetName extends StatefulWidget` + `_WidgetNameState extends State<WidgetName>`. State class is always private.

---

*Convention analysis: 2026-05-30*
