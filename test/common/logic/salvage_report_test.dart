import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/common/logic/salvage_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the storage-recovery gate behind Phase-1 Test 2
/// (BOOT-04 / D-06). `SalvageReport` is the static flag that decides whether
/// the one-time "alarms were reset" notice is shown: it must be set ONLY when an
/// `Alarm` is lost, and stay silent for routine recovery (a dropped timer/city
/// entry, defaulted settings, an unparseable non-alarm list) — Pitfall 5.
void main() {
  // Keep tests independent: the flag is module-level static state.
  setUp(SalvageReport.clear);
  tearDown(SalvageReport.clear);

  group('SalvageReport — alarm-loss gate (positive cases → notice shows)', () {
    test('starts clear', () {
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('markEntryDropped<Alarm>() sets the flag', () {
      SalvageReport.markEntryDropped<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);
    });

    test('markListReset<Alarm>() sets the flag', () {
      SalvageReport.markListReset<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);
    });
  });

  group('SalvageReport — routine recovery (negative cases → stay silent)', () {
    // String/int stand in for the non-Alarm entities that get salvaged during
    // normal recovery (timers, cities, settings groups). None must trip the
    // user-facing alarm-loss notice.
    test('markEntryDropped<non-Alarm>() does NOT set the flag', () {
      SalvageReport.markEntryDropped<String>();
      SalvageReport.markEntryDropped<int>();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('markListReset<non-Alarm>() does NOT set the flag', () {
      SalvageReport.markListReset<String>();
      SalvageReport.markListReset<int>();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });
  });

  group('SalvageReport — clear / show-once semantics', () {
    test('clear() resets the flag after a loss', () {
      SalvageReport.markEntryDropped<Alarm>();
      expect(SalvageReport.alarmsWereLost, isTrue);

      SalvageReport.clear();
      expect(SalvageReport.alarmsWereLost, isFalse);
    });

    test('flag is sticky: an alarm loss among non-alarm losses still flags', () {
      SalvageReport.markEntryDropped<String>(); // timer dropped — silent
      SalvageReport.markEntryDropped<Alarm>(); // alarm dropped — must flag
      SalvageReport.markEntryDropped<int>(); // city dropped — irrelevant now
      expect(SalvageReport.alarmsWereLost, isTrue);
    });
  });
}
