import 'package:clock_app/alarm/logic/escape_hatch_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// CI-runnable coverage for the scan task's escape hatch (SCAN-06/07 / D-ESC).
// The controller is pure: it owns a single Timer and fires an injected
// VoidCallback — no camera/audio/UI import, mirroring VolumeRampController.
//
// A real Timer governs the elapsed-time branch, so virtual time is advanced with
// fake_async's `async.elapse(...)`. (The `clock` package controls
// DateTime.now(), NOT Timer firing — fake_async is the correct tool here.) No
// real Future.delayed waits are used, so the suite is deterministic and fast on
// the headless CI runner. There are no OS calls, so nothing here is gated by
// FLUTTER_TEST.
//
// CLAUDE.md Testing Policy: the Flutter/Dart toolchain is ABSENT locally;
// `flutter test` (tests.yml) is the authoritative gate. These cases are authored
// + statically verified, NOT claimed locally green.

void main() {
  group('EscapeHatchController', () {
    test('time branch: start() then elapse 120s fires exactly once', () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);

        controller.start();
        // Just before the threshold: not yet.
        async.elapse(const Duration(seconds: 119));
        expect(fired, 0);
        // Crossing 120s arms the escape exactly once.
        async.elapse(const Duration(seconds: 1));
        expect(fired, 1);
        // Draining further time never re-fires (timer is one-shot + idempotent).
        async.elapse(const Duration(seconds: 600));
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('attempt branch: the 10th failed attempt (default) fires exactly once',
        () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);
        controller.start();

        // Nine non-matching valid decodes: still below the default threshold.
        for (var i = 0; i < 9; i++) {
          controller.recordFailedAttempt();
        }
        expect(fired, 0);
        // The 10th crosses maxFailedAttempts and fires once.
        controller.recordFailedAttempt();
        expect(fired, 1);
        // Further attempts never re-fire.
        controller.recordFailedAttempt();
        controller.recordFailedAttempt();
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('time-OR-attempts race: 9 attempts then 120s fires once (the timer)',
        () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);
        controller.start();

        // Below the attempt threshold...
        for (var i = 0; i < 9; i++) {
          controller.recordFailedAttempt();
        }
        expect(fired, 0);
        // ...so the elapsed-time branch is what fires — once, not twice.
        async.elapse(const Duration(seconds: 120));
        expect(fired, 1);

        controller.dispose();
      });
    });

    test(
        'time-OR-attempts race: 10 attempts before 120s fires once (the count), '
        'and the later timer does not double-fire', () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);
        controller.start();

        // The count branch wins before the timer would.
        for (var i = 0; i < 10; i++) {
          controller.recordFailedAttempt();
        }
        expect(fired, 1);
        // The still-armed timer must not fire a second time (idempotent).
        async.elapse(const Duration(seconds: 120));
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('fireNow() fires immediately and exactly once (SCAN-07)', () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);
        controller.start();

        controller.fireNow();
        expect(fired, 1);
        // A subsequent fireNow / failed attempt / elapsed timer never re-fires.
        controller.fireNow();
        controller.recordFailedAttempt();
        async.elapse(const Duration(seconds: 600));
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('enabled:false — start() timer and recordFailedAttempt() never fire',
        () {
      fakeAsync((async) {
        var fired = 0;
        final controller = EscapeHatchController(
          onEscapeAvailable: () => fired++,
          enabled: false,
        );

        controller.start();
        // The threshold paths are gated OFF by the toggle.
        for (var i = 0; i < 50; i++) {
          controller.recordFailedAttempt();
        }
        async.elapse(const Duration(seconds: 600));
        expect(fired, 0);

        controller.dispose();
      });
    });

    test(
        'enabled:false — fireNow() STILL fires (cam-denied/unavailable is '
        'non-negotiable, SCAN-07 asymmetry)', () {
      fakeAsync((async) {
        var fired = 0;
        final controller = EscapeHatchController(
          onEscapeAvailable: () => fired++,
          enabled: false,
        );
        controller.start();

        // The toggle gates the THRESHOLD path only — a camera failure must
        // always surface the escape, or a denied-camera scan task would be
        // un-dismissable. fireNow ignores `enabled`.
        controller.fireNow();
        expect(fired, 1);

        controller.dispose();
      });
    });

    test('dispose()/cancel() before threshold — no callback fires afterward',
        () {
      fakeAsync((async) {
        var fired = 0;
        final controller =
            EscapeHatchController(onEscapeAvailable: () => fired++);

        controller.start();
        async.elapse(const Duration(seconds: 60)); // partway to 120s
        controller.dispose();

        // Drain well past the original threshold: the cancelled timer is silent.
        async.elapse(const Duration(seconds: 600));
        expect(fired, 0);
      });
    });

    test('custom thresholds are honored (injectable maxFailedAttempts/elapsed)',
        () {
      fakeAsync((async) {
        var fired = 0;
        final controller = EscapeHatchController(
          onEscapeAvailable: () => fired++,
          maxFailedAttempts: 3,
          elapsedThreshold: const Duration(seconds: 30),
        );
        controller.start();

        controller.recordFailedAttempt();
        controller.recordFailedAttempt();
        expect(fired, 0);
        controller.recordFailedAttempt(); // 3rd hits the custom count
        expect(fired, 1);

        controller.dispose();
      });
    });
  });
}
