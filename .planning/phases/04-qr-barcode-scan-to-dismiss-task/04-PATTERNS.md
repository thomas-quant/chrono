# Phase 4: QR/Barcode Scan-to-Dismiss Task - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 13 (6 new Dart + 2 new tests + 5 edits) — non-code edits (pubspec, gradle, manifest, ARB) tracked separately
**Analogs found:** 11 / 11 code files have a strong in-repo analog (all `exact` or `role-match`)

> Almost the entire feature is *assembly of existing seams* (per RESEARCH.md). The new task slots into the existing `AlarmTask` framework with **zero ring-orchestration change**. Only two genuinely-new pure seams (`code_match`, `escape_hatch_controller`) and three thin widgets (ring task, register screen, register card) need authoring. The planner should copy structure directly from the analogs below.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/alarm/logic/code_match.dart` (NEW) | utility (pure) | transform | `lib/audio/types/volume_ramp_controller.dart` (pure-seam idiom) | role-match |
| `lib/alarm/logic/escape_hatch_controller.dart` (NEW) | service/controller (pure) | event-driven (Timer + callbacks) | `lib/audio/types/volume_ramp_controller.dart` | exact |
| `lib/alarm/widgets/tasks/scan_task.dart` (NEW) | component (task widget) | streaming (live camera decode) | `lib/alarm/widgets/tasks/math_task.dart` | role-match |
| `lib/alarm/screens/scan_register_screen.dart` (NEW) | screen | request-response (scan → pop) | `lib/alarm/screens/try_alarm_task_screen.dart` | exact |
| `lib/alarm/widgets/scan_register_card.dart` (NEW) | component (setting card) | request-response (tap → action) | `lib/settings/widgets/setting_action_card.dart` + `custom_setting_card.dart` | role-match |
| `lib/alarm/types/alarm_task.dart` (EDIT) | model (enum) | — | self (add `scan` enum value) | exact |
| `lib/alarm/data/alarm_task_schemas.dart` (EDIT) | config (schema registry) | CRUD (registration map) | self (math/retype entries) | exact |
| `lib/l10n/app_en.arb` (EDIT) | config (l10n) | — | self (`mathTask` key pattern) | exact |
| `test/alarm/logic/code_match_test.dart` (NEW) | test (unit, pure) | transform assertions | `test/audio/types/volume_ramp_controller_test.dart` | role-match |
| `test/alarm/logic/escape_hatch_controller_test.dart` (NEW) | test (unit, pure, fake_async) | event-driven assertions | `test/audio/types/volume_ramp_controller_test.dart` | exact |
| `android/app/build.gradle` (EDIT) | config (build) | — | self (`minSdkVersion` line) | exact |
| `android/app/src/main/AndroidManifest.xml` (EDIT) | config (manifest) | — | self (`uses-permission` block) | exact |
| `pubspec.yaml` (EDIT) | config (deps) | — | self (dependencies block) | exact |

**No-orchestration-change confirmed:** `lib/alarm/screens/alarm_notification_screen.dart` is **NOT** in the edit list. Its `_setNextWidget()` (lines 41-63) iterates `alarm.tasks[_currentIndex].builder(_setNextWidget)` type-agnostically and dismisses at index ≥ length — the new `scan` task is auto-picked-up. Do not edit it.

---

## Pattern Assignments

### `lib/alarm/types/alarm_task.dart` (model/enum — EDIT)

**Analog:** self (the existing enum + JSON round-trip). Add `scan` to the enum; the rest rides for free.

**Enum** (`alarm_task.dart:8-14`) — add `scan`:
```dart
enum AlarmTaskType {
  math,
  retype,
  sequence,
  shake,
  memory,
  scan,        // ← ADD (SCAN-01). 'shake' is already present but unused in the schema map.
}
```

**JSON round-trip is fully generic** (`alarm_task.dart:66-77, 100-108`) — no edit needed beyond the enum. `AlarmTask.fromJson` resolves `AlarmTaskType.values.byName(json['type'])` and `alarmTaskSchemasMap[type]!.copy()`; `toJson` writes `type.name` + `_schema.toJson()`. An additive enum value needs **no `alarmSchemaVersion` bump** (currently 5, `alarm_settings_schema.dart:31`) — unknown/new types default-construct (RESEARCH Runtime State Inventory).

**`AlarmTaskBuilder` signature** the new schema's builder must match (`alarm_task.dart:16-17`):
```dart
typedef AlarmTaskBuilder = Widget Function(Function() onSolve, SettingGroup settings);
```

---

### `lib/alarm/data/alarm_task_schemas.dart` (config/registry — EDIT)

**Analog:** the `AlarmTaskType.math` entry (`alarm_task_schemas.dart:11-47`) — copy its exact shape.

**Schema entry to add** (mirror the math entry's `(getLocalizedName, SettingGroup, builder)` triple):
```dart
// Source pattern: alarm_task_schemas.dart:11-47 (math entry)
AlarmTaskType.scan: AlarmTaskSchema(
  (context) => AppLocalizations.of(context)!.scanTask,
  SettingGroup("Scan Settings",
      (context) => AppLocalizations.of(context)!.scanTask, [
    // Registered code: hidden raw value (D-REG-DISPLAY status-only / privacy).
    StringSetting("Registered Code",
        (context) => AppLocalizations.of(context)!.scanRegisteredCodeTitle, "",
        isVisual: false),                                  // isVisual:false → not auto-rendered as a card
    // Escape hatch on/off (D-ESC-EXPOSURE). DEFAULT true (SCAN-06).
    SwitchSetting("Escape Hatch",
        (context) => AppLocalizations.of(context)!.scanEscapeHatch, true,
        getDescription: (context) =>
            AppLocalizations.of(context)!.scanEscapeHatchDescription),
    // The inline "Scan to register" affordance is a CUSTOM card — see Pattern 2
    // (scan_register_card.dart). Two valid hosting options, both in get_setting_widget.dart:
    //   (A) CustomSetting<RegisteredCode> (custom_setting_card.dart) — needs a
    //       fromJsonFactories[RegisteredCode] entry (setting.dart:281). NOTE: this is
    //       the ONE place D-STORE-FORMAT's "no factory entry needed" would NOT hold.
    //   (B) a plain StringSetting + a new ScanRegisterSettingCard registered in
    //       get_setting_widget.dart (mirrors setting_action_card.dart). Honors
    //       D-STORE-FORMAT literally (no factory entry). PLANNER'S CALL.
  ]),
  (onSolve, settings) => ScanTask(onSolve: onSolve, settings: settings),
),
```

**Imports to add at top** (mirror existing task-widget imports, lines 2-5):
```dart
import 'package:clock_app/alarm/widgets/tasks/scan_task.dart';
// SwitchSetting/StringSetting already available via the existing
// 'package:clock_app/settings/types/setting.dart' import (line 6).
```

**`SettingGroup` reads in the widget** use string keys (`math_task.dart:89-90` precedent): `widget.settings.getSetting("Registered Code").value` / `getSetting("Escape Hatch").value`.

---

### `lib/alarm/widgets/tasks/scan_task.dart` (component/ring task widget — NEW)

**Analog:** `lib/alarm/widgets/tasks/math_task.dart` — same `StatefulWidget(onSolve, settings)` contract, same `onSolve()`-to-dismiss flow, same `dispose()` discipline.

**Widget shell + constructor** (copy `math_task.dart:68-101`):
```dart
class ScanTask extends StatefulWidget {
  const ScanTask({super.key, required this.onSolve, required this.settings});
  final VoidCallback onSolve;          // call to advance/dismiss (math_task.dart:75)
  final SettingGroup settings;
  @override
  State<ScanTask> createState() => _ScanTaskState();
}
```

**Read settings in `initialize()`** (mirror `math_task.dart:88-95`):
```dart
final storedNormalized = normalizeCode(widget.settings.getSetting("Registered Code").value);
final escapeEnabled    = widget.settings.getSetting("Escape Hatch").value;
```

**`dispose()` releases resources** (math_task.dart:124-127 disposes its controller; here the `ReaderWidget` disposes the `CameraController` when removed from the tree — SCAN-11). On every exit path (`onSolve` on match, `onSolve` on escape-fire, app→background) the widget must leave the tree.

**Build/layout** mirrors `math_task.dart:130-196` — `Padding(EdgeInsets.all(16))` → `Column` with a `headlineMedium` header (`math_task.dart:140-143` "Solve the equation" → here `scanRingInstruction`), then the live preview slot. UI-SPEC Surface 3 pins: `ReaderWidget(showFlashlight: true, showToggleCamera: false, showGallery: false)`, default torch OFF, wrong-scan = `error`-role flash + `vibration` haptic (~600ms), escape "Dismiss" button reuses `dismissAlarmButton`, all wrapped in `Semantics`.

**Result handling** (RESEARCH Pattern 3): `onScan: (Code c) { codesMatch(normalizeCode(c.text), storedNormalized) ? onSolve() : (vibrate + escape.recordFailedAttempt()); }`; `onControllerCreated: (_, exception) { if (exception != null) escape.fireNow(); }` (SCAN-07).

**Theme access** (every widget uses this, `math_task.dart:131-133`): `Theme.of(context)` → `colorScheme`/`textTheme`; NEVER hardcode color/size (UI-SPEC Color/Typography).

---

### `lib/alarm/screens/scan_register_screen.dart` (screen — NEW)

**Analog:** `lib/alarm/screens/try_alarm_task_screen.dart` (the entire 24-line file) — a `Scaffold(appBar: AppTopBar(), body: ...)` that renders a scan surface and pops on completion.

**Full structure to copy** (`try_alarm_task_screen.dart:5-24`):
```dart
class ScanRegisterScreen extends StatelessWidget {  // or Stateful if holding a controller ref
  const ScanRegisterScreen({super.key, required this.setting});
  final StringSetting setting;          // the "Registered Code" StringSetting to write into
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),        // try_alarm_task_screen.dart:13
      body: ReaderWidget(
        onScan: (code) {
          setting.setValue(context, normalizeCode(code.text));  // normalize BEFORE store (D-MATCH-NORMALIZE)
          Navigator.pop(context);                               // try_alarm_task_screen.dart:18 idiom
        },
      ),
    );
  }
}
```
> Registration **is** the test scan (D-REG-TEST/SCAN-10) — a successful decode here proves it scans. NEVER log `code.text` (privacy / RESEARCH Security V7). Import: `package:clock_app/navigation/widgets/app_top_bar.dart` (try_alarm_task_screen.dart:2).

---

### `lib/alarm/widgets/scan_register_card.dart` (component/setting card — NEW)

**Analog:** `lib/settings/widgets/setting_action_card.dart` (tappable card running an action) blended with `custom_setting_card.dart` (pushes a screen + shows a value-display + `setState` on return).

**Card body — copy `setting_action_card.dart:28-64`** (`Material`→`InkWell`→`Padding(16)`→`Row[Column(title displaySmall + status bodyMedium), trailing icon]`, wrapped in `CardContainer`):
```dart
// Source: setting_action_card.dart:28-64
Widget inner = Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: () => _handleScanToRegister(context),     // permission → push ScanRegisterScreen → setState
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: textTheme.displaySmall),     // "Registered code" (setting_action_card.dart:42)
            const SizedBox(height: 4),
            Text(statusLine, style: textTheme.bodyMedium),   // "✓ Code registered" / "No code registered yet"
          ])),
        Icon(Icons.chevron_right_rounded,
            color: colorScheme.onBackground.withOpacity(0.6)),  // setting_action_card.dart:54-56
      ]),
    ),
  ),
);
return showAsCard ? CardContainer(child: inner) : inner;       // setting_action_card.dart:64
```

**Refresh-on-return idiom — copy `custom_setting_card.dart:25-31`** (await the push, then `setState(() {})` so the status line updates after registration):
```dart
await Navigator.of(context).push(MaterialPageRoute(
    builder: (context) => ScanRegisterScreen(setting: codeSetting)));
