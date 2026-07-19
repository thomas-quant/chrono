import 'dart:io';

import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/common/data/paths.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

const _alarmsWereLostMarker = '.alarms_were_lost';

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
  static String? _markerPathOverride;

  /// True once at least one Alarm entry has been dropped or the alarm list was
  /// reset during recovery. The durable marker keeps this true when the loss
  /// was detected by another isolate. Stays false for non-alarm recovery.
  static bool get alarmsWereLost {
    if (_alarmsWereLost) return true;

    try {
      return File(_markerPath).existsSync();
    } catch (_) {
      // Storage is not initialized in some pure serialization tests. A
      // salvage event is still reported in memory there; production storage
      // is initialized before any list salvage can occur.
      return false;
    }
  }

  /// Record that a single list entry of type [T] was skipped during per-entry
  /// salvage. Sets the user-facing flag only when [T] is `Alarm`.
  static void markEntryDropped<T>() {
    if (T == Alarm) {
      _alarmsWereLost = true;
      _writeDurableMarker();
    }
  }

  /// Record that a whole list of type [T] was reset (top-level JSON
  /// unparseable). Sets the user-facing flag only when [T] is `Alarm`.
  static void markListReset<T>() {
    if (T == Alarm) {
      _alarmsWereLost = true;
      _writeDurableMarker();
    }
  }

  /// Reset the flag (after the one-time notice has been shown, or in test
  /// `setUp` to keep tests independent). This also consumes the durable
  /// marker, so it must only be called after the UI has shown the notice.
  static void clear() {
    _alarmsWereLost = false;
    try {
      final marker = File(_markerPath);
      if (marker.existsSync()) {
        marker.deleteSync();
      }
    } catch (_) {
      // Keep the in-memory clear behavior if storage is unavailable.
    }
  }

  /// Test seam for simulating a fresh isolate while sharing the durable
  /// marker. Production code must use [clear], which also consumes the marker.
  @visibleForTesting
  static void clearMemoryForTesting() {
    _alarmsWereLost = false;
  }

  /// Test seam for using a temporary marker file without platform storage.
  @visibleForTesting
  static void setMarkerPathForTesting(String? markerPath) {
    _markerPathOverride = markerPath;
  }

  static String get _markerPath {
    return _markerPathOverride ??
        path.join(getAppDataDirectoryPathSync(), _alarmsWereLostMarker);
  }

  static void _writeDurableMarker() {
    try {
      File(_markerPath).writeAsStringSync('1', flush: true);
    } catch (_) {
      // The app data directory is initialized before production salvage. The
      // catch preserves the existing in-memory salvage behavior in headless
      // serialization contexts where no app directory exists.
    }
  }
}
