# Testing Patterns

**Analysis Date:** 2026-05-30

## Test Framework

**Runner:**
- `flutter_test` (Flutter SDK) — the sole test runner
- No separate config file; tests run via `flutter test`
- `TestWidgetsFlutterBinding.ensureInitialized()` called manually in tests that schedule alarms or interact with platform channels

**Assertion Library:**
- `flutter_test` built-in: `expect()`, `find.*`, `isA<T>()`, `isTrue`, `isFalse`, `findsOneWidget`, `findsNothing`, `throwsA()`

**Run Commands:**
```bash
flutter test              # Run all tests
flutter test --watch      # Watch mode (not built-in, use test_cov or re-run manually)
flutter test --coverage   # Generate coverage report
```

## Test File Organization

**Location:** Tests live in a separate `test/` tree that mirrors `lib/`'s feature module structure.

```
test/
├── alarm/
│   ├── logic/
│   │   ├── alarm_time.dart              # helper (no _test suffix — reusable test utilities)
│   │   └── schedule_description_test.dart
│   ├── types/
│   │   ├── alarm_runner_test.dart
│   │   └── schedules/
│   │       ├── daily_alarm_schedule_test.dart
│   │       ├── once_alarm_schedule_test.dart
│   │       └── weekly_alarm_schedule_test.dart
│   └── widgets/
│       └── alarm_card_test.dart
├── clock/
│   └── widgets/
│       ├── time_display_test.dart
│       ├── timezone_card_test.dart
│       └── timezone_search_card_test.dart
├── common/
│   ├── utils/
│   │   ├── date_time_utils_test.dart
│   │   ├── duration_utils_test.dart
│   │   ├── time_of_day_utils_test.dart
│   │   └── weekday_utils_test.dart
│   └── widgets/
│       ├── time_picker_test.dart
│       └── fields/
│           ├── date_picker_field_test.dart
│           ├── input_field_test.dart
│           ├── select_field_test.dart
│           ├── slider_field_test.dart
│           ├── switch_field_test.dart
│           └── toggle_field_test.dart
├── settings/
│   └── widget/
│       └── setting_group_card_test.dart   # fully commented out — placeholder only
├── theme/
│   └── widgets/
│       ├── theme_card_test.dart
│       └── theme_preview_card_test.dart
└── timer/
    └── widgets/
        └── timer_card_test.dart
```

**Naming:**
- Test files: `<subject>_test.dart` — the `_test` suffix is required for `flutter test` discovery
- Helper files without the `_test` suffix (e.g., `test/alarm/logic/alarm_time.dart`) are reusable test utility modules, not discovered as test suites on their own

## Test Structure

**Suite Organization:**

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // only when needed for platform channels

  setUp(() {
    // Reset shared state before each test
    schedule = DailyAlarmSchedule();
  });

  group('ClassName', () {
    group('methodName()', () {
      test('returns X when Y', () async {
        // arrange
        const time = Time(hour: 10, minute: 30);
        // act
        await schedule.schedule(time, 'test');
        // assert
        expect(schedule.currentScheduleDateTime?.hour, time.hour);
      });
    });
  });
}
```

**Patterns:**
- Top-level `main()` function contains all test declarations
- `group()` nesting: class name → method name → scenario
- `setUp()` resets mutable module-level state (declared at top of file)
- `async`/`await` used throughout for methods that call `scheduleAlarm` or other async ops
- Test descriptions use natural language: `'returns null before scheduling'`, `'schedules alarm in the future'`

## Mocking

**Framework:** No mocking library (no `mockito`, `mocktail`, or similar). Tests rely on real implementations.

**Test environment guarding** replaces mocking for platform code. Production source files check `Platform.environment.containsKey('FLUTTER_TEST')` to skip device-specific calls:

```dart
// lib/alarm/logic/schedule_alarm.dart
if (!Platform.environment.containsKey('FLUTTER_TEST')) {
  AndroidAlarmManager.cancel(scheduleId);
}
```

This means `AlarmRunner.schedule()`, `DailyAlarmSchedule.schedule()`, etc. can be called in tests without triggering Android alarm manager calls. The guard is in the source — not injected.

**What is tested with real objects:**
- All domain types: `Alarm`, `AlarmRunner`, `DailyAlarmSchedule`, `WeeklyAlarmSchedule`, `TimeDuration`
- All utility extensions: `DateTimeUtils`, `WeekdayUtils`, `DurationUtils`
- All field widgets: `SwitchField`, `ToggleField`, `SliderField`, `SelectField`, `InputField`

**What is NOT mocked or tested:**
- `AndroidAlarmManager` (guarded out in test env)
- `AwesomeNotifications`
- `Logger` / `FileLoggerOutput`
- Storage (`GetStorage`, file I/O)

## Fixtures and Factories

**Test Data:** Module-level variables declared at the top of each test file, reset in `setUp()`:

```dart
// Reusable instances — reset in setUp to ensure test isolation
DailyAlarmSchedule schedule = DailyAlarmSchedule();