setState(() {});                              // custom_setting_card.dart:31
```

**Permission gate before push** (D-REG-CAMDENIED / SCAN-08) — see Shared Pattern *Camera Permission* below.

**Hosting:** this card must be emitted by `get_setting_widget.dart`. Either register a new `if (item is X) return ScanRegisterSettingCard(...)` branch (mirror `setting_action_card.dart` dispatch at `get_setting_widget.dart:89-93`) for option (B), or use `CustomSettingCard` (`get_setting_widget.dart:182-186`) for option (A). Status-only display; **never render the raw decoded value** (D-REG-DISPLAY).

---

### `lib/alarm/logic/code_match.dart` (utility/pure — NEW)

**Analog:** `lib/audio/types/volume_ramp_controller.dart` for the *pure-seam idiom* (dependency-free, no Flutter/camera import, doc-comment explaining the testability seam). The function bodies are given verbatim in RESEARCH "Code Examples → Pure normalize + match seam".

**Shape** (RESEARCH lines 351-361):
```dart
// lib/alarm/logic/code_match.dart — dependency-free; no camera/UI/flutter import.
String normalizeCode(String? raw) {
  if (raw == null) return '';
  final stripped = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');  // strip control chars (trailing \n/\r/\t/\0)
  return stripped.trim().toLowerCase();                            // trim + case-fold (O1: case-fold for v1)
}
bool codesMatch(String scannedNormalized, String storedNormalized) {
  if (storedNormalized.isEmpty) return false;   // never match an unregistered task
  return scannedNormalized == storedNormalized;
}
```
> Applied identically at register (`scan_register_screen.dart`) and compare (`scan_task.dart`) — D-MATCH-NORMALIZE. CI-tested (SCAN-03).

---

### `lib/alarm/logic/escape_hatch_controller.dart` (service/controller, pure — NEW)

**Analog:** `lib/audio/types/volume_ramp_controller.dart` — **exact structural twin**: a pure class owning a single `Timer?`, firing an injected `VoidCallback`, with `start()` / a record method / `dispose()`-style `cancel()`. Copy its doc-comment style + Timer-ownership discipline.

**Key idioms to copy from `volume_ramp_controller.dart`:**
- Single owned `Timer? _timer;` + `void dispose() => _timer?.cancel();` (volume_ramp_controller.dart:24, 65-71).
- Injected callback IS the seam — no camera/audio import (volume_ramp_controller.dart:19-22).
- Guard against double-fire (the `_fired` flag mirrors the controller's single-ramp invariant).

**Shape** (RESEARCH lines 369-401): `EscapeHatchController({onEscapeAvailable, maxFailedAttempts=10, elapsedThreshold=120s, enabled=true})`; `start()` arms a `Timer(elapsedThreshold, _fire)`; `recordFailedAttempt()` increments and fires at `>= maxFailedAttempts`; `fireNow()` for cam-denied/unavailable (SCAN-07); `_fire()` is idempotent via `_fired`; `dispose()` cancels the timer. Debounce: only count a *non-matching valid decode* — never raw decode frames (RESEARCH Pitfall 2 / D-ESC-DEFAULT; `ReaderWidget.scanDelay` 1000ms rate-limits upstream).

---

### `test/alarm/logic/code_match_test.dart` (test/unit, pure — NEW)

**Analog:** `test/audio/types/volume_ramp_controller_test.dart` for the `group(...)`/`test(...)` structure (no `fake_async` needed here — `code_match` has no timers). Assert SCAN-03 edge cases: trailing `\n` does not false-reject, case diff does not false-reject (case-fold), control chars stripped, wrong code does not match, empty stored never matches.

**Import idiom** (volume_ramp_controller_test.dart:1-3): `package:clock_app/alarm/logic/code_match.dart` + `package:flutter_test/flutter_test.dart`.

---

### `test/alarm/logic/escape_hatch_controller_test.dart` (test/unit, fake_async — NEW)

**Analog:** `test/audio/types/volume_ramp_controller_test.dart` — **exact** template (real `Timer` driven by `fakeAsync((async) { ... async.elapse(...); })`).

**Copy verbatim** the `fakeAsync` + recorder-callback harness (volume_ramp_controller_test.dart:12-37):
```dart
fakeAsync((async) {
  var fired = 0;
  final controller = EscapeHatchController(onEscapeAvailable: () => fired++);
  controller.start();
  async.elapse(const Duration(seconds: 120));   // time branch (D-ESC-TRIGGER)
  expect(fired, 1);
});
```
**Branches to cover** (SCAN-06/07): time fires at ≥120s; attempts fires at ≥N; `fireNow()` fires immediately and only once (idempotent); `enabled:false` never fires; cancel/dispose stops the timer (mirror volume_ramp_controller_test.dart "no callback fires after cancel()", lines 14-37).

> **Comment header idiom** (volume_ramp_controller_test.dart:5-10 / alarm_snooze_test.dart:8-18): explain *why* `fake_async` (the `clock` package controls `DateTime.now()`, NOT `Timer` firing — `fake_async` is the correct tool for timers). Note OS no-ops under `FLUTTER_TEST` are irrelevant here (pure seam, no OS calls).

---

### Non-Dart edits (config — exact self-analogs)

**`pubspec.yaml`** — add to the `dependencies:` block, **exact pin** (RESEARCH BUILD-02):
```yaml
flutter_zxing: 2.2.1   # exact pin — NOT ^2.2.0 (2.3.0 needs Flutter >=3.41)
```

**`android/app/build.gradle:56`** — `minSdkVersion 21` → `minSdkVersion 23` (BUILD-01). If Gradle complains about NDK, align `ndkVersion` (line 38 currently `flutter.ndkVersion`) to `27.0.12077973` (RESEARCH Pitfall 4).

**`android/app/src/main/AndroidManifest.xml`** — add alongside the existing `uses-permission` block (lines 4-22), mirroring its formatting:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
<uses-feature android:name="android.hardware.camera.flash" android:required="false" />
```

