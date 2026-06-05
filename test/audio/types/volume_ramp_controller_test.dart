import 'package:clock_app/audio/types/volume_ramp_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// CI-runnable coverage for VOL-01's rising-volume ramp. The controller is pure
// and audio-free: its injected callback is a plain recorder here (no just_audio).
// A real Timer governs the ramp, so virtual time is advanced with fake_async's
// `async.elapse(...)` (the `clock` package controls DateTime.now(), NOT Timer
// firing — fake_async is the correct tool). No real `Future.delayed` waits are
// used, so the suite is deterministic and fast on the headless CI runner.

void main() {
  group('VolumeRampController', () {
    test(
      'no callback fires after cancel() (clean stop on dismiss/snooze)',
      () {
        fakeAsync((async) {
          final values = <double>[];
          final controller = VolumeRampController((v) => values.add(v));

          controller.start(
            targetVolume: 1.0,
            duration: const Duration(seconds: 10),
          );
          // Advance partway through the ramp, then cancel mid-flight.
          async.elapse(const Duration(seconds: 3));
          controller.cancel();
          final countAtCancel = values.length;

          // Drain well past the full duration: nothing more may fire.
          async.elapse(const Duration(seconds: 30));

          expect(values.length, countAtCancel);
          expect(controller.isRunning, false);
        });
      },
    );

    test(
      'no cross-alarm bleed: after ramp B starts, ramp A emits no more ticks',
      () {
        fakeAsync((async) {
          // Two independent controllers, each recording into its own list — the
          // direct analog of one alarm's ramp followed by another's. The single-
          // ramp invariant lives per controller via start()'s leading cancel(),
          // and playAlarm()/_play() re-entry cancels the prior controller's ramp
          // in production; here we cancel A explicitly to mirror that hand-off.
          final aValues = <double>[];
          final bValues = <double>[];
          final controllerA = VolumeRampController((v) => aValues.add(v));
          final controllerB = VolumeRampController((v) => bValues.add(v));

          controllerA.start(
            targetVolume: 1.0,
            duration: const Duration(seconds: 10),
          );
          async.elapse(const Duration(seconds: 3));

          // A new alarm starts: cancel A (the re-entry hand-off), start B.
          controllerA.cancel();
          controllerB.start(
            targetVolume: 0.5,
            duration: const Duration(seconds: 10),
          );
          final aCountAtBStart = aValues.length;

          // Run B's ramp to completion and well beyond.
          async.elapse(const Duration(seconds: 30));

          // Not a single further A-tick after B began — no cross-alarm bleed.
          expect(aValues.length, aCountAtBStart);
          // B ran to its own target undisturbed.
          expect(bValues.last, closeTo(0.5, 1e-9));
        });
      },
    );

    test(
      'reaches max: the final volume equals the configured targetVolume',
      () {
        fakeAsync((async) {
          final values = <double>[];
          final controller = VolumeRampController((v) => values.add(v));

          controller.start(
            targetVolume: 0.8,
            duration: const Duration(seconds: 10),
            steps: 10,
          );
          async.elapse(const Duration(seconds: 10));

          expect(values.last, closeTo(0.8, 1e-9));
          // The ramp stops itself on the final step.
          expect(controller.isRunning, false);
        });
      },
    );

    test(
      'zero/negative duration applies the target immediately with no ticks',
      () {
        fakeAsync((async) {
          final values = <double>[];
          final controller = VolumeRampController((v) => values.add(v));

          controller.start(
            targetVolume: 0.7,
            duration: Duration.zero,
          );

          // Exactly the target was applied, immediately, with no timer started.
          expect(values, [0.7]);
          expect(controller.isRunning, false);

          // Elapsing time produces no further ticks (no timer exists).
          async.elapse(const Duration(seconds: 10));
          expect(values, [0.7]);
        });
      },
    );
  });
}
