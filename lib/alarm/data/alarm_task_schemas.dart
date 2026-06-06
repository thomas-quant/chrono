import 'package:clock_app/alarm/types/alarm_task.dart';
import 'package:clock_app/alarm/widgets/tasks/math_task.dart';
import 'package:clock_app/alarm/widgets/tasks/memory_task.dart';
import 'package:clock_app/alarm/widgets/tasks/retype_task.dart';
import 'package:clock_app/alarm/widgets/tasks/scan_task.dart';
import 'package:clock_app/alarm/widgets/tasks/sequence_task.dart';
import 'package:clock_app/settings/types/scan_register_setting.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:clock_app/settings/types/setting_group.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Map<AlarmTaskType, AlarmTaskSchema> alarmTaskSchemasMap = {
  AlarmTaskType.math: AlarmTaskSchema(
    (context) => AppLocalizations.of(context)!.mathTask,
    SettingGroup("Math Problems Settings",
        (context) => AppLocalizations.of(context)!.mathTask, [
      SelectSetting(
        "Difficulty",
        (context) => AppLocalizations.of(context)!.mathTaskDifficultySetting,
        [
          SelectSettingOption(
              (context) => AppLocalizations.of(context)!.mathEasyDifficulty,
              MathTaskDifficultyLevel([Operator.add])),
          SelectSettingOption(
              (context) => AppLocalizations.of(context)!.mathMediumDifficulty,
              MathTaskDifficultyLevel([Operator.multiply])),
          SelectSettingOption(
              (context) => AppLocalizations.of(context)!.mathHardDifficulty,
              MathTaskDifficultyLevel([Operator.multiply, Operator.add])),
          SelectSettingOption(
              (context) => AppLocalizations.of(context)!.mathVeryHardDifficulty,
              MathTaskDifficultyLevel([Operator.multiply, Operator.multiply])),
        ],
      ),
      SliderSetting(
          "Number of problems",
          (context) => AppLocalizations.of(context)!.numberOfProblemsSetting,
          1,
          10,
          1,
          snapLength: 1),
    ]),
    (onSolve, settings) {
      return MathTask(
        onSolve: onSolve,
        settings: settings,
      );
    },
  ),
  AlarmTaskType.retype: AlarmTaskSchema(
    (context) => AppLocalizations.of(context)!.retypeTask,
    SettingGroup("Retype Text Settings",
        (context) => AppLocalizations.of(context)!.retypeTask, [
      SliderSetting(
          "Number of characters",
          (context) => AppLocalizations.of(context)!.retypeNumberChars,
          5,
          20,
          5,
          snapLength: 1),
      SwitchSetting(
          "Include numbers",
          (context) => AppLocalizations.of(context)!.retypeIncludeNumSetting,
          false),
      SwitchSetting(
          "Include lowercase",
          (context) => AppLocalizations.of(context)!.retypeLowercaseSetting,
          true),
      SliderSetting(
          "Number of problems",
          (context) => AppLocalizations.of(context)!.numberOfProblemsSetting,
          1,
          10,
          1,
          snapLength: 1),
    ]),
    (onSolve, settings) {
      return RetypeTask(onSolve: onSolve, settings: settings);
    },
  ),
  AlarmTaskType.sequence: AlarmTaskSchema(
    (context) => AppLocalizations.of(context)!.sequenceTask,
    SettingGroup("Sequence Settings",
        (context) => AppLocalizations.of(context)!.sequenceTask, [
      SliderSetting(
          "Sequence length",
          (context) => AppLocalizations.of(context)!.sequenceLengthSetting,
          3,
          10,
          3,
          snapLength: 1),
      SliderSetting(
          "Grid size",
          (context) => AppLocalizations.of(context)!.sequenceGridSizeSetting,
          2,
          5,
          3,
          snapLength: 1),
    ]),
    (onSolve, settings) {
      return SequenceTask(onSolve: onSolve, settings: settings);
    },
  ),
  AlarmTaskType.memory: AlarmTaskSchema(
    (context) => AppLocalizations.of(context)!.memoryTask,
    SettingGroup("memorySettings",
        (context) => AppLocalizations.of(context)!.memoryTask, [
      SliderSetting(
          "numberOfPairs",
          (context) => AppLocalizations.of(context)!.numberOfPairsSetting,
          3,
          10,
          3,
          snapLength: 1),
    ]),
    (onSolve, settings) {
      return MemoryTask(onSolve: onSolve, settings: settings);
    },
  ),
  AlarmTaskType.scan: AlarmTaskSchema(
    (context) => AppLocalizations.of(context)!.scanTask,
    SettingGroup(
        "Scan Settings", (context) => AppLocalizations.of(context)!.scanTask, [
      // Registered code: hidden raw value (D-REG-DISPLAY status-only /
      // privacy). isVisual:false keeps the raw value out of the auto-rendered
      // settings UI — the user-facing affordance is the Plan 05 registration
      // card, never the raw string.
      StringSetting(
        "Registered Code",
        (context) => AppLocalizations.of(context)!.scanRegisteredCodeTitle,
        "",
        isVisual: false,
      ),
      // Marker that mounts the inline ScanRegisterCard (route B — D-STORE-FORMAT,
      // no factory entry). Dispatched in get_setting_widget.dart to a
      // ScanRegisterCard reading the sibling "Registered Code" StringSetting
      // above. Rendered ABOVE the Escape Hatch toggle (D-REG-UI / Surface 1).
      ScanRegisterSetting(
        "Register Code",
        (context) => AppLocalizations.of(context)!.scanRegisteredCodeTitle,
      ),
      // Escape hatch on/off (D-ESC-EXPOSURE). DEFAULT true (SCAN-06) — the
      // ethics-critical "never trap the user" guarantee is on out of the box.
      SwitchSetting(
        "Escape Hatch",
        (context) => AppLocalizations.of(context)!.scanEscapeHatch,
        true,
        getDescription: (context) =>
            AppLocalizations.of(context)!.scanEscapeHatchDescription,
      ),
    ]),
    (onSolve, settings) {
      return ScanTask(onSolve: onSolve, settings: settings);
    },
  ),
};