void main() {
  setUp(() {
    schedule = DailyAlarmSchedule();
  });
  ...
}
```

```dart
// Fixed DateTimes for deterministic time tests
DateTime currentDate = DateTime(2000, 1, 10, 10, 0);
// test/alarm/logic/alarm_time.dart
```

**Clock control for time-sensitive logic:** The `clock` package (`^1.1.1`) is used to freeze time in logic tests:

```dart
withClock(
  Clock.fixed(currentDate),   // freeze "now" to a known DateTime
  () {
    DateTime scheduledDateTime = getScheduleDateForTime(scheduleTime, ...);
    expect(scheduledDateTime, ...);
  },
);
// test/alarm/logic/alarm_time.dart
```

**Reusable test helper functions:** Extracted to top-level private functions or shared helper files:

```dart
// Widget rendering extracted to _renderWidget helper in each test file
Future<void> _renderWidget(WidgetTester tester, {bool isSelected = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: defaultTheme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ThemeCard(...)),
    ),
  );
}
// test/theme/widgets/theme_card_test.dart
```

**Shared helper module:**
- `test/alarm/logic/alarm_time.dart` — reusable `testGetScheduleDateForTime()` helper imported by related test files

**Location:** No centralized fixtures directory. Each test file defines its own inline test data.

## Coverage

**Requirements:** No enforced coverage threshold. No `.coveragerc` or coverage configuration file present.

**View Coverage:**
```bash
flutter test --coverage
# Generates lcov.info at coverage/lcov.info
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Types

**Unit Tests:**
- Scope: pure Dart logic — schedule calculations, JSON serialization, utility extensions, domain type methods
- Files: `test/*/logic/`, `test/*/types/`, `test/common/utils/`
- Use `test()` directly; no widget harness needed
- Example: `test/alarm/types/alarm_runner_test.dart`, `test/common/utils/date_time_utils_test.dart`

**Widget Tests:**
- Scope: individual Flutter widgets rendered in isolation via `WidgetTester`
- Files: `test/*/widgets/`, `test/common/widgets/`
- Use `testWidgets()` with `tester.pumpWidget()` and `find.*`
- Always wrap in `MaterialApp` with `locale`, `localizationsDelegates`, and `supportedLocales`
- Example: `test/alarm/widgets/alarm_card_test.dart`, `test/common/widgets/fields/switch_field_test.dart`

**Integration Tests:** Not present. No `integration_test/` directory or `integration_test` package dependency.

**E2E Tests:** Not used.

## Common Patterns

**Widget test boilerplate — always wrap with full locale setup:**
```dart
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: defaultTheme,           // include when widget reads Theme.of(context)
    home: Scaffold(
      body: YourWidget(...),
    ),
  ),
);
```

**Async testing — always `await` schedule operations:**
```dart
test('schedule sets currentScheduleDateTime to correct value', () async {
  const time = Time(hour: 10, minute: 30);
  await schedule.schedule(time, 'test');
  expect(schedule.currentScheduleDateTime?.hour, time.hour);
});
```

**Exception testing:**
```dart
test('in the past throws exception', () async {
  expect(
      () async => await alarmRunner.schedule(
          DateTime.now().subtract(const Duration(minutes: 1)), 'test'),
      throwsA(isA<Exception>()));
});
// test/alarm/types/alarm_runner_test.dart
```

**JSON round-trip testing — always test both `toJson()` and `fromJson()`:**
```dart
test('toJson() returns correct value', () async {
  await schedule.schedule(const Time(hour: 10, minute: 30), 'test');
  expect(schedule.toJson(), {
    'alarmRunner': {
      'id': schedule.currentAlarmRunnerId,
      'currentScheduleDateTime': schedule.currentScheduleDateTime?.millisecondsSinceEpoch,
    },
  });
});

test('fromJson() creates DailyAlarmSchedule with correct values', () async {
  final Json json = {'alarmRunner': {'id': 50, ...}};
  final DailyAlarmSchedule scheduleFromJson = DailyAlarmSchedule.fromJson(json);
  expect(scheduleFromJson.currentAlarmRunnerId, 50);
});
// test/alarm/types/schedules/daily_alarm_schedule_test.dart
```

**Widget interaction — tap and re-render pattern:**
```dart
testWidgets('when field is tapped', (WidgetTester tester) async {
  bool switchValue = false;
  await _renderWidget(tester, value: switchValue, onChanged: (bool value) {
    switchValue = value;
  });
  await tester.tap(find.byType(InkWell));
  expect(switchValue, true);

  // Re-render with updated state, then tap again
  await _renderWidget(tester, value: switchValue, onChanged: (bool value) {
    switchValue = value;
  });
  await tester.tap(find.byType(InkWell));
  expect(switchValue, false);
});
// test/common/widgets/fields/switch_field_test.dart
```

**Localizations-dependent widget tests** use `testWidgets` wrapped in a `Localizations` widget and a `Builder` to access `BuildContext`:

```dart
void testDescription(String name, Function(BuildContext) callback) {
  testWidgets(name, (WidgetTester tester) async {
    await tester.pumpWidget(
      Localizations(
        delegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('en'),
        child: Builder(
          builder: (BuildContext context) {
            callback(context);
            return const Placeholder();
          },
        ),
      ),
    );
  });
}
// test/alarm/logic/schedule_description_test.dart
```

**`pumpAndSettle()` for dialogs and animations:**
```dart
await tester.tap(find.text('Open Time Picker'));
await tester.pumpAndSettle();
expect(find.byType(TimePickerDialog), findsOneWidget);
// test/common/widgets/time_picker_test.dart
```

**Finding widgets by predicate:**
```dart
final finder = find.byWidgetPredicate(
    (widget) => widget is Switch && widget.value == true,
    description: 'Switch is enabled');
expect(finder, findsOneWidget);
// test/alarm/widgets/alarm_card_test.dart
```

---

*Testing analysis: 2026-05-30*
