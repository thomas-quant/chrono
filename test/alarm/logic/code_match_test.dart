import 'package:clock_app/alarm/logic/code_match.dart';
import 'package:flutter_test/flutter_test.dart';

// SCAN-03 regression gate for the pure normalize/match seam (D-MATCH-NORMALIZE).
//
// `normalizeCode` / `codesMatch` are dependency-free (no camera/UI/audio) — the
// same discipline as the Phase-3 VolumeRampController seam — so every guarantee
// below runs headlessly on the CI runner with no device. There are NO timers
// here, so (unlike escape_hatch_controller_test) this file needs no fake_async.
//
// CLAUDE.md Testing Policy: the Flutter/Dart toolchain is ABSENT in the authoring
// environment. `flutter test` (via tests.yml on push) is the authoritative gate;
// these cases are authored + statically verified, NOT claimed locally green.
//
// The core invariant: normalization is applied IDENTICALLY at register-time and
// at compare-time, so a trailing newline / surrounding whitespace / case
// difference can never false-reject — while a genuinely different code, or an
// empty (unregistered) stored code, never matches.

void main() {
  group('normalizeCode', () {
    test('trailing newline + case-fold collapse to the same value', () {
      // A scanner often appends a terminator; case can differ between the
      // registering scan and the ring-time scan. Neither may cause a mismatch.
      expect(normalizeCode('ABC123\n'), normalizeCode('abc123'));
      expect(normalizeCode('ABC123\n'), 'abc123');
    });

    test('surrounding whitespace is trimmed (after control-char strip)', () {
      expect(normalizeCode('  abc  '), 'abc');
      expect(normalizeCode('\tabc\t'), 'abc');
    });

    test('NUL and ASCII control chars (0x00-0x1F, 0x7F) are stripped', () {
      // Embedded NUL must not survive into the stored/compared value.
      expect(normalizeCode('ab\x00c'), 'abc');
      // \r and \t are control chars and are removed, not merely trimmed.
      expect(normalizeCode('a\rb\tc'), 'abc');
      // DEL (0x7F) is stripped too.
      expect(normalizeCode('ab\x7Fc'), 'abc');
    });

    test('null input is normalized to the empty string (null-safe)', () {
      expect(normalizeCode(null), '');
    });

    test('a CRLF terminator round-trips to the same value as the bare code', () {
      expect(normalizeCode('CODE\r\n'), normalizeCode('code'));
    });

    test('an already-clean lowercase code is returned unchanged', () {
      expect(normalizeCode('abc123'), 'abc123');
    });
  });

  group('codesMatch', () {
    test('CRLF + case difference does NOT false-reject (normalize both sides)',
        () {
      // The exact SCAN-03 guarantee: register "CODE\r\n", scan "code" → match.
      expect(
        codesMatch(normalizeCode('CODE\r\n'), normalizeCode('code')),
        isTrue,
      );
    });

    test('a genuinely different scanned code does not match', () {
      expect(
        codesMatch(normalizeCode('wrong'), normalizeCode('right')),
        isFalse,
      );
    });

    test('an empty (unregistered) stored code never matches anything', () {
      // SCAN-07 / save-gate safety floor — never auto-dismiss an unregistered
      // task. Holds whether or not the scanned side is also empty.
      expect(codesMatch('anything', ''), isFalse);
      expect(codesMatch('', ''), isFalse);
    });

    test('identical normalized codes match', () {
      final stored = normalizeCode('My-Code-42');
      expect(codesMatch(normalizeCode('  MY-CODE-42\n'), stored), isTrue);
    });
  });
}
