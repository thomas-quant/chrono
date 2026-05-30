import 'package:clock_app/alarm/logic/update_alarms.dart';
import 'package:clock_app/developer/logic/logger.dart';
import 'package:clock_app/system/logic/device_lock.dart';
import 'package:clock_app/system/logic/initialize_isolate.dart';
import 'package:clock_app/timer/logic/update_timers.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
void handleBoot() async {
  // String appDataDirectory = await getAppDataDirectoryPath();
  //
  // String message = '[${DateTime.now().toString()}] Test2\n';
  //
  // File('$appDataDirectory/log-dart.txt')
  //     .writeAsStringSync(message, mode: FileMode.append);
  //
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.f("Error in handleBoot isolate: ${details.exception.toString()}");
  };

  // Defer-until-unlock guard (BOOT-02 / D-07): before ANY storage touch, bail
  // out if the device is still locked (pre-unlock). Touching credential-
  // encrypted storage here would throw IllegalStateException and crash the
  // boot isolate with partial reschedule state. The OS redelivers
  // BOOT_COMPLETED after the user unlocks, so deferring loses nothing.
  if (await isDeviceLocked()) {
    logger.i(
        "handleBoot: device locked (pre-unlock) — deferring reschedule until unlock");
    return;
  }

  try {
    // initializeIsolate() touches credential-encrypted storage, so it must run
    // INSIDE this try/catch — a pre-unlock storage throw is then caught by the
    // handler below instead of crashing the isolate with partial state.
    await initializeIsolate();
    await updateAlarms("handleBoot(): Update alarms on system boot");
    await updateTimers("handleBoot(): Update timers on system boot");
  } catch (e) {
    logger.f("Error in handleBoot isolate: ${e.toString()}");
  }
}
