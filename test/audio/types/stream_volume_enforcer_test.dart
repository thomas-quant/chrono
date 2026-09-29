import 'package:audio_session/audio_session.dart';
import 'package:clock_app/audio/types/stream_volume_enforcer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// CI-runnable coverage for the opt-in force-max-volume hold. The enforcer is
// plugin-free: a fake AudioManager (per-stream levels + a write log) stands in
// for audio_session's AndroidAudioManager. The hold is a real periodic Timer,
// so virtual time is driven with fake_async. The platform side (does Android
// actually honour setStreamVolume on this OEM / under DND) is an on-device
// check, not covered here.

class FakeAudioManager {
  FakeAudioManager(this.levels, {this.maxVolume = 7});

  final Map<AndroidStreamType, int> levels;
  final int maxVolume;
  final List<(AndroidStreamType, int)> writes = [];
  int reads = 0;
  bool failReads = false;

  StreamVolumeEnforcer enforcer() => StreamVolumeEnforcer(
        getVolume: (stream) async {
          reads++;
          if (failReads) throw Exception("read failed");
          return levels[stream] ?? 0;
        },
        getMaxVolume: (stream) async => maxVolume,
        setVolume: (stream, volume) async {
          writes.add((stream, volume));
          levels[stream] = volume;
        },
      );
}

void main() {
  group('StreamVolumeEnforcer', () {
    test('forces the stream to max, then restores the original on stop', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2});
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();
        expect(audio.levels[AndroidStreamType.alarm], 7);
        expect(enforcer.isHolding, true);

        enforcer.stop();
        async.flushMicrotasks();
        expect(audio.levels[AndroidStreamType.alarm], 2);
        expect(enforcer.isHolding, false);
      });
    });

    test('re-asserts max within one interval if lowered mid-ring', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2});
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();

        // The user (or another app) turns the alarm stream down.
        audio.levels[AndroidStreamType.alarm] = 1;
        async.elapse(const Duration(seconds: 1));
        expect(audio.levels[AndroidStreamType.alarm], 7);

        audio.levels[AndroidStreamType.alarm] = 0;
        async.elapse(const Duration(seconds: 1));
        expect(audio.levels[AndroidStreamType.alarm], 7);

        enforcer.stop();
        async.flushMicrotasks();
        // Restores the level from before the ring, not the mid-ring one.
        expect(audio.levels[AndroidStreamType.alarm], 2);
      });
    });

    test('does not write when the stream is already at max', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 7});
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.elapse(const Duration(seconds: 5));
        expect(audio.writes, isEmpty);
      });
    });

    test('nothing is re-asserted after stop', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2});
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();
        enforcer.stop();
        async.flushMicrotasks();

        audio.levels[AndroidStreamType.alarm] = 1;
        final writesAtStop = audio.writes.length;
        async.elapse(const Duration(seconds: 30));

        expect(audio.writes.length, writesAtStop);
        expect(audio.levels[AndroidStreamType.alarm], 1);
      });
    });

    test('un-awaited start then stop never leaves the stream forced', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2});
        final enforcer = audio.enforcer();

        // Mirrors the alarm isolate, which fires both without awaiting.
        enforcer.start(AndroidStreamType.alarm);
        enforcer.stop();
        async.elapse(const Duration(seconds: 10));

        expect(audio.levels[AndroidStreamType.alarm], 2);
        expect(enforcer.isHolding, false);
      });
    });

    test('a second start on the same stream keeps the original level', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 3});
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();
        // A second alarm rings while the first is still ringing.
        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();

        enforcer.stop();
        async.flushMicrotasks();
        expect(audio.levels[AndroidStreamType.alarm], 3);
      });
    });

    test('switching streams restores the previous stream first', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({
          AndroidStreamType.alarm: 3,
          AndroidStreamType.music: 4,
        });
        final enforcer = audio.enforcer();

        enforcer.start(AndroidStreamType.alarm);
        async.flushMicrotasks();
        enforcer.start(AndroidStreamType.music);
        async.flushMicrotasks();

        expect(audio.levels[AndroidStreamType.alarm], 3);
        expect(audio.levels[AndroidStreamType.music], 7);

        enforcer.stop();
        async.flushMicrotasks();
        expect(audio.levels[AndroidStreamType.music], 4);
      });
    });

    test('stop without start makes no platform calls', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2});
        final enforcer = audio.enforcer();

        enforcer.stop();
        async.elapse(const Duration(seconds: 5));

        expect(audio.reads, 0);
        expect(audio.writes, isEmpty);
      });
    });

    test('platform errors are contained and do not stop the hold', () {
      fakeAsync((async) {
        final audio = FakeAudioManager({AndroidStreamType.alarm: 2})
          ..failReads = true;
        final enforcer = audio.enforcer();

        // Original level unreadable and every check throws: no crash, the
        // timer keeps running, and stop has nothing to restore.
        enforcer.start(AndroidStreamType.alarm);
        async.elapse(const Duration(seconds: 3));
        expect(enforcer.isHolding, true);

        // Reads recover mid-ring: the hold kicks in on the next tick.
        audio.failReads = false;
        async.elapse(const Duration(seconds: 1));
        expect(audio.levels[AndroidStreamType.alarm], 7);

        enforcer.stop();
        async.flushMicrotasks();
        expect(audio.levels[AndroidStreamType.alarm], 7);
      });
    });
  });

  group('androidStreamForUsage', () {
    test('maps each selectable audio channel to its system stream', () {
      expect(androidStreamForUsage(AndroidAudioUsage.alarm),
          AndroidStreamType.alarm);
      expect(androidStreamForUsage(AndroidAudioUsage.media),
          AndroidStreamType.music);
      expect(androidStreamForUsage(AndroidAudioUsage.notification),
          AndroidStreamType.notification);
      expect(androidStreamForUsage(AndroidAudioUsage.notificationRingtone),
          AndroidStreamType.ring);
    });
  });
}
