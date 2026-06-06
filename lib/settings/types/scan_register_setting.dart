import 'package:clock_app/settings/types/setting_enable_condition.dart';
import 'package:clock_app/settings/types/setting_item.dart';
import 'package:clock_app/settings/utils/description.dart';
import 'package:flutter/material.dart';

/// Marker `SettingItem` that mounts the inline `ScanRegisterCard` inside the
/// scan task's `SettingGroup` (route B — D-STORE-FORMAT). It carries NO
/// persisted value of its own (`valueToJson` returns null, like
/// [SettingAction]); the raw registered code lives in the sibling plain
/// "Registered Code" `StringSetting`, so NO `json_serialize.dart` /
/// `fromJsonFactories` entry is needed.
///
/// `get_setting_widget.dart` dispatches this marker to `ScanRegisterCard`,
/// passing the sibling `getSetting("Registered Code")`. This is intentionally a
/// dedicated tiny class (not a reused `SettingAction`) so the dispatch branch is
/// unambiguous — a `SettingAction` would dispatch to `SettingActionCard`, the
/// wrong widget.
class ScanRegisterSetting extends SettingItem {
  ScanRegisterSetting(
    String name,
    String Function(BuildContext) getLocalizedName, {
    String Function(BuildContext) getDescription = defaultDescription,
    List<String> searchTags = const [],
    List<EnableConditionParameter> enableConditions = const [],
  }) : super(name, getLocalizedName, getDescription, searchTags,
            enableConditions);

  @override
  ScanRegisterSetting copy() {
    return ScanRegisterSetting(
      name,
      getLocalizedName,
      getDescription: getDescription,
      searchTags: searchTags,
      enableConditions: enableConditions,
    );
  }

  @override
  dynamic valueToJson() {
    return null;
  }

  @override
  void loadValueFromJson(dynamic value) {
    return;
  }
}
