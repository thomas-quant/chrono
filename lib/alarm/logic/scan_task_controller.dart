import 'package:clock_app/alarm/logic/code_match.dart';

/// Camera-free interaction/latch seam for a ring-time scan task.
///
/// The widget feeds decoded text into [handleScan] and the emergency button
/// into [dismiss]. Raw payloads are normalized and compared only; this class
/// never stores, logs, or exposes a decoded value.
class ScanTaskController {
  String _storedNormalized = "";
  void Function()? _onSolve;
  bool _solved = false;

  bool get isSolved => _solved;

  /// Attaches the current task identity and resets all one-shot state.
  void configure({
    required String storedNormalized,
    required void Function() onSolve,
  }) {
    _storedNormalized = storedNormalized;
    _onSolve = onSolve;
    _solved = false;
  }

  /// Returns true when the frame was a match or the task was already solved.
  /// Returns false for a valid, non-matching decode so the widget can provide
  /// haptic/error feedback and count the failed attempt.
  bool handleScan(String decodedText) {
    if (_solved) return true;
    if (!codesMatch(normalizeCode(decodedText), _storedNormalized)) {
      return false;
    }

    _solved = true;
    _onSolve?.call();
    return true;
  }

  /// Solves the task through the emergency-dismiss path, exactly once.
  bool dismiss() {
    if (_solved) return false;
    _solved = true;
    _onSolve?.call();
    return true;
  }
}
