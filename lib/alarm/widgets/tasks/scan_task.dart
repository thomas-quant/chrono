import 'dart:async';

import 'package:clock_app/alarm/logic/camera_liveness_watchdog.dart';
import 'package:clock_app/alarm/logic/escape_hatch_controller.dart';
import 'package:clock_app/alarm/logic/scan_camera_lifecycle_controller.dart';
import 'package:clock_app/alarm/logic/scan_task_controller.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

/// Ring-time scan-to-dismiss task widget (SCAN-03/04/05/06/07/09/11 — ring
/// side). Mirrors the [math_task.dart] task-widget contract: a `StatefulWidget`
/// taking `onSolve` (advance/dismiss) + `settings` (the scan `SettingGroup`),
/// reading config via string keys in [_initialize], and releasing every owned
/// resource on [dispose].
///
/// It consumes Plan 02's pure seams — `normalizeCode`/`codesMatch`
/// (`code_match.dart`) and `EscapeHatchController` (`escape_hatch_controller.dart`)
/// — and Plan 01's `flutter_zxing` `ReaderWidget`. It deliberately
/// re-implements NEITHER the matching nor the escape logic.
///
/// Privacy (D-REG-DISPLAY / threat T-04-10): the decoded `code.text` and the
/// stored registered code are opaque strings — they are ONLY normalized and
/// compared for equality, NEVER `logger`/`print`ed, parsed into an action, or
/// rendered to the user.
///
/// "Unlock to scan" degradation (D-LOCK-NOGO-UX / SCAN-07 / threat T-04-21):
/// the no-go signal is a RUNTIME DEVICE-STATE branch — a camera-preview failure
/// surfaced by `onControllerCreated(_, exception != null)` — NOT a manufacturer
/// lookup. Any device whose preview fails to start (a secure keyguard that
/// blanks the camera is ONE cause; a missing/busy camera is another) degrades to
/// the Surface-4 "unlock to scan" prompt instead of a dead/black scanner, with
/// the escape hatch always running underneath so the user is never trapped. The
/// Plan 04-03 lock-screen spike verdict updates only the DOCUMENTED EXPECTED
/// DEFAULT per device class (recorded in 04-LOCKSCREEN-SPIKE.md, verified
/// behaviorally in Plan 06); it is never wired into a runtime per-device switch.
class ScanTask extends StatefulWidget {
  const ScanTask({
    super.key,
    required this.onSolve,
    required this.settings,
    this.controller,
    this.emergencyDismissTimeout = const Duration(seconds: 120),
  });

  final VoidCallback onSolve;
  final SettingGroup settings;
  final ScanTaskController? controller;

  /// Elapsed time after which the NON-DISABLEABLE emergency dismiss floor is
  /// revealed (never-trap guarantee), even when the Escape Hatch is off and the
  /// camera has surfaced no error. Matches the Escape Hatch's own elapsed
  /// default (120s) so it introduces no NEW bypass window in the common
  /// (hatch-enabled) case — it only becomes the sole backstop when the hatch is
  /// off. A slow scan is not a failure, so the floor never tears the scanner
  /// down; that is reserved for a DETECTABLE camera failure ([_handleCameraFailure]).
  final Duration emergencyDismissTimeout;

  @override
  State<ScanTask> createState() => _ScanTaskState();
}

class _ScanTaskState extends State<ScanTask> with WidgetsBindingObserver {
  /// The registered code, normalized once at init (normalize-both-sides
  /// invariant — the register side normalizes before storing, Plan 05).
  String _storedNormalized = "";

  EscapeHatchController? _escapeHatch;
  CameraLivenessWatchdog? _cameraLivenessWatchdog;
  late ScanCameraLifecycleController _lifecycleController;
  ScanTaskController? _taskController;
  int _scannerGeneration = 0;

  /// The ReaderWidget is removed while the app is backgrounded so its camera
  /// controller is released before another activity can use the camera.
  bool _scannerPaused = false;

