import 'package:clock_app/alarm/data/alarm_task_schemas.dart';
import 'package:clock_app/alarm/logic/code_match.dart';
import 'package:clock_app/common/types/json.dart';
import 'package:clock_app/common/types/list_item.dart';
import 'package:clock_app/common/utils/id.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum AlarmTaskType {
  math,
  retype,
  sequence,
  shake,
  memory,
  scan,
}

typedef AlarmTaskBuilder = Widget Function(
    Function() onSolve, SettingGroup settings);

class AlarmTaskSchema extends JsonSerializable {
  final String Function(BuildContext) getLocalizedName;
  final SettingGroup settings;
  final AlarmTaskBuilder _builder;

  const AlarmTaskSchema(this.getLocalizedName, this.settings, this._builder);

  AlarmTaskSchema.from(AlarmTaskSchema schema)
      : getLocalizedName = schema.getLocalizedName,
        settings = schema.settings.copy(),
        _builder = schema._builder;

  Widget getBuilder(Function() onSolve) {
    return _builder(onSolve, settings);
  }

  void loadFromJson(Json? json) {
    if (json == null) return;
    settings.loadValueFromJson(json['settings']);
  }

  AlarmTaskSchema copy() {
    return AlarmTaskSchema.from(this);
  }

  @override
  Json toJson() {
    return {
      'settings': settings.valueToJson(),
    };
  }
}

class AlarmTask extends CustomizableListItem {
  late int _id;
  late AlarmTaskType type;
  late AlarmTaskSchema _schema;

  AlarmTask(this.type)
      : _schema = alarmTaskSchemasMap[type]!.copy(),
        _id = getId();

  AlarmTask.from(AlarmTask task)
      : type = task.type,
        _id = getId(),
        _schema = task._schema.copy();

  AlarmTask.fromJson(Json json) {
    if (json == null) {
      _id = getId();
      type = AlarmTaskType.math;
      _schema = alarmTaskSchemasMap[type]!.copy();
      return;
    }
    _id = json['id'] ?? getId();
    type = AlarmTaskType.values.byName(json['type']);
    _schema = alarmTaskSchemasMap[type]!.copy();
    _schema.loadFromJson(json['schema']);
  }

  @override
  copy() {
    return AlarmTask.from(this);
  }

  @override
  void copyFrom(dynamic other) {
    type = other.type;
    _schema = other._schema.copy();
  }

  @override
  int get id => _id;
  @override
  bool get isDeletable => true;
  AlarmTaskSchema get schema => _schema;
  String Function(BuildContext) get getLocalizedName => _schema.getLocalizedName;
  @override
  SettingGroup get settings => _schema.settings;
  Widget Function(Function() onSolve) get builder => _schema.getBuilder;

  /// Save-gate predicate (D-REG-REQUIRED). For the scan task ONLY, a registered
  /// code is required to save: when the normalized "Registered Code" is empty,
  /// return the `scanCodeRequired` message to block Save (enforced at the
  /// CustomizeScreen Save button). Every other task type returns null (savable),
  /// so no other AlarmTask or CustomizableListItem is affected.
  ///
  /// `normalizeCode` is used here so emptiness is tested EXACTLY as the value was
  /// stored (the register screen normalizes before storing) — a whitespace-only
  /// scan can never satisfy the gate. This is the user-blocking half of the gate;
  /// the inline ScanRegisterCard renders the same `scanCodeRequired` copy as the
  /// visible explanation, and re-scanning a code clears the gate.
  @override
  String? validate(BuildContext context) {
    if (type != AlarmTaskType.scan) return null;
    final registered =
        normalizeCode(_schema.settings.getSetting("Registered Code").value);
    if (registered.isEmpty) {
      return AppLocalizations.of(context)!.scanCodeRequired;
    }
    return null;
  }

  @override
  Json toJson() {
    return {
      'id': _id,
      'schema': _schema.toJson(),
      'type': type.name,
    };
  }
}
