import 'dart:io';

import 'package:clock_app/common/data/paths.dart';
import 'package:clock_app/developer/logic/logger.dart';
import 'package:clock_app/system/data/device_info.dart';
import 'package:path_provider/path_provider.dart';

/// Returns `true` when the device is still locked (pre-unlock) such that
/// credential-encrypted (CE) storage is NOT yet available, and `false`
/// otherwise (unlocked, or a platform where Direct Boot does not apply).
///
/// This is the defer-until-unlock probe used at the head of [handleBoot]
/// (BOOT-02 / D-07). When it returns `true`, the boot path must NOT touch CE
/// storage — it should log and return early; the OS redelivers
/// `BOOT_COMPLETED` after the user unlocks.
///
/// ## Mechanism (B — probe-and-catch)
/// On Android File-Based-Encryption (FBE) devices, after a reboot-before-unlock
/// the app's credential-encrypted documents directory is unavailable and
/// `getApplicationDocumentsDirectory()` throws an `IllegalStateException`
/// ("not available until after the user is unlocked"). We treat ANY throw from
/// that cheap probe as "locked, defer."
///
/// Mechanism A (a native `UserManager.isUserUnlocked()` MethodChannel on
/// `MainActivity`) was rejected for the boot path: `handleBoot()` runs in a
/// background isolate spawned by `flutter_boot_receiver`'s `BootHandlerService`
/// (a `JobIntentService`) with NO `MainActivity` / `FlutterEngine` attached, so
/// a `MainActivity`-scoped channel is not reachable from the boot isolate
/// (RESEARCH Q2 / PATTERNS "BOOT-ISOLATE REACHABILITY CAVEAT"). The
/// probe-and-catch path needs no FlutterEngine and is robust in the boot
/// isolate, so it is the chosen mechanism.
Future<bool> isDeviceLocked() async {
  // Tests must never hit a platform channel / real filesystem probe.
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return false;
  }

  // API-gate: Direct Boot (and the pre-unlock CE-storage restriction) only
  // exists on API 24+. Below that, CE storage is always available, so the
  // device is never "locked" in the sense that matters here. `androidInfo` may
  // be null in the boot isolate before `initializeAndroidInfo()` has run — in
  // that case we skip the gate and fall through to the (always-safe) probe.
  final sdkInt = androidInfo?.version.sdkInt;
  if (sdkInt != null && sdkInt < 24) {
    return false;
  }

  // Probe-and-catch: a cheap credential-encrypted storage read. A throw means
  // CE storage is unavailable => device is still locked => defer.
  try {
    await getApplicationDocumentsDirectory();
    return false;
  } catch (e) {
    logger.i(
        "isDeviceLocked: credential-encrypted storage unavailable (pre-unlock) — treating device as locked: $e");
    return true;
  }
}