  /// Revealed once the escape hatch fires (time / attempts / camera-failure
  /// fireNow). Gates the Semantics-wrapped Dismiss affordance.
  bool _escapeAvailable = false;

  /// Set when the camera preview fails to start (onControllerCreated exception /
  /// dead preview). Switches build() to the Surface-4 unlock-to-scan prompt and
  /// un-mounts the ReaderWidget (SCAN-11 — a dead preview must not hold the
  /// camera). This is the runtime device-state no-go signal (D-LOCK-NOGO-UX).
  bool _cameraFailed = false;

  /// Transient "that's not the registered code" flash (~600ms) on a non-matching
  /// valid decode (D-RING-WRONGSCAN). Tuned so it never strobes.
  bool _showWrongCode = false;

  /// Set when an attempt to enable the flashlight fails — shows
  /// scanTorchUnavailable while the scanner keeps running (graceful no-flash,
  /// SCAN-09).
  bool _torchUnavailable = false;

  /// Symbology set (SCAN-04): broad ZXing format set — QR + DataMatrix + the
  /// common 1D codes. Narrow to Format.qrCode only if 1D false-reads surface
  /// on device (SCAN-04 escape clause). Bitmask of Format bit-shift constants.
  late final int _scanFormats = Format.qrCode |
      Format.dataMatrix |
      Format.ean8 |
      Format.ean13 |
      Format.upca |
      Format.upce |
      Format.code128 |
      Format.code39 |
      Format.itf;

  void _initialize() {
    _scannerGeneration++;
    _storedNormalized =
        normalizeCode(widget.settings.getSetting("Registered Code").value);
    final bool escapeEnabled =
        widget.settings.getSetting("Escape Hatch").value;

    _cameraLivenessWatchdog?.dispose();
    _cameraLivenessWatchdog = CameraLivenessWatchdog(
      timeout: widget.emergencyDismissTimeout,
      onTimeout: _revealEmergencyDismissFloor,
    );

    _taskController ??= widget.controller ?? ScanTaskController();
    if (widget.controller != null &&
        !identical(widget.controller, _taskController)) {
      _taskController = widget.controller;
    }
    _taskController!.configure(
      storedNormalized: _storedNormalized,
      onSolve: () {
        if (!mounted) return;
        widget.onSolve();
      },
    );

    // Reset every state value that belongs to the previous task. The ring host
    // also keys task widgets by AlarmTask.id, but this protects any host that
    // updates ScanTask in place as well.
    _escapeAvailable = false;
    _cameraFailed = false;
    _showWrongCode = false;
    _torchUnavailable = false;

    // Re-arm a fresh controller each time settings change (didUpdateWidget) so a
    // stale timer can never outlive the active task (SCAN-11).
    _escapeHatch?.dispose();
    _escapeHatch = EscapeHatchController(
      enabled: escapeEnabled,
      onEscapeAvailable: () {
        if (!mounted) return;
        setState(() => _escapeAvailable = true);
      },
    )..start();

    if (!_scannerPaused) {
      _cameraLivenessWatchdog!.start();
      unawaited(_checkCameraAccess(_scannerGeneration));
    }
  }

  @override
  void initState() {
    super.initState();
    _taskController = widget.controller ?? ScanTaskController();
    _lifecycleController = ScanCameraLifecycleController(
      onBackgrounded: _pauseScanner,
      onResumed: _resumeScanner,
    );
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ScanTask oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _lifecycleController.handle(ScanCameraLifecycleEvent.backgrounded);
      case AppLifecycleState.resumed:
        _lifecycleController.handle(ScanCameraLifecycleEvent.resumed);
      case AppLifecycleState.hidden:
        // inactive/paused already performed the required teardown.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleController.dispose();
    _cameraLivenessWatchdog?.dispose();
    // Cancel the owned escape timer so no callback fires after the task leaves
    // the tree. The ReaderWidget releases its CameraController when it is removed
    // from the tree (every exit path un-mounts this widget — SCAN-11).
    _escapeHatch?.dispose();
    super.dispose();
  }

