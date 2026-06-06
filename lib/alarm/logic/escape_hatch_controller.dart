import 'dart:async';

/// A pure, camera-free, idempotent controller for the scan task's escape hatch
/// (SCAN-06 / SCAN-07 / D-ESC) — the ethics-critical "never trap the user"
/// guarantee.
///
/// It is the structural twin of the Phase-3 `VolumeRampController`: it owns a
/// single [Timer] and fires an injected `void Function()` callback exactly once.
/// The callback is the testability seam — in production it makes the ring widget
/// reveal a plain "Dismiss" affordance; tests record that it fired. The
/// controller imports no camera/audio/UI package (only `dart:async`), so all of
/// its timing behavior runs headlessly in CI with no device.
///
/// The escape becomes available on the FIRST of two threshold paths
/// (D-ESC-TRIGGER, whichever comes first):
///   * elapsed time — [start] arms a `Timer(elapsedThreshold, _fire)`, OR
///   * failed attempts — [recordFailedAttempt] fires at `>= maxFailedAttempts`.
/// [recordFailedAttempt] must be called ONLY on a non-matching VALID decode,
/// never on raw decode frames: ZXing emits many reads/sec, and
/// `ReaderWidget.scanDelay` (1000ms) already rate-limits distinct reads upstream
/// to ~1/sec, so the count is meaningful (RESEARCH Pitfall 2 / D-ESC-DEFAULT).
///
/// Defaults are the single conservative D-ESC-DEFAULT pair — 10 attempts OR 120s
/// — because v1 exposes only an on/off toggle (D-ESC-EXPOSURE); the numbers live
/// behind it. This is the benign safety auto-dismiss ONLY (D-ESC-MODEL): it is a
/// plain time/attempts unlock, never an Alarmy-style predatory "Emergency
/// Escape" friction path (no guilt-pledge, no escalating tap penalty).
///
/// Enabled-vs-fireNow asymmetry (deliberate, SCAN-07): the [enabled] toggle gates
/// only the THRESHOLD paths ([start]'s timer and [recordFailedAttempt]). It does
/// NOT gate [fireNow], which is the camera-denied / camera-unavailable path —
/// because if a user disabled the threshold escape AND the camera fails to
/// initialise, the scan task would otherwise be un-dismissable, violating the
/// core "never trap the user" guarantee (threat T-04-05). A camera failure must
/// always surface the escape, regardless of the toggle.
class EscapeHatchController {
  EscapeHatchController({
    required this.onEscapeAvailable,
    this.maxFailedAttempts = 10,
    this.elapsedThreshold = const Duration(seconds: 120),
    this.enabled = true,
  });

  /// Injected seam: invoked exactly once when the escape becomes available.
  final void Function() onEscapeAvailable;

  /// Failed-attempt count that arms the escape (attempt branch, D-ESC-DEFAULT).
  final int maxFailedAttempts;

  /// Elapsed time that arms the escape (time branch, D-ESC-TRIGGER).
  final Duration elapsedThreshold;

  /// Whether the THRESHOLD paths are active. When false, [start] and
  /// [recordFailedAttempt] are no-ops — but [fireNow] still fires (SCAN-07).
  final bool enabled;

  int _attempts = 0;
  Timer? _timer;
  bool _fired = false;

  /// Whether the escape has already fired. After this is true the controller is
  /// inert — no path fires the callback a second time.
  bool get hasFired => _fired;

  /// Arms the elapsed-time branch. Call when the scanner opens. No-op when the
  /// escape is disabled (the threshold paths are toggled off).
  void start() {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(elapsedThreshold, _fire);
  }

  /// Records one non-matching VALID decode and fires the escape once the count
  /// reaches [maxFailedAttempts]. No-op when the escape is disabled. Must NOT be
  /// called on raw decode frames (Pitfall 2).
  void recordFailedAttempt() {
    if (!enabled) return;
    _attempts++;
    if (_attempts >= maxFailedAttempts) _fire();
  }

  /// Fires the escape immediately, regardless of [enabled] — the camera-denied /
  /// camera-unavailable path (SCAN-07). Idempotent like every other path.
  void fireNow() => _fire();

  void _fire() {
    if (_fired) return; // idempotent: the callback runs at most once
    _fired = true;
    _timer?.cancel();
    _timer = null;
    onEscapeAvailable();
  }

  /// Cancels the owned [Timer] so no callback fires after this returns. Call on
  /// every exit path (match / escape / background) so a lingering timer cannot
  /// fire after the scan task leaves the tree.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Alias for [cancel] mirroring the widget-disposal idiom.
  void dispose() => cancel();
}