**`lib/l10n/app_en.arb`** — add keys using the existing `"key": "value"` + `"@key": {}` pair pattern (`app_en.arb:344-345` `mathTask`). All UI-SPEC Copywriting keys: `scanTask`, `scanRegisteredCodeTitle`, `scanRegisterButton`, `scanRescanButton`, `scanCodeRegistered`, `scanNoCodeRegistered`, `scanCodeRequired`, `scanEscapeHatch`, `scanEscapeHatchDescription`, `scanRingInstruction`, `scanWrongCode`, `scanTorchLabel`, `scanTorchUnavailable`, `scanCameraPermissionPrompt`, `scanOpenSettings`, `scanUnlockToScanTitle`, `scanUnlockToScanBody`. **Reuse** existing `dismissAlarmButton` (`app_en.arb:404`) for the escape "Dismiss" button — do NOT add a duplicate. `flutter gen-l10n` is a CI/human gate (toolchain absent).

---

## Shared Patterns

### Pure controller / seam idiom (CI-testable)
**Source:** `lib/audio/types/volume_ramp_controller.dart` + `test/audio/types/volume_ramp_controller_test.dart`
**Apply to:** `code_match.dart`, `escape_hatch_controller.dart`, and both their tests.
- A pure class owns a single `Timer?`, fires an **injected callback** (the seam), imports no Flutter/camera/audio package, and has an idempotent stop (`cancel`/`dispose`).
- Tests drive it with `fakeAsync((async) { ...; async.elapse(...); })` and a recorder callback; the `clock` package controls `DateTime.now()` but **`fake_async` controls Timer firing** (volume_ramp_controller_test.dart:5-10).
```dart
// volume_ramp_controller.dart:18-27 — the seam + single-Timer ownership
class VolumeRampController {
  VolumeRampController(this._setVolume);
  final void Function(double volume) _setVolume;   // injected sink = the seam
  Timer? _timer;
  bool get isRunning => _timer?.isActive ?? false;
```

