/// Pure, dependency-free code normalization + matching for the scan-to-dismiss
/// task (SCAN-03 / D-MATCH-NORMALIZE).
///
/// This file imports NO camera/UI/audio package — mirroring the Phase-3
/// `VolumeRampController` pure-seam discipline — so every guarantee runs
/// headlessly in CI (`tests.yml`) with no device. The two functions are the
/// single source of truth for "are these two codes the same?"; both the
/// registration screen and the ring-time scan widget pass user input through
/// `normalizeCode` first, then compare via `codesMatch`.
///
/// Invariant — normalize BOTH sides identically: normalization is applied at
/// register-time (before storing) AND at compare-time (before equality). Because
/// the exact same transform runs on each side, a trailing newline, surrounding
/// whitespace, or a letter-case difference can never false-reject a code that is
/// otherwise identical (SCAN-03).
///
/// Case-fold decision (O1, v1): codes are lower-cased so two scans that differ
/// only by case still match. This is the lenient default (fewer false rejects);
/// it could in principle false-accept two codes differing only by case, which is
/// rare for physical QR/1D codes and reversible in one line if it ever bites.
///
/// Privacy: NEVER log or print a raw or normalized code value from this file
/// (D-REG-DISPLAY) — the registered code is treated as an opaque string and is
/// only ever normalized and compared for equality, never logged, parsed into an
/// action, or used to build a query/path/intent (threat T-04-03 / T-04-04).
String normalizeCode(String? raw) {
  if (raw == null) return '';
  // Strip ASCII control chars (0x00-0x1F incl. NUL/\n/\r/\t, and DEL 0x7F)
  // BEFORE trimming so embedded control bytes never survive into the value.
  final stripped = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
  return stripped.trim().toLowerCase();
}

/// Returns `true` only when [scannedNormalized] equals [storedNormalized] AND a
/// code is actually registered. Both arguments are expected to have already been
/// run through [normalizeCode].
///
/// The empty-stored guard is the SCAN-07 / save-gate safety floor: an
/// unregistered task (no stored code) must NEVER auto-dismiss on any scan — so
/// an empty stored side returns `false` before the equality compare, regardless
/// of what was scanned.
bool codesMatch(String scannedNormalized, String storedNormalized) {
  if (storedNormalized.isEmpty) return false; // never match an unregistered task
  return scannedNormalized == storedNormalized;
}
