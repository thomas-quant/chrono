import 'package:clock_app/alarm/logic/scan_task_controller.dart';
import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:clock_app/alarm/widgets/tasks/scan_task.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

// GAP-A regression guard (04-07): the host↔widget HEIGHT contract for ScanTask.
//
// The defect this guards: ScanTask used a top-level `Expanded` to size its
// scanner, but BOTH hosts mount the task widget as a NON-flex child of a
// `Column` (try_alarm_task_screen.dart `body: Column(children:[builder()])` and
// alarm_notification_screen.dart `Expanded > Column > [_currentWidget]`), giving
// ScanTask UNBOUNDED height. An `Expanded` under unbounded height collapses the
// `ReaderWidget`'s `Positioned.fill` Stack to zero height → no camera preview
// (silent in a release APK — no red overflow overlay). The fix made ScanTask
// self-sizing via a bounded LayoutBuilder path plus a MediaQuery-derived
// fallback `SizedBox`. This test reproduces the
// EXACT host condition — ScanTask as a non-flex child of an unbounded `Column`
// — and asserts the post-fix invariant: no overflow / layout exception, and a
// finite, non-zero rendered height.
//
// Scope note (why this asserts the OUTER box, not camera frames): the regression
// being guarded is the layout HEIGHT contract, not camera rendering. ScanTask's
// scanner branch builds a real `ReaderWidget` (flutter_zxing) whose camera
// platform channel cannot initialize under headless `flutter test`. So this test
// asserts the rendered size of the OUTER ScanTask subtree (which, post-fix, is
// driven by the MediaQuery-derived `SizedBox`) is finite and > 0, and that no
// `RenderFlex` overflow / layout exception was thrown while pumping. Against the
// pre-fix code (Expanded under an unbounded Column) the pump throws a layout
// error / the region collapses to zero → this test FAILS. The live camera
// preview itself remains an on-device gate (Plan 06 / 04-07 Task 4).
//
// Toolchain note (CLAUDE.md / STATE.md): Flutter/Dart is absent in the authoring
// environment, so `flutter test` was NOT run locally — GREEN is owed via CI
// (tests.yml auto-discovers all of test/) and is NOT claimed as locally passing.

