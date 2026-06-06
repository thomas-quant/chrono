import 'package:app_settings/app_settings.dart';
import 'package:clock_app/alarm/logic/code_match.dart';
import 'package:clock_app/alarm/screens/scan_register_screen.dart';
import 'package:clock_app/common/widgets/card_container.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';

/// Inline "Scan to register" card (setup; D-REG-UI / D-REG-DISPLAY /
/// D-REG-CAMDENIED / D-REG-REQUIRED). Mirrors [setting_action_card.dart] — a
/// tappable `CardContainer → Material(transparent) → InkWell → Padding(16) →
/// Row[ Expanded(Column[title, status]), trailing chevron ]` — and uses the
/// [custom_setting_card.dart] await-push-then-`setState` refresh idiom so the
/// status line updates after a registration.
///
/// Status is DISPLAY-ONLY (D-REG-DISPLAY / threat T-04-14): the card shows
/// "Code registered" / "No code registered yet", NEVER the raw decoded value,
/// and never logs it.
///
/// Camera permission is requested HERE at SETUP (SCAN-08) — never at fire time.
/// Granted → push [ScanRegisterScreen]. Denied → a prompt deep-links to system
/// settings ([AppSettings.openAppSettings]) then resumes the registration
/// attempt (D-REG-CAMDENIED).
///
/// Required-error surface (D-REG-REQUIRED): while no code is registered the card
/// renders the `scanCodeRequired` copy in an `error`-role tint — the visible,
/// screen-reader-reachable explanation that pairs with the Save-button block
/// (alarm_task.dart `validate()` + customize_screen.dart). Re-scanning REPLACES
/// the stored code, clearing the gate.
class ScanRegisterCard extends StatefulWidget {
  const ScanRegisterCard({super.key, required this.codeSetting});

  /// The sibling "Registered Code" StringSetting (route B — the raw value lives
  /// in a plain StringSetting; this card is a non-persisted status view over it).
  final StringSetting codeSetting;

  @override
  State<ScanRegisterCard> createState() => _ScanRegisterCardState();
}

class _ScanRegisterCardState extends State<ScanRegisterCard> {
  /// Whether a code is currently registered (normalized non-empty). Computed via
  /// the SAME [normalizeCode] seam the save gate uses, so the card status and the
  /// gate predicate can never disagree.
  bool get _hasCode => normalizeCode(widget.codeSetting.value).isNotEmpty;

  Future<void> _handleScanToRegister() async {
    // Request camera permission at SETUP (SCAN-08), mirroring the
    // permissions.dart status/request idiom.
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;

    if (status.isGranted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanRegisterScreen(setting: widget.codeSetting),
        ),
      );
      // Refresh the status line + required-error visibility after registration
      // (custom_setting_card.dart refresh idiom). Re-scanning REPLACES the
      // stored code (D-REG-REQUIRED), clearing the gate.
      if (mounted) setState(() {});
      return;
    }

    // Denied → deep-link to system settings then resume (D-REG-CAMDENIED).
    await _showPermissionDeniedPrompt();
  }

  Future<void> _showPermissionDeniedPrompt() async {
    final AppLocalizations localizations = AppLocalizations.of(context)!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool? openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Text(localizations.scanCameraPermissionPrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                AppLocalizations.of(dialogContext)!.cancelButton,
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(localizations.scanOpenSettings),
            ),
          ],
        );
      },
    );

    if (openSettings == true) {
      await AppSettings.openAppSettings();
      // Resume: re-attempt registration once the user returns from settings
      // (they may have just granted the permission there).
      if (mounted) await _handleScanToRegister();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme textTheme = theme.textTheme;
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations localizations = AppLocalizations.of(context)!;

    final bool hasCode = _hasCode;
    // STATUS-ONLY (D-REG-DISPLAY): never render the raw value.
    final String statusLine = hasCode
        ? localizations.scanCodeRegistered
        : localizations.scanNoCodeRegistered;
    // CTA semantics: re-test when a code exists, register when empty.
    final String ctaLabel =
        hasCode ? localizations.scanRescanButton : localizations.scanRegisterButton;

    final Widget inner = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleScanToRegister,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.scanRegisteredCodeTitle,
                      style: textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusLine,
                      style: textTheme.bodyMedium?.copyWith(
                        // Tint the success status with the primary accent (the
                        // check glyph is part of the localized string).
                        color: hasCode ? colorScheme.primary : null,
                      ),
                    ),
                    // Required-error surface (D-REG-REQUIRED): visible, announced
                    // explanation for why Save is blocked while empty.
                    if (!hasCode) ...[
                      const SizedBox(height: 4),
                      Text(
                        localizations.scanCodeRequired,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onBackground.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );

    return CardContainer(
      child: Semantics(
        button: true,
        label: "$ctaLabel. $statusLine"
            "${hasCode ? "" : ". ${localizations.scanCodeRequired}"}",
        child: ConstrainedBox(
          // Screen-reader reachable, min 48dp hit area (UI-SPEC Surface 5).
          constraints: const BoxConstraints(minHeight: 48),
          child: inner,
        ),
      ),
    );
  }
}