### Task widget contract
**Source:** `lib/alarm/widgets/tasks/math_task.dart`
**Apply to:** `scan_task.dart`
- `StatefulWidget` with `required this.onSolve` (VoidCallback) + `required this.settings` (SettingGroup) (math_task.dart:68-79).
- Read config via string keys in `initialize()`: `widget.settings.getSetting("<Name>").value` (math_task.dart:89-90).
- Call `widget.onSolve()` exactly once on success (math_task.dart:111); dispose owned resources in `dispose()` (math_task.dart:124-127).
- `Padding(EdgeInsets.all(16))` root, `headlineMedium` instruction header, theme-only colors/sizes (math_task.dart:131-143).

### Tappable setting card
**Source:** `lib/settings/widgets/setting_action_card.dart` (action) + `lib/settings/widgets/custom_setting_card.dart` (push-screen + refresh)
**Apply to:** `scan_register_card.dart`
- `Material(transparent) → InkWell(onTap) → Padding(16) → Row[ Expanded(Column[title displaySmall, status bodyMedium]), Icon(chevron_right_rounded, onBackground@0.6) ]`, wrapped in `CardContainer` when `showAsCard` (setting_action_card.dart:28-64).
- After a screen push, `await` it then `setState(() {})` to refresh the status line (custom_setting_card.dart:25-31).

