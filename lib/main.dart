import 'dart:async';
import 'dart:core';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:clock_app/alarm/logic/update_alarms.dart';
import 'package:clock_app/app.dart';
import 'package:clock_app/audio/logic/audio_session.dart';
import 'package:clock_app/audio/types/ringtone_player.dart';
import 'package:clock_app/common/data/paths.dart';
import 'package:clock_app/developer/logic/logger.dart';
import 'package:clock_app/navigation/types/app_visibility.dart';
import 'package:clock_app/notifications/logic/foreground_task.dart';
import 'package:clock_app/notifications/logic/notifications.dart';
import 'package:clock_app/settings/logic/initialize_settings.dart';
import 'package:clock_app/system/data/app_info.dart';
import 'package:clock_app/system/data/device_info.dart';
import 'package:clock_app/system/logic/background_service.dart';
import 'package:clock_app/system/logic/handle_boot.dart';
import 'package:clock_app/system/logic/initialize_isolate_ports.dart';
import 'package:clock_app/timer/logic/update_timers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_boot_receiver/flutter_boot_receiver.dart';
import 'package:flutter_show_when_locked/flutter_show_when_locked.dart';
import 'package:timezone/data/latest_all.dart';

void main() async {
  // FlutterError.onError = (FlutterErrorDetails details) {
  //   logger.e(details.exception.toString(), stackTrace: details.stack,);
  // };

  WidgetsFlutterBinding.ensureInitialized();

  initializeTimeZones();
  final initializeData = [
    initializePackageInfo(),
    initializeAndroidInfo(),
    initializeAppDataDirectory(),
    initializeNotifications(),
    AndroidAlarmManager.initialize(),
    BootReceiver.initialize(handleBoot),
    RingtonePlayer.initialize(),
    initializeAudioSession(),
    FlutterShowWhenLocked().hide(),
  ];
  await Future.wait(initializeData);

  // Time-box the storage + reschedule segment (BOOT-01 / D-06): a slow or
  // failed recovery must degrade to the normal UI rather than hang forever on
  // the splash. These steps rely on initializeAppDataDirectory (above, in the
  // Future.wait), but are wrapped here so any hang/throw still falls through to
  // runApp(App()). updateAlarms/updateTimers are the shared idempotent
  // reschedule funnel (D-08) — also called by handleBoot — so re-running on a
  // later launch re-arms exactly once (cancel-then-schedule by stable id).
  try {
    await () async {
      await initializeStorage();
      await initializeSettings();
      await updateAlarms("Update Alarms on Start");
      await updateTimers("Update Timers on Start");
    }()
        .timeout(const Duration(seconds: 8));
  } on TimeoutException catch (e) {
    logger.f(
        "main() init timed out — proceeding to UI with current state: $e");
  } catch (e) {
    logger.f("main() init failed — proceeding to UI: $e");
  }

  AppVisibility.initialize();
  initForegroundTask();
  initBackgroundService();
  initializeIsolatePorts();

  runApp(const App());

  registerHeadlessBackgroundService();
}
