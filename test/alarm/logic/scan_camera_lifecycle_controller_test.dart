import 'package:clock_app/alarm/logic/scan_camera_lifecycle_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tears down once on background and restarts once on resume', () {
    var teardownCount = 0;
    var restartCount = 0;
    final lifecycle = ScanCameraLifecycleController(
      onBackgrounded: () => teardownCount++,
      onResumed: () => restartCount++,
    );

    lifecycle.handle(ScanCameraLifecycleEvent.backgrounded);
    lifecycle.handle(ScanCameraLifecycleEvent.backgrounded);
    expect(teardownCount, 1);
    expect(lifecycle.isBackgrounded, true);

    lifecycle.handle(ScanCameraLifecycleEvent.resumed);
    lifecycle.handle(ScanCameraLifecycleEvent.resumed);
    expect(restartCount, 1);
    expect(lifecycle.isBackgrounded, false);

    lifecycle.dispose();
    lifecycle.handle(ScanCameraLifecycleEvent.backgrounded);
    expect(teardownCount, 1);
  });
}
