import 'package:clock_app/common/types/list_item.dart';
import 'package:clock_app/navigation/widgets/app_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CustomizeState {
  bool isSaved = false;
  bool isChanged = false;
}

class CustomizeScreen<Item extends CustomizableListItem>
    extends StatefulWidget {
  const CustomizeScreen({
    super.key,
    required this.item,
    this.onSave,
    required this.builder,
    required this.isNewItem,
    this.validate,
  });

  final Item item;
  final void Function(Item item)? onSave;
  final Widget Function(BuildContext context, Item item) builder;
  final bool isNewItem;

  /// Optional save-gate. When non-null and it returns a non-null error message
  /// for the working item, the Save button does NOT pop — it shows + announces
  /// the error instead (D-REG-REQUIRED). Default null = no gate (existing
  /// behavior for every other customize screen).
  final String? Function(Item item)? validate;

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState<Item>();
}

class _CustomizeScreenState<Item extends CustomizableListItem>
    extends State<CustomizeScreen<Item>> {
  late final Item _item = widget.item.copy();
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    ColorScheme colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppTopBar(actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(
            AppLocalizations.of(context)!.cancelButton,
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: TextButton(
            onPressed: () {
              // Save gate (D-REG-REQUIRED): block the pop and announce the error
              // when validation fails (e.g. a scan task with no registered code).
              // Never a silent dead button — the message is shown AND announced
              // to screen readers (UI-SPEC Surface 5).
              final String? error = widget.validate?.call(_item);
              if (error != null) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error,
                      style: TextStyle(color: colorScheme.onError),
                    ),
                    backgroundColor: colorScheme.error,
                  ),
                );
                SemanticsService.announce(error, Directionality.of(context));
                return;
              }
              widget.onSave?.call(_item);
              _isSaved = true;
              Navigator.pop(context, _item);
            },
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        )
      ]),
      body: WillPopScope(
        onWillPop: () async {
          if (_isSaved) return true;
          if (_item.hasSameSettingsAs(widget.item) && !widget.isNewItem) {
            return true;
          }
          bool? shouldPop = await showDialog<bool>(
            context: context,
            builder: (buildContext) {
              return AlertDialog(
                actionsPadding: const EdgeInsets.only(bottom: 6, right: 10),
                content: Text(AppLocalizations.of(context)!.saveReminderAlert),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },
                    child: Text(AppLocalizations.of(context)!.noButton,
                        style: TextStyle(color: colorScheme.primary)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                    child: Text(AppLocalizations.of(context)!.yesButton,
                        style: TextStyle(color: colorScheme.error)),
                  ),
                ],
              );
            },
          );
          return shouldPop ?? false;
        },
        child: widget.builder(context, _item),
      ),
    );
  }
}
