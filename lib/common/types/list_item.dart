import 'dart:convert';

import 'package:clock_app/common/types/json.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter/material.dart';

abstract class ListItem extends JsonSerializable {
  int get id;
  bool get isDeletable;

  dynamic copy();

  void copyFrom(dynamic other);
}

abstract class CustomizableListItem extends ListItem {
  SettingGroup get settings;

  bool hasSameSettingsAs(CustomizableListItem other) {
    return json.encode(settings.valueToJson()) ==
        json.encode(other.settings.valueToJson());
  }

  /// Save-gate hook. Returns a localized error message when this item is NOT in
  /// a savable state, or `null` when it is savable. The default is a no-op
  /// (always savable) so existing items (themes, timers, alarms) are unaffected;
  /// only items that need a save precondition override it.
  ///
  /// Enforced at the single Save control in `customize_screen.dart`: a non-null
  /// result blocks the Save (no pop) and the message is shown + announced to
  /// screen readers (never a silent dead button). See `AlarmTask.validate` for
  /// the scan-task D-REG-REQUIRED gate (a scan task with no registered code
  /// cannot be saved).
  String? validate(BuildContext context) => null;
}
