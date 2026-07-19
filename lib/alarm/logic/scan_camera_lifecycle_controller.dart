/// The lifecycle events relevant to an owned scanner surface.
enum ScanCameraLifecycleEvent { backgrounded, resumed }

/// Pure, idempotent lifecycle seam for scanner camera ownership.
///
/// Widgets map Flutter's [AppLifecycleState] values to these two events. The
/// controller itself has no Flutter or camera dependency, so teardown and
/// restart behavior can be tested headlessly.
class ScanCameraLifecycleController {
  ScanCameraLifecycleController({
    required this.onBackgrounded,
    required this.onResumed,
  });

  final void Function() onBackgrounded;
  final void Function() onResumed;

  bool _isBackgrounded = false;
  bool _disposed = false;

  bool get isBackgrounded => _isBackgrounded;

  void handle(ScanCameraLifecycleEvent event) {
    if (_disposed) return;

    if (event == ScanCameraLifecycleEvent.backgrounded) {
      if (_isBackgrounded) return;
      _isBackgrounded = true;
      onBackgrounded();
      return;
    }

    if (!_isBackgrounded) return;
    _isBackgrounded = false;
    onResumed();
  }

  void dispose() {
    _disposed = true;
  }
}
