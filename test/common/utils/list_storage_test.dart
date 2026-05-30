import 'dart:io';

import 'package:clock_app/common/data/paths.dart';
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
}