### Setting-card dispatch (hosting a custom card)
**Source:** `lib/settings/logic/get_setting_widget.dart`
**Apply to:** wiring `scan_register_card.dart` into the task `SettingGroup` page.
- `getSettingItemWidget` is an `if (item is X) return XCard(...)` chain (get_setting_widget.dart:89-196). Add a branch for the marker setting OR use the existing `CustomSetting → CustomSettingCard` branch (lines 182-186).
- `isVisual: false` settings are skipped (`get_setting_widget.dart:95`) — that is why the raw "Registered Code" `StringSetting` (set `isVisual:false`) renders no card; the custom card is what the user sees.
- The task settings page renders via `getSettingWidgets(item.settings.settingItems, ..., isAppSettings: false)` (customize_list_item_screen.dart:53-62).

### Camera permission at setup (never fire time)
**Source:** `lib/system/logic/permissions.dart` (request idiom) + `lib/settings/data/general_settings_schema.dart:344,354` (`AppSettings.openAppSettings(...)` deep-link)
**Apply to:** `scan_register_card.dart` tap handler (SCAN-08 / D-REG-CAMDENIED)
```dart
// Mirror permissions.dart:5-10 status/request idiom, with Permission.camera:
var status = await Permission.camera.status;
if (!status.isGranted) status = await Permission.camera.request();
if (status.isGranted) { /* push ScanRegisterScreen */ }
else { /* show scanCameraPermissionPrompt → AppSettings.openAppSettings() (general_settings_schema.dart:344), then resume */ }
```

