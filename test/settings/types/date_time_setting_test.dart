import 'package:clock/clock.dart';
import 'package:clock_app/alarm/types/range_interval.dart';
import 'package:clock_app/alarm/types/schedules/range_alarm_schedule.dart';
import 'package:clock_app/common/types/time.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression suite locking in the Plan 03-01 date-only serialization fix
// (DATE-01 / DATE-02). These tests drive DateTimeSetting.valueToJson /
// loadValueFromJson DIRECTLY and assert on the recovered .year/.month/.day
// components — NEVER on `==` of a whole DateTime — so the assertions are
// timezone-agnostic and still hold under CI's UTC runner (a `==` test would
// silently pass in UTC and hide the off-by-one on negative-UTC devices).
//
// RangeAlarmSchedule shares DateTimeSetting, so the last test proves the
// date-only round-trip does not flip the range fire/finish boundary
// (03-RESEARCH.md Pitfall 2 — the top regression risk of this phase). The
// schedule's OS calls (AndroidAlarmManager) no-op under FLUTTER_TEST, so the
// model logic runs to completion and mutates `isFinished` without the OS.

/// Builds a bare `DateTimeSetting` reachable without any storage init.
DateTimeSetting _dateSetting(List<DateTime> initial, {bool rangeOnly = false}) {
  final setting = DateTimeSetting(
    "TestDates",
    (_) => "Test Dates",
    const [],
    rangeOnly: rangeOnly,
  );
  setting.setValueWithoutNotify(initial);
  return setting;
}

/// Builds a `SelectSetting<RangeInterval>` for the range schedule's interval.
/// Per the SelectSetting-by-index gotcha (alarm_snooze_test.dart:105-110), it
/// is set by the option index, not by passing the enum.
SelectSetting<RangeInterval> _intervalSetting(RangeInterval interval) {
  final setting = SelectSetting<RangeInterval>(
    "Interval",
    (_) => "Interval",
    [
      SelectSettingOption((_) => "Daily", RangeInterval.daily),
      SelectSettingOption((_) => "Weekly", RangeInterval.weekly),
    ],
  );
  setting.setValueWithoutNotify(setting.getIndexOfValue(interval));
  return setting;
}

List<DateTime> _values(DateTimeSetting s) => s.value as List<DateTime>;