  void _onScan(Code code) {
    // Privacy: the decoded payload is opaque — never emitted to logger/print/UI
    // (D-REG-DISPLAY / threat T-04-10). It is only normalized and compared.
    //
    // NB: we deliberately do NOT signal the emergency-dismiss floor here. A
    // decode is not proof the camera is healthy, and a single wrong scan must
    // never disarm the non-disableable floor — the floor is purely time-based.
    if (_taskController!.handleScan(code.text)) return;

    // Non-matching valid decode: haptic + transient error flash + count toward
    // the escape threshold. ReaderWidget.scanDelay (1000ms) rate-limits distinct
    // reads to ~1/sec so the count is meaningful (Pitfall 2 — never count raw
    // decode frames).
    Vibration.vibrate(duration: 200);
    _escapeHatch?.recordFailedAttempt();
    if (!mounted) return;
    setState(() => _showWrongCode = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _showWrongCode = false);
    });
  }

  void _onControllerCreated(dynamic controller, Object? exception) {
    if (exception == null) return;
    // Camera preview failed to start (camera-unavailable / secure-keyguard
    // blanked camera / busy camera). Fire the escape immediately — fireNow()
    // ignores the enabled toggle so the user can never be trapped (SCAN-07) —
    // AND degrade to the Surface-4 unlock-to-scan prompt instead of a dead
    // scanner (D-LOCK-NOGO-UX). This is a runtime device-state branch, NOT a
    // manufacturer lookup.
    _handleCameraFailure();
  }

  Future<void> _checkCameraAccess(int generation) async {
    try {
      // Ring time must never request permission. A denied permission is an
      // immediate camera failure; the liveness watchdog covers a granted but
      // unusable, black, or frozen feed.
      final PermissionStatus status = await Permission.camera.status;
      if (!mounted ||
          generation != _scannerGeneration ||
          _scannerPaused ||
          _cameraFailed) {
        return;
      }
      if (!status.isGranted) _handleCameraFailure();
    } catch (_) {
      // A headless/platform-channel failure is not treated as denial. The
      // bounded watchdog remains the fallback for camera availability.
    }
  }

  /// Non-disableable emergency dismiss floor (never-trap guarantee). Fired by the
  /// time-based [CameraLivenessWatchdog] after [ScanTask.emergencyDismissTimeout].
  /// Reveals the Dismiss affordance regardless of the Escape Hatch toggle
  /// (`fireNow` ignores `enabled`), but does NOT tear the scanner down: a healthy
  /// but not-yet-scanned camera (a slow scan is not a failure) must keep working,
  /// and the "unlock to scan" prompt would be wrong messaging when nothing is
  /// actually wrong. A silent black/frozen feed is indistinguishable from a slow
  /// scan here (ReaderWidget exposes no frame signal), so this time floor is the
  /// honest backstop for that case too.
  void _revealEmergencyDismissFloor() {
    if (_scannerPaused) return;
    _escapeHatch?.fireNow();
  }

  /// A DETECTABLE camera failure — an `onControllerCreated` exception or a
  /// not-granted camera permission at ring time. Surfaces the escape immediately
  /// (`fireNow` ignores the Escape Hatch toggle) AND degrades to the Surface-4
  /// unlock-to-scan prompt, un-mounting the dead ReaderWidget (SCAN-11).
  void _handleCameraFailure() {
    if (_scannerPaused) return;
    _cameraLivenessWatchdog?.cancel();
    _escapeHatch?.fireNow();
    if (!mounted || _cameraFailed) return;
    setState(() => _cameraFailed = true);
  }

  void _pauseScanner() {
    _cameraLivenessWatchdog?.cancel();
    if (!mounted) return;
    setState(() => _scannerPaused = true);
  }

  void _resumeScanner() {
    if (!mounted) return;
    setState(() => _scannerPaused = false);
    if (!_cameraFailed) {
      _cameraLivenessWatchdog?.start();
      unawaited(_checkCameraAccess(_scannerGeneration));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final AppLocalizations localizations = AppLocalizations.of(context)!;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Widget instruction = Text(
            localizations.scanRingInstruction,
            style: textTheme.headlineMedium,
            textAlign: TextAlign.center,
          );

          if (constraints.hasBoundedHeight) {
            // Reserve the emergency control below the flexible scanner. The
            // control therefore remains in the viewport and hit-testable at
            // landscape sizes and large text scales.
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      shrinkWrap: true,
                      child: instruction,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Expanded(
                    child: _buildScannerSurface(
                      context, colorScheme, textTheme, localizations,
                    ),
                  ),
                  if (_escapeAvailable)
                    _buildDismissButton(context, localizations),
                ],
              ),
            );
          }

          // GAP-A compatibility: both existing task hosts can provide an
          // unbounded Column. Keep a definite, sane scanner height there so
          // ReaderWidget's Positioned.fill receives real height. The bounded
          // ring-host path above handles viewport reservation.
          final double scannerHeight =
              (MediaQuery.of(context).size.height * 0.6)
                  .clamp(120.0, 480.0)
                  .toDouble();
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                instruction,
                const SizedBox(height: 16.0),
                SizedBox(
                  height: scannerHeight,
                  child: _buildScannerSurface(
                    context, colorScheme, textTheme, localizations,
                  ),
                ),
                if (_escapeAvailable)
                  _buildDismissButton(context, localizations),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScannerSurface(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations localizations,
  ) {
    if (_cameraFailed) {
      return _buildUnlockToScanPrompt(
          context, colorScheme, textTheme, localizations);
    }
    if (_scannerPaused) return const SizedBox.expand();
    return _buildScanner(context, colorScheme, textTheme, localizations);
  }

  Widget _buildScanner(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations localizations,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: ReaderWidget(
            codeFormat: _scanFormats,
            showFlashlight: true, // SCAN-09 torch (built in; default OFF)
            showToggleCamera: false,
            showGallery: false,
            scanDelay: const Duration(milliseconds: 1000),
            scanDelaySuccess: const Duration(milliseconds: 1000),
            onControllerCreated: _onControllerCreated,
            onScan: (Code code) async => _onScan(code),
          ),
        ),
        // Graceful torch-failure copy — the scanner keeps running (SCAN-09).
        if (_torchUnavailable)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                localizations.scanTorchUnavailable,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        // Transient wrong-scan feedback: error-role border + inline message
        // (~600ms), paired with the haptic in _onScan (D-RING-WRONGSCAN).
        if (_showWrongCode)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.error, width: 4),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      localizations.scanWrongCode,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Surface-4 "unlock to scan" prompt (D-LOCK-NOGO-UX). A centered block — NO
  /// ReaderWidget is mounted in this branch (a dead/black preview is exactly
  /// what we degrade away from). The alarm keeps ringing (audio is the firing
  /// isolate's; this widget only changes the dismiss-step UI) and the escape
  /// hatch keeps running underneath (fireNow already armed the Dismiss).
  Widget _buildUnlockToScanPrompt(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations localizations,
  ) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.scanUnlockToScanTitle,
                style: textTheme.displaySmall ?? textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              Text(
                localizations.scanUnlockToScanBody,
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The escape-hatch Dismiss affordance (SCAN-06/07 / D-ESC-SCOPE). Reuses the
  /// existing dismissAlarmButton string, wrapped in Semantics so it is
  /// screen-reader reachable (ethics-critical — it is also the accessibility
  /// path). Tapping calls onSolve(), skipping ONLY this scan task.
  Widget _buildDismissButton(
      BuildContext context, AppLocalizations localizations) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Semantics(
        button: true,
        label: localizations.dismissAlarmButton,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            // Same one-shot latch as _onScan (CR-02): a double-tap must not
            // double-fire onSolve().
            onPressed: () {
              _taskController!.dismiss();
            },
            child: Text(localizations.dismissAlarmButton),
          ),
        ),
      ),
    );
  }
}
