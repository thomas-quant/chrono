import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:clock_app/alarm/widgets/tasks/scan_task.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// GAP-A regression guard (04-07): the host↔widget HEIGHT contract for ScanTask.
//
// The defect this guards: ScanTask used a top-level `Expanded` to size its
// scanner, but BOTH hosts mount the task widget as a NON-flex child of a
// `Column` (try_alarm_task_screen.dart `body: Column(children:[builder()])` and
// alarm_notification_screen.dart `Expanded > Column > [_currentWidget]`), giving
// ScanTask UNBOUNDED height. An `Expanded` under unbounded height collapses the
// `ReaderWidget`'s `Positioned.fill` Stack to zero height → no camera preview
// (silent in a release APK — no red overflow overlay). The fix made ScanTask
// self-sizing via a MediaQuery-derived `SizedBox`. This test reproduces the
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
        // Post-fix this is driven by the MediaQuery-derived SizedBox; pre-fix it
        // would collapse to zero height.
        final Size size = tester.getSize(find.byType(ScanTask));
        expect(size.height, isFinite);
        expect(size.height, greaterThan(0.0));
        expect(size.width, isFinite);
        expect(size.width, greaterThan(0.0));
      },
    );
  });
}
