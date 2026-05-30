import 'package:clock_app/alarm/types/alarm.dart';

/// Module-level flag recording whether one or more **Alarm** entries were lost
/// during storage recovery (per-entry salvage dropped a corrupt alarm, or the
/// whole alarm list was reset because its top-level JSON was unparseable).
///
/// Per CLAUDE.md there is NO state-management library — this is a plain static
/// flag (same static-utility style as `RingingManager`). The boot/UI path
/// (later plan) reads [alarmsWereLost] to show a one-time "alarms were reset"
/// notice, then calls [clear].
///
/// The flag is set ONLY for `Alarm` loss (D-06 / Pitfall 5): routine recovery —
/// settings defaulted, a corrupt timer/city entry skipped — must NOT set it, or
/// the one case that matters (a dropped alarm = a possible missed wake-up) gets
/// lost in the noise.
class SalvageReport {
  static bool _alarmsWereLost = false;

  /// True once at least one Alarm entry has been dropped or the alarm list was
  /// reset during recovery. Stays false for all non-alarm recovery.
  static bool get alarmsWereLost => _alarmsWereLost;

  /// Record that a single list entry of type [T] was skipped during per-entry
  /// salvage. Sets the user-facing flag only when [T] is `Alarm`.
  static void markEntryDropped<T>() {
    if (T == Alarm) {
      _alarmsWereLost = true;
    }
  }

  /// Record that a whole list of type [T] was reset (top-level JSON
  /// unparseable). Sets the user-facing flag only when [T] is `Alarm`.
  static void markListReset<T>() {
    if (T == Alarm) {
      _alarmsWereLost = true;
    }
  }

  /// Reset the flag (after the one-time notice has been shown, or in test
  /// `setUp` to keep tests independent).
  static void clear() {
    _alarmsWereLost = false;
  }
}