void main() {
  // Required so the statically-constructed alarmTaskSchemasMap + embedded
  // SettingGroups are reachable for AlarmTask construction (construction analog:
  // alarm_task_scan_test.dart).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScanTask layout under an unbounded Column (GAP-A host contract)', () {
    testWidgets(
      'lays out with no overflow and a finite, non-zero height when mounted as '
      'a non-flex child of an unbounded Column (the exact host condition)',
      (WidgetTester tester) async {
        // A real scan SettingGroup (Registered Code + Escape Hatch), exactly as
        // the hosts construct it.
        final SettingGroup settings = AlarmTask(AlarmTaskType.scan).settings;

        await tester.pumpWidget(
          MaterialApp(
            // English AppLocalizations so AppLocalizations.of(context)! (read in
            // ScanTask.build) is non-null.
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              // A body with a KNOWN finite width but whose Column main axis is
              // the only unbounded axis — exactly like the hosts, which place
              // the task widget as a non-flex child of a Column.
              body: SingleChildScrollView(
                child: Column(
                  // No Expanded / Flexible around the task → ScanTask receives
                  // unbounded height, reproducing the host contract.
                  children: <Widget>[
                    ScanTask(
                      onSolve: () {},
                      settings: settings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // (a) No RenderFlex overflow / layout exception was thrown while pumping.
        // The pre-fix Expanded-under-unbounded-Column would error here.
        expect(tester.takeException(), isNull);

        // (b) The ScanTask subtree resolves to a finite, non-zero, bounded size.
        // Post-fix this is driven by the unbounded-host fallback SizedBox;
        // pre-fix it would collapse to zero height.
        final Size size = tester.getSize(find.byType(ScanTask));
        expect(size.height, isFinite);
        expect(size.height, greaterThan(0.0));
        expect(size.width, isFinite);
        expect(size.width, greaterThan(0.0));
      },
    );

    testWidgets(
      'resets consecutive task state: the second task can solve independently',
      (WidgetTester tester) async {
        final firstSettings = AlarmTask(AlarmTaskType.scan).settings;
        firstSettings
            .getSetting("Registered Code")
            .setValueWithoutNotify("first-code");
        final secondSettings = AlarmTask(AlarmTaskType.scan).settings;
        secondSettings
            .getSetting("Registered Code")
            .setValueWithoutNotify("second-code");

        final firstController = ScanTaskController();
        final secondController = ScanTaskController();
        var firstSolved = 0;
        var secondSolved = 0;
        var currentTask = ScanTask(
          controller: firstController,
          emergencyDismissTimeout: const Duration(hours: 1),
          onSolve: () => firstSolved++,
          settings: firstSettings,
        );
        late void Function(Widget) replaceTask;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  replaceTask = (task) => setState(() => currentTask = task);
                  return SizedBox(
                    width: 640,
                    height: 320,
                    child: currentTask,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Drive the same controller seam used by the ReaderWidget callback.
        firstController.handleScan("first-code");
        expect(firstSolved, 1);

        // Deliberately leave the two ScanTask widgets unkeyed here: didUpdateWidget
        // must still reset all task-specific state for hosts that reuse a state.
        currentTask = ScanTask(
          controller: secondController,
          emergencyDismissTimeout: const Duration(hours: 1),
          onSolve: () => secondSolved++,
          settings: secondSettings,
        );
        replaceTask(currentTask);
        await tester.pump();
        secondController.handleScan("second-code");

        expect(firstSolved, 1);
        expect(secondSolved, 1);
      },
    );

    testWidgets(
      'the second consecutive task still exposes emergency dismiss',
      (WidgetTester tester) async {
        final firstSettings = AlarmTask(AlarmTaskType.scan).settings;
        firstSettings
            .getSetting("Registered Code")
            .setValueWithoutNotify("first-code");
        firstSettings
            .getSetting("Escape Hatch")
            .setValueWithoutNotify(false);
        final secondSettings = AlarmTask(AlarmTaskType.scan).settings;
        secondSettings
            .getSetting("Registered Code")
            .setValueWithoutNotify("second-code");
        secondSettings
            .getSetting("Escape Hatch")
            .setValueWithoutNotify(false);

        final firstController = ScanTaskController();
        var firstSolved = 0;
        var secondSolved = 0;
        var currentTask = ScanTask(
          controller: firstController,
          emergencyDismissTimeout: const Duration(hours: 1),
          onSolve: () => firstSolved++,
          settings: firstSettings,
        );
        late void Function(Widget) replaceTask;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  replaceTask = (task) => setState(() => currentTask = task);
                  return SizedBox(
                    width: 640,
                    height: 320,
                    child: currentTask,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        firstController.handleScan("first-code");
        expect(firstSolved, 1);

        final secondController = ScanTaskController();
        currentTask = ScanTask(
          controller: secondController,
          emergencyDismissTimeout: Duration.zero,
          onSolve: () => secondSolved++,
          settings: secondSettings,
        );
        replaceTask(currentTask);
        await tester.pump();
        await tester.pump();

        final dismissButton = find.byType(ElevatedButton);
        expect(dismissButton, findsOneWidget);
        final buttonRect = tester.getRect(dismissButton);
        expect(buttonRect.top, greaterThanOrEqualTo(0.0));
        expect(buttonRect.bottom, lessThanOrEqualTo(320.0));
        await tester.tap(dismissButton);
        await tester.pump();

        expect(secondSolved, 1);
      },
    );

    testWidgets(
      'keeps the emergency button visible and hit-testable in landscape at large text',
      (WidgetTester tester) async {
        final settings = AlarmTask(AlarmTaskType.scan).settings;
        settings.getSetting("Escape Hatch").setValueWithoutNotify(false);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(640, 320),
                textScaleFactor: 2.5,
              ),
              child: Scaffold(
                body: SizedBox(
                  width: 640,
                  height: 320,
                  child: ScanTask(
                    emergencyDismissTimeout: Duration.zero,
                    onSolve: () {},
                    settings: settings,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        final dismissButton = find.byType(ElevatedButton);
        expect(dismissButton, findsOneWidget);
        final buttonRect = tester.getRect(dismissButton);
        expect(buttonRect.top, greaterThanOrEqualTo(0.0));
        expect(buttonRect.bottom, lessThanOrEqualTo(320.0));
        await tester.tap(dismissButton);
      },
    );

    testWidgets(
      'emergency floor reveals dismiss but does NOT tear the scanner down',
      (WidgetTester tester) async {
        // Escape Hatch off + the emergency floor elapses immediately, with NO
        // detectable camera failure (no onControllerCreated exception).
        final settings = AlarmTask(AlarmTaskType.scan).settings;
        settings.getSetting("Escape Hatch").setValueWithoutNotify(false);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SizedBox(
                width: 640,
                height: 320,
                child: ScanTask(
                  emergencyDismissTimeout: Duration.zero,
                  onSolve: () {},
                  settings: settings,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Never-trap: the floor revealed the Dismiss affordance even with the
        // Escape Hatch off...
        expect(find.byType(ElevatedButton), findsOneWidget);
        // ...but the live scanner is NOT torn down. A slow scan is not a
        // failure, and "unlock to scan" (which un-mounts the ReaderWidget) is
        // reserved for a DETECTABLE camera failure — so the ReaderWidget must
        // stay mounted here.
        expect(find.byType(ReaderWidget), findsOneWidget);
      },
    );

    testWidgets(
      'emergency floor keeps counting across an inactive/resumed cycle',
      (WidgetTester tester) async {
        // Pulling the notification shade (or screen off/on) sends the app
        // through inactive -> resumed. That must not restart the 120s floor,
        // or a user who keeps doing it at 3am never gets the dismiss.
        final settings = AlarmTask(AlarmTaskType.scan).settings;
        settings.getSetting("Escape Hatch").setValueWithoutNotify(false);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: SizedBox(
                width: 640,
                height: 320,
                child: ScanTask(
                  emergencyDismissTimeout: const Duration(seconds: 10),
                  onSolve: () {},
                  settings: settings,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 6));
        expect(find.byType(ElevatedButton), findsNothing);

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        // 11s since the task started, but only 5s since resume.
        await tester.pump(const Duration(seconds: 5));
        expect(find.byType(ElevatedButton), findsOneWidget);
      },
    );
  });
}
