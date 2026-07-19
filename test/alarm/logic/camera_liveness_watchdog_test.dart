import 'package:clock_app/alarm/logic/camera_liveness_watchdog.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraLivenessWatchdog', () {
    test('fires after the timeout when no liveness signal arrives', () {
      fakeAsync((async) {
        var timedOut = 0;
        final watchdog = CameraLivenessWatchdog(
          timeout: const Duration(seconds: 10),
          onTimeout: () => timedOut++,
        );

        watchdog.start();
        async.elapse(const Duration(seconds: 9));
        expect(timedOut, 0);
        async.elapse(const Duration(seconds: 1));
        expect(timedOut, 1);
        async.elapse(const Duration(minutes: 1));
        expect(timedOut, 1);

        watchdog.dispose();
      });
    });

    test('cancels when a decodable/liveness signal arrives', () {
      fakeAsync((async) {
        var timedOut = 0;
        final watchdog = CameraLivenessWatchdog(
          timeout: const Duration(seconds: 10),
          onTimeout: () => timedOut++,
        );

        watchdog.start();
        watchdog.signalLiveness();
        async.elapse(const Duration(minutes: 1));

        expect(timedOut, 0);
        expect(watchdog.hasLiveness, true);
        watchdog.dispose();
      });
    });
  });
}
