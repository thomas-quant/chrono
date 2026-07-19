import 'package:clock_app/alarm/screens/scan_register_screen.dart';
import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

void main() {
  testWidgets(
    'registration scanner tears down on paused and restarts on resumed',
    (WidgetTester tester) async {
      final setting = AlarmTask(AlarmTaskType.scan)
          .settings
          .getSetting("Registered Code") as StringSetting;

      await tester.pumpWidget(
        MaterialApp(
          home: ScanRegisterScreen(setting: setting),
        ),
      );
      await tester.pump();
      expect(find.byType(ReaderWidget), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.byType(ReaderWidget), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(ReaderWidget), findsOneWidget);
    },
  );
}
