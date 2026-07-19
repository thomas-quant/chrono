import 'dart:async';

/// Timer factory used by [CameraLivenessWatchdog]. Keeping timer creation
/// injectable makes the camera-free watchdog behavior deterministic in tests.
typedef CameraLivenessTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// A bounded one-shot timer used as the scan task's NON-DISABLEABLE emergency
/// dismiss floor (the never-trap guarantee).
///
/// A silently black or frozen camera surfaces NO `onControllerCreated`
/// exception, and `flutter_zxing`'s `ReaderWidget` exposes no per-frame
/// callback — so a live-but-not-yet-scanned camera and a dead feed are
/// indistinguishable in Dart. The ring task therefore does NOT tie this timer to
/// decode events: [onTimeout] fires after a bounded elapsed time regardless of
/// scans, revealing the Dismiss affordance even when the configurable escape
/// hatch is off, WITHOUT tearing the scanner down. [signalLiveness] is an
/// optional cancel hook retained for the generic timer, but the ring task must
/// NOT wire it to decodes — a slow scan is not a failure, and a single wrong
/// scan must never disarm this safety floor.
class CameraLivenessWatchdog {
  CameraLivenessWatchdog({
    required this.onTimeout,
    this.timeout = const Duration(seconds: 15),
    CameraLivenessTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? _defaultTimerFactory;

  final void Function() onTimeout;
  final Duration timeout;
  final CameraLivenessTimerFactory _timerFactory;

  Timer? _timer;
  bool _hasLiveness = false;
  bool _timedOut = false;

  bool get hasLiveness => _hasLiveness;
  bool get hasTimedOut => _timedOut;

  /// Starts a fresh bounded liveness window for the currently mounted camera.
  void start() {
    cancel();
    _hasLiveness = false;
    _timedOut = false;
    _timer = _timerFactory(timeout, _fire);
  }

  /// Marks the mounted scanner usable and cancels the watchdog timer.
  void signalLiveness() {
    _hasLiveness = true;
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    if (_hasLiveness || _timedOut) return;
    _timedOut = true;
    onTimeout();
  }

  /// Stops the timer while the scanner is unmounted or the task is disposed.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();

  static Timer _defaultTimerFactory(
    Duration duration,
    void Function() callback,
  ) {
    return Timer(duration, (_) => callback());
  }
}
