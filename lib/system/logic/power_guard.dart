import 'package:clock_app/common/utils/list_storage.dart';
import 'package:clock_app/developer/logic/logger.dart';
import 'package:clock_app/settings/data/settings_schema.dart';
import 'package:flutter/services.dart';

// Opt-in "prevent power off while ringing". The native PowerGuardService
// (android/.../PowerGuardService.kt) closes the power menu while armed.
//
// The alarm isolate runs in a background FlutterEngine that can't reach
// MainActivity's channels, so arming goes through a file the service reads:
// "<app data dir>/power_guard_until.txt" holding an expiry in epoch ms. Keep
// the key in sync with PowerGuardService.ARM_FILE. The channel below is only
// used from the UI isolate (settings screen).

const String powerGuardFileKey = "power_guard_until";

/// Upper bound on how long one ring keeps the guard armed, so a missed disarm
/// (isolate killed mid-ring) can't block the power menu indefinitely. Matches
/// the 1h window after which triggerAlarm stops ringing a missed alarm.
const Duration powerGuardMaxDuration = Duration(hours: 1);

const String powerGuardDisarmedValue = "0";

const MethodChannel _powerGuardChannel =
    MethodChannel("com.vicolo.chrono/power_guard");

bool get isPowerGuardSettingEnabled =>
    appSettings.getGroup("Alarm").getSetting("prevent_power_off").value;

/// The value written to the arm file for a ring starting at [now].
String powerGuardArmValue(DateTime now) =>
    "${now.add(powerGuardMaxDuration).millisecondsSinceEpoch}";

/// Arms the guard for the ringing alarm if the user turned the setting on.
Future<void> armPowerGuard({DateTime? now, bool? enabled}) async {
  if (!(enabled ?? isPowerGuardSettingEnabled)) return;
  try {
    await saveTextFile(
        powerGuardFileKey, powerGuardArmValue(now ?? DateTime.now()));
    logger.i("Power guard armed");
  } catch (e) {
    logger.e("Could not arm power guard: $e");
  }
}

/// Disarms unconditionally, so turning the setting off mid-ring still releases
/// the power menu once the alarm stops.
Future<void> disarmPowerGuard() async {
  try {
    await saveTextFile(powerGuardFileKey, powerGuardDisarmedValue);
  } catch (e) {
    logger.e("Could not disarm power guard: $e");
  }
}

/// Whether the user has turned on Chrono's accessibility service. UI isolate
/// only.
Future<bool> isPowerGuardServiceEnabled() async {
  try {
    return await _powerGuardChannel.invokeMethod<bool>("isServiceEnabled") ??
        false;
  } catch (e) {
    logger.e("Could not check power guard service: $e");
    return false;
  }
}

/// Opens Android's accessibility settings. UI isolate only.
Future<void> openPowerGuardSettings() async {
  try {
    await _powerGuardChannel.invokeMethod("openSettings");
  } catch (e) {
    logger.e("Could not open accessibility settings: $e");
  }
}
