import 'dart:io';

import 'package:clock_app/common/data/paths.dart';
import 'package:clock_app/system/logic/power_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// CI coverage for the Dart half of "prevent power off while ringing": the arm
// file the native PowerGuardService reads. The service itself (does the OEM
// power menu match, does BACK close it) is an on-device check.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File armFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chrono_power_guard_test');
    // PowerGuardService.ARM_FILE is "Clock/power_guard_until.txt" under the
    // documents dir; the app data dir is the "Clock" part.
    armFile = File(path.join(tempDir.path, 'power_guard_until.txt'));
    setAppDataDirectoryPathForTesting(tempDir.path);
  });

  tearDown(() async {
    setAppDataDirectoryPathForTesting('');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('arming writes an expiry one hour out, in epoch ms', () async {
    final now = DateTime(2026, 9, 29, 7, 0);
    await armPowerGuard(now: now, enabled: true);

    expect(armFile.readAsStringSync(),
        '${now.add(const Duration(hours: 1)).millisecondsSinceEpoch}');
  });

  test('arming does nothing when the setting is off', () async {
    await armPowerGuard(now: DateTime(2026, 9, 29, 7, 0), enabled: false);

    expect(armFile.existsSync(), isFalse);
  });

  test('disarming writes a past expiry, even if the setting is off', () async {
    await armPowerGuard(now: DateTime.now(), enabled: true);
    await disarmPowerGuard();

    final until = int.parse(armFile.readAsStringSync());
    expect(until, lessThan(DateTime.now().millisecondsSinceEpoch));
  });

  test('arm file is plain digits the native side can parse as a Long', () {
    final value = powerGuardArmValue(DateTime(2026, 9, 29, 7, 0));
    expect(RegExp(r'^\d+$').hasMatch(value), isTrue);
    expect(RegExp(r'^\d+$').hasMatch(powerGuardDisarmedValue), isTrue);
  });
}
