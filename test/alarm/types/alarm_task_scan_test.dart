import 'package:clock_app/alarm/data/alarm_task_schemas.dart';
import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:flutter_test/flutter_test.dart';

// SCAN-01 regression gate for the scan-to-dismiss task TYPE. These tests assert
// on the AlarmTask object + its JSON only — they import NO camera/UI package, so
// they run headlessly in CI (tests.yml) with no device, mirroring the
// alarm_snooze_test.dart discipline.
//
// The ring-side ScanTask widget (camera/ReaderWidget) is intentionally NOT
// exercised here — that is an on-device gate (Plan 06). What this file proves is
// the persistence contract: the scan schema is registered in
// alarmTaskSchemasMap, an AlarmTask(scan) exposes the Registered Code +
// Escape Hatch settings (Escape Hatch default ON, SCAN-06), and an
// AlarmTask(scan) round-trips through toJson/fromJson preserving its type, the
// stored registered code, and the escape-hatch flag (SCAN-01).
//
// Toolchain note (CLAUDE.md / STATE.md): Flutter/Dart is absent in the authoring
// environment, so `flutter test` was NOT run locally — GREEN is owed via CI and
// is NOT claimed as locally passing.

void main() {
  // Required so the statically-constructed alarmTaskSchemasMap and the embedded
  // SettingGroups are reachable for AlarmTask construction (construction analog:
  // alarm_card_test.dart / alarm_snooze_test.dart).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlarmTask(scan)', () {
    test('the scan schema is registered in alarmTaskSchemasMap', () {
      expect(alarmTaskSchemasMap.containsKey(AlarmTaskType.scan), true);
    });

    test(
      'a fresh scan task exposes Registered Code (empty) and Escape Hatch '
      '(default ON, SCAN-06)',
      () {
        final task = AlarmTask(AlarmTaskType.scan);

        // Both settings exist and are reachable by their string keys.
        final registeredCode = task.settings.getSetting("Registered Code");
        final escapeHatch = task.settings.getSetting("Escape Hatch");

        // No code registered yet (the Plan 05 save gate enforces non-empty; not
        // here — a fresh task must not crash with an empty stored code).
        expect(registeredCode.value, "");
        // Escape hatch defaults ON — the ethics-critical anti-trap guarantee.
        expect(escapeHatch.value, true);
      },
    );

    test(
      'AlarmTask(scan) round-trips through toJson/fromJson preserving type, the '
      'registered code, and the escape-hatch flag (SCAN-01)',
      () {
        final task = AlarmTask(AlarmTaskType.scan);
        task.settings
            .getSetting("Registered Code")
            .setValueWithoutNotify("my-registered-code");
        task.settings.getSetting("Escape Hatch").setValueWithoutNotify(false);

        final rebuilt = AlarmTask.fromJson(task.toJson());

        expect(rebuilt.type, AlarmTaskType.scan);
        expect(
          rebuilt.settings.getSetting("Registered Code").value,
          "my-registered-code",
        );
        expect(rebuilt.settings.getSetting("Escape Hatch").value, false);
      },
    );

    test(
      'a scan task with no registered code keeps Registered Code empty after a '
      'round-trip (no crash; save-gate is enforced in Plan 05)',
      () {
        final task = AlarmTask(AlarmTaskType.scan);

        final rebuilt = AlarmTask.fromJson(task.toJson());

        expect(rebuilt.type, AlarmTaskType.scan);
        expect(rebuilt.settings.getSetting("Registered Code").value, "");
        // Escape hatch default survives the round-trip too (SCAN-06).
        expect(rebuilt.settings.getSetting("Escape Hatch").value, true);
      },
    );
  });
}
