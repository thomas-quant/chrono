import 'package:clock_app/alarm/logic/code_match.dart';
import 'package:clock_app/navigation/widgets/app_top_bar.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Registration scanner screen (SCAN-02 / SCAN-10 / D-REG-TEST). Mirrors
/// [try_alarm_task_screen.dart]'s 24-line analog — a `Scaffold(appBar:
/// AppTopBar(), body: ...)` that renders a task surface and pops on completion.
///
/// On a valid decode it normalizes the scanned payload via [normalizeCode]
/// (D-MATCH-NORMALIZE — the SAME transform the ring-time compare uses, so a
/// trailing newline / whitespace / case difference can never false-reject) and
/// stores it into the task's "Registered Code" [StringSetting], then pops.
/// Registration IS the test scan (D-REG-TEST / SCAN-10): a successful decode
/// here inherently proves the code scans, so there is no separate mandatory
/// test step.
///
/// Privacy (D-REG-DISPLAY / threat T-04-14): the decoded payload is an opaque
/// string — it is ONLY normalized and stored, NEVER `logger`/`print`ed or
/// rendered to the user. The card that hosts this screen shows status only.
class ScanRegisterScreen extends StatefulWidget {
  const ScanRegisterScreen({super.key, required this.setting});

  /// The task's "Registered Code" StringSetting (route B — the raw value lives
  /// in a plain StringSetting; this screen writes the normalized code into it).
  final StringSetting setting;

  @override
  State<ScanRegisterScreen> createState() => _ScanRegisterScreenState();
}

class _ScanRegisterScreenState extends State<ScanRegisterScreen> {
  /// Guards against a second decode arriving after we have already stored +
  /// scheduled the pop (ReaderWidget can deliver another frame before the route
  /// is gone).
  bool _registered = false;

  /// Symbology set (SCAN-04): the SAME broad ZXing format set the ring widget
  /// uses (scan_task.dart) — QR + DataMatrix + the common 1D codes — so a code
  /// that registers here will also be readable at ring time. Bitmask of Format
  /// bit-shift constants.
  late final int _scanFormats = Format.qrCode |
      Format.dataMatrix |
      Format.ean8 |
      Format.ean13 |
      Format.upca |
      Format.upce |
      Format.code128 |
      Format.code39 |
      Format.itf;

  void _onScan(Code code) {
    if (_registered) return;
    // Privacy: the payload is opaque — normalize BEFORE storing (D-MATCH-NORMALIZE)
    // and never log/print/render it (D-REG-DISPLAY).
    widget.setting.setValue(context, normalizeCode(code.text));
    _registered = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: ReaderWidget(
        codeFormat: _scanFormats,
        showFlashlight: true, // torch available while registering
        showToggleCamera: false,
        showGallery: false,
        scanDelay: const Duration(milliseconds: 1000),
        scanDelaySuccess: const Duration(milliseconds: 1000),
        onScan: (Code code) async => _onScan(code),
      ),
    );
  }
}
