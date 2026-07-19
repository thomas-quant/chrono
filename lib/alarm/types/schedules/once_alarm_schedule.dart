import 'package:clock_app/alarm/logic/alarm_time.dart';
import 'package:clock_app/alarm/types/alarm_runner.dart';
import 'package:clock_app/alarm/types/schedules/alarm_schedule.dart';
import 'package:clock_app/common/types/json.dart';
import 'package:clock_app/common/types/time.dart';

class OnceAlarmSchedule extends AlarmSchedule {
  late final AlarmRunner _alarmRunner;
  bool _isDisabled = false;
  bool _isResolved = false;

  @override
  DateTime? get currentScheduleDateTime => _alarmRunner.currentScheduleDateTime;

  @override
  int get currentAlarmRunnerId => _alarmRunner.id;

  @override
  bool get isDisabled => _isDisabled;

  bool get isResolved => _isResolved;

  @override
  bool get isFinished => false;

  OnceAlarmSchedule()
      : _alarmRunner = AlarmRunner(),
        super();

  @override
  Future<void> schedule(Time time, String description,
      [bool alarmClock = false]) async {
    // A once alarm remains resolved after its runner is cancelled. This keeps
    // a fired alarm distinguishable from a never-scheduled alarm.
    if (_isResolved) {
      _isDisabled = true;
      await _alarmRunner.cancel();
      return;
    }

    // If the alarm has already been scheduled in the past, disable it.
    if (currentScheduleDateTime?.isBefore(DateTime.now()) ?? false) {
      _isResolved = true;
      _isDisabled = true;
    } else {
      DateTime alarmDate = getScheduleDateForTime(time);
      await _alarmRunner.schedule(alarmDate, description, alarmClock);
      _isDisabled = false;
    }
  }

  @override
  Future<void> cancel() async {
    await _alarmRunner.cancel();
  }

  /// Permanently resolves this once alarm and removes any OS-level runner.
  Future<void> resolve() async {
    _isResolved = true;
    _isDisabled = true;
    await cancel();
  }

  /// Clears the resolved/disabled state so an explicit user re-enable or edit
  /// can arm this once alarm again. Must be called ONLY from user-initiated
  /// reactivation (Alarm.enable / Alarm.handleEdit), never from system
  /// re-evaluation — otherwise a snooze-fire update() could revive a resolved
  /// alarm and reintroduce the next-day re-ring (#3). The subsequent schedule()
  /// re-arms from the (null) runner via its normal future-time path.
  void reactivate() {
    _isResolved = false;
    _isDisabled = false;
  }

  @override
  toJson() => {
        'alarmRunner': _alarmRunner.toJson(),
        'isDisabled': _isDisabled,
        'isResolved': _isResolved,
      };

  OnceAlarmSchedule.fromJson(Json json) {
    if (json == null) {
      _alarmRunner = AlarmRunner();
      return;
    }
    _alarmRunner = AlarmRunner.fromJson(json['alarmRunner']);
    _isDisabled = json['isDisabled'] ?? false;
    // Old once-alarm JSON has no resolution marker. Such data represents an
    // unresolved schedule by default so never-scheduled alarms still arm.
    _isResolved = json['isResolved'] ?? false;
  }

  @override
  bool hasId(int id) {
    return _alarmRunner.id == id;
  }

  @override
  List<AlarmRunner> get alarmRunners => [_alarmRunner];
}
