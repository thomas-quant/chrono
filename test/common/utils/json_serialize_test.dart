import 'dart:convert';

import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/clock/types/city.dart';
import 'package:clock_app/common/logic/salvage_report.dart';
import 'package:clock_app/common/utils/json_serialize.dart';
import 'package:clock_app/timer/types/timer.dart';
import 'package:clock_app/timer/types/time_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encode a heterogeneous list of raw maps as a JSON array string, exactly as
/// it would be stored on disk.
String encodeRaw(List<dynamic> raw) => json.encode(raw);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Keep each test independent — the salvage flag is a module-level static.
    SalvageReport.clear();
  });

  group('SalvageReport flag', () {
    test('alarmsWereLost is false initially', () {
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('markEntryDropped<Alarm>() sets the flag true', () {
      SalvageReport.markEntryDropped<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);
    });

    test('markEntryDropped<ClockTimer>() leaves the flag false', () {
      SalvageReport.markEntryDropped<ClockTimer>();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('markListReset<Alarm>() sets the flag true', () {
      SalvageReport.markListReset<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);
    });

    test('markListReset<City>() leaves the flag false', () {
      SalvageReport.markListReset<City>();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('clear() resets the flag to false', () {
      SalvageReport.markEntryDropped<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);
      SalvageReport.clear();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });
  });

  group('listFromString per-entry salvage — Alarm', () {
    test('one corrupt alarm entry: all OTHER alarms load, flag set', () {
      // A valid alarm round-tripped through toJson, plus a deliberately
      // malformed entry (schedules is not the expected 5-element array, so
      // Alarm.fromJson throws when it indexes json['schedules'][0]).
      final validAlarm = Alarm.fromTimeOfDay(const TimeOfDay(hour: 7, minute: 0));
      final encoded = encodeRaw([
        validAlarm.toJson(),
        {'timeOfDay': null, 'schedules': []}, // corrupt — index out of range
        validAlarm.toJson(),
      ]);

      final result = listFromString<Alarm>(encoded);

      expect(result.length, 2, reason: 'only the bad entry is skipped');
      expect(SalvageReport.alarmsWereLost, isTrue);
    });

    test('top-level unparseable alarm list: returns empty, no throw, flag set',
        () {
      List<Alarm> result = const [];
      expect(() {
        result = listFromString<Alarm>('{not a list');
      }, returnsNormally);

      expect(result, isEmpty);
      expect(SalvageReport.alarmsWereLost, isTrue);
    });

    test('well-formed valid alarm list: all entries load, flag stays false',
        () {
      final a1 = Alarm.fromTimeOfDay(const TimeOfDay(hour: 6, minute: 30));
      final a2 = Alarm.fromTimeOfDay(const TimeOfDay(hour: 8, minute: 15));
      final encoded = encodeRaw([a1.toJson(), a2.toJson()]);

      final result = listFromString<Alarm>(encoded);

      expect(result.length, 2);
      expect(SalvageReport.alarmsWereLost, isFalse);
    });
  });

  group('listFromString per-entry salvage — ClockTimer (non-alarm)', () {
    test('one corrupt timer entry: other timers load, flag NOT set', () {
      // ClockTimer.fromJson does json['durationRemainingOnPause'] * 1000;
      // a missing key makes that null * 1000 throw — a clean corrupt-entry
      // vector. The valid timer round-trips through toJson.
      final validTimer =
          ClockTimer(const TimeDuration(hours: 0, minutes: 5, seconds: 0));
      final encoded = encodeRaw([
        validTimer.toJson(),
        {'duration': 60}, // corrupt — durationRemainingOnPause absent
      ]);

      final result = listFromString<ClockTimer>(encoded);

      expect(result.length, 1, reason: 'only the bad timer is skipped');
      expect(SalvageReport.alarmsWereLost, isFalse,
          reason: 'non-alarm loss must not set the user-facing flag');
    });
  });
}
