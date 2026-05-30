import 'dart:convert';

import 'package:clock_app/alarm/types/alarm.dart';
import 'package:clock_app/alarm/types/alarm_event.dart';
import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:clock_app/common/types/file_item.dart';
import 'package:clock_app/common/types/schedule_id.dart';
import 'package:clock_app/common/types/tag.dart';
import 'package:clock_app/common/types/time.dart';
import 'package:clock_app/clock/types/city.dart';
import 'package:clock_app/common/types/json.dart';
import 'package:clock_app/common/logic/salvage_report.dart';
import 'package:clock_app/developer/logic/logger.dart';
import 'package:clock_app/stopwatch/types/lap.dart';
import 'package:clock_app/stopwatch/types/stopwatch.dart';
import 'package:clock_app/theme/types/color_scheme.dart';
import 'package:clock_app/theme/types/style_theme.dart';
import 'package:clock_app/timer/types/timer.dart';
import 'package:clock_app/timer/types/timer_preset.dart';
import 'package:flutter/material.dart';
import 'package:clock_app/common/utils/time_of_day.dart';

final fromJsonFactories = <Type, Function>{
  Alarm: (Json json) => Alarm.fromJson(json),
  City: (Json json) => City.fromJson(json),
  ClockTimer: (Json json) => ClockTimer.fromJson(json),
  ClockStopwatch: (Json json) => ClockStopwatch.fromJson(json),
  TimerPreset: (Json json) => TimerPreset.fromJson(json),
  ColorSchemeData: (Json json) => ColorSchemeData.fromJson(json),
  StyleTheme: (Json json) => StyleTheme.fromJson(json),
  AlarmTask: (Json json) => AlarmTask.fromJson(json),
  Time: (Json json) => Time.fromJson(json),
  Lap: (Json json) => Lap.fromJson(json),
  TimeOfDay: (Json json) => TimeOfDayUtils.fromJson(json),
  FileItem: (Json json) => FileItem.fromJson(json),
  AlarmEvent: (Json json) => AlarmEvent.fromJson(json),
  ScheduleId: (Json json) => ScheduleId.fromJson(json),
  Tag: (Json json) => Tag.fromJson(json),
};

String listToString<T extends JsonSerializable>(List<T> items) => json.encode(
      items.map<Json>((item) => item.toJson()).toList(),
    );

List<T> listFromString<T extends JsonSerializable>(String encodedItems) {
  // Missing factory is a developer error (a type was never registered), not a
  // data error — keep it loud.
  if (!fromJsonFactories.containsKey(T)) {
    throw Exception(
        "No fromJson factory for type '$T'. Please add one in the file 'common/utils/json_serialize.dart'");
  }
  final Function fromJson = fromJsonFactories[T]!;

  // Per-entry salvage (BOOT-04 / D-04): guard the top-level decode separately
  // from each element. An unparseable list structure recovers to empty; a
  // single corrupt element is skipped+logged while every other entry loads.
  // Never rethrow — the load path must not crash or hang on bad data.
  late final List<dynamic> rawList;
  try {
    rawList = json.decode(encodedItems) as List<dynamic>;
  } catch (e) {
    logger.e("Top-level list JSON unparseable for '$T' — recovering to empty: $e");
    SalvageReport.markListReset<T>();
    return <T>[];
  }

  final List<T> list = <T>[];
  for (final raw in rawList) {
    try {
      list.add(fromJson(raw) as T);
    } catch (e) {
      logger.e("Skipping corrupt $T entry during salvage: $e");
      SalvageReport.markEntryDropped<T>();
    }
  }
  return list;
}
