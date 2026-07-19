import 'dart:convert';
import 'dart:io';

import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/common/data/paths.dart';
import 'package:clock_app/common/logic/salvage_report.dart';
import 'package:clock_app/common/utils/json_serialize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File marker;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chrono_salvage_test');
    marker = File(path.join(tempDir.path, 'alarms_lost.marker'));
    setAppDataDirectoryPathForTesting(tempDir.path);
    SalvageReport.setMarkerPathForTesting(marker.path);
    SalvageReport.clear();
  });

  tearDown(() async {
    SalvageReport.clear();
    SalvageReport.setMarkerPathForTesting(null);
    setAppDataDirectoryPathForTesting('');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('salvage marker crosses a fresh UI-side report and clears after show',
      () {
    listFromString<Alarm>(json.encode([
      {'timeOfDay': null, 'schedules': []},
    ]));

    expect(marker.existsSync(), isTrue,
        reason: 'alarm salvage must persist a durable marker');

    // Simulate the UI isolate's fresh static flag; it shares the app data file.
    SalvageReport.clearMemoryForTesting();
    expect(SalvageReport.alarmsWereLost, isTrue,
        reason: 'the UI-side check must see boot-isolate salvage');

    // Mirrors App: clear only after deciding to show the notice.
    if (SalvageReport.alarmsWereLost) {
      SalvageReport.clear();
    }
    expect(marker.existsSync(), isFalse);
    expect(SalvageReport.alarmsWereLost, isFalse);
  });

  test('routine non-alarm recovery does not create a marker', () {
    SalvageReport.markEntryDropped<String>();

    expect(marker.existsSync(), isFalse);
    expect(SalvageReport.alarmsWereLost, isFalse);
  });
}
