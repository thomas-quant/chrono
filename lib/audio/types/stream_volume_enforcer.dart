import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:clock_app/developer/logic/logger.dart';

/// Maps the alarm's audio channel (player usage) to the Android system stream
/// that actually carries it, mirroring AudioAttributes' usage→stream mapping.
/// (`AndroidAudioUsage` is a class with value equality, not an enum.)
AndroidStreamType androidStreamForUsage(AndroidAudioUsage usage) {
  if (usage == AndroidAudioUsage.alarm) return AndroidStreamType.alarm;
  if (usage == AndroidAudioUsage.notificationRingtone) {
    return AndroidStreamType.ring;
  }
  if (const [
    AndroidAudioUsage.notification,
    AndroidAudioUsage.notificationCommunicationRequest,
    AndroidAudioUsage.notificationCommunicationInstant,
    AndroidAudioUsage.notificationCommunicationDelayed,
    AndroidAudioUsage.notificationEvent,
  ].contains(usage)) {
    return AndroidStreamType.notification;
  }
  return AndroidStreamType.music;
}

/// Forces a system audio stream to its maximum level while an alarm rings,
/// holds it there, and restores the user's original level on [stop].
///
/// `alarm.volume` only attenuates the player *within* the system stream, so a
/// stream the user lowered before bed stays lowered and the alarm is quiet.
/// This raises the stream itself.
///
/// Pure and plugin-free: stream access goes through injected callbacks (in
/// production, audio_session's `AndroidAudioManager`, which is registered in
/// the alarm isolate's engine), so the hold/restore logic is testable headless
/// with fake_async.
///
/// All state changes run through a single serial queue, so an un-awaited
/// [start]/[stop] pair (the alarm isolate fires both without awaiting) and the
/// periodic re-assert can never interleave — a re-assert can't land after the
/// restore.
class StreamVolumeEnforcer {
  StreamVolumeEnforcer({
    required this.getVolume,
    required this.getMaxVolume,
    required this.setVolume,
    this.checkInterval = const Duration(seconds: 1),
  });

  final Future<int> Function(AndroidStreamType stream) getVolume;
  final Future<int> Function(AndroidStreamType stream) getMaxVolume;
  final Future<void> Function(AndroidStreamType stream, int volume) setVolume;

  /// How often the stream is checked and pushed back to max if lowered.
  final Duration checkInterval;

  AndroidStreamType? _stream;
  int? _maxVolume;

  /// The level to restore on [stop]. Null if it couldn't be read, in which
  /// case the stream is still forced but left as-is on stop.
  int? _originalVolume;

  Timer? _timer;
  Future<void> _queue = Future.value();

  /// Whether the periodic hold is running.
  bool get isHolding => _timer?.isActive ?? false;

  /// Forces [stream] to max and starts holding it. Re-entrant: calling again
  /// for the same stream keeps the originally captured level (so a second
  /// alarm doesn't record "max" as the level to restore); calling for a
  /// different stream restores the previous one first.
  Future<void> start(AndroidStreamType stream) {
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _enqueue(_reassert));
    return _enqueue(() async {
      if (_stream != null && _stream != stream) await _restore();
      if (_stream == null) {
        _stream = stream;
        try {
          _originalVolume = await getVolume(stream);
        } catch (e) {
          logger.e("Could not read original volume of $stream: $e");
        }
      }
      _maxVolume ??= await getMaxVolume(stream);
      logger.i("Forcing $stream to max volume ($_maxVolume)");
      await _reassert();
    });
  }

  /// Stops the hold and restores the original level. The timer is cancelled
  /// synchronously, so no re-assert is scheduled after this returns. Safe to
  /// call when not started (no platform calls are made).
  Future<void> stop() {
    _timer?.cancel();
    _timer = null;
    return _enqueue(_restore);
  }

  Future<void> _reassert() async {
    final stream = _stream;
    final maxVolume = _maxVolume;
    if (stream == null || maxVolume == null) return;
    if (await getVolume(stream) < maxVolume) {
      logger.t("Re-asserting max volume on $stream");
      await setVolume(stream, maxVolume);
    }
  }

  Future<void> _restore() async {
    final stream = _stream;
    final originalVolume = _originalVolume;
    _stream = null;
    _maxVolume = null;
    _originalVolume = null;
    if (stream == null || originalVolume == null) return;
    logger.i("Restoring $stream volume to $originalVolume");
    await setVolume(stream, originalVolume);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    return _queue = _queue.then((_) async {
      try {
        await operation();
      } catch (e) {
        logger.e("StreamVolumeEnforcer error: $e");
      }
    });
  }
}