### Over-lock window (already wired — do not re-implement)
**Source:** `lib/notifications/logic/alarm_notifications.dart:182` (`await FlutterShowWhenLocked().show();`) / `:105` (`.hide()`)
**Apply to:** the ring-time scanner inherits this window — **no new call needed**. This window is the lock-screen spike's subject (criterion #1). The "unlock to scan" prompt (UI-SPEC Surface 4) is only shown on no-go OEMs.

### Localization
**Source:** `lib/l10n/app_en.arb` (`mathTask` pair, lines 344-345)
**Apply to:** every new user-facing string (SCAN-12). `"camelCaseKey": "Sentence-case value"` + `"@camelCaseKey": {}`. Resolve in widgets via `AppLocalizations.of(context)!.<key>` (alarm_task_schemas.dart:12 idiom).

### Logging discipline (privacy)
**Source:** CONVENTIONS.md logging (`logger.t/i/e/f`); RESEARCH Security V7
**Apply to:** all scan code paths — **NEVER** `logger.*`/`print` the decoded `code.text` (D-REG-DISPLAY). If touching settings-card code, also remove the pre-existing `print(setting.value)` leak at `dynamic_toggle_setting_card.dart:39` (STATE.md / RESEARCH todo).

---

## No Analog Found

No code file in this phase lacks a strong in-repo analog. The single thing with **no analog** is the third-party `flutter_zxing` `ReaderWidget` itself (camera preview + ZXing decode) — that is an external library surface, not Chrono code to mirror. Its usage shape is pinned in RESEARCH Pattern 3 (lines 251-276) and UI-SPEC Surface 3; the planner should reference those directly for `onScan`/`onScanFailure`/`onControllerCreated`/`showFlashlight` wiring.

| Surface | Role | Data Flow | Source to use instead of an in-repo analog |
|---------|------|-----------|--------------------------------------------|
| `ReaderWidget(...)` call sites | external widget | streaming | RESEARCH Pattern 3 (251-276) + UI-SPEC Surface 3 |

---

## Metadata

**Analog search scope:** `lib/alarm/{types,data,widgets/tasks,screens,logic}`, `lib/settings/{types,widgets,logic}`, `lib/common/widgets/{fields,list}`, `lib/audio/types`, `lib/system/logic`, `lib/notifications/logic`, `lib/l10n`, `test/alarm`, `test/audio`, `android/app`
**Files scanned:** ~24 (13 read in full; supporting greps on `setting.dart`, `alarm_settings_schema.dart`, `app_en.arb`, `build.gradle`, `alarm_notifications.dart`)
**Pattern extraction date:** 2026-06-05
</content>
</invoke>
