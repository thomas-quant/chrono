import 'dart:async';

import 'package:clock_app/developer/logic/logger.dart';

/// A pure, audio-free, cancellable controller for a rising-volume ramp.
///
/// It owns a single [Timer] and steps a volume from `0` toward a target over a
/// duration, invoking an injected `void Function(double)` callback on each tick.
/// The callback is the testability seam: in production it wraps
/// `RingtonePlayer.activePlayer?.setVolume`, while tests record the values it
/// receives. The controller imports no audio package — all volume application
/// lives in the injected callback.
///
/// The single-ramp invariant ([start] cancels first) guarantees that two ramps
/// never run at once, so a new alarm's ramp emits no stray ticks from a prior
/// alarm's ramp (no cross-alarm bleed), and [cancel] is the only ramp-stop
/// signal — decoupled from any plain volume write.
class VolumeRampController {
  VolumeRampController(this._setVolume);

  /// Injected volume sink. Receives each stepped volume value.
  final void Function(double volume) _setVolume;

  Timer? _timer;

  /// Whether a ramp [Timer] is currently active.
  bool get isRunning => _timer?.isActive ?? false;

  /// Ramps the volume from `0` toward [targetVolume] over [duration] in [steps]
  /// increments, calling the injected callback on each tick.
  ///
  /// Cancels any in-flight ramp first (single-ramp invariant — no cross-alarm
  /// bleed). A zero or negative [duration] applies [targetVolume] immediately
  /// and starts no timer. The final tick lands exactly on [targetVolume] and
  /// then the ramp stops itself.
  void start({
    required double targetVolume,
    required Duration duration,
    int steps = 10,
  }) {
    cancel();

    if (duration <= Duration.zero || steps <= 0) {
      _setVolume(targetVolume);
      return;
    }

    logger.t(
        "Starting volume ramp to $targetVolume over $duration in $steps steps");

    final stepInterval =
        Duration(microseconds: duration.inMicroseconds ~/ steps);
    var i = 0;
    _setVolume(0);
    _timer = Timer.periodic(stepInterval, (timer) {
      i++;
      _setVolume((i / steps) * targetVolume);
      if (i >= steps) {
        cancel();
      }
    });
  }

  /// Stops the owned [Timer] so no further callback fires after this returns.
  void cancel() {
    if (_timer != null) {
      logger.t("Cancelling volume ramp");
    }
    _timer?.cancel();
    _timer = null;
  }
}
