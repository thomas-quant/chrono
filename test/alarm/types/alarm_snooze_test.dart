import 'package:clock/clock.dart';
import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/alarm/types/schedules/dates_alarm_schedule.dart';
import 'package:clock_app/common/types/time.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression suite locking in the Plan 02-01 snooze state-machine fixes
// (SNZ-01..05). These tests drive Alarm.snooze() / Alarm.handleDismiss()
// DIRECTLY and assert on Alarm flags only (snoozeTime / snoozeCount /
// isEnabled / isSnoozed / isFinished). They never assert on
// AndroidAlarmManager — scheduleAlarm / cancelAlarm / scheduleSnoozeAlarm
// all no-op under FLUTTER_TEST (schedule_alarm.dart:28,101,136), so the
// model logic runs to completion and mutates flags without touching the OS.
//
// The SNZ-02 exact "now + 30s" assertion is only valid because Plan 01
// switched snooze() to read clock.now() (D-B); withClock(Clock.fixed(...))
// pins the time the model reads.

/// Returns a copy of [base] whose OnceAlarmSchedule has already "fired": its
/// runner holds a *past* schedule time. This is required to exercise the real
/// production "dismiss disables a one-shot" path. A fresh, never-scheduled
/// once-alarm has a null runner time, so re-evaluating it on dismiss recomputes
/// a *future* fire time and leaves it enabled — a OnceAlarmSchedule disables
/// only once its scheduled instant is in the past (once_alarm_schedule.dart:30).
/// In production the alarm has always fired (past instant) by dismiss time.
Alarm _firedOnceAlarm(Alarm base) {
  final json = base.toJson()!;
  // schedules[0] is the OnceAlarmSchedule (createSchedules / fromJson ordering).
  json['schedules'][0]['alarmRunner']['currentScheduleDateTime'] =
      DateTime(2000, 1, 1, 2, 30).millisecondsSinceEpoch;
  return Alarm.fromJson(json);
}

void main() {
  // Required so the statically-constructed appSettings schema is reachable
  // for Alarm() construction (construction analog: alarm_card_test.dart).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Alarm snooze', () {
    late Alarm alarm;

    setUp(() {
      // Fresh alarm per test — builds without any storage init.
      alarm = Alarm(const Time(hour: 2, minute: 30));
    });

    test(
      'SNZ-02: a 0.5-min Length pins snoozeTime to exactly now + 30s under a '
      'frozen clock (fractional honored, never floored to 0)',
      () async {
        // A future instant so the displayed/scheduled snooze time is in the
        // future. The exact value is what we assert against clock.now().
        final fixedNow = DateTime(2030, 1, 1, 8, 0, 0);
        alarm.setSettingWithoutNotify("Length", 0.5);

        await withClock(Clock.fixed(fixedNow), () async {
          await alarm.snooze();
        });

        // 0.5 min -> 30 seconds, computed via (snoozeLength * 60).round().
        expect(
          alarm.snoozeTime,
          fixedNow.add(const Duration(seconds: 30)),
        );
        // It must NOT have floored the fractional length to 0 (the SNZ-02 bug).
        expect(alarm.snoozeTime, isNot(equals(fixedNow)));
        expect(alarm.isSnoozed, true);
      },
    );

    test(
      'SNZ-03: a once-alarm snoozed then dismissed is disabled and not '
      're-armed (no re-arm; #457)',
      () async {
        // Default Type is OnceAlarmSchedule. Simulate one that has already
        // fired (past runner time) so dismiss exercises the real disable path;
        // a fresh, never-scheduled once-alarm would re-arm to a future time.
        alarm = _firedOnceAlarm(alarm);
        await alarm.snooze();
        expect(alarm.isSnoozed, true);
        expect(alarm.isEnabled, true);
        expect(alarm.snoozeCount, 1);

        await alarm.handleDismiss();

        // Deactivated, snooze cleared, count reset — the #457 fix: a
        // dismissed one-shot can never re-arm because it is disabled.
        expect(alarm.isEnabled, false);
        expect(alarm.isSnoozed, false);
        expect(alarm.snoozeCount, 0);
      },
    );

    test(
      'SNZ-03 (dates): a finished dates-alarm snoozed then dismissed is '
      'finished/disabled and not snoozed (#457 generalizes)',
      () async {
        // Switch to a DatesAlarmSchedule whose only date is in the past, so
        // the schedule finishes when re-evaluated by update() on dismiss.
        alarm.setSettingWithoutNotify("Type", DatesAlarmSchedule);
        final pastDate = DateTime(2000, 1, 1, 2, 30);
        alarm.setSettingWithoutNotify("Dates", [pastDate]);

        await alarm.snooze();
        expect(alarm.isSnoozed, true);

        await alarm.handleDismiss();

        // The finished dates schedule is deactivated (finish() -> disable()).
        expect(alarm.isFinished, true);
        expect(alarm.isEnabled, false);
        expect(alarm.isSnoozed, false);
      },
    );

    test(
      'SNZ-04: snoozing past Max Snoozes does not increment and resolves as a '
      'dismiss (never left ringing)',
      () async {
        // A fired once-alarm (past runner time) so the over-max dismiss
        // resolves to disabled — matching production, where the alarm has
        // already fired by the time the max-snooze gate trips.
        alarm = _firedOnceAlarm(alarm);
        alarm.setSettingWithoutNotify("Max Snoozes", 2);

        await alarm.snooze(); // count -> 1
        expect(alarm.snoozeCount, 1);
        await alarm.snooze(); // count -> 2 (now at max)
        expect(alarm.snoozeCount, 2);

        // Third snooze is over-max: the authoritative gate resolves it as a
        // dismiss (D-A) rather than incrementing to 3 or leaving it ringing.
        await alarm.snooze();

        expect(alarm.snoozeCount, isNot(equals(3)));
        expect(alarm.snoozeCount, 0);
        expect(alarm.isSnoozed, false);
        expect(alarm.isEnabled, false);
      },
    );

    test(
      'SNZ-04 (persist): snoozeCount round-trips through toJson -> fromJson '
      '(disk durability across the isolate boundary)',
      () async {
        await alarm.snooze(); // count -> 1

        final rebuilt = Alarm.fromJson(alarm.toJson());

        // The count is the cross-isolate source of truth; it must survive
        // serialization so the firing isolate reloads the correct value. The
        // snooze state itself must also round-trip (the firing isolate reloads
        // a still-snoozed, still-enabled alarm — not a silently reset one).
        expect(rebuilt.snoozeCount, 1);
        expect(rebuilt.isSnoozed, true);
        expect(rebuilt.isEnabled, true);
      },
    );

    test(
      'SNZ-01/SNZ-05: a snoozed alarm survives an unrelated update() still '
      'enabled and snoozed (never silently disabled)',
      () async {
        await alarm.snooze();
        expect(alarm.isEnabled, true);
        expect(alarm.isSnoozed, true);

        // An unrelated re-evaluation (mirrors triggerAlarm's updateAlarms
        // re-arm funnel running while a snooze is still pending) must not
        // destroy the pending snooze or disable the alarm.
        await alarm.update("test: unrelated update while snoozed");

        expect(alarm.isEnabled, true);
        expect(alarm.isSnoozed, true);
      },
    );
  });
}
