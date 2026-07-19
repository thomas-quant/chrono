import 'dart:io';

import 'package:clock_app/common/data/paths.dart';
import 'package:clock_app/common/types/schedule_id.dart';
import 'package:clock_app/common/utils/list_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    // Point the storage layer at an isolated temp directory so the atomic
    // temp-write + rename runs on a real filesystem without touching the
    // (platform-only) app documents directory.
    tempDir = await Directory.systemTemp.createTemp('chrono_storage_test');
    setAppDataDirectoryPathForTesting(tempDir.path);
  });

  tearDown(() async {
    setAppDataDirectoryPathForTesting('');
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('saveTextFile / loadTextFile (atomic write)', () {
    test('round-trips content unchanged', () async {
      const content = '[{"hello":"world"},{"n":42}]';

      await saveTextFile('round_trip', content);

      expect(await loadTextFile('round_trip'), content);
      expect(loadTextFileSync('round_trip'), content);
    });

    test('leaves no .tmp file behind after a successful save', () async {
      await saveTextFile('no_temp', 'some content');

      final tmp = File(path.join(tempDir.path, 'no_temp.txt.tmp'));
      expect(tmp.existsSync(), isFalse,
          reason: 'temp file must be renamed away, not left behind');

      final target = File(path.join(tempDir.path, 'no_temp.txt'));
      expect(target.existsSync(), isTrue);
    });

    test('fully replaces existing content (no truncation/partial bytes)',
        () async {
      const oldContent =
          'this is a long string of previous valid content that must be replaced';
      const newContent = 'short';

      await saveTextFile('replace', oldContent);
      expect(await loadTextFile('replace'), oldContent);

      await saveTextFile('replace', newContent);

      // Round-trip must equal the NEW content exactly — not old bytes left over
      // from a truncate-in-place write, and not a concatenation of the two.
      expect(await loadTextFile('replace'), newContent);
      expect(loadTextFileSync('replace'), newContent);
    });

    test('writes the target into the configured data directory', () async {
      await saveTextFile('located', 'x');

      final target = File(path.join(tempDir.path, 'located.txt'));
      expect(target.existsSync(), isTrue,
          reason: 'target must live in the same dir so rename is atomic');
    });
  });

  group('loadListResult', () {
    test('represents an absent file as a successful empty list', () async {
      final result = await loadListResult<ScheduleId>('absent');

      expect(result, isA<ListLoadSuccess<ScheduleId>>());
      expect((result as ListLoadSuccess<ScheduleId>).items, isEmpty);
    });

    test('represents a stored [] as a successfully decoded empty list',
        () async {
      await saveTextFile('stored_empty', '[]');

      final result = await loadListResult<ScheduleId>('stored_empty');

      expect(result, isA<ListLoadSuccess<ScheduleId>>());
      expect((result as ListLoadSuccess<ScheduleId>).items, isEmpty);
    });

    test('surfaces a read failure instead of returning an empty list',
        () async {
      // Force a DETERMINISTIC read failure: the file exists (so loadTextFile
      // calls readAsString) but holds invalid UTF-8, which the default utf8
      // decoder rejects on every platform. A directory would NOT work here —
      // File.existsSync() is false for a directory, so loadTextFile would take
      // the empty-list fallback — and permission tricks are unreliable in CI
      // (often runs as root).
      await File(path.join(tempDir.path, 'read_failure.txt'))
          .writeAsBytes(<int>[0xC3, 0x28]);

      final result = await loadListResult<ScheduleId>('read_failure');

      expect(result, isA<ListLoadFailure<ScheduleId>>());
    });
  });
}