void main() {
  // Required so the statically-constructed appSettings schema is reachable
  // for setting/schedule construction (harness mirrors alarm_snooze_test.dart:38).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DateTimeSetting date-only serialization', () {
    test(
      'DATE-02 round-trip: a picked calendar date survives valueToJson -> '
      'loadValueFromJson with its y/m/d intact (TZ-agnostic)',
      () {
        final setting = _dateSetting([DateTime(2026, 6, 7)]);

        final json = setting.valueToJson();
        // The persisted form is a date-only string, never an epoch instant.
        expect(json, ['2026-06-07']);

        // Round-trip into a fresh setting and assert on components only.
        final reloaded = _dateSetting([]);
        reloaded.loadValueFromJson(json);

        final recovered = _values(reloaded).single;
        expect(recovered.year, 2026);
        expect(recovered.month, 6);
        expect(recovered.day, 7);
      },
    );

    test(
      'DATE-01 legacy-epoch migration: a legacy UTC-midnight epoch recovers the '
      'originally-picked day regardless of test timezone',
      () {
        // table_calendar historically stored the picked day as midnight-UTC;
        // the old code persisted its millisecondsSinceEpoch. Feeding that legacy
        // int must recover 2026-06-07 even when the runner is east/west of UTC.
        final legacyEpoch = DateTime.utc(2026, 6, 7).millisecondsSinceEpoch;

        final setting = _dateSetting([]);
        setting.loadValueFromJson([legacyEpoch]);

        final recovered = _values(setting).single;
        expect(recovered.year, 2026);
        expect(recovered.month, 6);
        expect(recovered.day, 7);
      },
    );

    test(
      'salvage: a malformed value does not throw and does not lose the list '
      '(Phase-1 BOOT-04 salvage principle)',
      () {
        final setting = _dateSetting([]);

        // A malformed string element must be tolerated (salvaged to a safe
        // default), never rethrown — a corrupt date can never lose the whole
        // alarm list. The other (valid) element must still load.
        expect(
          () => setting.loadValueFromJson(['not-a-date', '2026-06-07']),
          returnsNormally,
        );
        expect(_values(setting).length, 2);
        // The valid element is recovered correctly.
        final valid = _values(setting).last;
        expect(valid.year, 2026);
        expect(valid.month, 6);
        expect(valid.day, 7);
      },
    );

    test(
      'WR-05 validation: an out-of-range YYYY-MM-DD string is salvaged to a '
      'plausible date instead of silently rolling over',
      () {
        final setting = _dateSetting([]);

        // '2026-13-40' parses without throwing and a raw DateTime(2026, 13, 40)
        // would silently roll over (month 13 -> next Jan, day 40 -> overflow).
        // With range validation it must be rejected and salvaged, never loaded
        // as a plausible-but-wrong date.
        final now = DateTime.now();
        expect(
          () => setting.loadValueFromJson(['2026-13-40']),
          returnsNormally,
        );
        final salvaged = _values(setting).single;
        // Salvaged to today's date-only (the BOOT-04 fallback), NOT to the
        // rolled-over 2027-02-09 that an unvalidated DateTime would produce.
        expect(salvaged.year, now.year);
        expect(salvaged.month, now.month);
        expect(salvaged.day, now.day);
      },
    );

    test(
      'WR-05 validation: a YYYY-MM-DD string with trailing junk is salvaged, '
      'not silently truncated to its first three parts',
      () {
        final setting = _dateSetting([]);

        // '2026-06-07-extra' splits into 4 parts; the old code parsed only the
        // first three and ignored the tail. With the length check it must be
        // rejected and salvaged rather than silently accepted as 2026-06-07.
        final now = DateTime.now();
        expect(
          () => setting.loadValueFromJson(['2026-06-07-extra']),
          returnsNormally,
        );
        final salvaged = _values(setting).single;
        expect(salvaged.year, now.year);
        expect(salvaged.month, now.month);
        expect(salvaged.day, now.day);
      },
    );

    test(
      'DATE-02 range safety: RangeAlarmSchedule produces the same finish '
      'boundary before and after a date-only round-trip (Pitfall 2)',
      () async {
        // A fixed "now" so getScheduleDateForTime (which reads clock.now()) is
        // deterministic. The range starts in the future, so the schedule is NOT
        // finished; the last day must not flip across the round-trip.
        final fixedNow = DateTime(2026, 6, 1, 8, 0, 0);
        const time = Time(hour: 9, minute: 0);

        Future<bool> finishedFor(List<DateTime> range) async {
          final datesSetting = _dateSetting(range, rangeOnly: true);
          final schedule = RangeAlarmSchedule(
            datesSetting,
            _intervalSetting(RangeInterval.daily),
          );
          await withClock(Clock.fixed(fixedNow), () async {
            await schedule.schedule(time, "range-safety-test");
          });
          return schedule.isFinished;
        }

        // Original (pre-serialization) range: 2026-06-05 .. 2026-06-10.
        final original = [DateTime(2026, 6, 5), DateTime(2026, 6, 10)];
        final before = await finishedFor(original);

        // Round-trip the same range through the new date-only format.
        final rt = _dateSetting(original, rangeOnly: true);
        rt.loadValueFromJson(rt.valueToJson());
        final after = await finishedFor(_values(rt));

        // The finish boundary must be identical across the round-trip.
        expect(before, after);
        // And, for this in-window range, the schedule must NOT be finished.
        expect(after, false);

        // Boundary case: a range that has fully elapsed must be finished both
        // before and after the round-trip (the last-day boundary must not flip
        // a finished range back to live, nor a live one to finished).
        final past = [DateTime(2026, 5, 1), DateTime(2026, 5, 2)];
        final pastBefore = await finishedFor(past);
        final pastRt = _dateSetting(past, rangeOnly: true);
        pastRt.loadValueFromJson(pastRt.valueToJson());
        final pastAfter = await finishedFor(_values(pastRt));
        expect(pastBefore, pastAfter);
        expect(pastAfter, true);
      },
    );
  });
}
