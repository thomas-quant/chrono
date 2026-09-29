import 'package:clock_app/system/logic/power_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Explains what the accessibility service does before sending the user to
/// Android's accessibility settings to turn it on.
Future<void> showPowerGuardDialog(BuildContext context) async {
  final localizations = AppLocalizations.of(context)!;
  final bool? openSettings = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(localizations.preventPowerOffDialogTitle),
      content: SingleChildScrollView(
        child: Text(localizations.preventPowerOffDialogContent),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(localizations.cancelButton),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(localizations.scanOpenSettings),
        ),
      ],
    ),
  );
  if (openSettings == true) await openPowerGuardSettings();
}
